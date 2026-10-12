import 'dart:convert';
import 'dart:io';
import 'package:finn/agent/llm/groq/groq_chat_provider.dart';
import 'package:finn/agent/llm/llm_provider.dart';
import 'package:finn/agent/llm/llm_transport.dart';
import 'package:finn/agent/orchestration/agent_runner.dart';
import 'package:finn/agent/orchestration/conversation.dart';
import 'package:finn/core/money/money.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import '../actions/action_harness.dart';
import '../agent/agent_fakes.dart';

/// Test-only stand-in for the relay: adds model + key like the server does.
class DirectGroq implements LlmTransport {
  DirectGroq(this.key, this.model);
  final String key, model;
  int calls = 0;
  @override
  Future<Map<String, Object?>> post(Map<String, Object?> body) async {
    calls++;
    final res = await http.post(Uri.parse('https://api.groq.com/openai/v1/chat/completions'),
        headers: {'authorization': 'Bearer $key', 'content-type': 'application/json'},
        body: jsonEncode({'model': model, ...body, 'reasoning_effort': 'low'}));
    final j = jsonDecode(res.body) as Map<String, Object?>;
    if (res.statusCode == 429) {
      final after = int.tryParse(res.headers['retry-after'] ?? '');
      // ignore: avoid_print
      print('429 retry-after=${res.headers['retry-after']} remaining=${res.headers['x-ratelimit-remaining-tokens']} reset=${res.headers['x-ratelimit-reset-tokens']}');
      throw LlmException(LlmErrorKind.rateLimited, 'rate limited', retryable: true,
          retryAfter: after == null ? null : Duration(seconds: after));
    }
    if (res.statusCode != 200) throw LlmException(LlmErrorKind.rejected, 'HTTP ${res.statusCode}: ${(j['error'] as Map?)?['message']}');
    final c = (j['choices'] as List).first as Map;
    return {'id': j['id'], 'finish_reason': c['finish_reason'], 'message': c['message'], 'usage': j['usage']};
  }
}

void main() {
  test('live multi-task loop on Groq', () async {
    final env = {for (final l in File('../finn-backend/.env.local').readAsLinesSync()) if (l.contains('=') && !l.startsWith('#')) l.substring(0, l.indexOf('=')): l.substring(l.indexOf('=') + 1)};
    final h = await ActionHarness.create();
    final rahul = await addPending(h, counterparty: 'Rahul', rupees: 2000);
    final transport = DirectGroq(env['GROQ_API_KEY']!, env['GROQ_MODEL'] ?? 'openai/gpt-oss-20b');
    final rig = AgentRig(h, ScriptedProvider([]));
    final runner = AgentRunner(
      provider: GroqChatProvider(transport),
      executor: rig.executor,
      toolbox: rig.toolbox,
      loadSnapshot: h.snapshot,
      conversation: Conversation(id: 'live'),
      selection: rig.selection,
    );
    final result = await runner.runTurn('Rahul paid back the 2000 he owed me and I spent 300 on an auto today',
        approve: rig.approveAll);
    // ignore: avoid_print
    print('REPLY: ${result.reply}\nEND: ${result.end}\nMODEL CALLS: ${transport.calls}\nAPPROVAL CARDS: ${rig.approvals.length} '
        '(${rig.approvals.expand((p) => p).map((p) => p.preview.summary).join(' | ')})\n'
        'ACTIONS: ${result.actions.map((a) => '${a.summary}=${a.status.name}').join(', ')}\nTOKENS: ${result.usage.inputTokens}/${result.usage.outputTokens}');
    for (final m in runner.conversation.messages) {
      final c = (m.content ?? '').replaceAll(RegExp(r'\s+'), ' ');
      // ignore: avoid_print
      print('MSG ${m.role.name}${m.toolName == null ? '' : '(${m.toolName})'}: ${c.length > 220 ? c.substring(0, 220) : c} ${m.toolCalls.map((t) => '${t.name}${t.arguments}').join(' ')}');
    }
    final s = await h.snapshot();
    // ignore: avoid_print
    print('RAHUL OUTSTANDING: ${s.pendingView(rahul.id)!.outstanding.toDecimalString()}  TX: ${s.transactions.map((t) => '${t.categoryId}:${t.amount.toDecimalString()}').join(', ')}');
    expect(runner, isNotNull);
    expect(s.pendingView(rahul.id)!.outstanding, Money.zero);
  }, timeout: const Timeout(Duration(minutes: 3)));
}

