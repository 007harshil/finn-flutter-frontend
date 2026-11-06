import 'package:flutter/foundation.dart';

/// Wall-clock time spent in each stage of one agent turn.
///
/// The runner calls [lap] when a stage ends; the time since the previous
/// lap is charged to that stage. Stages can repeat (a retried model call,
/// a second wave), and [totals] adds them up. Time spent waiting for the
/// user to approve is kept apart ([userWait]) so latency figures only count
/// the app, the network and the model.
///
/// Holds names, durations and counts only: never request text, amounts or
/// record data. Logged in debug and profile builds, never in release.
class AgentTrace {
  AgentTrace() : _clock = Stopwatch()..start();

  /// Stage charged to the user's own time, not the agent's.
  static const approval = 'approval';

  final Stopwatch _clock;
  int _last = 0;

  /// Every lap in order: stage name and microseconds.
  final List<(String, int)> laps = [];

  /// Sizes and counts of the turn (prompt characters, tokens, calls, steps).
  final Map<String, int> facts = {};

  /// Ends the current stage as [stage].
  void lap(String stage) {
    final now = _clock.elapsedMicroseconds;
    laps.add((stage, now - _last));
    _last = now;
  }

  void fact(String name, int value) => facts[name] = value;

  void add(String name, int value) => facts[name] = (facts[name] ?? 0) + value;

  /// Microseconds per stage, summed over repeats, in first-seen order.
  Map<String, int> get totals {
    final out = <String, int>{};
    for (final (stage, us) in laps) {
      out[stage] = (out[stage] ?? 0) + us;
    }
    return out;
  }

  /// Microseconds spent waiting for the user's decision.
  int get userWait => totals[approval] ?? 0;

  /// Microseconds of agent work (everything except [userWait]).
  int get agentTime => laps.fold(0, (s, l) => s + l.$2) - userWait;

  /// Microseconds from the start of the turn until the first review card
  /// was ready (the user's "it answered" moment when changes are proposed),
  /// or null when the turn proposed nothing.
  int? get untilReview {
    var us = 0;
    for (final (stage, t) in laps) {
      if (stage == approval) return us;
      us += t;
    }
    return null;
  }

  /// One log line: `agent.trace total=… stage=…ms … | fact=…`.
  String describe() {
    String ms(int us) => (us / 1000).toStringAsFixed(us < 10000 ? 1 : 0);
    final stages = [
      for (final e in totals.entries)
        if (e.key != approval) '${e.key}=${ms(e.value)}ms',
    ];
    final review = untilReview;
    return [
      'agent.trace agent=${ms(agentTime)}ms',
      if (review != null) 'untilReview=${ms(review)}ms',
      ...stages,
      if (userWait > 0) '(user ${ms(userWait)}ms)',
      if (facts.isNotEmpty) '| ${facts.entries.map((e) => '${e.key}=${e.value}').join(' ')}',
    ].join(' ');
  }

  /// Prints [describe] in debug and profile builds only.
  void log() {
    if (kReleaseMode) return;
    debugPrint(describe());
  }
}
