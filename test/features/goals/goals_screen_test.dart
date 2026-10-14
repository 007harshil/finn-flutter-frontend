import 'package:finn/core/money/money.dart';
import 'package:finn/features/goals/application/goal_view.dart';
import 'package:finn/features/goals/presentation/goal_detail_screen.dart';
import 'package:finn/features/goals/presentation/goals_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/test_app.dart';

void _tallView(WidgetTester tester, {double width = 400}) {
  tester.view.physicalSize = Size(width, 1600) * tester.view.devicePixelRatio;
  addTearDown(tester.view.resetPhysicalSize);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 500));
  }
}

void main() {
  group('GoalsScreen', () {
    testWidgets('hero, emergency line, tabs and status filters', (tester) async {
      _tallView(tester);
      final env = await TestEnv.create();
      final board = buildGoalsBoard(await env.snapshot());
      await env.pumpWidget(tester, const GoalsScreen());
      await tester.pumpAndSettle();

      expect(find.text('Saved for goals'), findsOneWidget);
      expect(find.byKey(const ValueKey('goals-emergency-line')), findsOneWidget);
      for (final g in board.active) {
        expect(find.byKey(ValueKey(g.goal.id)), findsOneWidget);
        expect(find.byKey(ValueKey('goal-add:${g.goal.id}')), findsOneWidget);
      }

      // Completed tab.
      final completed = board.all.where((g) => goalTabOf(g) == GoalTab.completed).toList();
      await tester.tap(find.byKey(const ValueKey('goal-tab:completed')));
      await tester.pumpAndSettle();
      for (final g in completed) {
        expect(find.byKey(ValueKey(g.goal.id)), findsOneWidget);
        expect(find.byKey(ValueKey('goal-add:${g.goal.id}')), findsNothing);
      }

      // Back on Active, a status filter keeps only goals with that status.
      await tester.tap(find.byKey(const ValueKey('goal-tab:active')));
      await tester.pumpAndSettle();
      final pace = [GoalPace.behind, GoalPace.onTrack, GoalPace.noPlan].firstWhere((p) => board.count(p) > 0);
      await tester.tap(find.byKey(ValueKey('goal-attn:${pace.name}')));
      await tester.pumpAndSettle();
      for (final g in board.active) {
        expect(find.byKey(ValueKey(g.goal.id)), goalPaceOf(g) == pace ? findsOneWidget : findsNothing);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('fits a 320 px screen without overflow', (tester) async {
      _tallView(tester, width: 320);
      final env = await TestEnv.create();
      await env.pumpWidget(tester, const GoalsScreen());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('GoalDetailScreen', () {
    testWidgets('what-if slider moves the finish date and can become the plan', (tester) async {
      _tallView(tester);
      final env = await TestEnv.create();
      const id = 'goal_seed_japan';
      final before = (await env.snapshot()).goal(id)!;
      await env.pumpWidget(tester, const GoalDetailScreen(id: id));
      await tester.pumpAndSettle();

      expect(find.text('Monthly plan'), findsOneWidget);
      expect(find.text('What if I put in'), findsOneWidget);
      expect(find.text('Add money'), findsOneWidget);
      expect(find.byKey(const ValueKey('goal-use-plan')), findsNothing, reason: 'slider starts at the current plan');

      final slider = find.byKey(const ValueKey('goal-whatif-slider'));
      final doneBefore = tester.widget<Text>(find.textContaining('Done by')).data;
      await tester.drag(slider, const Offset(120, 0));
      await tester.pumpAndSettle();
      final value = tester.widget<Slider>(slider).value.round();
      expect(value, greaterThan(before.goal.plannedMonthlyContribution!.paise ~/ 100));
      expect(tester.widget<Text>(find.textContaining('Done by')).data, isNot(doneBefore));

      await tester.tap(find.byKey(const ValueKey('goal-use-plan')));
      await _settle(tester);
      if (find.text('Confirm').evaluate().isNotEmpty) {
        await tester.tap(find.text('Confirm'));
        await _settle(tester);
      }
      final after = (await env.snapshot()).goal(id)!;
      expect(after.goal.plannedMonthlyContribution, Money.rupees(value));
      expect(after.saved, before.saved, reason: 'changing the plan moves no money');
      expect(tester.takeException(), isNull);
    });
  });
}
