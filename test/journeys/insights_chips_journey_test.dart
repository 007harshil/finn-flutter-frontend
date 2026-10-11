import 'package:finn/app/router/routes.dart';
import 'package:finn/data/local/local_data_store.dart';
import 'package:finn/features/analytics/application/analytics_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../helpers/test_app.dart';
import 'journey_helpers.dart';

void main() {
  testWidgets('insights chips show one topic at a time', (tester) async {
    final env = await TestEnv.create();
    await env.pumpApp(tester);
    await tester.pumpAndSettle();
    GoRouter.of(tester.element(find.byType(Navigator).first)).push(AppRoutes.analytics);
    await tester.pumpAndSettle();

    // Overview first: health check and topic tiles, no topic-only cards.
    expect(find.text('Money health check'), findsOneWidget);
    expect(find.textContaining('cost you the most'), findsNothing);
    for (final s in InsightsSection.values) {
      expect(find.byKey(Key('insights-chip:${s.name}')), findsOneWidget);
    }

    // Daily spend: baseline average, day chart and weekday pattern.
    await tester.tap(find.byKey(const Key('insights-chip:spending')));
    await tester.pumpAndSettle();
    expect(find.text('Money health check'), findsNothing);
    expect(find.text('DAILY AVERAGE'), findsOneWidget);
    await scrollTo(tester, find.textContaining('cost you the most'));
    expect(find.textContaining('cost you the most'), findsOneWidget);

    // In vs out: "every ₹100" framing.
    await tester.tap(find.byKey(const Key('insights-chip:cashFlow')));
    await tester.pumpAndSettle();
    expect(find.textContaining('of every ₹100 you earned'), findsOneWidget);
    expect(find.text('AVG INCOME'), findsOneWidget);

    // An overview tile jumps straight to its topic.
    await tester.ensureVisible(find.byKey(const Key('insights-chip:overview')));
    await tester.tap(find.byKey(const Key('insights-chip:overview')));
    await tester.pumpAndSettle();
    expect(find.text('Money health check'), findsOneWidget);
    await scrollAndTap(tester, find.byKey(const Key('insights-explore:budgets')));
    expect(find.text('Money health check'), findsNothing);
    expect(find.textContaining('Tick = today'), findsOneWidget);

    // Remaining chips all render without errors.
    for (final s in [
      InsightsSection.categories,
      InsightsSection.payments,
      InsightsSection.savings,
      InsightsSection.loans,
      InsightsSection.subscriptions,
    ]) {
      await tester.ensureVisible(find.byKey(Key('insights-chip:${s.name}')));
      await tester.tap(find.byKey(Key('insights-chip:${s.name}')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: s.name);
    }
  });

  for (final scenario in [DataScenario.empty, DataScenario.stressed]) {
    testWidgets('every insights chip lays out on a narrow phone (${scenario.name} data)', (tester) async {
      final env = await TestEnv.create(scenario: scenario);
      await env.pumpApp(tester, size: const Size(340, 720));
      await tester.pumpAndSettle();
      GoRouter.of(tester.element(find.byType(Navigator).first)).push(AppRoutes.analytics);
      await tester.pumpAndSettle();
      for (final s in InsightsSection.values) {
        await tester.ensureVisible(find.byKey(Key('insights-chip:${s.name}')));
        await tester.tap(find.byKey(Key('insights-chip:${s.name}')));
        await tester.pumpAndSettle();
        await tester.drag(find.byType(CustomScrollView).last, const Offset(0, -4000));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: s.name);
      }
    });
  }
}
