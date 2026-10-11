import 'package:finn/core/money/money.dart';
import 'package:finn/core/time/dates.dart';
import 'package:finn/core/time/frequency.dart';
import 'package:finn/features/budgets/domain/budget.dart';
import 'package:finn/features/budgets/domain/budget_calculator.dart';
import 'package:finn/features/subscriptions/domain/subscription.dart';
import 'package:finn/features/transactions/domain/transaction.dart';
import 'package:flutter_test/flutter_test.dart';

const calc = BudgetCalculator();
final today = DateTime(2026, 10, 10);
final stamp = DateTime(2026, 1, 1);
DateTime d(int y, int m, int day) => DateTime(y, m, day);
DateRange range(DateTime a, DateTime b) => DateRange(a, b);

Budget budget({
  Money limit = const Money.rupees(10000),
  String category = 'cat_food',
  BudgetStatus status = BudgetStatus.active,
  int warning = 8000,
  List<BudgetLimitChange> previousLimits = const [],
}) =>
    Budget(
      id: 'b1',
      categoryId: category,
      limit: limit,
      previousLimits: previousLimits,
      status: status,
      warningThresholdBps: warning,
      createdAt: stamp,
      updatedAt: stamp,
    );

int _n = 0;
Transaction tx(
  int rupees,
  DateTime date, {
  String category = 'cat_food',
  TransactionType type = TransactionType.expense,
  TransactionOrigin origin = TransactionOrigin.manual,
  String? id,
}) =>
    Transaction(
      id: id ?? 'tx_${_n++}',
      type: type,
      amount: Money.rupees(rupees),
      categoryId: category,
      date: date,
      origin: origin,
      createdAt: stamp,
      updatedAt: stamp,
    );

Subscription sub(int rupees, DateTime next, {
  String category = 'cat_food',
  Frequency frequency = Frequency.monthly,
  SubscriptionStatus status = SubscriptionStatus.active,
}) =>
    Subscription(
      id: 'sub_${_n++}',
      name: 'Sub',
      amount: Money.rupees(rupees),
      categoryId: category,
      frequency: frequency,
      nextDueDate: next,
      status: status,
      createdAt: stamp,
      updatedAt: stamp,
    );

BudgetUsage usage(Budget b, List<Transaction> txs, {List<Subscription> subs = const [], int startDay = 1, DateTime? on}) =>
    calc.usage(budget: b, transactions: txs, subscriptions: subs, today: on ?? today, monthStartDay: startDay);

void main() {
  group('monthlyPeriod', () {
    test('start day 1 is the calendar month', () {
      expect(calc.monthlyPeriod(today, 1), range(d(2026, 10, 1), d(2026, 10, 31)));
      expect(calc.monthlyPeriod(d(2026, 12, 31), 1), range(d(2026, 12, 1), d(2026, 12, 31)));
      expect(calc.monthlyPeriod(d(2028, 2, 10), 1), range(d(2028, 2, 1), d(2028, 2, 29)));
      expect(calc.monthlyPeriod(DateTime(2026, 10, 1, 23, 59), 1), range(d(2026, 10, 1), d(2026, 10, 31)));
    });

    test('start day 25 spans two months and wraps years', () {
      expect(calc.monthlyPeriod(today, 25), range(d(2026, 9, 25), d(2026, 10, 24)));
      expect(calc.monthlyPeriod(d(2026, 10, 24), 25), range(d(2026, 9, 25), d(2026, 10, 24)));
      expect(calc.monthlyPeriod(d(2026, 10, 25), 25), range(d(2026, 10, 25), d(2026, 11, 24)));
      expect(calc.monthlyPeriod(d(2026, 12, 31), 25), range(d(2026, 12, 25), d(2027, 1, 24)));
      expect(calc.monthlyPeriod(d(2027, 1, 10), 25), range(d(2026, 12, 25), d(2027, 1, 24)));
      expect(calc.monthlyPeriod(d(2027, 1, 25), 25), range(d(2027, 1, 25), d(2027, 2, 24)));
      expect(calc.monthlyPeriod(d(2028, 2, 26), 25), range(d(2028, 2, 25), d(2028, 3, 24)));
    });

    test('start days above 28 are clamped to 28', () {
      expect(calc.monthlyPeriod(d(2026, 3, 1), 31), range(d(2026, 2, 28), d(2026, 3, 27)));
      expect(calc.monthlyPeriod(d(2026, 3, 28), 30), range(d(2026, 3, 28), d(2026, 4, 27)));
    });

    test('consecutive periods tile without gaps or overlaps', () {
      for (final startDay in [1, 5, 15, 25, 28]) {
        var p = calc.monthlyPeriod(d(2026, 1, 15), startDay);
        for (var i = 0; i < 24; i++) {
          final next = calc.monthlyPeriod(p.end.add(const Duration(days: 1)), startDay);
          expect(daysBetween(p.end, next.start), 1, reason: 'start $startDay after $p');
          expect(next.start.day, startDay);
          p = next;
        }
      }
    });

    test('budget months: periodOf and monthOf agree with the start day', () {
      expect(calc.periodOf(MonthKey(2026, 9), 25), range(d(2026, 9, 25), d(2026, 10, 24)));
      expect(calc.periodOf(MonthKey(2026, 12), 1), range(d(2026, 12, 1), d(2026, 12, 31)));
      expect(calc.monthOf(today, 25), MonthKey(2026, 9));
      expect(calc.monthOf(today, 1), MonthKey(2026, 10));
    });

    test('each month uses the limit that applied then', () {
      final b = budget(previousLimits: [
        BudgetLimitChange(until: MonthKey(2026, 8), limit: const Money.rupees(6000)),
      ]);
      Money limitIn(int month) => calc
          .usage(
            budget: b,
            transactions: const [],
            subscriptions: const [],
            today: today,
            monthStartDay: 1,
            period: calc.periodOf(MonthKey(2026, month), 1),
          )
          .budget
          .limit;
      expect(limitIn(7), const Money.rupees(6000));
      expect(limitIn(8), const Money.rupees(6000));
      expect(limitIn(9), const Money.rupees(10000));
      expect(limitIn(10), const Money.rupees(10000));
    });
  });

  group('usage', () {
    test('counts only expenses in the same category inside the period', () {
      final txs = [
        tx(1000, d(2026, 10, 1)), // first day: counted
        tx(2000, d(2026, 10, 9)), // counted
        tx(500, d(2026, 10, 31)), // last day (future-dated, still in period): counted
        tx(700, d(2026, 9, 30)), // previous period
        tx(800, d(2026, 11, 1)), // next period
        tx(900, d(2026, 10, 5), category: 'cat_travel'), // other category
        tx(5000, d(2026, 10, 5), type: TransactionType.income), // income
        tx(9000, d(2026, 10, 5), origin: TransactionOrigin.loanDisbursement), // disbursement
      ];
      final u = usage(budget(), txs);
      expect(u.period, range(d(2026, 10, 1), d(2026, 10, 31)));
      expect(u.spent, const Money.rupees(3500));
      expect(u.transactionIds, [txs[0].id, txs[1].id, txs[2].id]);
      expect(u.remaining, const Money.rupees(6500));
      expect(u.utilizationBps, 3500);
      expect(u.health, BudgetHealth.healthy);
    });

    test('linked settlement / repayment expenses in the category still count', () {
      final u = usage(budget(), [tx(1200, d(2026, 10, 2), origin: TransactionOrigin.subscription)]);
      expect(u.spent, const Money.rupees(1200));
    });

    test('honours the month start day', () {
      final txs = [tx(1000, d(2026, 9, 24)), tx(2000, d(2026, 9, 25)), tx(3000, d(2026, 10, 24)), tx(4000, d(2026, 10, 25))];
      expect(usage(budget(), txs, startDay: 25).spent, const Money.rupees(5000));
      expect(usage(budget(), txs, startDay: 1).spent, const Money.rupees(7000));
    });

    test('warning at the threshold, breached only when strictly over the limit', () {
      Budget b = budget(limit: const Money.rupees(10000));
      BudgetHealth h(int spentPaise) => calc
          .usage(
            budget: b,
            transactions: [
              Transaction(
                id: 't', type: TransactionType.expense, amount: Money.fromPaise(spentPaise), categoryId: 'cat_food',
                date: d(2026, 10, 2), createdAt: stamp, updatedAt: stamp),
            ],
            subscriptions: const [],
            today: today,
            monthStartDay: 1,
          )
          .health;
      expect(h(799999), BudgetHealth.healthy);
      expect(h(800000), BudgetHealth.warning); // exactly 80%
      expect(h(1000000), BudgetHealth.warning); // exactly at the limit
      expect(h(1000001), BudgetHealth.breached); // one paisa over
      b = budget(limit: const Money.rupees(10000), warning: 5000);
      expect(h(500000), BudgetHealth.warning);
      expect(h(499999), BudgetHealth.healthy);
    });

    test('over-limit usage', () {
      final u = usage(budget(limit: const Money.rupees(1000)), [tx(1500, d(2026, 10, 2))]);
      expect(u.isOver, isTrue);
      expect(u.remaining, const Money.rupees(-500));
      expect(u.utilizationBps, 15000);
      expect(u.health, BudgetHealth.breached);
    });

    test('paused budgets report paused regardless of spending', () {
      final u = usage(budget(status: BudgetStatus.paused, limit: const Money.rupees(100)), [tx(1500, d(2026, 10, 2))]);
      expect(u.health, BudgetHealth.paused);
      expect(u.spent, const Money.rupees(1500));
    });

    test('zero limit gives zero utilisation and is breached by any spend', () {
      final u = usage(budget(limit: Money.zero), [tx(1, d(2026, 10, 2))]);
      expect(u.utilizationBps, 0);
      expect(u.health, BudgetHealth.breached);
    });

    test('committed = expected subscription charges in the rest of the period', () {
      final subs = [
        sub(499, d(2026, 10, 10)), // due today: counted
        sub(199, d(2026, 10, 25)), // later this period: counted
        sub(99, d(2026, 10, 5)), // overdue, next cycle is next month: not counted
        sub(299, d(2026, 11, 2)), // next period
        sub(149, d(2026, 10, 20), category: 'cat_travel'), // other category
        sub(999, d(2026, 10, 20), status: SubscriptionStatus.paused), // paused
        sub(50, d(2026, 10, 12), frequency: Frequency.weekly), // 12, 19, 26 Oct
      ];
      final u = usage(budget(), [tx(1000, d(2026, 10, 2))], subs: subs);
      expect(u.committed, const Money.rupees(499 + 199 + 150));
      expect(u.spent, const Money.rupees(1000), reason: 'committed is never added to spent');
      expect(u.remainingAfterCommitted, const Money.rupees(10000 - 1000 - 848));
    });

    test('committed is zero for a period that has ended and counts from period start for future periods', () {
      final subs = [sub(499, d(2026, 9, 15)), sub(100, d(2026, 11, 3))];
      final past = calc.usage(
          budget: budget(), transactions: const [], subscriptions: subs, today: today, monthStartDay: 1,
          period: range(d(2026, 9, 1), d(2026, 9, 30)));
      expect(past.committed, Money.zero);
      final future = calc.usage(
          budget: budget(), transactions: const [], subscriptions: subs, today: today, monthStartDay: 1,
          period: range(d(2026, 11, 1), d(2026, 11, 30)));
      expect(future.committed, const Money.rupees(499 + 100), reason: 'the overdue 15 Sep charge projects 15 Nov');
    });

    test('elapsed share of the period', () {
      expect(usage(budget(), const []).elapsedBps, 10 * 10000 ~/ 31);
      expect(usage(budget(), const [], on: d(2026, 10, 31)).elapsedBps, 10000);
      expect(usage(budget(), const [], on: d(2026, 10, 1)).elapsedBps, 10000 ~/ 31);
    });

    test('edits and deletes are reflected on recompute (nothing is stored)', () {
      final a = tx(3000, d(2026, 10, 2), id: 'a');
      final b = tx(4000, d(2026, 10, 3), id: 'b');
      final bud = budget();
      expect(usage(bud, [a, b]).spent, const Money.rupees(7000));
      expect(usage(bud, [a, b]).health, BudgetHealth.healthy);

      // Edit amount.
      final a2 = a.copyWith(amount: const Money.rupees(5000), version: 2);
      expect(usage(bud, [a2, b]).spent, const Money.rupees(9000));
      expect(usage(bud, [a2, b]).health, BudgetHealth.warning);
      // Re-categorise.
      final b2 = b.copyWith(categoryId: 'cat_travel', version: 2);
      expect(usage(bud, [a2, b2]).spent, const Money.rupees(5000));
      expect(usage(bud, [a2, b2]).transactionIds, ['a']);
      // Move out of the period.
      final a3 = a2.copyWith(date: d(2026, 9, 30), version: 3);
      expect(usage(bud, [a3, b2]).spent, Money.zero);
      // Delete.
      expect(usage(bud, [b]).spent, const Money.rupees(4000));
      // Limit change.
      expect(usage(bud.copyWith(limit: const Money.rupees(4000)), [a, b]).health, BudgetHealth.breached);
    });
  });
}
