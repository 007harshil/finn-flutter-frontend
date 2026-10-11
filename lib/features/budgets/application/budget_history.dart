import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/data_providers.dart';
import '../../../core/money/money.dart';
import '../../../core/time/dates.dart';
import '../../../finance/finance_snapshot.dart';
import '../domain/budget.dart';

/// Read models for the budgets screens: overview of the current period,
/// per-budget spending history and a limit suggestion. Pure functions of a
/// [FinanceSnapshot], exposed through providers.

/// Sort order by health: breached first, paused last.
int _healthRank(BudgetHealth h) => switch (h) {
      BudgetHealth.breached => 0,
      BudgetHealth.warning => 1,
      BudgetHealth.healthy => 2,
      BudgetHealth.paused => 3,
    };

@immutable
class BudgetsOverview {
  const BudgetsOverview({
    required this.period,
    required this.totalLimit,
    required this.totalSpent,
    required this.totalCommitted,
    required this.daysLeft,
    required this.elapsedBps,
    required this.active,
    required this.paused,
  });

  /// The current monthly period (honours the month start day).
  final DateRange period;

  /// Totals across active *monthly* budgets (custom periods are excluded so
  /// the summary compares like with like).
  final Money totalLimit;
  final Money totalSpent;
  final Money totalCommitted;

  /// Days remaining in [period], including today.
  final int daysLeft;
  final int elapsedBps;

  /// Active budgets sorted by health (breached, warning, healthy), then by
  /// utilisation (highest first).
  final List<BudgetUsage> active;
  final List<BudgetUsage> paused;

  bool get isEmpty => active.isEmpty && paused.isEmpty;
  Money get totalRemaining => totalLimit - totalSpent;
  int get utilizationBps => totalSpent.ratioBps(totalLimit) ?? 0;
  int get breachedCount => active.where((u) => u.health == BudgetHealth.breached).length;
  int get warningCount => active.where((u) => u.health == BudgetHealth.warning).length;

  @override
  bool operator ==(Object other) =>
      other is BudgetsOverview &&
      other.period == period &&
      other.totalLimit == totalLimit &&
      other.totalSpent == totalSpent &&
      other.totalCommitted == totalCommitted &&
      other.daysLeft == daysLeft &&
      listEquals(other.active, active) &&
      listEquals(other.paused, paused);

  @override
  int get hashCode => Object.hash(period, totalLimit, totalSpent, totalCommitted, daysLeft, active.length, paused.length);
}

BudgetsOverview buildBudgetsOverview(FinanceSnapshot s) {
  final period = s.currentBudgetPeriod;
  final active = <BudgetUsage>[];
  final paused = <BudgetUsage>[];
  var limit = Money.zero;
  var spent = Money.zero;
  var committed = Money.zero;
  for (final u in s.budgetUsages) {
    if (u.budget.isPaused) {
      paused.add(u);
      continue;
    }
    active.add(u);
    if (u.budget.periodType == BudgetPeriodType.monthly) {
      limit += u.budget.limit;
      spent += u.spent;
      committed += u.committed;
    }
  }
  active.sort((a, b) {
    final h = _healthRank(a.health).compareTo(_healthRank(b.health));
    return h != 0 ? h : b.utilizationBps.compareTo(a.utilizationBps);
  });
  final daysLeft = (daysBetween(s.today, period.end) + 1).clamp(0, period.dayCount);
  final elapsed = (daysBetween(period.start, s.today) + 1) * 10000 ~/ period.dayCount;
  return BudgetsOverview(
    period: period,
    totalLimit: limit,
    totalSpent: spent,
    totalCommitted: committed,
    daysLeft: daysLeft,
    elapsedBps: elapsed.clamp(0, 10000),
    active: active,
    paused: paused,
  );
}

final budgetsOverviewProvider = Provider<AsyncValue<BudgetsOverview>>(
    (ref) => ref.watch(financeSnapshotProvider).whenData(buildBudgetsOverview));

/// Spending of one budget in one period.
@immutable
class BudgetPeriodPoint {
  const BudgetPeriodPoint({required this.period, required this.spent, required this.limit, required this.isCurrent});

  final DateRange period;
  final Money spent;
  final Money limit;
  final bool isCurrent;

  bool get isOver => spent > limit;

  @override
  bool operator ==(Object other) =>
      other is BudgetPeriodPoint &&
      other.period == period &&
      other.spent == spent &&
      other.limit == limit &&
      other.isCurrent == isCurrent;

  @override
  int get hashCode => Object.hash(period, spent, limit, isCurrent);
}

/// How many monthly periods the trend chart shows (including the current).
const budgetHistoryPeriods = 6;

/// Spending in the budget's category over recent periods, oldest first.
/// Monthly budgets: the last [budgetHistoryPeriods] monthly periods. Custom
/// budgets: the equal-length period before, then the budget's own period.
List<BudgetPeriodPoint> buildBudgetHistory(FinanceSnapshot s, Budget budget) {
  const calc = FinanceSnapshot.budgetCalc;
  final current = calc.periodFor(budget, s.today, s.monthStartDay);
  final periods = <DateRange>[current];
  if (budget.periodType == BudgetPeriodType.custom) {
    periods.insert(0, current.previous);
  } else {
    var p = current;
    for (var i = 1; i < budgetHistoryPeriods; i++) {
      p = calc.monthlyPeriod(p.start.subtract(const Duration(days: 1)), s.monthStartDay);
      periods.insert(0, p);
    }
  }
  return [
    for (final p in periods)
      BudgetPeriodPoint(
        period: p,
        spent: calc
            .usage(
              budget: budget,
              transactions: s.transactions,
              subscriptions: const [],
              today: s.today,
              monthStartDay: s.monthStartDay,
              period: p,
            )
            .spent,
        limit: budget.limit,
        isCurrent: p == current,
      ),
  ];
}

final budgetHistoryProvider = Provider.family<AsyncValue<List<BudgetPeriodPoint>>, String>((ref, id) {
  return ref.watch(financeSnapshotProvider).whenData((s) {
    final b = s.budgets.where((x) => x.id == id).firstOrNull;
    return b == null ? const <BudgetPeriodPoint>[] : buildBudgetHistory(s, b);
  });
});

/// Last month's spending in [categoryId] rounded up to the next ₹500, as a
/// starting point for a new limit. Null when there was no spending.
Money? suggestBudgetLimit(FinanceSnapshot s, String categoryId) {
  const calc = FinanceSnapshot.budgetCalc;
  final current = s.currentBudgetPeriod;
  final previous = calc.monthlyPeriod(current.start.subtract(const Duration(days: 1)), s.monthStartDay);
  final spent = s.summary(previous).byCategory.where((e) => e.key == categoryId).firstOrNull?.value;
  if (spent == null || !spent.isPositive) return null;
  const step = 50000; // ₹500 in paise
  return Money.fromPaise(roundDiv(spent.paise, step, RoundingMode.up) * step);
}

final budgetLimitSuggestionProvider = Provider.family<Money?, String>((ref, categoryId) {
  final s = ref.watch(financeSnapshotProvider).value;
  return s == null ? null : suggestBudgetLimit(s, categoryId);
});

/// Category ids that already have an active monthly budget (for the picker).
final budgetedCategoryIdsProvider = Provider<Set<String>>((ref) {
  final s = ref.watch(financeSnapshotProvider).value;
  if (s == null) return const {};
  return {
    for (final b in s.budgets)
      if (b.periodType == BudgetPeriodType.monthly && !b.isPaused) b.categoryId,
  };
});

/// Average spending of the non-current periods in [points] (null if none).
Money? averageSpentBefore(List<BudgetPeriodPoint> points) {
  final previous = points.where((p) => !p.isCurrent).toList();
  if (previous.isEmpty) return null;
  return Money.sum(previous.map((p) => p.spent)).scale(1, previous.length);
}
