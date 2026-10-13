import 'dart:convert';

import 'package:finn/agent/llm/chat_completions_provider.dart';
import 'package:finn/agent/llm/llm_provider.dart';
import 'package:finn/agent/llm/llm_transport.dart';
import 'package:finn/agent/prompt/agent_prompt.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../remote/remote_fakes.dart';

/// The relay's trimmed Chat Completions reply.
Map<String, Object?> relayReply({String? content, String finish = 'stop', Map<String, Object?>? usage, String? refusal}) => {
  'id': 'chatcmpl_1',
  'finish_reason': finish,
  'message': {'content': content, 'tool_calls': const [], 'refusal': ?refusal},
  'usage': usage ?? {'prompt_tokens': 1600, 'completion_tokens': 40, 'total_tokens': 1640},
};

void main() {
  group('request encoding (relay contract)', () {
    test('a plan request: system message first, JSON output, no tools', () {
      final body = ChatCompletionsProvider.encodeRequest(const LlmRequest(
        instructions: agentInstructions,
        messages: [LlmMessage.user('[FiNN context] Today: Sat 2026-10-10.'), LlmMessage.user('spent 450 on lunch')],
        output: LlmOutputFormat.json,
        maxOutputTokens: 700,
      ));
      expect(body.keys, unorderedEquals(['messages', 'max_completion_tokens', 'response_format']));
      expect(body['response_format'], {'type': 'json_object'});
      expect(body['messages'], [
        {'role': 'system', 'content': agentInstructions},
        {'role': 'user', 'content': '[FiNN context] Today: Sat 2026-10-10.'},
        {'role': 'user', 'content': 'spent 450 on lunch'},
      ]);
      // Server-owned: model, key, reasoning effort, prompt caching, user id.
      for (final k in ['model', 'user', 'reasoning_effort', 'prompt_cache_options', 'prompt_cache_key', 'tools']) {
        expect(body.containsKey(k), isFalse, reason: k);
      }
    });

    test('tool requests keep the OpenAI shape (other callers of the provider)', () {
      final body = ChatCompletionsProvider.encodeRequest(const LlmRequest(
        instructions: 'x',
        messages: [
          LlmMessage.assistant(toolCalls: [LlmToolCall(id: 'c1', name: 'f', arguments: '{}')]),
          LlmMessage.toolResult(callId: 'c1', toolName: 'f', content: '{}'),
        ],
        tools: [LlmToolSpec(name: 'f', description: 'F', parameters: {'type': 'object'})],
      ));
      expect(body['tool_choice'], 'auto');
      expect((body['messages'] as List)[1], containsPair('tool_calls', isA<List<Object?>>()));
      expect(body.containsKey('response_format'), isFalse);
    });

    test('the whole plan request fits the relay limits', () {
      expect(agentInstructions.length, lessThan(20000)); // relay: system content ≤ 20,000 characters
    });
  });

  group('response decoding', () {
    test('text, usage with cache and reasoning details', () {
      final r = ChatCompletionsProvider.decodeResponse(relayReply(content: ' {"ops":[]} ', usage: {
        'prompt_tokens': 1600,
        'completion_tokens': 40,
        'cached_tokens': 1463,
        'cache_write_tokens': 0,
        'reasoning_tokens': 0,
      }));
      expect(r.text, '{"ops":[]}');
      expect(r.finishReason, LlmFinishReason.stop);
      expect((r.usage.inputTokens, r.usage.cachedInputTokens, r.usage.outputTokens, r.usage.calls), (1600, 1463, 40, 1));
    });

    test('refusals and cut-offs', () {
      expect(ChatCompletionsProvider.decodeResponse(relayReply(refusal: 'I can’t help with that.')).refusal,
          'I can’t help with that.');
      expect(ChatCompletionsProvider.decodeResponse(relayReply(content: '{"ops":[', finish: 'length')).finishReason,
          LlmFinishReason.length);
    });

    test('a reply without a message is an invalid response', () {
      expect(
        () => ChatCompletionsProvider.decodeResponse({'id': 'x'}),
        throwsA(isA<LlmException>().having((e) => e.kind, 'kind', LlmErrorKind.invalidResponse)),
      );
    });
  });

  group('relay transport', () {
    test('posts to /agent/completions with the session token only', () async {
      late http.Request seen;
      final client = MockClient((req) async {
        seen = req;
        return ok(relayReply(content: '{"ops":[]}'));
      });
      final provider = ChatCompletionsProvider(FinnRelayTransport(apiWith(client)));
      await provider.complete(const LlmRequest(instructions: 'x', messages: [LlmMessage.user('hi')], output: LlmOutputFormat.json));
      expect(seen.url.toString(), 'https://api.test/api/v1/agent/completions');
      expect(seen.headers['authorization'], 'Bearer token-1');
      expect((jsonDecode(seen.body) as Map)['response_format'], {'type': 'json_object'});
    });

    http.Response failure(String code, String message, {bool retryable = false, Map<String, Object?>? details, int status = 503}) =>
        http.Response(
          jsonEncode({
            'error': {'code': code, 'message': message, 'retryable': retryable, 'details': ?details},
          }),
          status,
        );

    Future<LlmException> failureFor(http.Response response) async {
      final provider = ChatCompletionsProvider(FinnRelayTransport(apiWith(MockClient((_) async => response))));
      try {
        await provider.complete(const LlmRequest(instructions: 'x', messages: [LlmMessage.user('hi')]));
      } on LlmException catch (e) {
        return e;
      }
      fail('expected LlmException');
    }

    test('maps relay errors onto LLM error kinds', () async {
      final limited = await failureFor(failure('unavailable', 'Busy.',
          retryable: true, details: {'reason': 'providerRateLimited', 'retryAfterSeconds': 7}));
      expect(limited.kind, LlmErrorKind.rateLimited);
      expect(limited.retryAfter, const Duration(seconds: 7));
      final notConfigured = await failureFor(
          failure('unavailable', 'The assistant is not configured on this server.', details: {'reason': 'notConfigured'}));
      expect(notConfigured.kind, LlmErrorKind.notConfigured);
      final timeout = await failureFor(failure('unavailable', 'Unavailable.', retryable: true, details: {'reason': 'timeout'}));
      expect(timeout.kind, LlmErrorKind.timeout);
      final tooLarge = await failureFor(failure('validation', 'Too long.', details: {'reason': 'tooLarge'}, status: 422));
      expect(tooLarge.kind, LlmErrorKind.rejected);
      final outage = await failureFor(http.Response('gateway down', 502));
      expect(outage.kind, LlmErrorKind.unavailable);
    });

    test('cancellation abandons the request', () async {
      final client = MockClient((_) => Future.delayed(const Duration(milliseconds: 150), () => ok(relayReply(content: 'x'))));
      final provider = ChatCompletionsProvider(FinnRelayTransport(apiWith(client)));
      final token = CancellationToken();
      final future = provider.complete(const LlmRequest(instructions: 'x', messages: [LlmMessage.user('hi')]), cancel: token);
      token.cancel();
      await expectLater(future, throwsA(isA<LlmException>().having((e) => e.kind, 'kind', LlmErrorKind.cancelled)));
    });
  });
}
