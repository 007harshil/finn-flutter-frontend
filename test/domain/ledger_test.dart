import 'package:finn/core/money/money.dart';
import 'package:finn/core/time/dates.dart';
import 'package:finn/data/mock/seed_data.dart';
import 'package:finn/features/categories/domain/category.dart';
import 'package:finn/features/goals/domain/goal.dart';
import 'package:finn/features/transactions/domain/transaction.dart';
import 'package:finn/finance/ledger.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

const ledger = LedgerCalculator();
const cashFlow = CashFlowCalculator();

void main() {
  group('LedgerCalculator.balance', () {
    test('cash = opening + inflows − outflows; earmarked = goals + EF; available = cash − earmarked', () {
      final b = ledger.balance(
        profile: fxProfile(opening: 1000),
        transactions: [
          tx(5000, d(2026, 2, 1), income: true),
          tx(1200, d(2026, 3, 1)),
          tx(300, fxToday), // on asOf: included
        ],
        movements: [
          goalMove(2000, d(2026, 4, 1)),
          goalMove(500, d(2026, 5, 1), withdraw: true),
          efMove(1000, d(2026, 6, 1)),
        ],
        asOf: fxToday,
      );
      expect(b.openingBalance, rs(1000));
      expect(b.totalInflow, rs(5000));
      expect(b.totalOutflow, rs(1500));
      expect(b.cash, rs(4500));
      expect(b.earmarkedGoals, rs(1500));
      expect(b.earmarkedEmergency, rs(1000));
      expect(b.earmarked, rs(2500));
      expect(b.available, rs(2000));
    });

    test('future-dated transactions and movements are excluded (asOf compares calendar dates)', () {
      final b = ledger.balance(
        profile: fxProfile(opening: 1000),
        transactions: [tx(999, d(2026, 10, 11), income: true), tx(1, d(2026, 10, 11))],
        movements: [efMove(700, d(2026, 10, 11))],
        asOf: DateTime(2026, 10, 10, 23, 59),
      );
      expect(b.cash, rs(1000));
      expect(b.earmarked, Money.zero);
    });

    test('transactions before the opening date are already in the opening balance', () {
      final b = ledger.balance(
        profile: fxProfile(opening: 1000, openingDate: d(2026, 3, 1)),
        transactions: [tx(300, d(2026, 2, 28)), tx(200, d(2026, 3, 1))],
        movements: const [],
        asOf: fxToday,
      );
      expect(b.totalOutflow, rs(200), reason: 'the opening day itself counts');
      expect(b.cash, rs(800));
    });

    test('without a profile the opening balance is zero and every past transaction counts', () {
      final b = ledger.balance(
        profile: null,
        transactions: [tx(300, d(2020, 1, 1)), tx(1000, d(2026, 1, 1), income: true)],
        movements: const [],
        asOf: fxToday,
      );
      expect(b.openingBalance, Money.zero);
      expect(b.cash, rs(700));
    });

    test('allocations never change cash; only available', () {
      final txs = [tx(10000, d(2026, 2, 1), income: true)];
      final before = ledger.balance(profile: fxProfile(opening: 0), transactions: txs, movements: const [], asOf: fxToday);
      final after = ledger.balance(
        profile: fxProfile(opening: 0),
        transactions: txs,
        movements: [goalMove(4000, d(2026, 3, 1)), efMove(1000, d(2026, 3, 1))],
        asOf: fxToday,
      );
      expect(after.cash, before.cash);
      expect(after.available, before.available - rs(5000));
    });

    test('available can go negative when cash falls below earmarked money', () {
      final b = ledger.balance(
        profile: fxProfile(opening: 1000),
        transactions: [tx(900, d(2026, 5, 1))],
        movements: [goalMove(500, d(2026, 4, 1))],
        asOf: fxToday,
      );
      expect(b.available, rs(-400));
    });

    test('paise are exact', () {
      final b = ledger.balance(
        profile: fxProfile(opening: 0),
        transactions: [
          tx(0, d(2026, 2, 1)).copyWith(amount: Money.fromPaise(10)),
          tx(0, d(2026, 2, 1)).copyWith(amount: Money.fromPaise(20)),
        ],
        movements: const [],
        asOf: fxToday,
      );
      expect(b.cash, Money.fromPaise(-30));
    });

    test('BalanceSnapshot equality and empty', () {
      expect(BalanceSnapshot.empty.cash, Money.zero);
      expect(BalanceSnapshot.empty.available, Money.zero);
      final a = ledger.balance(profile: fxProfile(), transactions: const [], movements: const [], asOf: fxToday);
      final b = ledger.balance(profile: fxProfile(), transactions: const [], movements: const [], asOf: fxToday);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == BalanceSnapshot.empty, isFalse);
    });
  });

  test('bucketBalance sums one bucket, including future-dated movements', () {
    final ms = [
      goalMove(1000, d(2026, 3, 1)),
      goalMove(300, d(2026, 4, 1), withdraw: true),
      goalMove(50, d(2026, 12, 1)),
      goalMove(9999, d(2026, 3, 1), goalId: 'g2'),
      efMove(777, d(2026, 3, 1)),
    ];
    expect(ledger.bucketBalance(ms, SavingsBucketType.goal, 'g1'), rs(750));
    expect(ledger.bucketBalance(ms, SavingsBucketType.goal, 'g2'), rs(9999));
    expect(ledger.bucketBalance(ms, SavingsBucketType.emergencyFund, SavingsMovement.emergencyFundBucketId), rs(777));
    expect(ledger.bucketBalance(ms, SavingsBucketType.goal, 'missing'), Money.zero);
  });

  group('CashFlowCalculator.summarize', () {
    final october = MonthKey(2026, 10).range;

    test('loan disbursements are neither income nor spending; repayments and settlements are spending', () {
      final s = cashFlow.summarize([
        tx(100000, d(2026, 10, 1), income: true),
        tx(500000, d(2026, 10, 2), income: true, category: SystemCategories.loanReceived, origin: TransactionOrigin.loanDisbursement),
        tx(50000, d(2026, 10, 2), category: SystemCategories.loanGiven, origin: TransactionOrigin.loanDisbursement),
        tx(12602, d(2026, 10, 5), category: SystemCategories.loanEmi, origin: TransactionOrigin.loanRepayment),
        tx(2000, d(2026, 10, 6), category: SystemCategories.settlementPaid, origin: TransactionOrigin.pendingSettlement),
      ], october);
      expect(s.income, rs(100000));
      expect(s.expense, rs(14602));
      expect(s.transactionCount, 3);
      expect(s.net, rs(85398));
    });

    test('range is inclusive at both ends', () {
      final s = cashFlow.summarize([
        tx(1, d(2026, 9, 30)),
        tx(10, d(2026, 10, 1)),
        tx(100, d(2026, 10, 31)),
        tx(1000, d(2026, 11, 1)),
      ], october);
      expect(s.expense, rs(110));
      expect(s.transactionCount, 2);
    });

    test('per-category, per-account and per-channel totals are sorted descending', () {
      final s = cashFlow.summarize([
        tx(300, d(2026, 10, 1), category: SeedCategoryIds.food, accountId: 'acc_sbi', channel: 'UPI'),
        tx(700, d(2026, 10, 2), category: SeedCategoryIds.rent, accountId: 'acc_axis', channel: 'NEFT'),
        tx(200, d(2026, 10, 3), category: SeedCategoryIds.food, accountId: 'acc_sbi', channel: 'UPI'),
        tx(50, d(2026, 10, 4), category: SeedCategoryIds.travel),
        tx(9999, d(2026, 10, 4), income: true),
      ], october);
      expect(s.byCategory.map((e) => e.key), [SeedCategoryIds.rent, SeedCategoryIds.food, SeedCategoryIds.travel]);
      expect(s.byCategory.map((e) => e.value), [rs(700), rs(500), rs(50)]);
      expect(s.byAccount.map((e) => e.key), ['acc_axis', 'acc_sbi', 'acc_cash']);
      expect(s.byChannel.map((e) => e.key), ['NEFT', 'UPI']);
      expect(s.byChannel.map((e) => e.value), [rs(700), rs(500)]);
      expect(Money.sum(s.byCategory.map((e) => e.value)), s.expense);
      expect(Money.sum(s.byAccount.map((e) => e.value)), s.expense);
    });

    test('savings rate in basis points; null without income', () {
      final s = cashFlow.summarize([tx(80000, d(2026, 10, 1), income: true), tx(60000, d(2026, 10, 2))], october);
      expect(s.savingsRateBps, 2500);
      final deficit = cashFlow.summarize([tx(1000, d(2026, 10, 1), income: true), tx(1500, d(2026, 10, 2))], october);
      expect(deficit.savingsRateBps, -5000);
      expect(cashFlow.summarize([tx(10, d(2026, 10, 2))], october).savingsRateBps, isNull);
      expect(cashFlow.summarize(const [], october).savingsRateBps, isNull);
    });
  });
}
