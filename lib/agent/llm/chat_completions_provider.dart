import 'llm_provider.dart';
import 'llm_transport.dart';

/// OpenAI-compatible Chat Completions wire format, sent through the FiNN API
/// relay (currently OpenAI `gpt-6-luna`).
///
/// Requests are stateless: the instructions become the system message and
/// the given messages follow. Model, reasoning effort, prompt caching, the
/// token ceiling and the API key are applied by the relay, so this class
/// never sees credentials (see [LlmTransport]) and a model change needs no
/// app release. Reasoning text is never returned by the relay.
class ChatCompletionsProvider implements LlmProvider {
  ChatCompletionsProvider(this.transport);

  final LlmTransport transport;

  @override
  String get name => 'chat-completions';

  @override
  Future<LlmResponse> complete(LlmRequest request, {CancellationToken? cancel}) async {
    final body = encodeRequest(request);
    final json = cancel == null ? await transport.post(body) : await cancel.guard(transport.post(body));
    return decodeResponse(json);
  }

  /// Wire body for the relay (`/agent/completions`).
  static Map<String, Object?> encodeRequest(LlmRequest r) => {
    'messages': [
      {'role': 'system', 'content': r.instructions},
      for (final m in r.messages) _encodeMessage(m),
    ],
    if (r.tools.isNotEmpty) ...{
      'tools': [
        for (final t in r.tools)
          {
            'type': 'function',
            'function': {'name': t.name, 'description': t.description, 'parameters': t.parameters},
          },
      ],
      'tool_choice': r.toolChoice.name,
      'parallel_tool_calls': ?r.parallelToolCalls,
    },
    'max_completion_tokens': ?r.maxOutputTokens,
    if (r.output == LlmOutputFormat.json) 'response_format': {'type': 'json_object'},
  };

  static Map<String, Object?> _encodeMessage(LlmMessage m) => switch (m.role) {
    LlmRole.user => {'role': 'user', 'content': m.content ?? ''},
    LlmRole.tool => {'role': 'tool', 'tool_call_id': m.toolCallId, 'name': ?m.toolName, 'content': m.content ?? ''},
    LlmRole.assistant => {
      'role': 'assistant',
      'content': m.content,
      if (m.toolCalls.isNotEmpty)
        'tool_calls': [
          for (final c in m.toolCalls)
            {
              'id': c.id,
              'type': 'function',
              'function': {'name': c.name, 'arguments': c.arguments},
            },
        ],
    },
  };

  /// Parses the relay's `{id, finish_reason, message, usage}`. Throws
  /// [LlmException] when it is not usable.
  static LlmResponse decodeResponse(Map<String, Object?> json) {
    final message = json['message'];
    if (message is! Map) {
      throw const LlmException(
        LlmErrorKind.invalidResponse,
        'The assistant sent an unexpected reply. Please try again.',
        retryable: true,
      );
    }
    final calls = <LlmToolCall>[];
    final rawCalls = message['tool_calls'];
    if (rawCalls is List) {
      for (final raw in rawCalls.whereType<Map>()) {
        final fn = raw['function'];
        final id = raw['id'];
        final name = fn is Map ? fn['name'] : null;
        if (id is! String || id.isEmpty || name is! String || name.isEmpty) {
          throw const LlmException(
            LlmErrorKind.invalidResponse,
            'The assistant sent an incomplete request. Please try again.',
            retryable: true,
          );
        }
        final args = fn is Map ? fn['arguments'] : null;
        calls.add(LlmToolCall(id: id, name: name, arguments: args is String ? args : '{}'));
      }
    }
    final content = message['content'];
    final text = content is String ? content.trim() : '';
    final refusal = message['refusal'];

    final finish = switch (json['finish_reason']) {
      _ when calls.isNotEmpty => LlmFinishReason.toolCalls,
      'stop' || null => LlmFinishReason.stop,
      'length' => LlmFinishReason.length,
      _ => LlmFinishReason.other,
    };
    final usage = json['usage'];
    int tokens(String key) => usage is Map && usage[key] is num ? (usage[key] as num).toInt() : 0;

    return LlmResponse(
      text: text.isEmpty ? null : text,
      toolCalls: calls,
      finishReason: finish,
      refusal: refusal is String && refusal.trim().isNotEmpty ? refusal.trim() : null,
      usage: LlmUsage(
        inputTokens: tokens('prompt_tokens'),
        outputTokens: tokens('completion_tokens'),
        cachedInputTokens: tokens('cached_tokens'),
        cacheWriteTokens: tokens('cache_write_tokens'),
        reasoningTokens: tokens('reasoning_tokens'),
        calls: 1,
      ),
    );
  }
}
