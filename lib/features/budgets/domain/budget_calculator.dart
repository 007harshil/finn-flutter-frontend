import '../../../core/money/money.dart';
import '../../../core/time/dates.dart';
import '../../subscriptions/domain/subscription.dart';
import '../../transactions/domain/transaction.dart';
import 'budget.dart';

/// Derives budget usage from transactions. Pure and deterministic.
class BudgetCalculator {
  const BudgetCalculator();

  static const _subs = SubscriptionCalculator();

  /// The monthly period containing [reference], honouring [monthStartDay]
  /// (e.g. start day 25 → 25 Sep … 24 Oct). Start days above 28 are clamped
  /// so every month has a valid start.
  DateRange monthlyPeriod(DateTime reference, int monthStartDay) {
    final day = monthStartDay.clamp(1, 28);
    final r = reference.dateOnly;
    final start = r.day >= day ? DateTime(r.year, r.month, day) : DateTime(r.year, r.month - 1, day);
    final end = DateTime(start.year, start.month + 1, day - 1);
    return DateRange(start, end);
  }

  /// The period a budget covers around [reference].
  DateRange periodFor(Budget b, DateTime reference, int monthStartDay) =>
      b.periodType == BudgetPeriodType.custom && b.customRange != null
          ? b.customRange!
          : monthlyPeriod(reference, monthStartDay);

  /// The previous period (monthly budgets only; custom → same length before).
  DateRange previousPeriod(Budget b, DateTime reference, int monthStartDay) {
    final current = periodFor(b, reference, monthStartDay);
    if (b.periodType == BudgetPeriodType.custom) return current.previous;
    return monthlyPeriod(current.start.subtract(const Duration(days: 1)), monthStartDay);
  }

  BudgetUsage usage({
    required Budget budget,
    required List<Transaction> transactions,
    required List<Subscription> subscriptions,
    required DateTime today,
    required int monthStartDay,
    DateRange? period,
  }) {
    final range = period ?? periodFor(budget, today, monthStartDay);
    var spent = 0;
    final ids = <String>[];
    for (final t in transactions) {
      if (t.isExpense &&
          t.categoryId == budget.categoryId &&
          t.countsInCashFlowAnalytics &&
          range.contains(t.date)) {
        spent += t.amount.paise;
        ids.add(t.id);
      }
    }
    // Committed: expected subscription charges in this category for the
    // rest of the period (from today), not yet recorded as transactions.
    var committed = 0;
    final t0 = today.dateOnly;
    if (!range.end.isBefore(t0)) {
      final rest = DateRange(range.start.isAfter(t0) ? range.start : t0, range.end);
      for (final s in subscriptions) {
        if (s.categoryId != budget.categoryId) continue;
        committed += s.amount.paise * _subs.occurrencesIn(s, rest).length;
      }
    }
    final spentMoney = Money.fromPaise(spent);
    // Exact comparison (spent / limit ≥ threshold), not the rounded
    // utilisation, so 79.999% never counts as reaching an 80% threshold.
    final reachedWarning = budget.limit.isPositive &&
        BigInt.from(spent) * BigInt.from(10000) >=
            BigInt.from(budget.limit.paise) * BigInt.from(budget.warningThresholdBps);
    final BudgetHealth health;
    if (budget.isPaused) {
      health = BudgetHealth.paused;
    } else if (spentMoney > budget.limit) {
      health = BudgetHealth.breached;
    } else if (reachedWarning) {
      health = BudgetHealth.warning;
    } else {
      health = BudgetHealth.healthy;
    }
    final elapsedDays = daysBetween(range.start, t0) + 1;
    final elapsedBps = (elapsedDays * 10000 ~/ range.dayCount).clamp(0, 10000);
    return BudgetUsage(
      budget: budget,
      period: range,
      spent: spentMoney,
      committed: Money.fromPaise(committed),
      transactionIds: ids,
      health: health,
      elapsedBps: elapsedBps,
    );
  }
}
