import 'package:finn/core/money/money.dart';
import 'package:finn/design_system/design_system.dart';
import 'package:finn/features/alerts/domain/alert.dart';
import 'package:finn/features/alerts/presentation/alert_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

FinancialAlert _alert(AlertType type, AlertSeverity severity, AlertVisual visual, {Money? amount}) => FinancialAlert(
      key: type.name,
      type: type,
      severity: severity,
      title: 'Title',
      message: 'Message.',
      reason: 'Reason.',
      actionLabel: 'Act now',
      target: AlertTarget.transactions,
      amount: amount,
      visual: visual,
    );

final _cases = <String, FinancialAlert>{
  'overdue EMI': _alert(
    AlertType.emiOverdue,
    AlertSeverity.critical,
    const DueVisual(outgoing: true, party: DueParty.bank, counterparty: 'HDFC Bank', daysUntil: -3),
    amount: const Money.rupees(12400),
  ),
  'collect': _alert(
    AlertType.collectDue,
    AlertSeverity.warning,
    const DueVisual(outgoing: false, party: DueParty.person, counterparty: 'Rahul', daysUntil: 0),
    amount: const Money.rupees(800),
  ),
  'renewal': _alert(
    AlertType.subscriptionRenewal,
    AlertSeverity.info,
    const DueVisual(outgoing: true, party: DueParty.service, counterparty: 'Netflix', daysUntil: 2, recurring: true),
    amount: const Money.rupees(649),
  ),
  'aged': _alert(
    AlertType.collectDue,
    AlertSeverity.info,
    const AgedVisual(counterparty: 'Asha', daysOpen: 41),
    amount: const Money.rupees(2000),
  ),
  'aged to pay': _alert(
    AlertType.pendingOverdue,
    AlertSeverity.info,
    const AgedVisual(counterparty: 'Ramesh', daysOpen: 40, outgoing: true),
    amount: const Money.rupees(1500),
  ),
  'budget over': _alert(
    AlertType.budgetBreached,
    AlertSeverity.critical,
    const BudgetVisual(category: 'Food', spent: Money.rupees(9300), limit: Money.rupees(7000), daysLeft: 9),
  ),
  'safety net': _alert(
    AlertType.emergencyFundLow,
    AlertSeverity.info,
    const SafetyNetVisual(
      saved: Money.rupees(60000),
      target: Money.rupees(300000),
      coverageMonths: 1.2,
      targetMonths: 6,
    ),
  ),
  'no safety net': _alert(AlertType.emergencyFundNotSet, AlertSeverity.info, const SafetyNetVisual()),
  'goal reached': _alert(
    AlertType.goalMilestone,
    AlertSeverity.positive,
    const GoalVisual(name: 'Bike', saved: Money.rupees(90000), target: Money.rupees(90000)),
  ),
  'goal behind': _alert(
    AlertType.goalAtRisk,
    AlertSeverity.info,
    GoalVisual(
      name: 'Trip',
      saved: const Money.rupees(10000),
      target: const Money.rupees(80000),
      requiredMonthly: const Money.rupees(11667),
      targetDate: DateTime(2027, 4),
    ),
  ),
  'deficit': _alert(
    AlertType.monthlyDeficit,
    AlertSeverity.warning,
    const CashFlowVisual(income: Money.rupees(50000), expense: Money.rupees(61000)),
  ),
};

void main() {
  for (final entry in _cases.entries) {
    testWidgets('alert card draws "${entry.key}" in a carousel slot and settles', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: FinnTheme.light(),
        home: Scaffold(
          body: Center(
            child: SizedBox(width: 300, height: 220, child: AlertCard(alert: entry.value, expand: true, position: 1, total: 3)),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Act now'), findsOneWidget);
      expect(find.text('1/3'), findsOneWidget);
    });
  }

  testWidgets('headline speaks in figures, not sentences', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: FinnTheme.light(),
      home: Scaffold(body: AlertCard(alert: _cases['budget over']!)),
    ));
    await tester.pumpAndSettle();
    expect(find.text('₹2,300 over'), findsOneWidget);
    expect(find.text('Food budget'), findsOneWidget);
    expect(find.text('Limit crossed'), findsOneWidget);
  });

  testWidgets('long-pending payment shows days passed, never "late"', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: FinnTheme.light(),
      home: Scaffold(body: AlertCard(alert: _cases['aged to pay']!)),
    ));
    await tester.pumpAndSettle();
    expect(find.text('You owe Ramesh'), findsOneWidget);
    expect(find.text('40 days pending'), findsOneWidget);
    expect(find.textContaining('late'), findsNothing);
  });
}
