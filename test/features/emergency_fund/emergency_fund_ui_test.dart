import 'package:finn/core/money/money.dart';
import 'package:finn/data/local/local_data_store.dart';
import 'package:finn/kit/kit.dart';
import 'package:finn/features/emergency_fund/domain/emergency_fund.dart';
import 'package:finn/features/emergency_fund/presentation/emergency_fund_screen.dart';
import 'package:finn/features/emergency_fund/presentation/emergency_movement_sheet.dart';
import 'package:finn/features/emergency_fund/presentation/emergency_plan_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/test_app.dart';

void _tallView(WidgetTester tester) {
  tester.view.physicalSize = const Size(400, 1400) * tester.view.devicePixelRatio;
  addTearDown(tester.view.resetPhysicalSize);
}

/// Lets toasts / overlays finish their timers.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 500));
  }
}

Future<void> _enterAmount(WidgetTester tester, int index, String text) async {
  final field = find.descendant(of: find.byWidgetPredicate((w) => w is LedgerAmountField).at(index), matching: find.byType(TextField));
  await tester.enterText(field, text);
  await tester.pump();
}

void main() {
  group('EmergencyFundScreen', () {
    testWidgets('shows coverage, plan and history for the demo plan', (tester) async {
      _tallView(tester);
      final env = await TestEnv.create();
      await env.pumpWidget(tester, const EmergencyFundScreen());
      await tester.pumpAndSettle();

      final s = (await env.snapshot()).emergency;
      expect(s.level, EmergencyFundLevel.building);
      expect(find.text('Plan'), findsOneWidget);
      expect(find.text('Monthly expenses'), findsOneWidget);
      expect(find.text('Edit plan'), findsWidgets);
      expect(find.text('Add money'), findsOneWidget);
      expect(find.text('Withdraw'), findsOneWidget);
      expect(find.text('2.5 of 6 months covered'), findsOneWidget);
      await tester.scrollUntilVisible(find.textContaining('Initial buffer'), 300);
      expect(find.textContaining('History'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('prompts to set up a plan when none exists', (tester) async {
      _tallView(tester);
      final env = await TestEnv.create(scenario: DataScenario.empty);
      await env.pumpWidget(tester, const EmergencyFundScreen());
      await tester.pumpAndSettle();

      expect(find.text('Plan your safety net'), findsOneWidget);
      expect(find.text('Set up plan'), findsOneWidget);
      expect(find.text('Monthly expenses'), findsNothing);
      expect(find.textContaining('Nothing set aside yet'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('EmergencyPlanSheet', () {
    testWidgets('saves a new plan from essentials × months', (tester) async {
      _tallView(tester);
      final env = await TestEnv.create(scenario: DataScenario.empty);
      await env.pumpWidget(tester, const EmergencyPlanSheet());
      await tester.pumpAndSettle();

      expect(find.text('Plan your emergency fund'), findsOneWidget);
      await _enterAmount(tester, 0, '40000');
      await tester.tap(find.byTooltip('More months'));
      await tester.pump();
      expect(find.text('7 months'), findsOneWidget);
      await tester.tap(find.text('3 months'));
      await tester.pump();

      await tester.tap(find.text('Save plan'));
      await tester.pump();
      if (find.text('Confirm').evaluate().isNotEmpty) {
        await tester.pumpAndSettle();
        await tester.tap(find.text('Confirm'));
      }
      await _settle(tester);

      final plan = (await env.snapshot()).emergencyPlan;
      expect(plan, isNotNull);
      expect(plan!.essentialMonthlyExpenses, const Money.rupees(40000));
      expect(plan.targetMonths, 3);
      expect(plan.target, const Money.rupees(120000));
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows an inline error when essentials are missing', (tester) async {
      _tallView(tester);
      final env = await TestEnv.create(scenario: DataScenario.empty);
      await env.pumpWidget(tester, const EmergencyPlanSheet());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save plan'));
      await tester.pump();
      expect(find.text('Enter your essential monthly spending.'), findsOneWidget);
      expect((await env.snapshot()).emergencyPlan, isNull);
    });

    testWidgets('pre-fills an existing plan', (tester) async {
      _tallView(tester);
      final env = await TestEnv.create();
      await env.pumpWidget(tester, const EmergencyPlanSheet());
      await tester.pumpAndSettle();

      expect(find.text('Edit emergency fund plan'), findsOneWidget);
      expect(find.text('6 months'), findsWidgets);
      expect(find.text('Save changes'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('EmergencyMovementSheet', () {
    testWidgets('adding money earmarks it after review', (tester) async {
      _tallView(tester);
      final env = await TestEnv.create();
      final before = (await env.snapshot()).emergency.saved;
      await env.pumpWidget(tester, const EmergencyMovementSheet());
      await tester.pumpAndSettle();

      expect(find.text('Add money to emergency fund'), findsOneWidget);
      await _enterAmount(tester, 0, '5000');
      await tester.tap(find.text('Add money'));
      await _settle(tester);
      expect(find.text('Confirm'), findsOneWidget);
      await tester.tap(find.text('Confirm'));
      await _settle(tester);

      final after = (await env.snapshot()).emergency.saved;
      expect(after, before + const Money.rupees(5000));
    });

    testWidgets('adding offers an account picker with what is free to spend; cards are not listed', (tester) async {
      _tallView(tester);
      final env = await TestEnv.create();
      await env.pumpWidget(tester, const EmergencyMovementSheet());
      await tester.pumpAndSettle();

      expect(find.text('Set aside on'), findsWidgets);
      await tester.tap(find.byType(LedgerPickerField<String>));
      await tester.pumpAndSettle();
      expect(find.textContaining('Free to spend'), findsWidgets);
      expect(find.text('SBI'), findsWidgets);
      expect(find.text('HDFC Millennia'), findsNothing, reason: 'a credit card cannot hold savings');
      await tester.tap(find.text('SBI').last);
      await tester.pumpAndSettle();

      await _enterAmount(tester, 0, '1000');
      await tester.tap(find.text('Add money'));
      await _settle(tester);
      await tester.tap(find.text('Confirm'));
      await _settle(tester);

      final moves = (await env.snapshot()).savingsMovements.where((m) => m.amount == const Money.rupees(1000));
      expect(moves.single.accountId, isNotNull);
      expect((await env.snapshot()).account(moves.single.accountId!)!.name, 'SBI');
    });

    testWidgets('withdrawing is disabled when nothing is saved', (tester) async {
      _tallView(tester);
      final env = await TestEnv.create(scenario: DataScenario.empty);
      await env.pumpWidget(tester, const EmergencyMovementSheet(withdraw: true));
      await tester.pumpAndSettle();

      expect(find.text('Nothing is saved in your emergency fund yet.'), findsOneWidget);
      final button = tester.widget<LedgerButton>(find.widgetWithText(LedgerButton, 'Withdraw'));
      expect(button.onPressed, isNull);
      expect(tester.takeException(), isNull);
    });
  });
}
