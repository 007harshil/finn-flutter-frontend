// Live, model-graded run of the golden eval set (test/agent/evals). Fails
// when any kind of case falls below its pass-rate threshold, so a prompt or
// model change cannot ship a regression unnoticed.
//
// FINN_LIVE=1 flutter test test/agent/live/golden_eval_test.dart
// (OPENAI_API_KEY from the environment, else ../finn-backend/.env.local).
// Writes docs/agent-benchmarks/golden_eval.json.

import 'dart:io';

import 'package:finn/actions/action_registry.dart';
import 'package:finn/agent/execution/plan_gateway.dart';
import 'package:finn/agent/execution/proposals.dart';
import 'package:finn/agent/history/agent_history.dart';
import 'package:finn/agent/llm/chat_completions_provider.dart';
import 'package:finn/agent/orchestration/agent_runner.dart';
import 'package:finn/agent/prompt/agent_prompt.dart';
import 'package:finn/app/di/action_catalog.dart';
import 'package:finn/data/local/local_data_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../actions/action_harness.dart';
import '../evals/golden.dart';
import 'live_support.dart';

void main() {
  test('golden eval set on the live model', () async {
    final set = GoldenSet.load();
    // FINN_GOLDEN_ONLY=id1,id2 runs only those cases (debugging; thresholds
    // are then not enforced).
    final only = Platform.environment['FINN_GOLDEN_ONLY']?.split(',').map((s) => s.trim()).toSet();
    final cases = only == null ? set.cases : set.cases.where((c) => only.contains(c.id)).toList();
    final rows = <Map<String, Object?>>[];
    final passed = <String, int>{};
    final total = <String, int>{};
    var cost = 0.0;
    for (final c in cases) {
      final h = await ActionHarness.create(scenario: DataScenario.demo);
      final transport = OpenAiLiveTransport();
      final runner = AgentRunner(
        provider: ChatCompletionsProvider(transport),
        gateway: DispatcherPlanGateway(h.dispatcher, history: InMemoryAgentHistory(), now: h.clock.now),
        registry: ActionRegistry(allActions),
        loadSnapshot: h.snapshot,
        conversationId: 'c_golden',
        now: h.clock.now,
      );
      Future<Set<String>> approveAll(List<ProposedAction> p) async => {for (final x in p) x.id};

      final saved = <({String actionId, Map<String, Object?> input})>[];
      AgentTurnResult? last;
      for (final t in c.turns) {
        last = await runner.runTurn(t, approve: approveAll);
        for (final a in last.actions.where((a) => a.succeeded)) {
          saved.add((actionId: a.proposal.descriptor.id, input: a.proposal.input.toJson()));
        }
      }
      final failure = grade(c, GoldenRun(saved, last!, transport.calls.length));
      total[c.kind] = (total[c.kind] ?? 0) + 1;
      if (failure == null) passed[c.kind] = (passed[c.kind] ?? 0) + 1;
      cost += costOf(transport.calls);
      rows.add({
        'id': c.id,
        'kind': c.kind,
        'pass': failure == null,
        'failure': ?failure,
        'llmCalls': transport.calls.length,
        'reply': last.reply,
        'saved': [for (final o in saved) '${o.actionId} ${o.input}'],
      });
      // ignore: avoid_print
      print('${failure == null ? 'PASS' : 'FAIL'} ${c.kind}/${c.id}${failure == null ? '' : ': $failure\n  reply: ${last.reply}'}');
    }
    if (only != null) return;

    final rates = {for (final k in total.keys) k: (passed[k] ?? 0) / total[k]!};
    writeReport('golden_eval', {
      'promptVersion': agentPromptVersion,
      'date': DateTime.now().toIso8601String().substring(0, 10),
      'passRates': rates,
      'thresholds': set.thresholds,
      'costUsd': cost,
      'cases': rows,
    });
    // ignore: avoid_print
    print('pass rates $rates (thresholds ${set.thresholds}), cost \$${cost.toStringAsFixed(4)}');
    for (final e in set.thresholds.entries) {
      expect(rates[e.key] ?? 0, greaterThanOrEqualTo(e.value), reason: '${e.key} pass rate below ${e.value}');
    }
  }, skip: liveSkipReason, timeout: const Timeout(Duration(minutes: 30)));
}
