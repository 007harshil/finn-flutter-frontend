import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../actions/action.dart';
import '../../actions/dispatcher.dart';
import '../../core/result/result.dart';
import '../llm/llm_provider.dart';
import '../orchestration/agent_events.dart';
import '../tools/agent_tool.dart';
import '../tools/json_schema.dart';
import '../tools/tool_catalog.dart';
import 'proposals.dart';

/// Asks the user to approve [proposals]; completes with the approved ids.
/// Completing with an empty set declines everything.
typedef ApprovalHandler = Future<Set<String>> Function(List<ProposedAction> proposals);

/// Tool results of one model step, in call order. Always one result per
/// call (even when refused or cancelled) so the conversation stays well
/// formed.
class StepExecution {
  const StepExecution(this.results);
  final List<LlmMessage> results;
}

/// Turns model tool calls into application operations.
///
/// The model's output is never trusted:
/// * unknown tools, malformed JSON and non-object arguments are rejected;
/// * arguments are pruned to the tool's schema, then decoded and validated
///   by the action itself, then previewed by the dispatcher (the same
///   preview the app's forms use) on fresh data;
/// * actions are only *queued* while the model works. When it has finished
///   planning, [settleQueue] shows every queued preview on one review card
///   and runs the approved ones through [OperationDispatcher] on the
///   `agent` channel, which enforces policy (no deletes), confirmation
///   fingerprints and idempotency (in remote mode on the FiNN API).
///
/// Duplicate protection: the idempotency key is derived from the request
/// itself (`conversation : request fingerprint : occurrence`). Repeating a
/// request whose outcome was unknown reuses its key, so the backend replays
/// instead of writing twice. Identical requests inside one turn are queued
/// once. Mutations are never retried automatically.
class ToolExecutor {
  ToolExecutor({
    required this.toolbox,
    required this.dispatcher,
    required this.context,
    required this.sessionId,
    this.channel = ActionChannel.agent,
    this.maxCallsPerStep = 8,
  });

  final AgentToolbox toolbox;
  final OperationDispatcher dispatcher;
  final ToolContext context;

  /// Stable id of the conversation; part of every idempotency key.
  final String sessionId;
  final ActionChannel channel;

  /// Calls beyond this in one model step are refused (runaway protection).
  final int maxCallsPerStep;

  /// Completed requests in this conversation: fingerprint → count.
  final Map<String, int> _completed = {};

  /// Requests completed during the current turn.
  final Set<String> _doneThisTurn = {};

  /// Proposals waiting for the end-of-plan review.
  final List<ProposedAction> _queue = [];

  int _proposalSeq = 0;

  bool get hasQueued => _queue.isNotEmpty;

  List<ProposedAction> get queued => List.unmodifiable(_queue);

  /// Call at the start of every user turn.
  void beginTurn() {
    _doneThisTurn.clear();
    _queue.clear();
  }

  Future<StepExecution> executeStep(
    List<LlmToolCall> calls, {
    void Function(AgentEvent event)? onEvent,
    CancellationToken? cancel,
    int? limit,
  }) async {
    final allowed = limit == null || limit > maxCallsPerStep ? maxCallsPerStep : limit;
    final results = <ToolResult>[];

    for (var i = 0; i < calls.length; i++) {
      final call = calls[i];
      if (cancel?.isCancelled ?? false) {
        results.add(ToolResult.error('cancelled', 'The user stopped the request.'));
      } else if (i >= allowed) {
        results.add(ToolResult.error(
            'tooManyCalls', 'The tool call limit for this request was reached, so this call was not run.',
            hint: 'Tell the user what is still outstanding.'));
      } else {
        results.add(await _handle(call, onEvent));
      }
    }
    return StepExecution([
      for (var i = 0; i < calls.length; i++)
        LlmMessage.toolResult(callId: calls[i].id, toolName: calls[i].name, content: results[i].encode()),
    ]);
  }

  Future<ToolResult> _handle(LlmToolCall call, void Function(AgentEvent event)? onEvent) async {
    final tool = toolbox.lookup(call.name);
    if (tool == null) {
      return ToolResult.error('unknownTool', 'There is no tool named "${call.name}".',
          hint: 'Use only the tools provided. If the user asks for something unsupported, say so.');
    }
    final args = _parseArguments(call.arguments);
    if (args == null) {
      return ToolResult.error('invalidArguments', 'Arguments must be a JSON object.',
          hint: 'Call the tool again with valid JSON matching its schema.');
    }
    final pruned = JsonSchema.prune(args, tool.parameters)! as Map<String, Object?>;
    onEvent?.call(AgentToolStarted(tool.name, tool.progressLabel));
    return switch (tool) {
      ReadTool() => _runRead(tool, pruned),
      ActionTool() => _propose(tool, call, pruned),
    };
  }

  static Map<String, Object?>? _parseArguments(String raw) {
    final text = raw.trim().isEmpty ? '{}' : raw;
    try {
      final decoded = jsonDecode(text);
      return decoded is Map ? Map<String, Object?>.from(decoded) : null;
    } on FormatException {
      return null;
    }
  }

  Future<ToolResult> _runRead(ReadTool tool, Map<String, Object?> args) async {
    try {
      return ToolResult.data(await tool.run(args, context));
    } on AppFailure catch (f) {
      return ToolResult.failure(f);
    } catch (e, st) {
      debugPrint('Agent read tool ${tool.name} failed: $e\n$st');
      return ToolResult.error('unavailable', 'The lookup failed. Your data could not be read right now.');
    }
  }

  static const _distinctHint =
      'If the user really asked for two separate identical entries, add a note that tells them apart and call again.';

  Future<ToolResult> _propose(ActionTool tool, LlmToolCall call, Map<String, Object?> args) async {
    final ActionInput input;
    try {
      input = tool.action.decode(args);
    } on AppFailure catch (f) {
      return ToolResult.failure(f, hint: 'Fix the arguments and call the tool again.');
    } catch (e) {
      // Wrong-typed values can fail inside a decoder with a non-AppFailure.
      debugPrint('Agent could not decode ${tool.name} arguments: $e');
      return ToolResult.error('invalidArguments', 'The arguments do not match the tool schema.',
          hint: 'Check each field type against the schema and call the tool again.');
    }

    final fingerprint = fingerprintOf(tool.descriptor.id, input);
    for (final p in _queue) {
      if (fingerprintOf(p.descriptor.id, p.input) == fingerprint) {
        return ToolResult.data({
          'status': 'duplicateCall',
          'proposalId': p.id,
          'message': 'Identical to an action already queued; it will be reviewed once.',
          'hint': _distinctHint,
        });
      }
    }
    if (_doneThisTurn.contains(fingerprint)) {
      return ToolResult.data({
        'status': 'alreadyHandled',
        'message': 'This exact operation was already completed in this request. It was not repeated.',
        'hint': _distinctHint,
      });
    }

    final Result<ActionPreview> previewed;
    try {
      previewed = await dispatcher.preview<ActionInput, Object?>(tool.action, input, channel: channel);
    } catch (e) {
      debugPrint('Agent preview of ${tool.name} failed: $e');
      return ToolResult.error('unavailable', 'This could not be checked right now. Nothing was changed.');
    }
    switch (previewed) {
      case Err(:final failure):
        return ToolResult.failure(failure,
            hint: failure.code == FailureCode.validation ? 'Fix the arguments or ask the user.' : null);
      case Ok(:final value):
        final occurrence = _completed[fingerprint] ?? 0;
        final proposal = ProposedAction(
          id: 'p${++_proposalSeq}',
          toolCallId: call.id,
          tool: tool,
          input: input,
          preview: value,
          idempotencyKey: 'agent:$sessionId:$fingerprint:$occurrence',
          notes: [
            if (occurrence > 0)
              'You already recorded an identical entry earlier in this chat. Approve only if this is a separate one.',
          ],
        );
        _queue.add(proposal);
        return ToolResult.data({
          'status': 'queuedForApproval',
          'proposalId': proposal.id,
          'summary': value.summary,
          'message': 'Valid and queued. The user reviews all queued actions together after your reply; it is NOT '
              'done yet. If another action needs this record\'s id, finish your reply and wait for the outcome.',
        });
    }
  }

  /// Shows every queued proposal for approval, runs the approved ones and
  /// returns the confirmed outcome of each. Empties the queue.
  Future<List<ActionRecord>> settleQueue({
    required ApprovalHandler approve,
    void Function(AgentEvent event)? onEvent,
    CancellationToken? cancel,
  }) async {
    if (_queue.isEmpty) return const [];
    final proposals = List<ProposedAction>.unmodifiable(_queue);
    _queue.clear();
    onEvent?.call(AgentAwaitingApproval(proposals));

    Set<String> approved;
    try {
      approved = cancel == null ? await approve(proposals) : await cancel.guard(approve(proposals));
    } on LlmException {
      approved = const {}; // stopped while waiting: nothing runs
    }
    final toRun = proposals.where((p) => approved.contains(p.id)).length;
    if (toRun > 0) onEvent?.call(AgentExecuting(toRun));

    final records = <ActionRecord>[];
    for (final p in proposals) {
      if (approved.contains(p.id)) {
        // Deliberately not cancellable: once approved and sent, the outcome
        // must be recorded truthfully.
        records.add(await _execute(p));
      } else {
        records.add(ActionRecord(
          proposal: p,
          status: (cancel?.isCancelled ?? false) ? ActionResultStatus.cancelled : ActionResultStatus.declined,
        ));
      }
    }
    onEvent?.call(AgentActionsSettled(List.unmodifiable(records)));
    return records;
  }

  Future<ActionRecord> _execute(ProposedAction p) async {
    final ActionOutcome<Object?> outcome;
    try {
      outcome = await dispatcher.dispatch<ActionInput, Object?>(
        p.tool.action,
        p.input,
        idempotencyKey: p.idempotencyKey,
        confirmation: ActionConfirmation(p.preview.fingerprint, confirmedBy: 'user:agent'),
        channel: channel,
      );
    } catch (e) {
      debugPrint('Agent action ${p.descriptor.id} threw: $e');
      return ActionRecord(
          proposal: p, status: ActionResultStatus.failed, message: 'Something went wrong.', outcomeUnknown: true);
    }
    switch (outcome) {
      case ActionCompleted(:final value, :final replayed):
        final fp = fingerprintOf(p.descriptor.id, p.input);
        _completed[fp] = (_completed[fp] ?? 0) + 1;
        _doneThisTurn.add(fp);
        return ActionRecord(
          proposal: p,
          status: replayed ? ActionResultStatus.alreadyDone : ActionResultStatus.completed,
          message: replayed ? 'This had already been recorded; it was not added twice.' : null,
          recordId: _recordId(value),
        );
      case ActionNeedsConfirmation():
        return ActionRecord(
          proposal: p,
          status: ActionResultStatus.needsReapproval,
          message: 'The details changed after you reviewed them, so nothing was changed.',
        );
      case ActionRejected(:final failure):
        return ActionRecord(
          proposal: p,
          status: ActionResultStatus.failed,
          message: failure.message,
          outcomeUnknown: failure.code == FailureCode.unavailable || failure.code == FailureCode.unknown,
        );
    }
  }

  /// Id(s) of the record an action created or changed, for follow-ups.
  static Object? _recordId(Object? value) {
    if (value == null) return null;
    if (value is List) return [for (final v in value) _recordId(v)];
    try {
      final dynamic d = value;
      final Object? id = d.id;
      return id;
    } catch (_) {
      return null;
    }
  }
}

/// The message that tells the model what happened to its proposals. Sent
/// as an app-authored user message because the original tool calls were
/// already answered with "queued".
String outcomesMessage(List<ActionRecord> records) {
  final items = [
    for (final r in records)
      {
        'proposalId': r.proposal.id,
        'summary': r.summary,
        'status': switch (r.status) {
          ActionResultStatus.failed when r.outcomeUnknown => 'outcomeUnknown',
          final s => s.name,
        },
        'message': ?r.message,
        'recordId': ?r.recordId,
      },
  ];
  return '[FiNN app message, not typed by the user] Outcome of the actions you proposed: ${jsonEncode(items)}\n'
      'Tell the user the result of each in one short line. "completed" and "alreadyDone" mean saved; anything else '
      'means not saved. Do not retry failed or unknown ones on your own. Propose follow-up actions only if they were '
      'waiting for these results.';
}
