import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../helpers/test_app.dart';
import 'journey_helpers.dart';

Uri _location(WidgetTester tester) => GoRouter.of(tester.element(find.byType(Navigator).first)).state.uri;

void main() {
  testWidgets('hero totals split set-aside money; this month swipes between months', (tester) async {
    final env = await TestEnv.create();
    await env.pumpApp(tester);
    await tester.pumpAndSettle();
    final b = (await env.snapshot()).balance;

    // Tapping the totals splits "set aside" into goals and emergencies, and back.
    expect(inHero(rupees(b.cash)), findsOneWidget);
    await tester.tap(inHero('Set aside'));
    await tester.pumpAndSettle();
    expect(inHero('Goals'), findsOneWidget);
    expect(inHero(rupees(b.earmarkedGoals)), findsOneWidget);
    expect(inHero(rupees(b.earmarkedEmergency)), findsOneWidget);
    expect(inHero(rupees(b.cash)), findsNothing);
    await tester.tap(inHero('Goals'));
    await tester.pumpAndSettle();
    expect(inHero(rupees(b.cash)), findsOneWidget);

    // Swiping right goes to last month.
    expect(find.text('This month'), findsOneWidget);
    await scrollTo(tester, find.text('Income'));
    await tester.fling(find.text('Income'), const Offset(300, 0), 1000);
    await tester.pumpAndSettle();
    expect(find.text('September 2026'), findsOneWidget, reason: 'tests run on 10 Oct 2026');
    expect(find.text('This month'), findsNothing);

    // A bar opens that month's transactions of its type.
    await tester.tap(find.text('Spent'));
    await tester.pumpAndSettle();
    final uri = _location(tester);
    expect(uri.queryParameters['type'], 'expense');
    expect(uri.queryParameters['month'], isNotNull);
    expect(tester.takeException(), isNull);
  });
}
