import 'dart:convert';

import 'package:finn/actions/action.dart';
import 'package:finn/actions/action_registry.dart';
import 'package:finn/actions/dispatcher.dart';
import 'package:finn/agent/agent_config.dart';
import 'package:finn/agent/execution/proposals.dart';
import 'package:finn/agent/execution/tool_executor.dart';
import 'package:finn/agent/llm/llm_provider.dart';
import 'package:finn/agent/orchestration/agent_runner.dart';
import 'package:finn/agent/orchestration/conversation.dart';
import 'package:finn/agent/tools/agent_tool.dart';
import 'package:finn/agent/tools/tool_catalog.dart';
import 'package:finn/agent/tools/tool_groups.dart';
import 'package:finn/app/di/action_catalog.dart';
import 'package:finn/core/money/money.dart';
import 'package:finn/core/result/result.dart';
import 'package:finn/features/pending/application/pending_actions.dart';
import 'package:finn/features/pending/domain/pending_payment.dart';

import '../actions/action_harness.dart';

/// A model that replies from a script and records every request, so tests
/// drive the real agent loop without a network.
class ScriptedProvider implements LlmProvider {
  ScriptedProvider(List<Object> script) : _script = List.of(script);

  /// Each entry is an [LlmResponse], an [LlmException] to throw, or a
  /// function `LlmResponse Function(LlmRequest)` for replies that depend on
  /// earlier tool results.
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

int _callSeq = 0;

LlmToolCall toolCall(String name, Map<String, Object?> args, {String? id}) =>
    LlmToolCall(id: id ?? 'call_${_callSeq++}', name: name, arguments: jsonEncode(args));

LlmResponse callsTools(List<LlmToolCall> calls) => LlmResponse(toolCalls: calls, finishReason: LlmFinishReason.toolCalls);

LlmResponse says(String text) => LlmResponse(text: text);

/// Decoded tool results the model received in [request], keyed by call id.
Map<String, Map<String, Object?>> toolResultsIn(LlmRequest request) => {
      for (final m in request.messages)
        if (m.role == LlmRole.tool) m.toolCallId!: Map<String, Object?>.from(jsonDecode(m.content!) as Map),
    };

/// Wires the real toolbox, executor and runner onto an [ActionHarness]
/// (local dispatcher, in-memory data).
class AgentRig {
  AgentRig(this.harness, this.provider, {OperationDispatcher? dispatcher, AgentConfig config = const AgentConfig()}) {
    final registry = ActionRegistry(allActions);
    toolbox = AgentToolbox.standard(registry);
    executor = ToolExecutor(
      toolbox: toolbox,
      dispatcher: dispatcher ?? harness.dispatcher,
      context: ToolContext(loadSnapshot: harness.snapshot, selection: selection),
      sessionId: 'c1',
      maxCallsPerStep: config.maxToolCallsPerStep,
    );
    runner = AgentRunner(
      provider: provider,
      executor: executor,
      toolbox: toolbox,
      loadSnapshot: harness.snapshot,
      conversation: Conversation(id: 'c1'),
      selection: selection,
      config: config,
    );
  }

  final ToolSelection selection = ToolSelection();

  final ActionHarness harness;
  final ScriptedProvider provider;
  late final AgentToolbox toolbox;
  late final ToolExecutor executor;
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
}) =>
    h.run(
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

/// A dispatcher whose writes fail like a dropped connection, while
/// previews work normally. Counts write attempts per idempotency key.
class FlakyDispatcher extends OperationDispatcher {
  FlakyDispatcher(OperationDispatcher inner, {this.failures = 1})
      : _inner = inner,
        super(environment: inner.environment);

  final OperationDispatcher _inner;
  int failures;
  final Map<String, int> attemptsByKey = {};

  @override
  Future<ActionOutcome<O>> dispatch<I extends ActionInput, O>(
    FinancialAction<I, O> action,
    I input, {
    required String idempotencyKey,
    ActionConfirmation? confirmation,
    ActionChannel channel = ActionChannel.ui,
  }) async {
    attemptsByKey[idempotencyKey] = (attemptsByKey[idempotencyKey] ?? 0) + 1;
    final out = await _inner.dispatch(action, input,
        idempotencyKey: idempotencyKey, confirmation: confirmation, channel: channel);
    if (failures > 0 && out is ActionCompleted<O>) {
      // The write happened, but the reply was lost.
      failures--;
      return const ActionRejected(AppFailure.unavailable('Could not reach FiNN. Check your connection and try again.'));
    }
    return out;
  }
}
