import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/data_providers.dart';
import '../../../core/money/money.dart';
import '../../../core/time/dates.dart';
import '../../../finance/finance_snapshot.dart';
import '../domain/budget.dart';

/// Read models for the budgets screens: per-budget spending history and a
/// limit suggestion. Pure functions of a [FinanceSnapshot], exposed through
/// providers. The current-period overview lives in `budget_view.dart`.

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
