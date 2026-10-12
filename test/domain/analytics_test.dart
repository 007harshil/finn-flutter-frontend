import 'package:finn/core/money/money.dart';
import 'package:finn/core/time/dates.dart';
import 'package:finn/data/mock/seed_data.dart';
import 'package:finn/features/analytics/domain/analytics.dart';
import 'package:finn/features/categories/domain/category.dart';
import 'package:finn/features/loans/domain/loan.dart';
import 'package:finn/features/transactions/domain/transaction.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

const analytics = AnalyticsService();
final oct = MonthKey(2026, 10);
final sep = MonthKey(2026, 9);

void main() {
  test('cashFlow returns [count] months ending with [last], oldest first', () {
    final s = snapshotOf(
      transactions: [
        tx(50000, d(2026, 8, 1), income: true),
        tx(60000, d(2026, 9, 1), income: true),
        tx(20000, d(2026, 9, 2)),
        tx(70000, d(2026, 10, 1), income: true),
      ],
    );
    final flow = analytics.cashFlow(s, oct, 3);
    expect(flow.map((m) => m.month), [MonthKey(2026, 8), sep, oct]);
    expect(flow.map((m) => m.income), [rs(50000), rs(60000), rs(70000)]);
    expect(flow[1].expense, rs(20000));
    expect(flow[1].net, rs(40000));
  });

  group('categoryBreakdown', () {
    final s = snapshotOf(
      transactions: [
        tx(5000, d(2026, 9, 3), category: SeedCategoryIds.food),
        tx(6000, d(2026, 10, 3), category: SeedCategoryIds.food),
        tx(3000, d(2026, 10, 4), category: SeedCategoryIds.rent),
        tx(1000, d(2026, 10, 5), category: 'cat_unknown'),
      ],
    );

    test('shares and comparison with the previous period', () {
      final slices = analytics.categoryBreakdown(s, oct.range, compareTo: sep.range);
      expect(slices.map((x) => x.categoryId), [SeedCategoryIds.food, SeedCategoryIds.rent, 'cat_unknown']);
      expect(slices.map((x) => x.shareBps), [6000, 3000, 1000]);
      expect(slices.first.name, 'Food & Dining');
      expect(slices.first.previous, rs(5000));
      expect(slices.first.changeBps, 2000);
      expect(slices[1].previous, Money.zero);
      expect(slices[1].changeBps, isNull, reason: 'no honest % change from zero');
      expect(slices.last.name, 'Uncategorised');
    });

    test('without a comparison period previous is null', () {
      final slices = analytics.categoryBreakdown(s, oct.range);
      expect(slices.every((x) => x.previous == null && x.changeBps == null), isTrue);
    });
  });

  group('compare', () {
    final s = snapshotOf(
      transactions: [
        tx(900, d(2026, 8, 31)),
        tx(1000, d(2026, 9, 21)),
        tx(400, d(2026, 9, 30)),
        tx(2000, d(2026, 10, 5)),
      ],
    );

    test('a calendar month is compared with the previous calendar month', () {
      final c = analytics.compare(s, oct.range);
      expect(c.previous.range, sep.range);
      expect(c.previous.expense, rs(1400), reason: '31 Aug is not part of September');
      expect(c.current.expense, rs(2000));
      expect(c.expenseChangeBps, 4286);
      expect(c.incomeChangeBps, isNull);
    });

    test('other ranges are compared with the same number of days before', () {
      final c = analytics.compare(s, DateRange(d(2026, 10, 1), d(2026, 10, 10)));
      expect(c.previous.range, DateRange(d(2026, 9, 21), d(2026, 9, 30)));
      expect(c.previous.expense, rs(1400));
    });
  });

  test('debtTrend: outstanding borrowed principal at each month end (today for the current month)', () {
    final s = snapshotOf(
      loans: [
        emiLoan(id: 'b', principal: 100000, start: d(2026, 8, 1), firstDue: d(2026, 9, 5)),
        emiLoan(id: 'l', principal: 50000, direction: LoanDirection.lent, start: d(2026, 1, 1)),
      ],
      loanPayments: [loanPayment('b', d(2026, 9, 15), interestPaise: 0, principalPaise: 2500000)],
    );
    final trend = analytics.debtTrend(s, oct, 4);
    expect(trend.map((p) => p.month), [MonthKey(2026, 7), MonthKey(2026, 8), sep, oct]);
    expect(trend.map((p) => p.value), [Money.zero, rs(100000), rs(75000), rs(75000)]);
  });

  test('savingsTrend: cumulative earmarked total at each month end', () {
    final s = snapshotOf(
      movements: [
        goalMove(10000, d(2026, 8, 10)),
        efMove(5000, d(2026, 9, 1)),
        goalMove(2000, d(2026, 9, 30), withdraw: true),
      ],
    );
    final trend = analytics.savingsTrend(s, sep, 3);
    expect(trend.map((p) => p.value), [Money.zero, rs(10000), rs(13000)]);
  });

  test('dailyBurn divides by elapsed days only', () {
    final s = snapshotOf(transactions: [tx(1000, d(2026, 10, 3)), tx(3000, d(2026, 9, 15))]);
    expect(analytics.dailyBurn(s, oct.range), rs(100), reason: '10 days elapsed');
    expect(analytics.dailyBurn(s, sep.range), rs(100));
    expect(analytics.dailyBurn(s, MonthKey(2026, 11).range), Money.zero);
  });

  test('discretionaryShareBps excludes essential and system categories from the numerator', () {
    final s = snapshotOf(
      transactions: [
        tx(600, d(2026, 10, 1), category: SeedCategoryIds.food),
        tx(300, d(2026, 10, 1), category: SeedCategoryIds.rent),
        tx(100, d(2026, 10, 1), category: SystemCategories.loanEmi, origin: TransactionOrigin.loanRepayment),
      ],
    );
    expect(analytics.discretionaryShareBps(s, oct.range), 6000);
    expect(analytics.discretionaryShareBps(snapshotOf(), oct.range), isNull);
  });

  test('goalContributions nets contributions and withdrawals in range', () {
    final ms = [
      goalMove(1000, d(2026, 10, 1)),
      goalMove(300, d(2026, 10, 2), withdraw: true),
      goalMove(50, d(2026, 9, 30)),
    ];
    expect(analytics.goalContributions(ms, oct.range), rs(700));
  });

  group('insights and narrative', () {
    final s = snapshotOf(
      transactions: [
        tx(100000, d(2026, 9, 1), income: true),
        tx(5000, d(2026, 9, 3), category: SeedCategoryIds.food),
        tx(4000, d(2026, 9, 4), category: SeedCategoryIds.shopping),
        tx(100000, d(2026, 10, 1), income: true),
        tx(8000, d(2026, 10, 3), category: SeedCategoryIds.food),
        tx(2000, d(2026, 10, 4), category: SeedCategoryIds.shopping),
        tx(20000, d(2026, 10, 5), category: SeedCategoryIds.rent),
      ],
      subscriptions: [subscription(amount: 649)],
      movements: [goalMove(5000, d(2026, 10, 6))],
      loans: [emiLoan(id: 'b')],
      loanPayments: [loanPayment('b', d(2026, 10, 5), interestPaise: 475000, principalPaise: 785200, period: 9)],
    );

    test('savings rate, rising and falling categories, top category, subscriptions', () {
      final list = analytics.insights(s, oct);
      expect(list.take(4).map((i) => i.title), [
        'You kept 70% of your income',
        'Food & Dining is up 60%',
        'Shopping is down 50%',
        'Top category: Rent & Housing',
      ]);
      expect(list.last.title, startsWith('Subscriptions take'));
      expect(list.map((i) => i.tone), [
        InsightTone.positive,
        InsightTone.caution,
        InsightTone.positive,
        InsightTone.neutral,
        InsightTone.neutral,
      ]);
    });

    test('spending above income is a caution, never a judgement', () {
      final deficit = snapshotOf(transactions: [tx(1000, d(2026, 10, 1), income: true), tx(1500, d(2026, 10, 2))]);
      final first = analytics.insights(deficit, oct).first;
      expect(first.title, 'Spending exceeded income');
      expect(first.tone, InsightTone.caution);
      expect(analytics.insights(snapshotOf(), oct), isEmpty);
    });

    test('monthly narrative for the current month', () {
      final lines = analytics.monthlyNarrative(s, oct);
      expect(lines.first, startsWith('So far this month you have spent'));
      expect(lines.first, contains('more than all of last month'));
      expect(lines[1], startsWith('Rent & Housing was your largest spend'));
      expect(lines, contains(predicate<String>((l) => l.startsWith('You moved') && l.contains('goals'))));
      expect(lines.last, startsWith('Loan principal went down by'));
    });

    test('narrative for a month without data and for a past month without comparison', () {
      expect(analytics.monthlyNarrative(s, MonthKey(2026, 7)).single, 'No transactions recorded for July 2026 yet.');
      final past = analytics.monthlyNarrative(s, sep);
      expect(past.first, startsWith('You spent'));
      expect(past.first, contains('and received'));
    });
  });
}
