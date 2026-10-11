import 'package:finn/data/mock/seed_data.dart';
import 'package:finn/features/budgets/application/budget_view.dart';
import 'package:finn/features/budgets/domain/budget.dart';
import 'package:finn/features/budgets/presentation/budget_charts.dart';
import 'package:finn/features/budgets/presentation/budget_detail_screen.dart';
import 'package:finn/features/budgets/presentation/budgets_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/test_app.dart';

void _tallView(WidgetTester tester) {
  tester.view.physicalSize = const Size(400, 1600) * tester.view.devicePixelRatio;
  addTearDown(tester.view.resetPhysicalSize);
}

void main() {
  group('BudgetsScreen', () {
    testWidgets('pulse card, status tabs and sort options narrow the list', (tester) async {
      _tallView(tester);
      final env = await TestEnv.create();
      final s = await env.snapshot();
      final pulse = buildBudgetsPulse(s);
      await env.pumpWidget(tester, const BudgetsScreen());
      await tester.pumpAndSettle();

      expect(find.text('LEFT TO SPEND THIS MONTH'), findsOneWidget);
      for (final p in pulse.paces) {
        expect(find.byKey(ValueKey(p.usage.budget.id)), findsOneWidget);
      }
      expect(find.text('${pulse.paces.length} BUDGETS'), findsOneWidget);

      // Paused tab shows only the paused budget.
      await tester.ensureVisible(find.byKey(const ValueKey('budget-tab:paused')));
      await tester.tap(find.byKey(const ValueKey('budget-tab:paused')));
      await tester.pumpAndSettle();
      final paused = pulse.paces.where((p) => p.state == BudgetState.paused).toList();
      expect(find.text('${paused.length} ${paused.length == 1 ? 'BUDGET' : 'BUDGETS'}'), findsOneWidget);
      expect(find.byKey(ValueKey(paused.single.usage.budget.id)), findsOneWidget);
      expect(find.byKey(ValueKey(pulse.paces.firstWhere((p) => p.state != BudgetState.paused).usage.budget.id)),
          findsNothing);

      // Back to all, then sort by name through the options sheet.
      await tester.ensureVisible(find.byKey(const ValueKey('budget-tab:all')));
      await tester.tap(find.byKey(const ValueKey('budget-tab:all')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('budget-options')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('budget-sort:name')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('budget-apply')));
      await tester.pumpAndSettle();
      expect(find.text('Name'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('fits a 320 px screen without overflow', (tester) async {
      tester.view.physicalSize = const Size(320, 1400) * tester.view.devicePixelRatio;
      addTearDown(tester.view.resetPhysicalSize);
      final env = await TestEnv.create();
      await env.pumpWidget(tester, const BudgetsScreen());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('BudgetDetailScreen', () {
    testWidgets('gauge, pace stats, chart readout and filters', (tester) async {
      _tallView(tester);
      final env = await TestEnv.create();
      final s = await env.snapshot();
      final food = s.budgetUsages.firstWhere(
        (u) => u.budget.categoryId == SeedCategoryIds.food && u.budget.periodType == BudgetPeriodType.monthly,
      );
      await env.pumpWidget(tester, BudgetDetailScreen(id: food.budget.id));
      await tester.pumpAndSettle();

      expect(find.text(food.isOver ? 'OVER BY' : 'LEFT'), findsOneWidget);
      expect(find.text('SAFE PER DAY'), findsOneWidget);
      expect(find.text('AT THIS PACE'), findsOneWidget);
      expect(find.text('SO FAR'), findsOneWidget);

      // Tapping the chart reads a day and filters the list to it.
      final chart = find.byType(BurnChart);
      await tester.tapAt(tester.getTopLeft(chart) + const Offset(4, 60));
      await tester.pumpAndSettle();
      expect(find.text('SO FAR'), findsNothing);
      expect(find.byKey(const ValueKey('budget-day-chip')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('budget-day-chip')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('budget-day-chip')), findsNothing);

      // Payee chip filters the list to that payee.
      final burn = buildBudgetBurn(s, food);
      final top = topPayees(burn.transactions).first;
      await tester.tap(find.byKey(ValueKey('budget-payee:${top.$1}')));
      await tester.pumpAndSettle();
      expect(find.text('${top.$3}'), findsOneWidget);

      // History view.
      await tester.tap(find.textContaining('LAST'));
      await tester.pumpAndSettle();
      expect(find.text('AVERAGE BEFORE'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
