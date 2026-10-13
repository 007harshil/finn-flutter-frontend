import 'dart:convert';

import 'package:finn/actions/action.dart';
import 'package:finn/actions/action_registry.dart';
import 'package:finn/actions/dispatcher.dart';
import 'package:finn/agent/agent_config.dart';
import 'package:finn/agent/execution/plan_gateway.dart';
import 'package:finn/agent/execution/proposals.dart';
import 'package:finn/agent/history/agent_history.dart';
import 'package:finn/agent/llm/llm_provider.dart';
import 'package:finn/agent/orchestration/agent_runner.dart';
import 'package:finn/app/di/action_catalog.dart';
import 'package:finn/core/ids/id_generator.dart';
import 'package:finn/core/money/money.dart';
import 'package:finn/core/result/result.dart';
import 'package:finn/features/pending/application/pending_actions.dart';
import 'package:finn/features/pending/domain/pending_payment.dart';

import '../actions/action_harness.dart';

/// A model that replies from a script and records every request, so tests
/// drive the real agent without a network.
class ScriptedProvider implements LlmProvider {
  ScriptedProvider(List<Object> script) : _script = List.of(script);

  /// Each entry is an [LlmResponse], an [LlmException] to throw, or a
  /// function `LlmResponse Function(LlmRequest)`.
  final List<Object> _script;
  final List<LlmRequest> requests = [];

  @override
  String get name => 'scripted';

  int get remaining => _script.length;

  @override
  Future<LlmResponse> complete(LlmRequest request, {CancellationToken? cancel}) async {
    requests.add(request);
    if (_script.isEmpty) throw StateError('ScriptedProvider ran out of responses');
    final next = _script.removeAt(0);
    return switch (next) {
      LlmResponse() => next,
      LlmException() => throw next,
      LlmResponse Function(LlmRequest) f => f(request),
      _ => throw StateError('Bad script entry $next'),
    };
  }
}

/// The model's JSON plan reply.
LlmResponse plan(List<Map<String, Object?>> ops, {String? ask, String? reply}) => LlmResponse(
  text: jsonEncode({'ops': ops, 'ask': ?ask, 'reply': ?reply}),
  usage: const LlmUsage(inputTokens: 1600, cachedInputTokens: 1460, outputTokens: 40, calls: 1),
);

LlmResponse says(String text) => LlmResponse(text: text, usage: const LlmUsage(calls: 1));

/// Counts plan gateway calls (in remote mode, each is one FiNN API request).
class CountingGateway implements PlanGateway {
  CountingGateway(this.inner);
  final PlanGateway inner;
  int previews = 0;
  int executions = 0;
  final List<List<PlanStep>> previewed = [];
  final List<HistoryWrite?> histories = [];

  @override
  Future<List<StepPreview>> preview(String planId, List<PlanStep> steps) {
    previews++;
    previewed.add(steps);
    return inner.preview(planId, steps);
  }

  @override
  Future<List<StepResult>> execute(
    String planId,
    List<PlanStep> steps, {
    required Map<String, String> approved,
    HistoryWrite? history,
  }) {
    executions++;
    histories.add(history);
    return inner.execute(planId, steps, approved: approved, history: history);
  }
}

/// Wires the real runner onto an [ActionHarness] (local dispatcher,
/// in-memory data and history).
class AgentRig {
  AgentRig(this.harness, this.provider, {OperationDispatcher? dispatcher, AgentConfig config = const AgentConfig()}) {
    history = InMemoryAgentHistory();
    gateway = CountingGateway(
      DispatcherPlanGateway(dispatcher ?? harness.dispatcher, history: history, now: harness.clock.now),
    );
    runner = AgentRunner(
      provider: provider,
      gateway: gateway,
      registry: ActionRegistry(allActions),
      loadSnapshot: harness.snapshot,
      conversationId: 'c_test',
      now: harness.clock.now,
      history: history,
      ids: SequentialIdGenerator(),
      config: config,
    );
  }

  final ActionHarness harness;
  final ScriptedProvider provider;
  late final InMemoryAgentHistory history;
  late final CountingGateway gateway;
  late final AgentRunner runner;

  /// Proposals shown to the "user" in order.
  final List<List<ProposedAction>> approvals = [];

  Future<Set<String>> approveAll(List<ProposedAction> p) async {
    approvals.add(p);
    return {for (final x in p) x.id};
  }

  Future<Set<String>> declineAll(List<ProposedAction> p) async {
    approvals.add(p);
    return const {};
  }

  Future<AgentTurnResult> turn(String text, {ApprovalHandler? approve, CancellationToken? cancel}) =>
      runner.runTurn(text, approve: approve ?? approveAll, cancel: cancel);
}

/// Adds an open pending item through the real action.
Future<PendingPayment> addPending(
  ActionHarness h, {
  required String counterparty,
  required int rupees,
  PendingDirection direction = PendingDirection.owedToMe,
  String purpose = 'Dinner',
}) => h.run(
  const CreatePendingAction(),
  PendingInput(
    counterparty: counterparty,
    direction: direction,
    kind: PendingKind.sharedExpense,
    amount: Money.rupees(rupees),
    purpose: purpose,
    createdDate: DateTime(2026, 10, 1),
  ),
);

/// A dispatcher whose writes succeed but whose replies are lost (like a
/// dropped connection), while previews work normally. Counts attempts per
/// idempotency key.
class FlakyDispatcher extends OperationDispatcher {
  FlakyDispatcher(OperationDispatcher inner, {this.failures = 1, this.failActionId})
    : _inner = inner,
      super(environment: inner.environment);

  final OperationDispatcher _inner;
  int failures;

  /// Only writes of this action are affected (all when null).
  final String? failActionId;
  final Map<String, int> attemptsByKey = {};

  @override
  Future<Result<ActionPreview>> preview<I extends ActionInput, O>(
    FinancialAction<I, O> action,
    I input, {
    ActionChannel channel = ActionChannel.ui,
  }) => _inner.preview(action, input, channel: channel);

  @override
  Future<ActionOutcome<O>> dispatch<I extends ActionInput, O>(
    FinancialAction<I, O> action,
    I input, {
    required String idempotencyKey,
    ActionConfirmation? confirmation,
    ActionChannel channel = ActionChannel.ui,
  }) async {
    attemptsByKey[idempotencyKey] = (attemptsByKey[idempotencyKey] ?? 0) + 1;
    final out = await _inner.dispatch(
      action,
      input,
      idempotencyKey: idempotencyKey,
      confirmation: confirmation,
      channel: channel,
    );
    final affected = failActionId == null || failActionId == action.descriptor.id;
    if (affected && failures > 0 && out is ActionCompleted<O>) {
      failures--;
      return const ActionRejected(AppFailure.unavailable('Could not reach FiNN. Check your connection and try again.'));
    }
    return out;
  }
}

/// A dispatcher whose writes of [actionId] are refused by the "server".
class RefusingDispatcher extends OperationDispatcher {
  RefusingDispatcher(OperationDispatcher inner, this.actionId, this.failure)
    : _inner = inner,
      super(environment: inner.environment);

  final OperationDispatcher _inner;
  final String actionId;
  final AppFailure failure;

  @override
  Future<Result<ActionPreview>> preview<I extends ActionInput, O>(
    FinancialAction<I, O> action,
    I input, {
    ActionChannel channel = ActionChannel.ui,
  }) => _inner.preview(action, input, channel: channel);

  @override
  Future<ActionOutcome<O>> dispatch<I extends ActionInput, O>(
    FinancialAction<I, O> action,
    I input, {
    required String idempotencyKey,
    ActionConfirmation? confirmation,
    ActionChannel channel = ActionChannel.ui,
  }) async {
    if (action.descriptor.id == actionId) return ActionRejected(failure);
    return _inner.dispatch(action, input, idempotencyKey: idempotencyKey, confirmation: confirmation, channel: channel);
  }
}
