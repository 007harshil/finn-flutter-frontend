// Live benchmark of the single-plan agent on the same scenarios as the
// baseline. FINN_LIVE=1 flutter test test/agent/live/plan_benchmark_test.dart

import 'package:finn/actions/action_registry.dart';
import 'package:finn/agent/execution/plan_gateway.dart';
import 'package:finn/agent/execution/proposals.dart';
import 'package:finn/agent/history/agent_history.dart';
import 'package:finn/agent/llm/chat_completions_provider.dart';
import 'package:finn/agent/orchestration/agent_runner.dart';
import 'package:finn/app/di/action_catalog.dart';
import 'package:finn/data/local/local_data_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../actions/action_harness.dart';
import 'live_support.dart';

/// Counts what would be FiNN API requests in remote mode: one
/// `POST /plans/preview` and one `POST /plans/execute` per wave, plus the one
/// sync the remote gateway starts after each execution.
class CountingGateway implements PlanGateway {
  CountingGateway(this.inner);
  final PlanGateway inner;
  int requests = 0;

  @override
  Future<List<StepPreview>> preview(String planId, List<PlanStep> steps) {
    requests++;
    return inner.preview(planId, steps);
  }

  @override
  Future<List<StepResult>> execute(String planId, List<PlanStep> steps,
      {required Map<String, String> approved, HistoryWrite? history}) {
    requests += 2;
    return inner.execute(planId, steps, approved: approved, history: history);
  }
}

/// Extra turns the baseline could not handle without the model.
final extra = <Scenario>[
  Scenario('history_question', ['spent 450 on lunch', 'what did I ask you to do today?'], [
    const Expect('transactions.create', {'type': 'expense', 'amount': 450, 'categoryId': 'cat_food'}),
  ]),
  Scenario('balance_question', ["what's my balance?"], const [], answerContains: 'available'),
  Scenario('ambiguous_then_choice', ['I paid Rahul back', 'the concert one'], [
    const Expect('pending.settle', {'pendingId': 'pend_seed_294', 'amount': 2000}),
  ]),
  Scenario('missing_then_amount', ['I bought groceries today', '350'], [
    const Expect('transactions.create', {'type': 'expense', 'amount': 350, 'categoryId': 'cat_groceries', 'date': '2026-10-10'}),
  ]),
];

void main() {
  test('single-plan agent on gpt-6-luna', () async {
    final rows = <Map<String, Object?>>[];
    for (final s in [...scenarios, ...extra]) {
      final h = await ActionHarness.create(scenario: DataScenario.demo);
      final transport = OpenAiLiveTransport();
      final history = InMemoryAgentHistory();
      final gateway = CountingGateway(DispatcherPlanGateway(h.dispatcher, history: history, now: h.clock.now));
      final runner = AgentRunner(
        provider: ChatCompletionsProvider(transport),
        gateway: gateway,
        registry: ActionRegistry(allActions),
        loadSnapshot: h.snapshot,
        conversationId: 'c_bench',
        now: h.clock.now,
        history: history,
      );
      Future<Set<String>> approveAll(List<ProposedAction> p) async => {for (final x in p) x.id};

      final saved = <SavedOp>[];
      var reply = '';
      final started = DateTime.now();
      for (final text in s.turns) {
        final r = await runner.runTurn(text, approve: approveAll);
        reply = r.reply;
        for (final a in r.actions.where((a) => a.succeeded)) {
          saved.add((actionId: a.proposal.descriptor.id, input: a.proposal.input.toJson()));
        }
      }
      final wall = DateTime.now().difference(started).inMilliseconds;
      final pass = s.expectQuestion
          ? saved.isEmpty && reply.contains('?')
          : s.answerContains != null
          ? saved.isEmpty && reply.contains(s.answerContains!)
          : opsMatch(saved, s.expected) && (s.id != 'history_question' || reply.contains('spent 450 on lunch'));
      final calls = transport.calls;
      int sum(int Function(CallMetric c) f) => calls.fold<int>(0, (a, c) => a + f(c));
      rows.add({
        'scenario': s.id,
        'pass': pass,
        'llmCalls': calls.length,
        'input': sum((c) => c.input),
        'cached': sum((c) => c.cached),
        'cacheWrite': sum((c) => c.cacheWrite),
        'output': sum((c) => c.output),
        'reasoning': sum((c) => c.reasoning),
        'llmMs': sum((c) => c.ms),
        'wallMs': wall,
        'backendRequests': gateway.requests,
        'costUsd': costOf(calls),
        'reply': reply,
        'saved': [for (final o in saved) '${o.actionId} ${o.input}'],
        'calls': [for (final c in calls) c.toJson()],
      });
      // ignore: avoid_print
      print('${s.id}: pass=$pass calls=${calls.length} in=${rows.last['input']} cached=${rows.last['cached']} '
          'out=${rows.last['output']} llmMs=${rows.last['llmMs']} backend=${rows.last['backendRequests']}\n  $reply');
    }
    writeReport('single_plan', {
      'model': 'gpt-6-luna',
      'reasoningEffort': 'none',
      'promptCache': 'explicit (relay breakpoint after the system message)',
      'date': '2026-10-13',
      'scenarios': rows,
    });
  }, skip: liveSkipReason, timeout: const Timeout(Duration(minutes: 15)));
}
