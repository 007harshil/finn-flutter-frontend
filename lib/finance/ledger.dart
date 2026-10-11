import 'package:flutter/foundation.dart';

import '../core/money/money.dart';
import '../core/time/dates.dart';
import '../features/goals/domain/goal.dart';
import '../features/settings/domain/financial_profile.dart';
import '../features/transactions/domain/transaction.dart';

/// Where the user's cash stands.
///
/// ```
/// cash       = opening balance + Σ inflows − Σ outflows   (completed only)
/// earmarked  = Σ goal allocations + Σ emergency-fund allocations
/// available  = cash − earmarked
/// ```
/// Allocations move money between *available* and *earmarked*; they never
/// change [cash] or net worth.
@immutable
class BalanceSnapshot {
  const BalanceSnapshot({
    required this.openingBalance,
    required this.totalInflow,
    required this.totalOutflow,
    required this.earmarkedGoals,
    required this.earmarkedEmergency,
  });

  static const empty = BalanceSnapshot(
    openingBalance: Money.zero,
    totalInflow: Money.zero,
    totalOutflow: Money.zero,
    earmarkedGoals: Money.zero,
    earmarkedEmergency: Money.zero,
  );

  final Money openingBalance;
  final Money totalInflow;
  final Money totalOutflow;
  final Money earmarkedGoals;
  final Money earmarkedEmergency;

  Money get cash => openingBalance + totalInflow - totalOutflow;
  Money get earmarked => earmarkedGoals + earmarkedEmergency;
  Money get available => cash - earmarked;

  @override
  bool operator ==(Object other) =>
      other is BalanceSnapshot &&
      other.openingBalance == openingBalance &&
      other.totalInflow == totalInflow &&
      other.totalOutflow == totalOutflow &&
      other.earmarkedGoals == earmarkedGoals &&
      other.earmarkedEmergency == earmarkedEmergency;

  @override
  int get hashCode =>
      Object.hash(openingBalance, totalInflow, totalOutflow, earmarkedGoals, earmarkedEmergency);
}

class LedgerCalculator {
  const LedgerCalculator();

  /// Transactions dated after [asOf] (scheduled/future) are excluded, as
  /// are transactions before the profile's opening date (already reflected
  /// in the opening balance).
  BalanceSnapshot balance({
    required FinancialProfile? profile,
    required List<Transaction> transactions,
    required List<SavingsMovement> movements,
    required DateTime asOf,
  }) {
    final opening = profile?.openingBalance ?? Money.zero;
    final from = profile?.openingDate.dateOnly;
    final to = asOf.dateOnly;
    var inflow = 0;
    var outflow = 0;
    for (final t in transactions) {
      final d = t.date;
      if (d.isAfter(to)) continue;
      if (from != null && d.isBefore(from)) continue;
      if (t.isIncome) {
        inflow += t.amount.paise;
      } else {
        outflow += t.amount.paise;
      }
    }
    var goals = 0;
    var emergency = 0;
    for (final m in movements) {
      if (m.date.isAfter(to)) continue;
      if (m.bucketType == SavingsBucketType.goal) {
        goals += m.signedAmount.paise;
      } else {
        emergency += m.signedAmount.paise;
      }
    }
    return BalanceSnapshot(
      openingBalance: opening,
      totalInflow: Money.fromPaise(inflow),
      totalOutflow: Money.fromPaise(outflow),
      earmarkedGoals: Money.fromPaise(goals),
      earmarkedEmergency: Money.fromPaise(emergency),
    );
  }

  /// Saved amount in one bucket.
  Money bucketBalance(List<SavingsMovement> movements, SavingsBucketType type, String bucketId) {
    var total = 0;
    for (final m in movements) {
      if (m.bucketType == type && m.bucketId == bucketId) total += m.signedAmount.paise;
    }
    return Money.fromPaise(total);
  }
}

/// Income vs spending for a date range (analytics view of cash flow).
@immutable
class PeriodSummary {
  const PeriodSummary({
    required this.range,
    required this.income,
    required this.expense,
    required this.byCategory,
    required this.byMethod,
    required this.transactionCount,
  });

  final DateRange range;

  /// Excludes loan disbursements (not income).
  final Money income;

  /// Excludes money lent (not spending). Includes EMIs and settlements.
  final Money expense;

  /// Expense per category id, sorted descending.
  final List<MapEntry<String, Money>> byCategory;

  /// Expense per payment method, sorted descending.
  final List<MapEntry<PaymentMethod, Money>> byMethod;
  final int transactionCount;

  Money get net => income - expense;

  /// Net ÷ income in basis points; null when there is no income.
  int? get savingsRateBps => net.ratioBps(income);

  @override
  bool operator ==(Object other) =>
      other is PeriodSummary &&
      other.range == range &&
      other.income == income &&
      other.expense == expense &&
      other.transactionCount == transactionCount;

  @override
  int get hashCode => Object.hash(range, income, expense, transactionCount);
}

class CashFlowCalculator {
  const CashFlowCalculator();

  PeriodSummary summarize(List<Transaction> transactions, DateRange range) {
    var income = 0;
    var expense = 0;
    var count = 0;
    final cat = <String, int>{};
    final method = <PaymentMethod, int>{};
    for (final t in transactions) {
      if (!range.contains(t.date) || !t.countsInCashFlowAnalytics) continue;
      count++;
      if (t.isIncome) {
        income += t.amount.paise;
      } else {
        expense += t.amount.paise;
        cat[t.categoryId] = (cat[t.categoryId] ?? 0) + t.amount.paise;
        final pm = t.paymentMethod ?? PaymentMethod.other;
        method[pm] = (method[pm] ?? 0) + t.amount.paise;
      }
    }
    List<MapEntry<K, Money>> sorted<K>(Map<K, int> m) =>
        (m.entries.map((e) => MapEntry(e.key, Money.fromPaise(e.value))).toList()
          ..sort((a, b) => b.value.compareTo(a.value)));
    return PeriodSummary(
      range: range,
      income: Money.fromPaise(income),
      expense: Money.fromPaise(expense),
      byCategory: sorted(cat),
      byMethod: sorted(method),
      transactionCount: count,
    );
  }
}
