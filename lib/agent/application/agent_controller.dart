import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/di/action_providers.dart';
import '../../app/di/core_providers.dart';
import '../../core/ids/id_generator.dart';
import '../../features/auth/application/auth_controller.dart';
import '../execution/proposals.dart';
import '../llm/llm_provider.dart';
import '../orchestration/agent_events.dart';
import '../orchestration/agent_runner.dart';
import 'action_deck.dart';
import 'agent_providers.dart';

export 'action_deck.dart';

enum AgentStatus { idle, thinking, awaitingApproval, executing }

/// One entry of the visible chat.
@immutable
sealed class ChatEntry {
  const ChatEntry(this.id);
  final String id;
}

final class UserChatEntry extends ChatEntry {
  const UserChatEntry(super.id, this.text);
  final String text;
}

final class AgentChatEntry extends ChatEntry {
  const AgentChatEntry(
    super.id, {
    required this.text,
    required this.end,
    this.actions = const [],
    this.retryText,
    this.turn,
    String? message,
  }) : message = message ?? text;
  final String text;
  final AgentTurnEnd end;

  /// Confirmed outcomes of every action proposed in this turn.
  final List<ActionRecord> actions;

  /// Set when the turn failed before anything was changed and can be resent.
  final String? retryText;

  /// Id of the user's message this answers (its deck, if any, is
  /// `AgentViewState.decks[turn]`).
  final String? turn;

  /// [text] without the recap of [actions], which the deck shows card by
  /// card; empty when the recap was all there was to say.
  final String message;
}

@immutable
class AgentViewState {
  const AgentViewState({
    this.available = true,
    this.entries = const [],
    this.status = AgentStatus.idle,
    this.progress,
    this.proposals = const [],
    this.plan,
    this.decks = const {},
    this.redoing,
  });

  /// False when no model provider is configured (local mode).
  final bool available;
  final List<ChatEntry> entries;
  final AgentStatus status;

  /// What the agent is doing right now, e.g. "Looking up your records".
  final String? progress;

  /// Actions waiting for approval (only while [status] is awaitingApproval).
  final List<ProposedAction> proposals;

  /// What the assistant said about its plan, shown above the review card.
  final String? plan;

  /// Proposed changes per user message id, shown as card decks.
  final Map<String, ActionDeck> decks;

  /// Key of the deck slot being regenerated, while that runs.
  final String? redoing;

  bool get busy => status != AgentStatus.idle;

  /// Awaiting the user's decision on [proposalId].
  bool reviewing(String proposalId) =>
      status == AgentStatus.awaitingApproval && proposals.any((p) => p.id == proposalId);

  AgentViewState copyWith({
    List<ChatEntry>? entries,
    AgentStatus? status,
    String? Function()? progress,
    List<ProposedAction>? proposals,
    String? Function()? plan,
    Map<String, ActionDeck>? decks,
    String? Function()? redoing,
  }) => AgentViewState(
    available: available,
    entries: entries ?? this.entries,
    status: status ?? this.status,
    progress: progress == null ? this.progress : progress(),
    proposals: proposals ?? this.proposals,
    plan: plan == null ? this.plan : plan(),
    decks: decks ?? this.decks,
    redoing: redoing == null ? this.redoing : redoing(),
  );
}

/// The small, stable interface the UI uses: [send], [decide], [decideRest],
/// [approve], [decline], [retry], [stop], [startOver]. Conversation state
/// lives for the app session (it is in memory only and cleared on
/// sign-out); pending approvals are never persisted, so an interrupted
/// session can never execute anything.
class AgentController extends Notifier<AgentViewState> {
  AgentRunner? _runner;
  CancellationToken? _cancel;
  Completer<Set<String>>? _approval;
  int _seq = 0;
  int _slotSeq = 0;

  /// Where the running turn's proposals go: new slots on the deck of
  /// `turnId`, or the slot being regenerated.
  ({String turnId, String? slot})? _target;

  /// Bumped whenever the conversation is reset, so a turn that finishes
  /// afterwards cannot write into the new session's state.
  int _generation = 0;

  @override
  AgentViewState build() {
    final provider = ref.watch(llmProviderProvider);
    // A different (or no) signed-in user starts a fresh conversation.
    ref.watch(authControllerProvider.select((s) => s?.email));
    ref.onDispose(_abort);
    _generation++;
    _runner = null;
    return AgentViewState(available: provider != null);
  }

  AgentRunner _runnerFor(LlmProvider provider) => _runner ??= AgentRunner(
    provider: provider,
    gateway: ref.read(agentPlanGatewayProvider),
    registry: ref.read(actionRegistryProvider),
    loadSnapshot: ref.read(actionEnvironmentProvider).loadSnapshot,
    conversationId: RandomIdGenerator().next('c'),
    userToday: ref.read(agentTodayProvider),
    now: () => ref.read(clockProvider).now(),
    history: ref.read(agentHistoryProvider),
    config: ref.read(agentConfigProvider),
  );

  /// Sends a request. Ignored while a turn is running (no duplicate
  /// submissions).
  Future<void> send(String text) async {
    final provider = ref.read(llmProviderProvider);
    final trimmed = text.trim();
    if (provider == null || state.busy || trimmed.isEmpty) return;

    final turnId = 'u${_seq++}';
    state = state.copyWith(
      entries: [...state.entries, UserChatEntry(turnId, trimmed)],
      status: AgentStatus.thinking,
      progress: () => null,
    );
    _target = (turnId: turnId, slot: null);
    final result = await _run(provider, (runner, approve, onEvent, token) =>
        runner.runTurn(trimmed, approve: approve, onEvent: onEvent, cancel: token));
    if (result == null) return;

    final canRetry = result.end == AgentTurnEnd.failed && result.actions.isEmpty && (result.error?.retryable ?? true);
    state = state.copyWith(
      entries: [
        ...state.entries,
        AgentChatEntry(
          'a${_seq++}',
          text: result.reply,
          end: result.end,
          actions: result.actions,
          retryText: canRetry ? trimmed : null,
          turn: turnId,
          message: result.message,
        ),
      ],
      decks: _withDeck(turnId, (d) => d.copyWith(request: result.request ?? trimmed)),
    );
  }

  /// Asks the agent to regenerate the declined (or unsaved) change in
  /// [slotKey] of [turnId]'s deck. The new proposal lands on the same card,
  /// for review like any other.
  Future<void> retry(String turnId, String slotKey) async {
    final provider = ref.read(llmProviderProvider);
    final deck = state.decks[turnId];
    final slot = deck?.slots.where((s) => s.key == slotKey).firstOrNull;
    if (provider == null || state.busy || deck == null || slot == null || !slot.canRetry) return;

    final redo = RedoRequest(request: deck.request, previous: slot.current.record!);
    state = state.copyWith(
      status: AgentStatus.thinking,
      progress: () => null,
      redoing: () => slotKey,
      decks: _withDeck(turnId, (d) => d.mapSlot(slotKey, (s) => s.copyWith(retrying: true, note: () => null))),
    );
    _target = (turnId: turnId, slot: slotKey);
    final result = await _run(provider, (runner, approve, onEvent, token) =>
        runner.runTurn('', approve: approve, onEvent: onEvent, cancel: token, redo: redo));
    if (result == null) return;

    final note = result.message.trim();
    state = state.copyWith(
      redoing: () => null,
      decks: _withDeck(
        turnId,
        (d) => d.mapSlot(slotKey, (s) => s.copyWith(retrying: false, note: () => note.isEmpty ? null : note)),
      ),
    );
  }

  /// Runs one turn and settles the shared state; null when the
  /// conversation was reset meanwhile.
  Future<AgentTurnResult?> _run(
    LlmProvider provider,
    Future<AgentTurnResult> Function(
      AgentRunner runner,
      ApprovalHandler approve,
      void Function(AgentEvent) onEvent,
      CancellationToken token,
    ) turn,
  ) async {
    final generation = _generation;
    final token = _cancel = CancellationToken();
    AgentTurnResult result;
    try {
      result = await turn(
        _runnerFor(provider),
        (p) => generation == _generation ? _requestApproval(p) : Future.value(const <String>{}),
        (e) {
          if (generation == _generation) _onEvent(e);
        },
        token,
      );
    } catch (e, st) {
      debugPrint('Agent turn crashed: $e\n$st');
      result = const AgentTurnResult(end: AgentTurnEnd.failed, reply: 'Something went wrong. Please try again.');
    }
    if (!ref.mounted || generation != _generation) return null;
    _attach(result.actions);
    _approval = null;
    _cancel = null;
    _target = null;
    state = state.copyWith(status: AgentStatus.idle, progress: () => null, proposals: const [], plan: () => null);
    return result;
  }

  /// Sets the user's call on one pending change ([decision] null undoes
  /// it). The review is submitted once every change has a decision.
  void decide(String proposalId, CardDecision? decision) {
    if (!state.reviewing(proposalId)) return;
    _setDecisions({proposalId: decision});
    if (decision != null && _undecided().isEmpty) _submit();
  }

  /// Gives every pending change without a decision [decision] and submits.
  void decideRest(CardDecision decision) {
    if (state.status != AgentStatus.awaitingApproval) return;
    _setDecisions({for (final id in _undecided()) id: decision});
    _submit();
  }

  /// Approves every pending change that has no decision yet and submits.
  void approveAll() => decideRest(CardDecision.approved);

  /// Approves the proposals with [ids]; the others are declined.
  void approve(Set<String> ids) {
    if (state.status != AgentStatus.awaitingApproval) return;
    _setDecisions({
      for (final p in state.proposals) p.id: ids.contains(p.id) ? CardDecision.approved : CardDecision.declined,
    });
    _submit();
  }

  /// Declines every pending proposal.
  void decline() => approve(const {});

  /// Stops the current turn. Approved actions already sent still finish
  /// and are reported truthfully.
  void stop() {
    _cancel?.cancel();
    final c = _approval;
    if (c != null && !c.isCompleted) c.complete(const {});
    _approval = null;
  }

  /// Clears the conversation (only when idle).
  void startOver() {
    if (state.busy) return;
    _generation++;
    _runner = null;
    state = AgentViewState(available: state.available);
  }

  Future<Set<String>> _requestApproval(List<ProposedAction> proposals) {
    final c = _approval = Completer<Set<String>>();
    final target = _target;
    if (target != null) {
      final fresh = [for (final p in proposals) DeckSlot(key: 's${_slotSeq++}', attempts: [DeckAttempt(proposal: p)])];
      state = state.copyWith(decks: _withDeck(target.turnId, (d) {
        final i = target.slot == null ? -1 : d.slots.indexWhere((s) => s.key == target.slot);
        if (i < 0) return d.copyWith(slots: [...d.slots, ...fresh]);
        // A regeneration: its first change replaces the card in place, any
        // others follow it.
        final slot = d.slots[i];
        final redone = slot.copyWith(attempts: [...slot.attempts, ...fresh.first.attempts], retrying: false);
        return d.copyWith(slots: [...d.slots.take(i), redone, ...fresh.skip(1), ...d.slots.skip(i + 1)]);
      }));
      // Later waves of the same turn add new cards.
      _target = (turnId: target.turnId, slot: null);
    }
    state = state.copyWith(status: AgentStatus.awaitingApproval, proposals: proposals, progress: () => null);
    return c.future;
  }

  /// Completes the open review with the approved changes.
  void _submit() {
    final c = _approval;
    if (c == null || c.isCompleted) return;
    final decisions = _decisions();
    final approved = {
      for (final p in state.proposals)
        if (decisions[p.id] == CardDecision.approved) p.id,
    };
    _approval = null;
    state = state.copyWith(
      status: AgentStatus.executing,
      proposals: const [],
      progress: () => approved.isEmpty ? 'Wrapping up' : 'Saving',
    );
    c.complete(approved);
  }

  Map<String, CardDecision?> _decisions() => {
    for (final d in state.decks.values)
      for (final s in d.slots)
        for (final a in s.attempts) a.proposal.id: a.decision,
  };

  List<String> _undecided() {
    final decisions = _decisions();
    return [
      for (final p in state.proposals)
        if (decisions[p.id] == null) p.id,
    ];
  }

  void _setDecisions(Map<String, CardDecision?> decisions) {
    final turnId = _target?.turnId;
    if (turnId == null) return;
    state = state.copyWith(decks: _withDeck(turnId, (d) => d.mapAttempts((a) {
      if (!decisions.containsKey(a.proposal.id)) return a;
      return a.copyWith(decision: () => decisions[a.proposal.id]);
    })));
  }

  /// Puts confirmed outcomes on their cards.
  void _attach(List<ActionRecord> records) {
    final turnId = _target?.turnId;
    if (turnId == null || records.isEmpty) return;
    final byId = {for (final r in records) r.proposal.id: r};
    state = state.copyWith(decks: _withDeck(turnId, (d) => d.mapAttempts((a) => a.copyWith(record: byId[a.proposal.id]))));
  }

  Map<String, ActionDeck> _withDeck(String turnId, ActionDeck Function(ActionDeck d) f) {
    final current = state.decks[turnId];
    if (current == null && _target?.turnId != turnId) return state.decks;
    final next = f(current ?? ActionDeck(turnId: turnId));
    // A turn that proposed nothing keeps no deck.
    if (next.slots.isEmpty) return state.decks;
    return {...state.decks, turnId: next};
  }

  void _onEvent(AgentEvent e) {
    if (!ref.mounted) return;
    switch (e) {
      case AgentThinking():
        state = state.copyWith(status: AgentStatus.thinking, progress: () => null);
      case AgentToolStarted(:final label) || AgentWaiting(:final label):
        state = state.copyWith(progress: () => label);
      case AgentPlanReady(:final text):
        state = state.copyWith(plan: () => text);
      case AgentExecuting():
        state = state.copyWith(status: AgentStatus.executing, progress: () => 'Saving');
      case AgentActionsSettled(:final records):
        _attach(records);
      case AgentAwaitingApproval():
        break; // handled by _requestApproval
    }
  }

  void _abort() {
    _cancel?.cancel();
    final c = _approval;
    if (c != null && !c.isCompleted) c.complete(const {});
  }
}
