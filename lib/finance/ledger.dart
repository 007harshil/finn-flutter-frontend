import 'package:flutter/foundation.dart';

import '../core/money/money.dart';
import '../core/time/dates.dart';
import '../features/accounts/domain/money_account.dart';
import '../features/accounts/domain/transfer.dart';
import '../features/goals/domain/goal.dart';
import '../features/settings/domain/financial_profile.dart';
import '../features/transactions/domain/transaction.dart';

/// Where the user's money stands.
///
/// ```
/// asset account balance = opening + income - expense + transfers in - out
/// credit card owed      = opening - (income - expense + transfers in - out)
/// cash       = sum of asset account balances      (archived included)
/// creditOwed = sum of credit-card owed
/// earmarked  = sum of goal allocations + emergency-fund allocations
/// available  = cash - earmarked
/// ```
/// Only movements dated on/after each account's opening date and on/before
/// today count. Allocations move money between *available* and
/// *earmarked*; they never change [cash] or net worth.
@immutable
class BalanceSnapshot {
  const BalanceSnapshot({
    required this.openingBalance,
    required this.totalInflow,
    required this.totalOutflow,
    required this.earmarkedGoals,
    required this.earmarkedEmergency,
    this.accounts = const [],
    this.creditOwed = Money.zero,
  });

  static const empty = BalanceSnapshot(
    openingBalance: Money.zero,
    totalInflow: Money.zero,
    totalOutflow: Money.zero,
    earmarkedGoals: Money.zero,
    earmarkedEmergency: Money.zero,
  );

  /// Sum of the opening balances of asset accounts.
  final Money openingBalance;

  /// Money into asset accounts from outside (income, credit-card advances).
  /// Transfers between asset accounts are neither inflow nor outflow.
  final Money totalInflow;

  /// Money out of asset accounts to outside (expenses, card bill payments).
  final Money totalOutflow;
  final Money earmarkedGoals;
  final Money earmarkedEmergency;

  /// Every account with its balance, ordered by sortOrder then createdAt.
  final List<AccountBalance> accounts;

  /// Total owed on credit cards (a liability, never part of [cash]).
  final Money creditOwed;

  /// Total money in asset accounts.
  Money get cash => openingBalance + totalInflow - totalOutflow;
  Money get earmarked => earmarkedGoals + earmarkedEmergency;
  Money get available => cash - earmarked;

  /// Balance (owed for credit cards) of one account; null when unknown.
  Money? balanceOf(String accountId) => accounts.where((a) => a.account.id == accountId).firstOrNull?.balance;

  @override
  bool operator ==(Object other) =>
      other is BalanceSnapshot &&
      other.openingBalance == openingBalance &&
      other.totalInflow == totalInflow &&
      other.totalOutflow == totalOutflow &&
      other.earmarkedGoals == earmarkedGoals &&
      other.earmarkedEmergency == earmarkedEmergency &&
      other.creditOwed == creditOwed &&
      listEquals(other.accounts, accounts);

  @override
  int get hashCode =>
      Object.hash(openingBalance, totalInflow, totalOutflow, earmarkedGoals, earmarkedEmergency, creditOwed, accounts.length);
}

/// Display order of accounts: sortOrder, then createdAt, then id.
List<MoneyAccount> sortAccounts(Iterable<MoneyAccount> accounts) => List<MoneyAccount>.unmodifiable(
  List<MoneyAccount>.of(accounts)..sort((a, b) {
    final o = a.sortOrder.compareTo(b.sortOrder);
    if (o != 0) return o;
    final c = a.createdAt.compareTo(b.createdAt);
    return c != 0 ? c : a.id.compareTo(b.id);
  }),
);

class LedgerCalculator {
  const LedgerCalculator();

  /// Movements dated after [asOf] (scheduled/future) are excluded, as are
  /// movements dated before the account's own opening date (already
  /// reflected in its opening balance).
  ///
  /// With no [accounts] (a user not yet bootstrapped) a synthetic Cash
  /// account is derived from the [profile] opening balance, and every
  /// transaction counts against it.
  BalanceSnapshot balance({
    required FinancialProfile? profile,
    required List<Transaction> transactions,
    required List<SavingsMovement> movements,
    required DateTime asOf,
    List<MoneyAccount> accounts = const [],
    List<Transfer> transfers = const [],
  }) {
    final to = asOf.dateOnly;
    final legacy = accounts.isEmpty;
    final list = legacy
        ? [
            MoneyAccount(
              id: cashAccountId,
              name: 'Cash',
              kind: MoneyAccountKind.cash,
              opening: profile?.openingBalance ?? Money.zero,
              openingDate: profile?.openingDate.dateOnly ?? DateTime(1970),
              isDefault: true,
              createdAt: DateTime(1970),
              updatedAt: DateTime(1970),
            ),
          ]
        : sortAccounts(accounts);
    final byId = {for (final a in list) a.id: a};

    // flow(a) in paise: income - expense + transfers in - transfers out.
    final flow = <String, int>{for (final a in list) a.id: 0};
    var inflow = 0;
    var outflow = 0;

    bool counts(MoneyAccount a, DateTime d) => !d.isAfter(to) && !d.isBefore(a.openingDate.dateOnly);

    for (final t in transactions) {
      final a = byId[legacy ? cashAccountId : t.accountId];
      if (a == null || !counts(a, t.date)) continue;
      flow[a.id] = flow[a.id]! + t.signedAmount.paise;
      if (!a.isLiability) {
        if (t.isIncome) {
          inflow += t.amount.paise;
        } else {
          outflow += t.amount.paise;
        }
      }
    }
    for (final tr in transfers) {
      final from = byId[tr.fromAccountId];
      final dest = byId[tr.toAccountId];
      final outCounts = from != null && counts(from, tr.date);
      final inCounts = dest != null && counts(dest, tr.date);
      if (outCounts) flow[from.id] = flow[from.id]! - tr.amount.paise;
      if (inCounts) flow[dest.id] = flow[dest.id]! + tr.amount.paise;
      final fromAsset = outCounts && !from.isLiability;
      final toAsset = inCounts && !dest.isLiability;
      if (fromAsset && toAsset) continue; // internal move between assets
      if (fromAsset) outflow += tr.amount.paise;
      if (toAsset) inflow += tr.amount.paise;
    }

    var opening = 0;
    var owed = 0;
    final balances = <AccountBalance>[];
    for (final a in list) {
      final f = flow[a.id]!;
      if (a.isLiability) {
        final o = a.opening.paise - f;
        owed += o;
        balances.add(AccountBalance(account: a, balance: Money.fromPaise(o)));
      } else {
        opening += a.opening.paise;
        balances.add(AccountBalance(account: a, balance: Money.fromPaise(a.opening.paise + f)));
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
      openingBalance: Money.fromPaise(opening),
      totalInflow: Money.fromPaise(inflow),
      totalOutflow: Money.fromPaise(outflow),
      earmarkedGoals: Money.fromPaise(goals),
      earmarkedEmergency: Money.fromPaise(emergency),
      accounts: List.unmodifiable(balances),
      creditOwed: Money.fromPaise(owed),
    );
  }

  /// Net movement on one account between [from] and [to] (inclusive):
  /// income - expense + transfers in - transfers out. The sign is the same
  /// for every kind; credit cards owe `opening - flow`.
  Money accountFlow({
    required String accountId,
    required DateTime from,
    required DateTime to,
    required List<Transaction> transactions,
    required List<Transfer> transfers,
  }) {
    final lo = from.dateOnly;
    final hi = to.dateOnly;
    bool within(DateTime d) => !d.isBefore(lo) && !d.isAfter(hi);
    var flow = 0;
    for (final t in transactions) {
      if (t.accountId == accountId && within(t.date)) flow += t.signedAmount.paise;
    }
    for (final tr in transfers) {
      if (!within(tr.date)) continue;
      if (tr.toAccountId == accountId) flow += tr.amount.paise;
      if (tr.fromAccountId == accountId) flow -= tr.amount.paise;
    }
    return Money.fromPaise(flow);
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
    required this.byAccount,
    required this.byChannel,
    required this.transactionCount,
  });

  final DateRange range;

  /// Excludes loan disbursements (not income).
  final Money income;

  /// Excludes money lent (not spending). Includes EMIs and settlements.
  final Money expense;

  /// Expense per category id, sorted descending.
  final List<MapEntry<String, Money>> byCategory;

  /// Expense per account id, sorted descending.
  final List<MapEntry<String, Money>> byAccount;

  /// Expense per channel (only transactions that have one), sorted descending.
  final List<MapEntry<String, Money>> byChannel;
  final int transactionCount;

  Money get net => income - expense;

  /// Net / income in basis points; null when there is no income.
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
    final account = <String, int>{};
    final channel = <String, int>{};
    for (final t in transactions) {
      if (!range.contains(t.date) || !t.countsInCashFlowAnalytics) continue;
      count++;
      if (t.isIncome) {
        income += t.amount.paise;
      } else {
        expense += t.amount.paise;
        cat[t.categoryId] = (cat[t.categoryId] ?? 0) + t.amount.paise;
        account[t.accountId] = (account[t.accountId] ?? 0) + t.amount.paise;
        final ch = t.channel;
        if (ch != null && ch.isNotEmpty) channel[ch] = (channel[ch] ?? 0) + t.amount.paise;
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
      byAccount: sorted(account),
      byChannel: sorted(channel),
      transactionCount: count,
    );
  }
}
