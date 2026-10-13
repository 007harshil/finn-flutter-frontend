import 'package:finn/core/time/dates.dart';
import 'package:finn/data/mock/seed_data.dart';
import 'package:finn/design_system/design_system.dart';
import 'package:finn/features/budgets/application/budget_view.dart';
import 'package:finn/features/budgets/presentation/budget_charts.dart';
import 'package:finn/features/budgets/presentation/budget_detail_screen.dart';
import 'package:finn/features/budgets/presentation/budgets_screen.dart';
import 'package:flutter/material.dart';
import 'package:finn/shared/presentation/transaction_row.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/test_app.dart';

void _tallView(WidgetTester tester) {
  tester.view.physicalSize = const Size(400, 1600) * tester.view.devicePixelRatio;
  addTearDown(tester.view.resetPhysicalSize);
}

void main() {
  group('BudgetsScreen', () {
    testWidgets('summary, status chips and sort narrow the list', (tester) async {
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
      expect(find.text('${pulse.paces.length} budgets'), findsOneWidget);

      // The paused chip shows only the paused budget.
      await tester.ensureVisible(find.byKey(const ValueKey('budget-tab:paused')));
      await tester.tap(find.byKey(const ValueKey('budget-tab:paused')));
      await tester.pumpAndSettle();
      final paused = pulse.paces.where((p) => p.state == BudgetState.paused).toList();
      expect(find.text('${paused.length} ${paused.length == 1 ? 'budget' : 'budgets'}'), findsOneWidget);
      expect(find.byKey(ValueKey(paused.single.usage.budget.id)), findsOneWidget);
      expect(find.byKey(ValueKey(pulse.paces.firstWhere((p) => p.state != BudgetState.paused).usage.budget.id)),
          findsNothing);

      // Tapping it again shows all, then sort by name from the list title.
      await tester.tap(find.byKey(const ValueKey('budget-tab:paused')));
      await tester.pumpAndSettle();
      expect(find.text('${pulse.paces.length} budgets'), findsOneWidget);
      await tester.tap(find.text('Most urgent'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Name').last);
      await tester.pumpAndSettle();
      expect(find.text('Name'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('previous months open read-only and come back to this month', (tester) async {
      _tallView(tester);
      final env = await TestEnv.create();
      final s = await env.snapshot();
      final september = s.budgetUsagesFor(MonthKey(2026, 9));
      await env.pumpWidget(tester, const BudgetsScreen());
      await tester.pumpAndSettle();
      expect(find.byTooltip('New budget'), findsOneWidget);

      await tester.tap(find.byTooltip('Previous'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Read-only'), findsOneWidget);
      expect(find.byTooltip('New budget'), findsNothing);
      expect(find.text('Left unspent').evaluate().isNotEmpty || find.text('Went over by').evaluate().isNotEmpty, isTrue);
      for (final u in september) {
        expect(find.byKey(ValueKey(u.budget.id)), findsOneWidget);
      }
      expect(find.byTooltip('Next'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('budget-this-month')));
      await tester.pumpAndSettle();
      expect(find.text('Left to spend'), findsOneWidget);
      expect(find.byTooltip('New budget'), findsOneWidget);
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

    testWidgets('summary, pace stats, chart readout and filters', (tester) async {
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
      await tester.tap(find.textContaining('Last'));
      await tester.pumpAndSettle();
      expect(find.text('Average before'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
