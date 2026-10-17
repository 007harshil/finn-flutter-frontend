import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../actions/action.dart';
import '../../actions/action_registry.dart';
import '../../core/ids/id_generator.dart';
import '../../core/result/result.dart';
import '../../finance/finance_snapshot.dart';
import '../agent_config.dart';
import '../answers/data_answers.dart';
import '../execution/action_recap.dart';
import '../execution/plan_gateway.dart';
import '../execution/proposals.dart';
import '../history/agent_history.dart';
import '../llm/llm_provider.dart';
import '../plan/agent_guard.dart';
import '../plan/agent_plan.dart';
import '../plan/op_catalog.dart';
import '../prompt/agent_prompt.dart';
import 'agent_events.dart';
import 'agent_memory.dart';
import 'local_intents.dart';

/// Asks the user to approve [proposals]; completes with the approved ids.
/// Completing with an empty set declines everything.
typedef ApprovalHandler = Future<Set<String>> Function(List<ProposedAction> proposals);

enum AgentTurnEnd {
  /// The turn finished (changes reviewed, a question asked or answered).
  completed,

  /// The request needed more rounds than allowed.
  limitReached,

  /// The user stopped the turn.
  cancelled,

  /// The model could not be reached or answered unusably.
  failed,
}

/// One change the user wants redone: [previous] was declined (or not
/// saved) and the model reads the part of [request] it came from again.
@immutable
class RedoRequest {
  const RedoRequest({required this.request, required this.previous});

  /// The message the change came from (as the turn understood it).
  final String request;
  final ActionRecord previous;

  /// Declined by the user: the same change must not come back.
  bool get rejected => previous.status == ActionResultStatus.declined;
}

/// Outcome of one user turn.
@immutable
class AgentTurnResult {
  const AgentTurnResult({
    required this.end,
    required this.reply,
    String? message,
    this.actions = const [],
    this.error,
    this.usage = const LlmUsage(),
    this.request,
  }) : message = message ?? reply;

  final AgentTurnEnd end;

  /// Text to show the user, built by the app from real outcomes.
  final String reply;

  /// [reply] without the recap of [actions] (for UIs that show each action
  /// on its own); empty when the recap was all there was to say.
  final String message;

  /// The request the turn acted on (the message, or a clarified request
  /// with its answer), for redoing one of its changes later.
  final String? request;

  /// Every change proposed in this turn and its confirmed outcome.
  final List<ActionRecord> actions;
  final LlmException? error;

  /// Model usage of the turn ([LlmUsage.calls] is 0 when it was answered
  /// without the model).
  final LlmUsage usage;
}

/// The agent: one model request turns a message into a structured plan,
/// and ordinary code does everything else.
///
/// 1. **Local first.** History questions, "what's my balance" and replies
///    that answer an open clarification (an option, a bare amount) are
///    handled without the model.
/// 2. **One plan request.** The model returns every operation of the
///    message as JSON (`agent_plan.dart`). It sees static instructions
///    (cached by the provider), today, category names and a bounded
///    follow-up context, never records or history.
/// 3. **Deterministic resolution.** Each op is resolved against the user's
///    synced data (`op_catalog.dart`): dates, amounts, categories, the
///    pending item or goal it names. Missing or ambiguous essentials become
///    one concise question instead of a guess.
/// 4. **One review, one backend call per wave.** Valid ops are previewed
///    together, shown on one card, and the approved ones run in one
///    [PlanGateway] call that also records the agent history entry. Ops
///    that need a record created in the same plan run in a second wave.
/// 5. **Local report.** The reply comes from the confirmed outcomes.
///
/// A second model call happens only when the first reply is not a usable
/// plan, or when the user's next message answers a question in a way the
/// app cannot resolve itself.
class AgentRunner {
  AgentRunner({
    required this.provider,
    required this.gateway,
    required this.registry,
    required this.loadSnapshot,
    required this.conversationId,
    this.userToday,
    DateTime Function()? now,
    AgentMemory? memory,
    this.history,
    IdGenerator? ids,
    this.config = const AgentConfig(),
  }) : memory = memory ?? AgentMemory(),
       _now = now ?? DateTime.now,
       ids = ids ?? RandomIdGenerator();

  final LlmProvider provider;
  final PlanGateway gateway;
  final ActionRegistry registry;
  final Future<FinanceSnapshot> Function() loadSnapshot;

  /// Stable id of the conversation; plan id `agent.<id>` keys every write.
  final String conversationId;
  final AgentMemory memory;
  final AgentHistoryRepository? history;
  final IdGenerator ids;
  final AgentConfig config;
  final DateTime Function() _now;

  /// Today in the user's configured time zone (defaults to the snapshot's).
  final DateTime Function()? userToday;

  String get planId => 'agent.$conversationId';

  /// Saved requests in this conversation: request fingerprint → count. A
  /// repeated request after an unknown outcome reuses its step id (and so
  /// its server idempotency key); a deliberate repeat after a success gets
  /// the next occurrence.
  final Map<String, int> _completed = {};
  int _proposalSeq = 0;

  static const waitingLabel = 'Still working on it…';

  /// Runs one turn for [userText]. With [redo], the turn instead reads the
  /// part of [RedoRequest.request] that produced one earlier change again
  /// (and, when that change was declined, never proposes it unchanged).
  Future<AgentTurnResult> runTurn(
    String userText, {
    required ApprovalHandler approve,
    void Function(AgentEvent event)? onEvent,
    CancellationToken? cancel,
    RedoRequest? redo,
  }) async {
    final token = cancel ?? CancellationToken();
    final text = (redo?.request ?? userText).trim();
    if (text.isEmpty) return const AgentTurnResult(end: AgentTurnEnd.failed, reply: 'Type what you would like to do.');
    if (text.length > config.maxUserMessageChars) {
      return AgentTurnResult(
        end: AgentTurnEnd.failed,
        reply: 'That message is too long. Please keep it under ${config.maxUserMessageChars} characters.',
      );
    }
    final FinanceSnapshot snapshot;
    try {
      snapshot = await loadSnapshot();
    } catch (e) {
      debugPrint('Agent could not load data: $e');
      return const AgentTurnResult(
        end: AgentTurnEnd.failed,
        reply: 'Your data is not available right now, so I cannot help with this yet. Please try again.',
      );
    }
    final today = userToday?.call() ?? snapshot.today;

    // 1. Answers and completions that need no model call.
    List<PlanOp>? ops;
    String? ask;
    String? modelReply;
    var grounding = '';
    var request = text;
    var usage = const LlmUsage();
    switch (redo == null ? LocalIntents.match(text, memory) : null) {
      case HistoryIntent(:final period):
        return AgentTurnResult(end: AgentTurnEnd.completed, reply: await _historyAnswer(period, onEvent));
      case BalanceIntent():
        return AgentTurnResult(end: AgentTurnEnd.completed, reply: DataAnswers.balance(snapshot));
      case OutOfScopeIntent():
        return const AgentTurnResult(end: AgentTurnEnd.completed, reply: AgentGuard.refusal);
      case ClarificationAnswer(ops: final answered):
        grounding = memory.pending!.originalText;
        request = '${memory.pending!.originalText} → $text';
        memory.pending = null;
        ops = answered;
      case null:
        break;
    }

    // 2. One model request for the plan.
    if (ops == null) {
      final open = redo == null ? memory.pending : null;
      if (open != null) {
        grounding = open.originalText;
        request = '${open.originalText} → $text';
      }
      final extra = [?memory.contextText(withPending: redo == null), if (redo != null) _redoContext(redo)].join('\n');
      final llmRequest = LlmRequest(
        instructions: agentInstructions,
        messages: [
          LlmMessage.user(agentContext(snapshot, today: today, extra: extra)),
          LlmMessage.user(text),
        ],
        output: LlmOutputFormat.json,
        maxOutputTokens: config.maxOutputTokens,
      );
      final AgentPlan plan;
      try {
        final (p, u) = await _plan(llmRequest, token, onEvent);
        plan = p;
        usage = u;
      } on _PlanFailure catch (f) {
        return AgentTurnResult(
          end: f.error?.kind == LlmErrorKind.cancelled ? AgentTurnEnd.cancelled : AgentTurnEnd.failed,
          reply: f.error?.kind == LlmErrorKind.cancelled ? 'Stopped. Nothing was changed.' : f.message,
          error: f.error,
          usage: f.usage,
        );
      }
      // The model saw the open question; its new plan replaces it.
      if (redo == null) memory.pending = null;
      ops = plan.ops;
      ask = plan.ask;
      modelReply = plan.reply;
    }

    // 3. Resolve every op deterministically.
    final ctx = OpContext(
      snapshot: snapshot,
      today: today,
      userText: text,
      memory: memory,
      groundingText: grounding,
      answer: DataAnswers.answer,
    );
    final outcomes = <String, OpOutcome>{for (final op in ops) op.ref: _checked(compileOp(op, ctx))};
    final answers = <String>[];
    for (final op in ops) {
      switch (outcomes[op.ref]) {
        case OpAnswer(:final text):
          answers.add(text);
        case OpHistory(:final period):
          answers.add(await _historyAnswer(period, onEvent));
        default:
          break;
      }
    }
    final rejected = [for (final o in outcomes.values) if (o is OpRejected) o.reason];
    final existing = <String, String>{
      for (final e in outcomes.entries) if (e.value case OpExisting(:final recordId)) e.key: recordId,
    };
    final actions = [
      for (final op in ops)
        if (outcomes[op.ref] case final OpAction a) (op: op, action: a),
    ];
    // A reused record's note goes on the changes that use it, or in the
    // reply when nothing does.
    final usedRefs = {for (final w in actions) ...w.action.refs.values};
    for (final e in outcomes.entries) {
      if (e.value case OpExisting(:final note) when !usedRefs.contains(e.key)) rejected.add(note);
    }
    // Ops that wait for an answer to this turn's question are asked about
    // with it, not skipped.
    final asking = {for (final e in outcomes.entries) if (e.value is OpQuestion) e.key};
    final dependents = [
      for (final w in actions)
        if (w.action.refs.values.any(asking.contains)) w.op,
    ];

    // 4. Review and execute, one wave per round of dependencies.
    final runId = ids.next('run');
    final avoid = {if (redo != null && redo.rejected) _fingerprintOfStep(redo.previous.proposal.stepId)};
    final records = <ActionRecord>[];
    final created = Map<String, String>.of(existing);
    final notSaved = <String>{};
    var waiting = [
      for (final w in actions)
        if (!dependents.contains(w.op)) w,
    ];
    var historyNotes = List.of(rejected);
    var wave = 0;
    var cancelled = false;
    while (waiting.isNotEmpty && wave < config.maxWaves && !cancelled) {
      final ready = <({PlanOp op, OpAction action, List<String> notes})>[];
      final later = <({PlanOp op, OpAction action})>[];
      for (final w in waiting) {
        final refs = w.action.refs.values;
        if (refs.every(created.containsKey)) {
          ready.add((
            op: w.op,
            action: w.action,
            notes: [
              for (final r in refs)
                if (outcomes[r] case OpExisting(:final note)) note,
            ],
          ));
        } else if (refs.any((r) => notSaved.contains(r) || outcomes[r] is! OpAction)) {
          rejected.add('Skipped: it needed a change that was not saved.');
        } else {
          later.add(w);
        }
      }
      waiting = later;
      if (ready.isEmpty) break;
      final round = await _round(
        ready,
        created: created,
        request: redo == null ? request : 'Redo: $request',
        runId: runId,
        historyNotes: historyNotes,
        avoid: avoid,
        approve: approve,
        onEvent: onEvent,
        token: token,
      );
      historyNotes = const [];
      rejected.addAll(round.problems);
      records.addAll(round.records);
      for (final r in round.records) {
        final id = r.recordId;
        if (r.succeeded && id is String) {
          created[r.proposal.opRef] = id;
        } else {
          notSaved.add(r.proposal.opRef);
        }
      }
      cancelled = token.isCancelled;
      wave++;
    }
    if (waiting.isNotEmpty && !cancelled) rejected.add('Some changes needed more steps than I can take at once.');

    // 5. Remember what was saved; keep an open question for the next turn.
    memory.remember([
      for (final r in records)
        if (r.succeeded) RecentOp(actionId: r.proposal.descriptor.id, summary: _recentSummary(r), recordId: _firstId(r.recordId)),
    ]);
    final questions = [for (final op in ops) if (outcomes[op.ref] case final OpQuestion q) (op: op, q: q)];
    final question = _question(ask, questions.map((e) => e.q).toList());
    if (question != null && !cancelled) {
      final single = questions.length == 1 ? questions.single : null;
      memory.pending = PendingClarification(
        question: question,
        originalText: request,
        ops: [for (final e in questions) e.op, ...dependents],
        opRef: single?.op.ref,
        field: single?.q.field,
        options: single?.q.options ?? const [],
      );
    }

    String join(List<String?> parts) => parts.whereType<String>().where((s) => s.trim().isNotEmpty).join('\n');
    final lead = [
      if (records.isEmpty && answers.isEmpty && modelReply != null) modelReply,
      ...answers,
    ];
    final tail = [
      if (rejected.isNotEmpty) rejected.toSet().join(' '),
      ?question,
    ];
    final reply = join([...lead, if (records.isNotEmpty) _outcomeSummary(records, lead: cancelled ? 'Stopped.' : ''), ...tail]);
    return AgentTurnResult(
      end: cancelled ? AgentTurnEnd.cancelled : AgentTurnEnd.completed,
      reply: reply.isEmpty ? 'Nothing was changed.' : reply,
      message: records.isEmpty && reply.isEmpty ? 'Nothing was changed.' : join([...lead, ...tail]),
      actions: records,
      usage: usage,
      request: request,
    );
  }

  /// One wave: preview together, one review card, one execution call.
  Future<({List<ActionRecord> records, List<String> problems})> _round(
    List<({PlanOp op, OpAction action, List<String> notes})> ready, {
    required Map<String, String> created,
    required String request,
    required String runId,
    required List<String> historyNotes,
    required Set<String> avoid,
    required ApprovalHandler approve,
    required void Function(AgentEvent event)? onEvent,
    required CancellationToken token,
  }) async {
    final problems = <String>[];
    final steps = <PlanStep>[];
    final refsOf = <String, String>{}; // step id → op ref
    final notesOf = <String, List<String>>{};
    final opsOf = <String, Map<String, Object?>>{};
    final seen = <String, int>{};
    for (final w in ready) {
      final input = {...w.action.input, for (final e in w.action.refs.entries) e.key: created[e.value]};
      final action = registry.lookup(w.action.actionId)!;
      final ActionInput decoded;
      try {
        decoded = action.decode(input);
      } on AppFailure catch (f) {
        problems.add('I couldn\'t prepare that: ${f.message}');
        continue;
      } catch (e) {
        debugPrint('Agent could not decode ${w.action.actionId}: $e');
        problems.add('I couldn\'t prepare one of the changes.');
        continue;
      }
      final fp = fingerprintOf(action.descriptor.id, decoded);
      if (avoid.contains(fp)) {
        problems.add('I came up with the same change again. Tell me what is different, such as the amount, category, person or date.');
        continue;
      }
      final inPlan = seen[fp] = (seen[fp] ?? 0) + 1;
      final occurrence = (_completed[fp] ?? 0) + inPlan - 1;
      final stepId = '$fp-$occurrence';
      steps.add(PlanStep(stepId: stepId, action: action, input: decoded));
      refsOf[stepId] = w.op.ref;
      opsOf[stepId] = w.op.toJson()..remove('id');
      notesOf[stepId] = [
        ...w.notes,
        ...w.action.notes,
        if (inPlan > 1) 'Same as another change in this request. Exclude it if it was said once.',
        if ((_completed[fp] ?? 0) > 0)
          'You already recorded an identical entry earlier in this chat. Approve only if this is a separate one.',
      ];
    }
    if (steps.isEmpty) return (records: const <ActionRecord>[], problems: problems);

    onEvent?.call(const AgentToolStarted('plan', 'Preparing your changes'));
    final previews = await gateway.preview(planId, steps);
    final proposals = <ProposedAction>[];
    final previewed = <PlanStep>[];
    for (var i = 0; i < steps.length; i++) {
      final s = steps[i];
      final p = previews[i];
      if (p.preview == null) {
        problems.add('Couldn\'t prepare "${s.action.descriptor.title.toLowerCase()}": ${p.failure?.message ?? 'unknown problem'}');
        continue;
      }
      final label = p.preview!.summary.length <= 300 ? p.preview!.summary : p.preview!.summary.substring(0, 300);
      previewed.add(PlanStep(stepId: s.stepId, action: s.action, input: s.input, label: label));
      proposals.add(ProposedAction(
        id: 'p${++_proposalSeq}',
        opRef: refsOf[s.stepId]!,
        action: s.action,
        input: s.input,
        preview: p.preview!,
        stepId: s.stepId,
        idempotencyKey: '$planId:${s.stepId}',
        notes: notesOf[s.stepId] ?? const [],
        opJson: opsOf[s.stepId] ?? const {},
      ));
    }
    if (proposals.isEmpty) return (records: const <ActionRecord>[], problems: problems);

    onEvent?.call(const AgentPlanReady(null));
    onEvent?.call(AgentAwaitingApproval(List.unmodifiable(proposals)));
    Set<String> approvedIds;
    try {
      approvedIds = await token.guard(approve(proposals));
    } on LlmException {
      approvedIds = const {}; // stopped while waiting: nothing runs
    }
    final approved = {
      for (final p in proposals)
        if (approvedIds.contains(p.id)) p.stepId: p.preview.fingerprint,
    };
    if (approved.isNotEmpty) onEvent?.call(AgentExecuting(approved.length));
    // Deliberately not cancellable once sent: outcomes are reported truthfully.
    final results = await gateway.execute(
      planId,
      previewed,
      approved: approved,
      // Within the API's limits: request <= 500 characters, <= 10 notes of <= 300.
      history: HistoryWrite(
        runId: runId,
        request: _clip(request, 500),
        notes: [for (final n in {...historyNotes, ...problems}.take(10)) _clip(n, 300)],
      ),
    );
    final byStep = {for (final r in results) r.stepId: r};
    final records = <ActionRecord>[];
    for (final p in proposals) {
      final r = byStep[p.stepId];
      final status = r == null
          ? ActionResultStatus.failed
          : (r.status == ActionResultStatus.declined && token.isCancelled ? ActionResultStatus.cancelled : r.status);
      if (status == ActionResultStatus.completed) {
        final fp = _fingerprintOfStep(p.stepId);
        _completed[fp] = (_completed[fp] ?? 0) + 1;
      }
      records.add(ActionRecord(
        proposal: p,
        status: status,
        message: r?.message,
        outcomeUnknown: r?.outcomeUnknown ?? true,
        recordId: r?.recordId,
      ));
    }
    onEvent?.call(AgentActionsSettled(List.unmodifiable(records)));
    return (records: records, problems: problems);
  }

  /// Ops whose actions are not registered or not exposed to the agent are
  /// refused here, whatever the model sent.
  OpOutcome _checked(OpOutcome o) {
    if (o is! OpAction) return o;
    final action = registry.lookup(o.actionId);
    if (action == null || o.actionId.endsWith('.delete')) return const OpRejected('That isn\'t something I can do here.');
    return o;
  }

  Future<String> _historyAnswer(String? period, void Function(AgentEvent event)? onEvent) async {
    final repo = history;
    if (repo == null) return 'Your agent history isn\'t available right now.';
    onEvent?.call(const AgentToolStarted('history', 'Checking your history'));
    try {
      final page = await repo.list(limit: 20);
      return historyAnswer(page.items, period: period, now: _now());
    } on AppFailure catch (f) {
      return 'I couldn\'t read your history: ${f.message}';
    } catch (e) {
      debugPrint('Agent history failed: $e');
      return 'I couldn\'t read your history right now.';
    }
  }

  /// The plan from one model call (plus one retry when the reply is not a
  /// usable plan, the only case where asking again can help).
  Future<(AgentPlan, LlmUsage)> _plan(LlmRequest request, CancellationToken token, void Function(AgentEvent event)? onEvent) async {
    var usage = const LlmUsage();
    final budget = _WaitBudget(config.rateLimitWaitBudget);
    for (var attempt = 0; ; attempt++) {
      onEvent?.call(const AgentThinking());
      final LlmResponse response;
      try {
        response = await _complete(request, token, onEvent, budget);
      } on LlmException catch (e) {
        throw _PlanFailure(e.message, usage: usage, error: e);
      }
      usage = usage + response.usage;
      if (response.refusal != null) return (AgentPlan(reply: response.refusal), usage);
      if (response.finishReason == LlmFinishReason.length) {
        throw _PlanFailure('That is a lot at once. Please send it in smaller parts.', usage: usage);
      }
      try {
        return (PlanParser.parse(response.text), usage);
      } on PlanFormatException catch (e) {
        debugPrint('Agent plan unusable (${e.reason})');
        if (attempt >= config.invalidPlanRetries) {
          throw _PlanFailure('I couldn\'t work out what to do. Please rephrase.', usage: usage);
        }
      }
    }
  }

  /// One model call with a timeout and bounded retries (safe: model calls
  /// change nothing): one retry after a timeout or outage, and after rate
  /// limits as long as the requested wait fits the turn's budget.
  Future<LlmResponse> _complete(
    LlmRequest request,
    CancellationToken token,
    void Function(AgentEvent event)? onEvent,
    _WaitBudget budget,
  ) async {
    var transientRetries = 0;
    while (true) {
      token.throwIfCancelled();
      try {
        return await token.guard(provider.complete(request, cancel: token).timeout(
          config.requestTimeout,
          onTimeout: () => throw const LlmException(
            LlmErrorKind.timeout,
            'The assistant is taking too long to respond. Please try again.',
            retryable: true,
          ),
        ));
      } on LlmException catch (e) {
        final Duration wait;
        if (e.kind == LlmErrorKind.rateLimited) {
          final hint = e.retryAfter;
          final after = hint == null || hint <= Duration.zero ? config.defaultRateLimitWait : hint;
          if (after > config.maxRateLimitWait || after > budget.remaining) rethrow;
          budget.remaining -= after;
          wait = after;
          onEvent?.call(const AgentWaiting(waitingLabel));
        } else {
          final transient = e.retryable &&
              (e.kind == LlmErrorKind.timeout || e.kind == LlmErrorKind.unavailable || e.kind == LlmErrorKind.invalidResponse);
          if (!transient || transientRetries >= config.transientRetries) rethrow;
          transientRetries++;
          wait = Duration(milliseconds: 800 * transientRetries);
        }
        await token.guard(Future<void>.delayed(wait));
        onEvent?.call(const AgentThinking());
      }
    }
  }

  /// The question to ask: the model's own wording when it asked, plus the
  /// app's questions about which record was meant (the model cannot see
  /// records).
  static String? _question(String? ask, List<OpQuestion> local) {
    final choices = [for (final q in local) if (q.options.isNotEmpty) q.question];
    if (ask != null) return [ask, ...choices.where((c) => c != ask)].join(' ');
    if (local.isEmpty) return null;
    return {for (final q in local) q.question}.join(' ');
  }

  /// What the model is told about the change to redo.
  static String _redoContext(RedoRequest redo) {
    final p = redo.previous;
    final op = _clip(jsonEncode(p.proposal.opJson), 400);
    final summary = _clip(p.summary, 160);
    return redo.rejected
        ? 'Redo: the user declined $op ("$summary"). Read the part of the message it came from again.'
        : 'Redo: $op ("$summary") was not saved${p.message == null ? '' : ': ${_clip(p.message!, 200)}'}. Return that part of the message again, fixed.';
  }

  /// Step ids are `<fingerprint>-<occurrence>`.
  static String _fingerprintOfStep(String stepId) => stepId.substring(0, stepId.lastIndexOf('-'));

  static String _clip(String s, int max) => s.length <= max ? s : '${s.substring(0, max - 1)}…';

  static String? _firstId(Object? id) => id is String ? id : (id is List ? id.whereType<String>().firstOrNull : null);

  /// How a saved change is described to the model in follow-ups.
  static String _recentSummary(ActionRecord r) {
    final j = r.proposal.input.toJson();
    final date = j['date'] ?? j['createdDate'];
    final note = j['note'] ?? j['purpose'];
    final recap = actionRecap(r).replaceAll(RegExp(r'\.$'), '');
    return '$recap${date is String ? ' on $date' : ''}${note is String && note.isNotEmpty ? ' "$note"' : ''}';
  }

  /// Factual summary built from action records (never from model text).
  static String _outcomeSummary(List<ActionRecord> actions, {required String lead}) {
    final done = actions.where((a) => a.succeeded).map(actionRecap).toList();
    final notDone = [
      for (final a in actions.where((a) => !a.succeeded))
        a.message == null || a.status == ActionResultStatus.declined ? a.summary : '${a.summary} (${a.message})',
    ];
    return [
      if (lead.isNotEmpty) lead,
      ...done,
      if (notDone.isNotEmpty) 'Not done: ${notDone.join('; ')}.',
    ].join(' ');
  }
}

class _PlanFailure implements Exception {
  const _PlanFailure(this.message, {required this.usage, this.error});
  final String message;
  final LlmUsage usage;
  final LlmException? error;
}

/// Rate-limit waiting left in one turn.
class _WaitBudget {
  _WaitBudget(this.remaining);
  Duration remaining;
}
