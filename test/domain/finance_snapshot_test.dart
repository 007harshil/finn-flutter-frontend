import 'package:finn/core/money/money.dart';
import 'package:finn/core/time/dates.dart';
import 'package:finn/data/local/local_data_store.dart';
import 'package:finn/features/goals/domain/goal.dart';
import 'package:finn/features/loans/domain/loan.dart';
import 'package:finn/features/pending/domain/pending_payment.dart';
import 'package:finn/finance/finance_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

import '../actions/action_harness.dart';
import 'fixtures.dart';

void main() {
  for (final scenario in [DataScenario.demo, DataScenario.stressed]) {
    group('${scenario.name} seed: every projection agrees with the raw records', () {
      late FinanceSnapshot s;

      setUpAll(() async {
        final h = await ActionHarness.create(scenario: scenario);
        s = await h.snapshot();
      });

      test('cash = opening + Σ signed transactions between the opening date and today', () {
        final from = s.profile!.openingDate.dateOnly;
        final expected = Money.sum([
          s.profile!.openingBalance,
          for (final t in s.transactions)
            if (!t.date.isBefore(from) && !t.date.isAfter(s.today)) t.signedAmount,
        ]);
        expect(s.balance.cash, expected);
      });

      test('earmarked = Σ goal saved + emergency fund saved', () {
        final goalIds = {for (final g in s.goals) g.id};
        expect(s.savingsMovements.where((m) => m.bucketType == SavingsBucketType.goal).every((m) => goalIds.contains(m.bucketId)),
            isTrue, reason: 'no orphaned goal movements in the seed');
        expect(s.balance.earmarkedGoals, Money.sum(s.goalProgress.map((g) => g.saved)));
        expect(s.balance.earmarkedEmergency, s.emergency.saved);
        expect(s.balance.available, s.balance.cash - s.balance.earmarked);
      });

      test('net worth counts cash once and splits liabilities/receivables consistently', () {
        final nw = s.netWorth;
        expect(nw.cash, s.balance.cash);
        expect(nw.assets, Money.sum(s.assets.map((a) => a.value)));
        final lent = Money.sum(s.loanStates.where((l) => !l.loan.isBorrowed).map((l) => l.outstanding));
        expect(nw.receivables, lent + s.pendingToCollect);
        expect(nw.liabilities, s.totalDebt + s.pendingToPay);
        expect(nw.netWorth, nw.cash + nw.assets + nw.receivables - nw.liabilities);
      });

      test('pending totals equal the outstanding of each direction', () {
        Money sum(PendingDirection dir) =>
            Money.sum(s.pendingViews.where((p) => p.payment.direction == dir).map((p) => p.outstanding));
        expect(s.pendingToPay, sum(PendingDirection.iOwe));
        expect(s.pendingToCollect, sum(PendingDirection.owedToMe));
      });

      test('one derived view per record, addressable by id', () {
        expect(s.budgetUsages.length, s.budgets.length);
        expect(s.goalProgress.length, s.goals.length);
        expect(s.loanStates.length, s.loans.length);
        expect(s.pendingViews.length, s.pending.length);
        for (final b in s.budgets) {
          expect(s.budgetUsage(b.id)!.budget, b);
        }
        for (final l in s.loans) {
          expect(s.loan(l.id)!.loan, l);
        }
        expect(s.budgetUsage('missing'), isNull);
        expect(s.goal('missing'), isNull);
        expect(s.loan('missing'), isNull);
        expect(s.pendingView('missing'), isNull);
      });

      test('transactions are newest first and indexed by id', () {
        for (var i = 1; i < s.transactions.length; i++) {
          expect(s.transactions[i - 1].date.isBefore(s.transactions[i].date), isFalse);
        }
        expect(s.transactionById.length, s.transactions.length);
      });

      test('linked transactions point back to their origin record', () {
        for (final l in s.loans) {
          for (final t in s.linkedTransactions(l.id)) {
            expect(t.originRefId, l.id);
            expect(t.isLinked, isTrue);
          }
        }
      });
    });
  }

  group('FinanceSnapshot', () {
    test('today is normalised to a calendar date', () {
      final s = snapshotOf(today: DateTime(2026, 10, 10, 18, 30));
      expect(s.today, d(2026, 10, 10));
      expect(s.currentMonth, MonthKey(2026, 10));
    });

    test('summaries are memoised per range', () {
      final s = snapshotOf(transactions: [tx(100, d(2026, 10, 1))]);
      final a = s.monthSummary(MonthKey(2026, 10));
      final b = s.summary(MonthKey(2026, 10).range);
      expect(identical(a, b), isTrue);
      expect(s.memoisedSummaryCount, 1);
      s.monthSummary(MonthKey(2026, 9));
      expect(s.memoisedSummaryCount, 2);
    });

    test('lazy projections are computed once', () {
      final s = snapshotOf(profile: fxProfile());
      expect(identical(s.balance, s.balance), isTrue);
      expect(identical(s.netWorth, s.netWorth), isTrue);
      expect(identical(s.budgetUsages, s.budgetUsages), isTrue);
    });

    test('empty snapshot is a fresh user with zero balances', () {
      final s = FinanceSnapshot.empty(fxToday);
      expect(s.isFreshUser, isTrue);
      expect(s.balance.cash, Money.zero);
      expect(s.netWorth.netWorth, Money.zero);
      expect(s.totalDebt, Money.zero);
      expect(s.monthlySubscriptionCommitment, Money.zero);
    });

    test('any transaction, pending, loan or goal ends the fresh-user state', () {
      expect(snapshotOf(transactions: [tx(1, d(2026, 10, 1))]).isFreshUser, isFalse);
      expect(snapshotOf(pending: [pendingPayment()]).isFreshUser, isFalse);
      expect(snapshotOf(loans: [emiLoan()]).isFreshUser, isFalse);
      expect(snapshotOf(goals: [savingsGoal()]).isFreshUser, isFalse);
      expect(snapshotOf(assets: [asset('Gold', 1)]).isFreshUser, isTrue);
    });

    test('totalDebt ignores lent and closed loans', () {
      final s = snapshotOf(loans: [
        emiLoan(id: 'b', principal: 100000),
        emiLoan(id: 'l', principal: 50000, direction: LoanDirection.lent),
        emiLoan(id: 'c', principal: 70000, status: LoanStatus.closed),
      ]);
      expect(s.totalDebt, rs(100000));
    });
  });
}
