import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../finance/finance_snapshot.dart';
import '../agent_config.dart';
import '../execution/proposals.dart';
import '../execution/tool_executor.dart';
import '../llm/llm_provider.dart';
import '../prompt/system_prompt.dart';
import '../tools/tool_catalog.dart';
import '../tools/tool_groups.dart';
import 'agent_events.dart';
import 'conversation.dart';

enum AgentTurnEnd {
  /// The model gave its final reply.
  completed,

  /// The tool-loop limit was reached; the reply summarises what happened.
  limitReached,

  /// The user stopped the turn.
  cancelled,

  /// The model could not be reached or answered unusably.
  failed,
}

/// Outcome of one user turn.
@immutable
class AgentTurnResult {
  const AgentTurnResult({
    required this.end,
    required this.reply,
    this.actions = const [],
    this.error,
    this.usage = const LlmUsage(),
  });

  final AgentTurnEnd end;

  /// Text to show the user. For failures, a safe explanation.
  final String reply;

  /// Every action proposed in this turn and its confirmed outcome.
  final List<ActionRecord> actions;
  final LlmException? error;
  final LlmUsage usage;
}

/// The agent loop.
///
/// 1. Model ↔ tools until the model stops calling tools. Lookups run at
///    once; actions are validated, previewed and queued.
/// 2. If anything is queued, the user reviews it all on one card; approved
///    actions run and their confirmed outcomes go back to the model.
/// 3. The model reports (or proposes follow-ups that needed those results,
///    which go through step 2 again), within [AgentConfig] limits.
///
/// Owns one [Conversation]. Knows nothing about vendors ([LlmProvider]),
/// widgets, or how actions are written ([ToolExecutor]).
class AgentRunner {
  AgentRunner({
    required this.provider,
    required this.executor,
    required this.toolbox,
    required this.loadSnapshot,
    required this.conversation,
    ToolSelection? selection,
    this.config = const AgentConfig(),
  }) : selection = selection ?? ToolSelection();

  final LlmProvider provider;
  final ToolExecutor executor;
  final AgentToolbox toolbox;
  final Future<FinanceSnapshot> Function() loadSnapshot;
  final Conversation conversation;

  /// Tool groups offered to the model; shared with `load_tools`.
  final ToolSelection selection;
  final AgentConfig config;

  Future<AgentTurnResult> runTurn(
    String userText, {
    required ApprovalHandler approve,
    void Function(AgentEvent event)? onEvent,
    CancellationToken? cancel,
  }) async {
    final token = cancel ?? CancellationToken();
    final text = userText.trim();
    if (text.isEmpty) {
      return const AgentTurnResult(end: AgentTurnEnd.failed, reply: 'Type what you would like to do.');
    }
    if (text.length > config.maxUserMessageChars) {
      return AgentTurnResult(
        end: AgentTurnEnd.failed,
        reply: 'That message is too long. Please keep it under ${config.maxUserMessageChars} characters.',
      );
    }

    executor.beginTurn();
    selection.enableFor(text);
    final mark = conversation.mark;
    final actions = <ActionRecord>[];
    var usage = const LlmUsage();
    var toolCalls = 0;

    final String instructions;
    try {
      instructions = AgentInstructions.build(await loadSnapshot());
    } catch (e) {
      debugPrint('Agent could not load data: $e');
      return const AgentTurnResult(
        end: AgentTurnEnd.failed,
        reply: 'Your data is not available right now, so I cannot help with this yet. Please try again.',
      );
    }
    conversation.add(LlmMessage.user(text));

    Future<List<ActionRecord>> settle() async {
      final records = await executor.settleQueue(approve: approve, onEvent: onEvent, cancel: token);
      actions.addAll(records);
      return records;
    }

    AgentTurnResult stopped() => AgentTurnResult(
          end: AgentTurnEnd.cancelled,
          reply: _outcomeSummary(actions, lead: 'Stopped.'),
          actions: actions,
          usage: usage,
        );

    for (var step = 0; step < config.maxModelCallsPerTurn; step++) {
      final remainingCalls = config.maxToolCallsPerTurn - toolCalls;
      final finalStep = step == config.maxModelCallsPerTurn - 1 || remainingCalls <= 0;
      final request = LlmRequest(
        instructions: instructions,
        messages: conversation.window(maxTurns: config.maxHistoryTurns, maxChars: config.maxHistoryChars),
        tools: [for (final t in selection.offered(toolbox.tools)) t.spec],
        // On the last allowed step the model must answer, not call tools.
        toolChoice: finalStep ? LlmToolChoice.none : LlmToolChoice.auto,
        maxOutputTokens: config.maxOutputTokens,
      );

      onEvent?.call(const AgentThinking());
      final LlmResponse response;
      try {
        response = await _complete(request, token, onEvent);
      } on LlmException catch (e) {
        if (e.kind == LlmErrorKind.cancelled) {
          await settle(); // reports queued items as stopped, runs nothing
          if (actions.isEmpty) conversation.rollbackTo(mark);
          return stopped();
        }
        // Whatever was already prepared is still valid: let the user decide.
        if (executor.hasQueued) await settle();
        if (actions.isEmpty) conversation.rollbackTo(mark);
        return AgentTurnResult(
          end: AgentTurnEnd.failed,
          reply: actions.isEmpty ? e.message : _outcomeSummary(actions, lead: '${e.message} Before that:'),
          actions: actions,
          error: e,
          usage: usage,
        );
      }
      usage = usage + response.usage;
      conversation.add(response.toMessage());

      if (response.toolCalls.isNotEmpty) {
        final execution = await executor.executeStep(
          response.toolCalls,
          onEvent: onEvent,
          cancel: token,
          limit: finalStep ? 0 : remainingCalls,
        );
        toolCalls += response.toolCalls.length;
        conversation.addAll(execution.results);
        if (token.isCancelled) {
          await settle();
          return stopped();
        }
        if (finalStep) break;
        continue;
      }

      // The model has finished this round.
      if (!executor.hasQueued) {
        final reply = response.text ??
            (response.finishReason == LlmFinishReason.length
                ? _outcomeSummary(actions, lead: 'My reply was cut short.')
                : _outcomeSummary(actions,
                    lead: actions.isEmpty ? 'I could not work out a reply. Please rephrase.' : ''));
        return AgentTurnResult(end: AgentTurnEnd.completed, reply: reply, actions: actions, usage: usage);
      }

      final raw = response.text ?? '';
      final wantsMore = raw.contains(continueMarker);
      final plan = raw.replaceAll(continueMarker, '').trim();
      onEvent?.call(AgentPlanReady(plan.isEmpty ? null : plan));
      final records = await settle();
      if (token.isCancelled) return stopped();
      conversation.add(LlmMessage.user(outcomesMessage(records)));
      // The report comes from the confirmed outcomes, not from another model
      // call: always truthful, and it saves a round trip (tokens are scarce
      // on free tiers). The model continues only when it asked to.
      if (!wantsMore || step == config.maxModelCallsPerTurn - 1) {
        final reply = _outcomeSummary(actions, lead: '');
        conversation.add(LlmMessage.assistant(text: reply));
        return AgentTurnResult(end: AgentTurnEnd.completed, reply: reply, actions: actions, usage: usage);
      }
    }

    // Out of steps: still let the user review what was prepared.
    if (executor.hasQueued) {
      await settle();
      if (token.isCancelled) return stopped();
    }
    return AgentTurnResult(
      end: AgentTurnEnd.limitReached,
      reply: _outcomeSummary(actions,
          lead: 'This needed more steps than I can take at once. Please split the request into smaller parts.'),
      actions: actions,
      usage: usage,
    );
  }

  /// One model call with a timeout and bounded retries (safe: model calls
  /// change nothing): one retry after a timeout or outage, and up to
  /// [AgentConfig.rateLimitRetries] after a rate limit that asks for a
  /// bounded wait.
  Future<LlmResponse> _complete(
    LlmRequest request,
    CancellationToken token,
    void Function(AgentEvent event)? onEvent,
  ) async {
    var transientRetries = 0;
    var rateLimitRetries = 0;
    while (true) {
      token.throwIfCancelled();
      try {
        return await token.guard(provider.complete(request, cancel: token).timeout(
              config.requestTimeout,
              onTimeout: () => throw const LlmException(
                  LlmErrorKind.timeout, 'The assistant is taking too long to respond. Please try again.',
                  retryable: true),
            ));
      } on LlmException catch (e) {
        final Duration wait;
        if (e.kind == LlmErrorKind.rateLimited) {
          final after = e.retryAfter ?? config.defaultRateLimitWait;
          if (rateLimitRetries >= config.rateLimitRetries || after > config.maxRateLimitWait) rethrow;
          rateLimitRetries++;
          wait = after;
          onEvent?.call(AgentWaiting('The assistant is busy. Retrying in ${after.inSeconds} s'));
        } else {
          final transient = e.retryable &&
              (e.kind == LlmErrorKind.timeout ||
                  e.kind == LlmErrorKind.unavailable ||
                  e.kind == LlmErrorKind.invalidResponse);
          if (!transient || transientRetries >= config.transientRetries) rethrow;
          transientRetries++;
          wait = Duration(milliseconds: 800 * transientRetries);
        }
        await token.guard(Future<void>.delayed(wait));
        onEvent?.call(const AgentThinking());
      }
    }
  }

  /// Ends a plan reply when the model needs the outcomes to continue.
  static const continueMarker = '[continue]';

  /// Factual summary built from action records (never from model text).
  static String _outcomeSummary(List<ActionRecord> actions, {required String lead}) {
    if (actions.isEmpty) return lead.isEmpty ? 'Nothing was changed.' : '$lead Nothing was changed.';
    final done = actions.where((a) => a.succeeded).map((a) => a.summary).toList();
    final notDone = actions.where((a) => !a.succeeded).map((a) => a.summary).toList();
    return [
      if (lead.isNotEmpty) lead,
      if (done.isNotEmpty) 'Done: ${done.join('; ')}.',
      if (notDone.isNotEmpty) 'Not done: ${notDone.join('; ')}.',
    ].join(' ');
  }
}
