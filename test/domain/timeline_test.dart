import 'package:finn/core/time/dates.dart';
import 'package:finn/data/mock/seed_data.dart';
import 'package:finn/features/categories/domain/category.dart';
import 'package:finn/features/loans/domain/loan.dart';
import 'package:finn/features/pending/domain/pending_payment.dart';
import 'package:finn/features/timeline/domain/timeline.dart';
import 'package:finn/features/transactions/domain/transaction.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

const timeline = TimelineService();
final oct = MonthKey(2026, 10);

void main() {
  group('eventsFor', () {
    test('manual income becomes an income event; salary gets its own story', () {
      final s = snapshotOf(transactions: [
        tx(100000, d(2026, 10, 1), income: true, id: 'sal'),
        tx(5000, d(2026, 10, 2), income: true, category: SeedCategoryIds.freelance, id: 'fl'),
      ]);
      final events = timeline.eventsFor(s, oct.range);
      expect(events.map((e) => e.title), ['Money came in', 'Hard work paid off']);
      final salary = events.last;
      expect(salary.kind, TimelineEventKind.income);
      expect(salary.id, 'tl_sal');
      expect(salary.route, '/transactions/sal');
      expect(salary.isInflow, isTrue);
      expect(salary.amount, rs(100000));
    });

    test('major expense: ₹5,000 floor without history', () {
      final s = snapshotOf(transactions: [
        tx(4999, d(2026, 10, 1), category: SeedCategoryIds.shopping),
        tx(5000, d(2026, 10, 2), category: SeedCategoryIds.travel),
      ]);
      final e = timeline.eventsFor(s, oct.range).single;
      expect(e.kind, TimelineEventKind.majorExpense);
      expect(e.title, 'Expanding horizons');
      expect(e.theme, StoryTheme.adventurous);
      expect(e.isInflow, isFalse);
    });

    test('major expense: 1.4× the average manual expense of the previous three months', () {
      final history = [
        tx(8000, d(2026, 7, 1)),
        tx(12000, d(2026, 9, 30)),
        tx(90000, d(2026, 6, 30)), // before the window
        tx(90000, d(2026, 8, 5), category: SystemCategories.loanEmi, origin: TransactionOrigin.loanRepayment), // not manual
      ];
      final s = snapshotOf(transactions: [
        ...history,
        tx(13999, d(2026, 10, 1), category: SeedCategoryIds.shopping),
        tx(14000, d(2026, 10, 2), category: SeedCategoryIds.shopping, id: 'big'),
      ]);
      final e = timeline.eventsFor(s, oct.range).single;
      expect(e.id, 'tl_big');
      expect(e.title, 'Personal upgrade');
    });

    test('future-dated transactions are not part of the story yet', () {
      final s = snapshotOf(transactions: [tx(100000, d(2026, 10, 20), income: true)]);
      expect(timeline.eventsFor(s, oct.range), isEmpty);
    });

    test('subscription payments of ₹1,000 or more link to the subscription', () {
      final s = snapshotOf(transactions: [
        tx(1499, d(2026, 10, 3), category: SeedCategoryIds.subscriptions, origin: TransactionOrigin.subscription,
            originRefId: 'sub_1', counterparty: 'Adobe'),
        tx(199, d(2026, 10, 3), category: SeedCategoryIds.subscriptions, origin: TransactionOrigin.subscription,
            originRefId: 'sub_2'),
      ]);
      final e = timeline.eventsFor(s, oct.range).single;
      expect(e.kind, TimelineEventKind.subscriptionPaid);
      expect(e.title, 'Adobe renewed');
      expect(e.route, '/more/subscriptions/sub_1');
    });

    test('loan payments: EMI, prepayment and money received back', () {
      final s = snapshotOf(
        loans: [emiLoan(id: 'car'), emiLoan(id: 'ravi', name: 'Loan to Ravi', direction: LoanDirection.lent)],
        loanPayments: [
          loanPayment('car', d(2026, 10, 5), interestPaise: 400000, principalPaise: 860200, period: 9),
          loanPayment('car', d(2026, 10, 6), interestPaise: 0, principalPaise: 5000000),
          loanPayment('ravi', d(2026, 10, 7), interestPaise: 0, principalPaise: 100000, period: 1),
          loanPayment('gone', d(2026, 10, 7), interestPaise: 0, principalPaise: 100000, period: 1),
        ],
      );
      final events = timeline.eventsFor(s, oct.range);
      expect(events.map((e) => e.title), ['Ravi repaid you', 'Power move on Car loan', 'Car loan instalment']);
      expect(events.first.isInflow, isTrue);
      expect(events[1].theme, StoryTheme.growth);
      expect(events.last.amount, rs(12602));
      expect(events.last.route, '/more/loans/car');
    });

    test('savings movements: goal contributions, withdrawals and the emergency fund', () {
      final s = snapshotOf(
        goals: [savingsGoal()],
        movements: [
          goalMove(5000, d(2026, 10, 1)),
          goalMove(1000, d(2026, 10, 2), withdraw: true),
          efMove(3000, d(2026, 10, 3)),
        ],
      );
      final events = timeline.eventsFor(s, oct.range);
      expect(events.map((e) => e.kind), [
        TimelineEventKind.emergencyContribution,
        TimelineEventKind.goalWithdrawal,
        TimelineEventKind.goalContribution,
      ]);
      expect(events.last.title, 'Closer to Japan trip');
      expect(events.last.route, '/goals/g1');
      expect(events.last.isInflow, isFalse, reason: 'earmarking takes money out of available cash');
      expect(events[1].isInflow, isTrue);
      expect(events.first.route, '/goals/emergency-fund');
      expect(events.first.title, 'Safety net strengthened');
    });

    test('settlements in both directions', () {
      final s = snapshotOf(
        pending: [
          pendingPayment(id: 'owe', counterparty: 'Priya'),
          pendingPayment(id: 'get', counterparty: 'Arjun', direction: PendingDirection.owedToMe),
        ],
        settlements: [settlement('owe', 500, d(2026, 10, 2)), settlement('get', 700, d(2026, 10, 3))],
      );
      final events = timeline.eventsFor(s, oct.range);
      expect(events.map((e) => e.title), ['Arjun paid you back', 'Squared away with Priya']);
      expect(events.map((e) => e.isInflow), [true, false]);
      expect(events.first.route, '/more/pending/get');
    });

    test('events are newest first and limited to the range', () {
      final s = snapshotOf(transactions: [
        tx(1000, d(2026, 9, 30), income: true),
        tx(1000, d(2026, 10, 1), income: true),
        tx(1000, d(2026, 10, 9), income: true),
      ]);
      final events = timeline.eventsFor(s, oct.range);
      expect(events.map((e) => e.date), [d(2026, 10, 9), d(2026, 10, 1)]);
    });
  });

  group('chapter names', () {
    test('Debt Slayer when more than two loan payments', () {
      final s = snapshotOf(
        loans: [emiLoan(id: 'car')],
        loanPayments: [
          for (var i = 1; i <= 3; i++) loanPayment('car', d(2026, 10, i), interestPaise: 0, principalPaise: 100, period: i),
        ],
      );
      expect(timeline.chapter(s, oct).name, 'The Debt Slayer');
    });

    test('Visionary Path when more than one goal contribution', () {
      final s = snapshotOf(goals: [savingsGoal()], movements: [goalMove(1, d(2026, 10, 1)), goalMove(1, d(2026, 10, 2))]);
      expect(timeline.chapter(s, oct).name, 'The Visionary Path');
    });

    test('Wealth Spring, Big Spend and Steady Stream', () {
      final spring = snapshotOf(transactions: [tx(1000, d(2026, 10, 1), income: true)]);
      expect(timeline.chapter(spring, oct).name, 'The Wealth Spring');
      final spend = snapshotOf(transactions: [
        tx(1000, d(2026, 10, 1), income: true),
        tx(6000, d(2026, 10, 2)),
        tx(7000, d(2026, 10, 3)),
      ]);
      expect(timeline.chapter(spend, oct).name, 'The Big Spend');
      final steady = snapshotOf();
      final c = timeline.chapter(steady, oct);
      expect(c.name, 'The Steady Stream');
      expect(c.events, isEmpty);
      expect(c.month, oct);
    });
  });

  test('availableMonths: current month plus months with transactions, newest first, never future', () {
    final s = snapshotOf(transactions: [
      tx(1, d(2026, 7, 3)),
      tx(1, d(2026, 7, 9)),
      tx(1, d(2026, 9, 1)),
      tx(1, d(2026, 12, 1)),
    ]);
    expect(timeline.availableMonths(s), [oct, MonthKey(2026, 9), MonthKey(2026, 7)]);
    expect(timeline.availableMonths(snapshotOf()), [oct]);
  });
}
