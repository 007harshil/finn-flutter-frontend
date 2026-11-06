// Live, model-graded run of the golden eval set (test/agent/evals). Fails
// when any kind of case falls below its pass-rate threshold, so a prompt or
// model change cannot ship a regression unnoticed.
//
// FINN_LIVE=1 flutter test test/agent/live/golden_eval_test.dart
// (OPENAI_API_KEY from the environment, else ../finn-backend/.env.local).
// Writes docs/agent-benchmarks/golden_eval.json.

import 'dart:io';

import 'package:finn/actions/action_registry.dart';
import 'package:finn/agent/answers/data_answers.dart';
import 'package:finn/agent/execution/plan_gateway.dart';
import 'package:finn/agent/execution/proposals.dart';
import 'package:finn/agent/history/agent_history.dart';
import 'package:finn/agent/llm/chat_completions_provider.dart';
import 'package:finn/agent/orchestration/agent_runner.dart';
import 'package:finn/agent/orchestration/agent_trace.dart';
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

      // Ground truth for data questions, from the scenario data itself.
      final snapshot = await h.snapshot();
      final truths = [for (final args in answerArgs(c)) DataAnswers.answer(args, snapshot, snapshot.today)];

      final saved = <({String actionId, Map<String, Object?> input})>[];
      AgentTurnResult? last;
      final turnTraces = <Map<String, Object?>>[];
      for (final t in c.turns) {
        last = await runner.runTurn(t, approve: approveAll);
        final trace = runner.lastTrace;
        turnTraces.add({
          'agentMs': trace.agentTime / 1000,
          'untilReviewMs': ?trace.untilReview == null ? null : trace.untilReview! / 1000,
          'stagesMs': {for (final e in trace.totals.entries) if (e.key != AgentTrace.approval) e.key: e.value / 1000},
          'facts': trace.facts,
        });
        for (final a in last.actions.where((a) => a.succeeded)) {
          saved.add((actionId: a.proposal.descriptor.id, input: a.proposal.input.toJson()));
        }
      }
      final failure = grade(c, GoldenRun(saved, last!, transport.calls.length), truths: truths);
      total[c.kind] = (total[c.kind] ?? 0) + 1;
      if (failure == null) passed[c.kind] = (passed[c.kind] ?? 0) + 1;
      cost += costOf(transport.calls);
      rows.add({
        'id': c.id,
        'kind': c.kind,
        'pass': failure == null,
        'failure': ?failure,
        'llmCalls': transport.calls.length,
        'modelMs': [for (final m in transport.calls) m.ms],
        'turns': turnTraces,
        'reply': last.reply,
        'saved': [for (final o in saved) '${o.actionId} ${o.input}'],
        if (truths.isNotEmpty) 'truth': truths,
      });
      // ignore: avoid_print
      print('${failure == null ? 'PASS' : 'FAIL'} ${c.kind}/${c.id}${failure == null ? '' : ': $failure\n  reply: ${last.reply}'}');
    }
    if (only != null) return;

    final rates = {for (final k in total.keys) k: (passed[k] ?? 0) / total[k]!};
    writeReport(Platform.environment['FINN_GOLDEN_REPORT'] ?? 'golden_eval', {
      'promptVersion': agentPromptVersion,
      'date': DateTime.now().toIso8601String().substring(0, 10),
      'passRates': rates,
      'thresholds': set.thresholds,
      'costUsd': cost,
      'latency': _latencySummary(rows),
      'cases': rows,
    });
    // ignore: avoid_print
    print('pass rates $rates (thresholds ${set.thresholds}), cost \$${cost.toStringAsFixed(4)}');
    for (final e in set.thresholds.entries) {
      expect(rates[e.key] ?? 0, greaterThanOrEqualTo(e.value), reason: '${e.key} pass rate below ${e.value}');
    }
  }, skip: liveSkipReason, timeout: const Timeout(Duration(minutes: 30)));
}

/// Median and p90 per stage over every turn, in milliseconds.
Map<String, Object?> _latencySummary(List<Map<String, Object?>> rows) {
  final byStage = <String, List<double>>{};
  final agent = <double>[];
  final review = <double>[];
  for (final row in rows) {
    for (final t in (row['turns']! as List).cast<Map<String, Object?>>()) {
      agent.add(t['agentMs']! as double);
      if (t['untilReviewMs'] case final double r) review.add(r);
      for (final e in (t['stagesMs']! as Map<String, double>).entries) {
        (byStage[e.key] ??= []).add(e.value);
      }
    }
  }
  Map<String, double> stats(List<double> v) {
    final s = [...v]..sort();
    double at(double q) => s.isEmpty ? 0 : s[((s.length - 1) * q).round()];
    return {'p50': at(0.5), 'p90': at(0.9), 'max': s.isEmpty ? 0 : s.last, 'n': s.length.toDouble()};
  }

  return {
    'agentMs': stats(agent),
    'untilReviewMs': stats(review),
    'stagesMs': {for (final e in byStage.entries) e.key: stats(e.value)},
  };
}
