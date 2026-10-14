import 'package:finn/core/time/dates.dart';
import 'package:finn/data/mock/seed_data.dart';
import 'package:finn/design_system/design_system.dart';
import 'package:finn/features/budgets/application/budget_view.dart';
import 'package:finn/features/budgets/presentation/budget_charts.dart';
import 'package:finn/features/budgets/presentation/budget_detail_screen.dart';
import 'package:finn/features/budgets/presentation/budgets_screen.dart';
import 'package:finn/shared/presentation/transaction_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/test_app.dart';

void _tallView(WidgetTester tester) {
  tester.view.physicalSize = const Size(400, 1600) * tester.view.devicePixelRatio;
  addTearDown(tester.view.resetPhysicalSize);
}

void main() {
  group('BudgetsScreen', () {
    testWidgets('month hero, status chips and sort narrow the list', (tester) async {
      _tallView(tester);
      final env = await TestEnv.create();
      final s = await env.snapshot();
      final pulse = buildBudgetsPulse(s);
      await env.pumpWidget(tester, const BudgetsScreen());
      await tester.pumpAndSettle();

      expect(find.text('Left to spend'), findsOneWidget);
      for (final p in pulse.paces) {
        expect(find.byKey(ValueKey(p.usage.budget.id)), findsOneWidget);
      }

      // Paused chip shows only the paused budget.
      await tester.ensureVisible(find.byKey(const ValueKey('budget-tab:paused')));
      await tester.tap(find.byKey(const ValueKey('budget-tab:paused')));
      await tester.pumpAndSettle();
      final paused = pulse.paces.where((p) => p.state == BudgetState.paused).toList();
      expect(find.byKey(ValueKey(paused.single.usage.budget.id)), findsOneWidget);
      expect(find.byKey(ValueKey(pulse.paces.firstWhere((p) => p.state != BudgetState.paused).usage.budget.id)),
          findsNothing);

      // Back to all, then sort by name through the sort menu.
      await tester.ensureVisible(find.byKey(const ValueKey('budget-tab:all')));
      await tester.tap(find.byKey(const ValueKey('budget-tab:all')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('budget-options')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(BudgetSort.name.label));
      await tester.pumpAndSettle();
      final byName = [...pulse.paces]
        ..sort((a, b) => s.categoryById[a.usage.budget.categoryId]!.name
            .toLowerCase()
            .compareTo(s.categoryById[b.usage.budget.categoryId]!.name.toLowerCase()));
      final ys = [for (final p in byName) tester.getTopLeft(find.byKey(ValueKey(p.usage.budget.id))).dy];
      expect(ys, [...ys]..sort());
      expect(tester.takeException(), isNull);
    });

    testWidgets('previous months open read-only and come back to this month', (tester) async {
      _tallView(tester);
      final env = await TestEnv.create();
      final s = await env.snapshot();
      final september = s.budgetUsagesFor(MonthKey(2026, 9));
      await env.pumpWidget(tester, const BudgetsScreen());
      await tester.pumpAndSettle();
      expect(find.text('New budget'), findsOneWidget);

      await tester.tap(find.byTooltip('Previous month'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Read-only'), findsOneWidget);
      expect(find.text('New budget'), findsNothing);
      expect(find.text('Left unspent'), findsOneWidget);
      for (final u in september) {
        expect(find.byKey(ValueKey(u.budget.id)), findsOneWidget);
      }
      expect(find.byTooltip('Next month'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('budget-this-month')));
      await tester.pumpAndSettle();
      expect(find.text('Left to spend'), findsOneWidget);
      expect(find.text('New budget'), findsOneWidget);
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
    testWidgets('a past month is read-only with its own totals', (tester) async {
      _tallView(tester);
      final env = await TestEnv.create();
      final s = await env.snapshot();
      final u = s.budgetUsagesFor(MonthKey(2026, 9)).firstWhere((u) => u.budget.categoryId == SeedCategoryIds.food);
      await env.pumpWidget(tester, BudgetDetailScreen(id: u.budget.id, month: MonthKey(2026, 9)));
      await tester.pumpAndSettle();

      expect(find.textContaining('read-only'), findsOneWidget);
      expect(find.byTooltip('Edit budget'), findsNothing);
      expect(find.byTooltip('More actions'), findsNothing);
      expect(find.text('Limit then'), findsOneWidget);
      expect(find.text('Month total'), findsOneWidget);
      expect(find.text('Safe per day'), findsNothing);
      expect(find.text(AmountText.formatted(u.spent)), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('hero, pace stats, chart readout and filters', (tester) async {
      _tallView(tester);
      final env = await TestEnv.create();
      final s = await env.snapshot();
      final food = s.budgetUsages.firstWhere(
        (u) => u.budget.categoryId == SeedCategoryIds.food,
      );
      await env.pumpWidget(tester, BudgetDetailScreen(id: food.budget.id));
      await tester.pumpAndSettle();

      expect(find.text(food.isOver ? 'Over by' : 'Left'), findsOneWidget);
      expect(find.text('Safe per day'), findsOneWidget);
      expect(find.text('At this pace'), findsOneWidget);
      expect(find.text('So far'), findsOneWidget);

      // Tapping the chart reads a day and filters the list to it.
      final chart = find.byType(BurnChart);
      await tester.tapAt(tester.getTopLeft(chart) + const Offset(4, 60));
      await tester.pumpAndSettle();
      expect(find.text('So far'), findsNothing);
      expect(find.byKey(const ValueKey('budget-day-chip')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('budget-day-chip')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('budget-day-chip')), findsNothing);

      // Payee chip filters the list to that payee.
      final burn = buildBudgetBurn(s, food);
      final top = topPayees(burn.transactions).first;
      await tester.tap(find.byKey(ValueKey('budget-payee:${top.$1}')));
      await tester.pumpAndSettle();
      expect(find.byType(TransactionRow), findsNWidgets(top.$3));

      // History view.
      await tester.tap(find.textContaining('Last '));
      await tester.pumpAndSettle();
      expect(find.text('Average before'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
