import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/data_providers.dart';
import '../../../core/money/money.dart';
import '../../../core/time/dates.dart';
import '../../../finance/finance_snapshot.dart';
import '../domain/goal.dart';

/// Read models for the redesigned goals screens. Pure functions of
/// [GoalProgress] / the snapshot; the UI only renders.

enum GoalTab {
  active('Active'),
  completed('Completed'),
  archived('Archived');

  const GoalTab(this.label);
  final String label;
}

/// One word per goal for scanning and filtering.
enum GoalPace {
  behind('Behind'),
  onTrack('On track'),
  noPlan('No plan'),
  done('Done'),
  archived('Archived');

  const GoalPace(this.label);
  final String label;
}

GoalTab goalTabOf(GoalProgress g) => g.goal.status == GoalStatus.archived
    ? GoalTab.archived
    : (g.isAchieved ? GoalTab.completed : GoalTab.active);

GoalPace goalPaceOf(GoalProgress g) {
  if (g.goal.status == GoalStatus.archived) return GoalPace.archived;
  if (g.isAchieved) return GoalPace.done;
  return switch (g.onTrack) {
    true => GoalPace.onTrack,
    false => GoalPace.behind,
    null => GoalPace.noPlan,
  };
}

/// Where the calendar says a dated goal should be by [today] (0..1), on a
/// straight line from the day it was created to its target date.
double? expectedShare(GoalProgress g, DateTime today) {
  final end = g.goal.targetDate;
  if (end == null) return null;
  final start = g.goal.createdAt.dateOnly;
  final total = daysBetween(start, end);
  if (total <= 0) return 1;
  return (daysBetween(start, today.dateOnly) / total).clamp(0.0, 1.0);
}

/// Whole months from [today] until [date] (0 when it has passed).
int monthsUntil(DateTime today, DateTime date) {
  final m = (date.year - today.year) * 12 + (date.month - today.month) - (date.day < today.day ? 1 : 0);
  return m < 0 ? 0 : m;
}

/// Finish date if [monthly] is set aside every month from [today]. Null
/// when [monthly] is not positive or the result is over 50 years away.
DateTime? finishWith(Money remaining, Money monthly, DateTime today) {
  if (remaining.isZero) return today;
  if (!monthly.isPositive) return null;
  final months = roundDiv(remaining.paise, monthly.paise, RoundingMode.up);
  return months > 600 ? null : addMonthsClamped(today.dateOnly, months);
}

/// Signed months between two dates (positive = [a] is later).
int monthsApart(DateTime a, DateTime b) => (a.year - b.year) * 12 + (a.month - b.month);

enum GoalSort {
  closest('Closest to done'),
  soonest('Due soonest'),
  behind('Behind first'),
  remaining('Most to go'),
  recent('Newest'),
  name('Name');

  const GoalSort(this.label);
  final String label;
}

@immutable
class GoalListFilter {
  const GoalListFilter({
    this.tab = GoalTab.active,
    this.paces = const {},
    this.categories = const {},
    this.sort = GoalSort.closest,
  });

  final GoalTab tab;
  final Set<GoalPace> paces;
  final Set<GoalCategory> categories;
  final GoalSort sort;

  int get activeCount => paces.length + categories.length + (sort == GoalSort.closest ? 0 : 1);

  GoalListFilter copyWith({
    GoalTab? tab,
    Set<GoalPace>? paces,
    Set<GoalCategory>? categories,
    GoalSort? sort,
  }) =>
      GoalListFilter(
        tab: tab ?? this.tab,
        paces: paces ?? this.paces,
        categories: categories ?? this.categories,
        sort: sort ?? this.sort,
      );

  GoalListFilter cleared() => GoalListFilter(tab: tab);

  bool accepts(GoalProgress g) =>
      goalTabOf(g) == tab &&
      (paces.isEmpty || paces.contains(goalPaceOf(g))) &&
      (categories.isEmpty || categories.contains(g.goal.category));

  @override
  bool operator ==(Object other) =>
      other is GoalListFilter &&
      other.tab == tab &&
      setEquals(other.paces, paces) &&
      setEquals(other.categories, categories) &&
      other.sort == sort;

  @override
  int get hashCode => Object.hash(tab, Object.hashAllUnordered(paces), Object.hashAllUnordered(categories), sort);
}

List<GoalProgress> filterGoals(List<GoalProgress> all, GoalListFilter f) {
  final out = all.where(f.accepts).toList();
  final far = DateTime(9999);
  int paceRank(GoalProgress g) => switch (goalPaceOf(g)) {
        GoalPace.behind => 0,
        GoalPace.noPlan => 1,
        GoalPace.onTrack => 2,
        _ => 3,
      };
  out.sort(switch (f.sort) {
    GoalSort.closest => (a, b) => b.progressBps.compareTo(a.progressBps),
    GoalSort.soonest => (a, b) => (a.goal.targetDate ?? far).compareTo(b.goal.targetDate ?? far),
    GoalSort.behind => (a, b) {
        final r = paceRank(a).compareTo(paceRank(b));
        return r != 0 ? r : (a.goal.targetDate ?? far).compareTo(b.goal.targetDate ?? far);
      },
    GoalSort.remaining => (a, b) => b.remaining.compareTo(a.remaining),
    GoalSort.recent => (a, b) => b.goal.createdAt.compareTo(a.goal.createdAt),
    GoalSort.name => (a, b) => a.goal.name.toLowerCase().compareTo(b.goal.name.toLowerCase()),
  });
  return out;
}

/// All goals at a glance: totals of active goals and the monthly effort
/// needed to keep every dated goal on time.
@immutable
class GoalsBoard {
  const GoalsBoard({
    required this.all,
    required this.active,
    required this.saved,
    required this.target,
    required this.neededMonthly,
    required this.plannedMonthly,
    required this.today,
  });

  final List<GoalProgress> all;

  /// Active (not achieved, not archived) goals.
  final List<GoalProgress> active;
  final Money saved;
  final Money target;

  /// Sum of "needed per month" of active dated goals.
  final Money neededMonthly;

  /// Sum of planned (else recent average) monthly amounts of active goals.
  final Money plannedMonthly;
  final DateTime today;

  Money get remaining => Money.max(target - saved, Money.zero);
  double get progress => target.isPositive ? (saved.paise / target.paise).clamp(0.0, 1.0) : 0;
  int count(GoalPace p) => active.where((g) => goalPaceOf(g) == p).length;
  Map<GoalTab, int> get tabCounts => {for (final t in GoalTab.values) t: all.where((g) => goalTabOf(g) == t).length};

  @override
  bool operator ==(Object other) =>
      other is GoalsBoard && listEquals(other.all, all) && other.today == today;

  @override
  int get hashCode => Object.hash(Object.hashAll(all), today);
}

GoalsBoard buildGoalsBoard(FinanceSnapshot s) {
  final all = s.goalProgress;
  final active = all.where((g) => goalTabOf(g) == GoalTab.active).toList();
  var saved = Money.zero;
  var target = Money.zero;
  var needed = Money.zero;
  var planned = Money.zero;
  for (final g in active) {
    saved += g.saved;
    target += g.goal.target;
    if (g.requiredMonthly != null) needed += g.requiredMonthly!;
    final rate = g.goal.plannedMonthlyContribution ?? g.averageMonthlyContribution;
    if (rate != null && rate.isPositive) planned += rate;
  }
  return GoalsBoard(
    all: all,
    active: active,
    saved: saved,
    target: target,
    neededMonthly: needed,
    plannedMonthly: planned,
    today: s.today,
  );
}

final goalsBoardProvider =
    Provider<AsyncValue<GoalsBoard>>((ref) => ref.watch(financeSnapshotProvider).whenData(buildGoalsBoard));

/// Running saved total after each movement, oldest first: (date, total).
List<(DateTime, Money)> savedOverTime(List<SavingsMovement> movements) {
  final sorted = [...movements]..sort((a, b) {
      final d = a.date.compareTo(b.date);
      return d != 0 ? d : a.createdAt.compareTo(b.createdAt);
    });
  var total = Money.zero;
  return [for (final m in sorted) (m.date, total += m.signedAmount)];
}
