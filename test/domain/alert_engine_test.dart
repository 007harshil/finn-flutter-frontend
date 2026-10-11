import 'package:finn/data/mock/seed_data.dart';
import 'package:finn/features/alerts/domain/alert.dart';
import 'package:finn/features/alerts/domain/alert_engine.dart';
import 'package:finn/features/budgets/domain/budget.dart';
import 'package:finn/features/goals/domain/goal.dart';
import 'package:finn/features/loans/domain/loan.dart';
import 'package:finn/features/pending/domain/pending_payment.dart';
import 'package:finn/features/settings/domain/app_settings.dart';
import 'package:finn/features/subscriptions/domain/subscription.dart';
import 'package:finn/finance/finance_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

const engine = AlertEngine();
const settings = AppSettings();

/// Default for most tests: the "set up your emergency fund" nudge fires for
/// any non-fresh user, so it is silenced unless a test is about it.
const quiet = AppSettings(disabledAlertTypes: {AlertType.emergencyFundNotSet});

List<FinancialAlert> alertsFor(FinanceSnapshot s, {AppSettings config = quiet}) => engine.generate(s, config);

/// One past transaction so the user is not "fresh".
final _activity = [tx(100, d(2026, 9, 1))];

void main() {
  group('loans', () {
    test('an overdue borrowed EMI is critical and cannot be dismissed', () {
      final a = alertsFor(snapshotOf(loans: [emiLoan(start: d(2026, 9, 1), firstDue: d(2026, 10, 5))])).single;
      expect(a.type, AlertType.emiOverdue);
      expect(a.severity, AlertSeverity.critical);
      expect(a.key, 'loan_overdue:loan1:1');
      expect(a.dismissible, isFalse);
      expect(a.target, AlertTarget.loan);
      expect(a.recordId, 'loan1');
      expect(a.dueDate, d(2026, 10, 5));
      expect(a.amount, rs(12602));
      expect(a.actionLabel, 'Record payment');
    });

    test('an overdue repayment on a lent loan is a warning', () {
      final a = alertsFor(snapshotOf(loans: [
        emiLoan(start: d(2026, 9, 1), firstDue: d(2026, 10, 5), direction: LoanDirection.lent),
      ])).single;
      expect(a.type, AlertType.emiOverdue);
      expect(a.severity, AlertSeverity.warning);
      expect(a.actionLabel, 'Record receipt');
    });

    test('upcoming EMI within the reminder window (inclusive)', () {
      List<FinancialAlert> due(DateTime first) =>
          alertsFor(snapshotOf(loans: [emiLoan(start: d(2026, 9, 1), firstDue: first)]));
      expect(due(d(2026, 10, 14)).single.type, AlertType.emiDue);
      expect(due(d(2026, 10, 15)).single.key, 'loan_due:loan1:1');
      expect(due(d(2026, 10, 10)).single.severity, AlertSeverity.warning);
      expect(due(d(2026, 10, 16)), isEmpty);
      final wider = alertsFor(snapshotOf(loans: [emiLoan(start: d(2026, 9, 1), firstDue: d(2026, 10, 16))]),
          config: quiet.copyWith(emiReminderDays: 6));
      expect(wider.single.type, AlertType.emiDue);
    });

    test('fully repaid loans raise nothing', () {
      final s = snapshotOf(
        loans: [emiLoan(principal: 10000, start: d(2026, 9, 1), firstDue: d(2026, 10, 5))],
        loanPayments: [loanPayment('loan1', d(2026, 9, 20), interestPaise: 0, principalPaise: 1000000)],
      );
      expect(alertsFor(s), isEmpty);
    });
  });

  group('pending', () {
    test('items open over 21 days are informative, never late, and show the days passed', () {
      final s = snapshotOf(pending: [
        pendingPayment(id: 'owe', counterparty: 'Ramesh', created: d(2026, 8, 31), due: d(2026, 9, 5)),
        pendingPayment(id: 'collect', direction: PendingDirection.owedToMe, created: d(2026, 9, 1)),
      ]);
      final byKey = {for (final a in alertsFor(s)) a.key: a};
      final owe = byKey['pending_aged:owe']!;
      expect(owe.type, AlertType.pendingOverdue);
      expect(owe.severity, AlertSeverity.info);
      expect(owe.title, 'You owe Ramesh ₹5,000');
      expect(owe.message, contains('pending for 40 days'));
      expect(owe.dueDate, isNull);
      expect((owe.visual! as AgedVisual).daysOpen, 40);
      expect((owe.visual! as AgedVisual).outgoing, isTrue);
      expect(byKey['pending_aged:collect']!.type, AlertType.collectDue);
      expect(byKey['pending_aged:collect']!.severity, AlertSeverity.info);
    });

    test('nothing shows until more than 21 days have passed', () {
      List<FinancialAlert> openFor(int days) =>
          alertsFor(snapshotOf(pending: [pendingPayment(id: 'p', created: fxToday.subtract(Duration(days: days)))]));
      expect(openFor(21), isEmpty);
      expect(openFor(22).single.key, 'pending_aged:p');
    });

    test('the alert amount is the outstanding balance after partial settlements', () {
      final s = snapshotOf(
        pending: [pendingPayment(id: 'p', amount: 5000, due: d(2026, 10, 1))],
        settlements: [settlement('p', 2000, d(2026, 9, 15))],
      );
      expect(alertsFor(s).single.amount, rs(3000));
    });

    test('recent, settled and cancelled obligations raise nothing, whatever the due date', () {
      final s = snapshotOf(
        pending: [
          pendingPayment(id: 'recent', created: d(2026, 9, 25), due: d(2026, 10, 1)),
          pendingPayment(id: 'done', due: d(2026, 10, 1)),
          pendingPayment(id: 'x', due: d(2026, 10, 1), cancelled: true),
        ],
        settlements: [settlement('done', 5000, d(2026, 9, 30))],
      );
      expect(alertsFor(s), isEmpty);
    });
  });

  group('subscriptions', () {
    test('unpaid past cycle → warning; renewal within the window → info', () {
      final s = snapshotOf(subscriptions: [
        subscription(id: 'late', nextDue: d(2026, 10, 8)),
        subscription(id: 'soon', name: 'Spotify', nextDue: d(2026, 10, 12)),
        subscription(id: 'today', name: 'iCloud', nextDue: d(2026, 10, 10)),
        subscription(id: 'later', nextDue: d(2026, 10, 20)),
        subscription(id: 'paused', nextDue: d(2026, 10, 1), status: SubscriptionStatus.paused),
      ]);
      final byKey = {for (final a in alertsFor(s)) a.key: a};
      expect(byKey.keys.toSet(), {'sub_overdue:late:2026-10-08', 'sub_due:soon:2026-10-12', 'sub_due:today:2026-10-10'});
      expect(byKey['sub_overdue:late:2026-10-08']!.severity, AlertSeverity.warning);
      expect(byKey['sub_due:soon:2026-10-12']!.title, 'Spotify renews in 2 days');
      expect(byKey['sub_due:today:2026-10-10']!.title, 'iCloud renews today');
      expect(byKey['sub_due:soon:2026-10-12']!.severity, AlertSeverity.info);
    });
  });

  group('budgets', () {
    Budget food({BudgetStatus status = BudgetStatus.active}) =>
        budget(id: 'food', limit: 10000, status: status);

    test('reaching the warning threshold exactly is a warning', () {
      final a = alertsFor(snapshotOf(budgets: [food()], transactions: [tx(8000, d(2026, 10, 2))])).single;
      expect(a.type, AlertType.budgetNearLimit);
      expect(a.severity, AlertSeverity.warning);
      expect(a.key, 'budget:food:2026-10-01:w');
      expect(a.dueDate, d(2026, 10, 31));
    });

    test('just below the threshold is quiet; over the limit is critical', () {
      expect(alertsFor(snapshotOf(budgets: [food()], transactions: [tx(7999, d(2026, 10, 2))])), isEmpty);
      final a = alertsFor(snapshotOf(budgets: [food()], transactions: [tx(12000, d(2026, 10, 2))])).single;
      expect(a.type, AlertType.budgetBreached);
      expect(a.severity, AlertSeverity.critical);
      expect(a.title, contains('Food & Dining is over budget'));
      expect(a.amount, rs(12000));
    });

    test('paused budgets and last month\'s spending raise nothing', () {
      expect(alertsFor(snapshotOf(budgets: [food(status: BudgetStatus.paused)], transactions: [tx(12000, d(2026, 10, 2))])),
          isEmpty);
      expect(alertsFor(snapshotOf(budgets: [food()], transactions: [tx(12000, d(2026, 9, 30))])), isEmpty);
    });
  });

  group('emergency fund', () {
    test('not set up: a nudge, but only once the user has activity', () {
      expect(alertsFor(snapshotOf(), config: settings), isEmpty, reason: 'fresh user');
      final a = alertsFor(snapshotOf(transactions: _activity), config: settings).single;
      expect(a.key, 'ef_not_set');
      expect(a.type, AlertType.emergencyFundNotSet);
    });

    test('coverage below the setting: info while building, warning when critical', () {
      final building = alertsFor(snapshotOf(
              transactions: _activity, emergencyPlan: efPlan(), movements: [efMove(100000, d(2026, 7, 1))]),
              config: settings)
          .single;
      expect(building.key, 'ef_low:2026-10');
      expect(building.severity, AlertSeverity.info);
      expect(building.title, 'Emergency fund covers 2.5 months');

      final critical = alertsFor(snapshotOf(transactions: _activity, emergencyPlan: efPlan()), config: settings).single;
      expect(critical.severity, AlertSeverity.warning);

      final enough = alertsFor(snapshotOf(
          transactions: _activity, emergencyPlan: efPlan(), movements: [efMove(120000, d(2026, 7, 1))]),
          config: settings);
      expect(enough, isEmpty, reason: '3.0 months is not below the 3-month setting');
    });
  });

  group('goals', () {
    test('fully funded → positive milestone', () {
      final a = alertsFor(snapshotOf(goals: [savingsGoal()], movements: [goalMove(100000, d(2026, 8, 1))])).single;
      expect(a.key, 'goal_done:g1');
      expect(a.severity, AlertSeverity.positive);
    });

    test('75% funded → milestone', () {
      final a = alertsFor(snapshotOf(goals: [savingsGoal()], movements: [goalMove(75000, d(2026, 8, 1))]))
          .where((a) => a.type == AlertType.goalMilestone)
          .single;
      expect(a.key, 'goal_75:g1');
    });

    test('behind schedule within a year → at risk; further out stays quiet', () {
      final risk = alertsFor(snapshotOf(goals: [savingsGoal(targetDate: d(2027, 3, 10), planned: 5000)])).single;
      expect(risk.type, AlertType.goalAtRisk);
      expect(risk.key, 'goal_risk:g1:2026-10');
      expect(risk.dueDate, d(2027, 3, 10));
      expect(alertsFor(snapshotOf(goals: [savingsGoal(targetDate: d(2028, 1, 1), planned: 1000)])), isEmpty);
    });

    test('archived goals raise nothing', () {
      final s = snapshotOf(
        goals: [savingsGoal(status: GoalStatus.archived)],
        movements: [goalMove(100000, d(2026, 8, 1))],
      );
      expect(alertsFor(s), isEmpty);
    });
  });

  group('monthly deficit', () {
    test('spending above income this month', () {
      final a = alertsFor(snapshotOf(
        emergencyPlan: efPlan(essentials: 1),
        movements: [efMove(100, d(2026, 1, 1))],
        transactions: [tx(1000, d(2026, 10, 1), income: true), tx(2000, d(2026, 10, 2))],
      )).single;
      expect(a.type, AlertType.monthlyDeficit);
      expect(a.key, 'deficit:2026-10');
    });

    test('no income this month → no deficit alert', () {
      final s = snapshotOf(
        emergencyPlan: efPlan(essentials: 1),
        movements: [efMove(100, d(2026, 1, 1))],
        transactions: [tx(2000, d(2026, 10, 2))],
      );
      expect(alertsFor(s).where((a) => a.type == AlertType.monthlyDeficit), isEmpty);
    });
  });

  test('disabled alert types are filtered out', () {
    final s = snapshotOf(budgets: [budget(id: 'food')], transactions: [tx(12000, d(2026, 10, 2))]);
    expect(alertsFor(s, config: settings).length, 2);
    expect(alertsFor(s, config: settings.copyWith(disabledAlertTypes: {AlertType.budgetBreached, AlertType.emergencyFundNotSet})),
        isEmpty);
  });

  group('ordering', () {
    FinanceSnapshot busy({bool reversed = false}) {
      List<T> o<T>(List<T> l) => reversed ? l.reversed.toList() : l;
      return snapshotOf(
        transactions: o([tx(12000, d(2026, 10, 2)), tx(1000, d(2026, 10, 1), income: true)]),
        budgets: o([budget(id: 'food'), budget(id: 'travel', category: SeedCategoryIds.travel)]),
        loans: o([
          emiLoan(id: 'a', start: d(2026, 9, 1), firstDue: d(2026, 10, 5)),
          emiLoan(id: 'b', start: d(2026, 9, 1), firstDue: d(2026, 10, 12)),
          emiLoan(id: 'c', start: d(2026, 9, 1), firstDue: d(2026, 10, 12)),
        ]),
        pending: o([
          pendingPayment(id: 'p1', due: d(2026, 10, 3)),
          pendingPayment(id: 'p2', direction: PendingDirection.owedToMe, created: d(2026, 7, 1)),
        ]),
        subscriptions: o([subscription(id: 's1', nextDue: d(2026, 10, 11))]),
        goals: o([savingsGoal()]),
        movements: o([goalMove(100000, d(2026, 8, 1))]),
      );
    }

    test('sorted by severity, then due date (dated first), then key', () {
      final list = alertsFor(busy());
      expect(list.length, greaterThan(6));
      for (var i = 1; i < list.length; i++) {
        final a = list[i - 1], b = list[i];
        expect(a.severity.rank <= b.severity.rank, isTrue, reason: '${a.key} before ${b.key}');
        if (a.severity == b.severity) {
          if (a.dueDate == null) expect(b.dueDate, isNull, reason: 'undated alerts come last');
          if (a.dueDate != null && b.dueDate != null) {
            expect(a.dueDate!.isAfter(b.dueDate!), isFalse);
            if (a.dueDate == b.dueDate) expect(a.key.compareTo(b.key) < 0, isTrue);
          }
        }
      }
      expect(list.first.severity, AlertSeverity.critical);
      expect(list.last.severity, AlertSeverity.positive);
    });

    test('deterministic regardless of record order', () {
      expect(alertsFor(busy(reversed: true)).map((a) => a.key).toList(), alertsFor(busy()).map((a) => a.key).toList());
    });

    test('keys are unique', () {
      final keys = alertsFor(busy()).map((a) => a.key).toList();
      expect(keys.toSet().length, keys.length);
    });
  });
}
