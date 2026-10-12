import '../llm_provider.dart';
import '../llm_transport.dart';

/// Groq through its OpenAI-compatible Chat Completions API
/// (`POST /openai/v1/chat/completions`), the stable endpoint Groq documents
/// for tool use (its Responses API is beta).
///
/// Requests are stateless: the instructions become the system message and
/// the whole windowed conversation is sent every time. Model, reasoning
/// effort, token cap and the API key are applied by the FiNN API relay, so
/// this class never sees credentials (see [LlmTransport]). Reasoning text
/// is not returned by the relay and never replayed.
class GroqChatProvider implements LlmProvider {
  GroqChatProvider(this.transport);

  final LlmTransport transport;

  @override
  String get name => 'groq';

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
      };

  static Map<String, Object?> _encodeMessage(LlmMessage m) => switch (m.role) {
        LlmRole.user => {'role': 'user', 'content': m.content ?? ''},
        LlmRole.tool => {
            'role': 'tool',
            'tool_call_id': m.toolCallId,
            'name': ?m.toolName,
            'content': m.content ?? '',
          },
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
      throw const LlmException(LlmErrorKind.invalidResponse, 'The assistant sent an unexpected reply. Please try again.',
          retryable: true);
    }
    final calls = <LlmToolCall>[];
    final rawCalls = message['tool_calls'];
    if (rawCalls is List) {
      for (final raw in rawCalls.whereType<Map>()) {
        final fn = raw['function'];
        final id = raw['id'];
        final name = fn is Map ? fn['name'] : null;
        if (id is! String || id.isEmpty || name is! String || name.isEmpty) {
          throw const LlmException(LlmErrorKind.invalidResponse,
              'The assistant sent an incomplete request. Please try again.', retryable: true);
        }
        final args = fn is Map ? fn['arguments'] : null;
        calls.add(LlmToolCall(id: id, name: name, arguments: args is String ? args : '{}'));
      }
    }
    final content = message['content'];
    final text = content is String ? content.trim() : '';

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
      usage: LlmUsage(inputTokens: tokens('prompt_tokens'), outputTokens: tokens('completion_tokens')),
    );
  }
}
