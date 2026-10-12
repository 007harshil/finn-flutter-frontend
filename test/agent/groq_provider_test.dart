import 'dart:convert';

import 'package:finn/actions/action_registry.dart';
import 'package:finn/agent/llm/groq/groq_chat_provider.dart';
import 'package:finn/agent/llm/llm_provider.dart';
import 'package:finn/agent/llm/llm_transport.dart';
import 'package:finn/agent/orchestration/conversation.dart';
import 'package:finn/agent/prompt/system_prompt.dart';
import 'package:finn/agent/tools/tool_catalog.dart';
import 'package:finn/agent/tools/tool_groups.dart';
import 'package:finn/app/di/action_catalog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../actions/action_harness.dart';
import '../remote/remote_fakes.dart';

/// The relay's trimmed Chat Completions reply.
Map<String, Object?> relayReply({String? content, List<Map<String, Object?>> toolCalls = const [], String finish = 'stop'}) => {
      'id': 'chatcmpl_1',
      'finish_reason': finish,
      'message': {'content': content, 'tool_calls': toolCalls},
      'usage': {'prompt_tokens': 900, 'completion_tokens': 40, 'total_tokens': 940},
    };

Map<String, Object?> fnCall(String id, String name, String args) => {
      'id': id,
      'type': 'function',
      'function': {'name': name, 'arguments': args},
    };

void main() {
  group('request encoding (Groq Chat Completions, relay contract)', () {
    test('system message first, tool calls and tool results in OpenAI shape', () {
      final body = GroqChatProvider.encodeRequest(const LlmRequest(
        instructions: 'Be FiNN.',
        messages: [
          LlmMessage.user('Paid Rahul 500'),
          LlmMessage.assistant(toolCalls: [LlmToolCall(id: 'call_1', name: 'find_records', arguments: '{"kind":"pending"}')]),
          LlmMessage.toolResult(callId: 'call_1', toolName: 'find_records', content: '{"ok":true}'),
          LlmMessage.assistant(text: 'Done.'),
        ],
        tools: [
          LlmToolSpec(name: 'find_records', description: 'Find', parameters: {'type': 'object', 'properties': {}}),
        ],
        maxOutputTokens: 512,
      ));
      expect(body.keys, unorderedEquals(['messages', 'tools', 'tool_choice', 'max_completion_tokens']));
      expect(body['tools'], [
        {
          'type': 'function',
          'function': {'name': 'find_records', 'description': 'Find', 'parameters': {'type': 'object', 'properties': {}}},
        },
      ]);
      expect(body['messages'], [
        {'role': 'system', 'content': 'Be FiNN.'},
        {'role': 'user', 'content': 'Paid Rahul 500'},
        {
          'role': 'assistant',
          'content': null,
          'tool_calls': [fnCall('call_1', 'find_records', '{"kind":"pending"}')],
        },
        {'role': 'tool', 'tool_call_id': 'call_1', 'name': 'find_records', 'content': '{"ok":true}'},
        {'role': 'assistant', 'content': 'Done.'},
      ]);
      // Never sent by the client: the relay owns model, key and user id;
      // parallel_tool_calls is left to the model's default.
      for (final k in ['model', 'user', 'reasoning_effort', 'parallel_tool_calls']) {
        expect(body.containsKey(k), isFalse, reason: k);
      }
    });

    test('no tools → no tool fields', () {
      final body = GroqChatProvider.encodeRequest(const LlmRequest(instructions: 'x', messages: [LlmMessage.user('hi')]));
      expect(body.containsKey('tools'), isFalse);
      expect(body.containsKey('tool_choice'), isFalse);
    });

    test('every tool fits the relay limits', () {
      final toolbox = AgentToolbox.standard(ActionRegistry(allActions));
      expect(toolbox.tools.length, lessThanOrEqualTo(64));
      for (final t in toolbox.tools) {
        expect(t.description.length, lessThanOrEqualTo(2000), reason: t.name);
      }
    });

    test('a first request stays small enough for free-tier token limits', () async {
      final h = await ActionHarness.create();
      final toolbox = AgentToolbox.standard(ActionRegistry(allActions));
      final selection = ToolSelection()..enableFor('Spent 450 on lunch');
      final body = GroqChatProvider.encodeRequest(LlmRequest(
        instructions: AgentInstructions.build(await h.snapshot()),
        messages: const [LlmMessage.user('Spent 450 on lunch')],
        tools: [for (final t in selection.offered(toolbox.tools)) t.spec],
      ));
      // ~4 characters per token: keep the opening request near 3k tokens.
      expect(jsonEncode(body).length, lessThan(14000));
    });

    test('long conversations are windowed under the relay item limit', () {
      final c = Conversation(id: 'c');
      for (var i = 0; i < 60; i++) {
        c.add(LlmMessage.user('turn $i'));
        c.add(LlmMessage.assistant(toolCalls: [
          for (var k = 0; k < 3; k++) LlmToolCall(id: 'c$i$k', name: 'find_records', arguments: '{}'),
        ]));
        for (var k = 0; k < 3; k++) {
          c.add(LlmMessage.toolResult(callId: 'c$i$k', content: '{}'));
        }
      }
      final window = c.window(maxTurns: 100, maxChars: 1 << 30);
      expect(window.length + 1, lessThanOrEqualTo(200), reason: '+1 for the system message');
      expect(window.first.role, LlmRole.user);
    });
  });

  group('response decoding', () {
    test('text reply', () {
      final r = GroqChatProvider.decodeResponse(relayReply(content: 'Done.'));
      expect(r.text, 'Done.');
      expect(r.finishReason, LlmFinishReason.stop);
      expect(r.usage.inputTokens, 900);
    });

    test('tool calls', () {
      final r = GroqChatProvider.decodeResponse(relayReply(
        finish: 'tool_calls',
        toolCalls: [fnCall('a', 'record_transaction', '{"amount":"5"}'), fnCall('b', 'find_records', '{}')],
      ));
      expect(r.toolCalls.map((c) => c.id), ['a', 'b']);
      expect(r.toolCalls.first.arguments, '{"amount":"5"}');
      expect(r.finishReason, LlmFinishReason.toolCalls);
    });

    test('length cut-off', () {
      expect(GroqChatProvider.decodeResponse(relayReply(content: 'Par', finish: 'length')).finishReason,
          LlmFinishReason.length);
    });

    test('missing message or incomplete calls are invalid responses', () {
      expect(() => GroqChatProvider.decodeResponse({'id': 'x'}),
          throwsA(isA<LlmException>().having((e) => e.kind, 'kind', LlmErrorKind.invalidResponse)));
      expect(
        () => GroqChatProvider.decodeResponse(relayReply(toolCalls: [
          {'type': 'function', 'function': {'arguments': '{}'}},
        ])),
        throwsA(isA<LlmException>().having((e) => e.kind, 'kind', LlmErrorKind.invalidResponse)),
      );
    });
  });

  group('relay transport', () {
    test('posts to /agent/completions with the session token only', () async {
      late http.Request seen;
      final client = MockClient((req) async {
        seen = req;
        return ok(relayReply(toolCalls: [fnCall('c', 'get_financial_overview', '{}')], finish: 'tool_calls'));
      });
      final provider = GroqChatProvider(FinnRelayTransport(apiWith(client)));
      final r = await provider.complete(const LlmRequest(instructions: 'x', messages: [LlmMessage.user('hi')]));
      expect(seen.url.toString(), 'https://api.test/api/v1/agent/completions');
      expect(seen.headers['authorization'], 'Bearer token-1');
      expect(seen.body, isNot(contains('gsk_')));
      expect((jsonDecode(seen.body) as Map)['messages'], [
        {'role': 'system', 'content': 'x'},
        {'role': 'user', 'content': 'hi'},
      ]);
      expect(r.toolCalls.single.name, 'get_financial_overview');
    });

    http.Response failure(String code, String message, {bool retryable = false, Map<String, Object?>? details, int status = 503}) =>
        http.Response(
          jsonEncode({
            'error': {'code': code, 'message': message, 'retryable': retryable, 'details': ?details},
          }),
          status,
        );

    Future<LlmException> failureFor(http.Response response) async {
      final provider = GroqChatProvider(FinnRelayTransport(apiWith(MockClient((_) async => response))));
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

      final toolCallFailed = await failureFor(failure('unknown', 'The assistant made a malformed request. Please try again.',
          retryable: true, details: {'reason': 'toolCallFailed'}, status: 500));
      expect(toolCallFailed.kind, LlmErrorKind.invalidResponse);
      expect(toolCallFailed.retryable, isTrue);

      final timeout = await failureFor(failure('unavailable', 'Unavailable.', retryable: true, details: {'reason': 'timeout'}));
      expect(timeout.kind, LlmErrorKind.timeout);

      final tooLarge = await failureFor(failure('validation', 'This conversation is too long. Start a new chat.',
          details: {'reason': 'tooLarge'}, status: 422));
      expect(tooLarge.kind, LlmErrorKind.rejected);
      expect(tooLarge.message, contains('Start a new chat'));

      final outage = await failureFor(http.Response('gateway down', 502));
      expect(outage.kind, LlmErrorKind.unavailable);
    });

    test('cancellation abandons the request', () async {
      final client = MockClient((_) => Future.delayed(const Duration(milliseconds: 150), () => ok(relayReply(content: 'x'))));
      final provider = GroqChatProvider(FinnRelayTransport(apiWith(client)));
      final token = CancellationToken();
      final future = provider.complete(const LlmRequest(instructions: 'x', messages: [LlmMessage.user('hi')]), cancel: token);
      token.cancel();
      await expectLater(future, throwsA(isA<LlmException>().having((e) => e.kind, 'kind', LlmErrorKind.cancelled)));
    });
  });
}
