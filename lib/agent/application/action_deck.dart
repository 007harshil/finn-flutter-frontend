import 'package:flutter/foundation.dart';

import '../execution/proposals.dart';

/// The user's call on one proposed change, before the turn runs it.
enum CardDecision { approved, declined }

/// One proposed change on a deck: the proposal, the user's decision while
/// the review is open and, once the turn has run, what actually happened.
@immutable
class DeckAttempt {
  const DeckAttempt({required this.proposal, this.decision, this.record});

  final ProposedAction proposal;
  final CardDecision? decision;

  /// Ground truth from the backend (null until the change has been run).
  final ActionRecord? record;

  DeckAttempt copyWith({CardDecision? Function()? decision, ActionRecord? record}) => DeckAttempt(
    proposal: proposal,
    decision: decision == null ? this.decision : decision(),
    record: record ?? this.record,
  );
}

/// One place on the deck: the change first proposed and every change
/// regenerated for it, newest last. Only the newest is shown in full.
@immutable
class DeckSlot {
  const DeckSlot({required this.key, required this.attempts, this.retrying = false, this.note});

  /// Stable within the conversation (`s1`, `s2`…).
  final String key;

  /// Never empty.
  final List<DeckAttempt> attempts;

  /// The agent is regenerating this change.
  final bool retrying;

  /// What the last regeneration said instead of proposing a new change
  /// (a question, or why it could not), shown on the card.
  final String? note;

  DeckAttempt get current => attempts.last;

  /// The shown change was regenerated after an earlier one was declined.
  bool get regenerated => attempts.length > 1;

  /// The shown change was settled without being saved, with a known
  /// outcome, so asking the agent again cannot apply anything twice.
  bool get canRetry {
    final r = current.record;
    return !retrying && r != null && !r.succeeded && !r.outcomeUnknown;
  }

  DeckSlot copyWith({List<DeckAttempt>? attempts, bool? retrying, String? Function()? note}) => DeckSlot(
    key: key,
    attempts: attempts ?? this.attempts,
    retrying: retrying ?? this.retrying,
    note: note == null ? this.note : note(),
  );
}

/// The changes proposed for one message, shown as a deck of cards right
/// under it. The deck stays after the turn: every card keeps its outcome,
/// and declined ones can be regenerated in place.
@immutable
class ActionDeck {
  const ActionDeck({required this.turnId, this.request = '', this.slots = const []});

  /// Id of the user's message the deck belongs to.
  final String turnId;

  /// The request the changes came from (what a regeneration re-reads).
  final String request;
  final List<DeckSlot> slots;

  int get saved => slots.where((s) => s.current.record?.succeeded ?? false).length;

  ActionDeck copyWith({String? request, List<DeckSlot>? slots}) =>
      ActionDeck(turnId: turnId, request: request ?? this.request, slots: slots ?? this.slots);

  /// Applies [f] to every attempt.
  ActionDeck mapAttempts(DeckAttempt Function(DeckAttempt a) f) => copyWith(
    slots: [for (final s in slots) s.copyWith(attempts: [for (final a in s.attempts) f(a)])],
  );

  /// Applies [f] to the slot with [key].
  ActionDeck mapSlot(String key, DeckSlot Function(DeckSlot s) f) =>
      copyWith(slots: [for (final s in slots) s.key == key ? f(s) : s]);
}
