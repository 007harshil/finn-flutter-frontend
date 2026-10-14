import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../helpers/test_app.dart';
import 'journey_helpers.dart';

Uri _location(WidgetTester tester) => GoRouter.of(tester.element(find.byType(Navigator).first)).state.uri;

void main() {
  testWidgets('hero bar splits set-aside money; cash flow swipes between months', (tester) async {
    final env = await TestEnv.create();
    await env.pumpApp(tester);
    await tester.pumpAndSettle();
    final b = (await env.snapshot()).balance;

    // Tapping the bar splits "set aside" into goals and emergencies, and back.
    expect(inHero(rupees(b.cash)), findsOneWidget);
    await tester.tap(inHero('Set aside'));
    await tester.pumpAndSettle();
    expect(inHero('For goals'), findsOneWidget);
    expect(inHero(rupees(b.earmarkedGoals)), findsOneWidget);
    expect(inHero(rupees(b.earmarkedEmergency)), findsOneWidget);
    expect(inHero(rupees(b.cash)), findsNothing);
    await tester.tap(inHero('For goals'));
    await tester.pumpAndSettle();
    expect(inHero(rupees(b.cash)), findsOneWidget);

    // The current month is partial; swiping right goes to last month.
    expect(find.text('This month'), findsOneWidget);
    expect(find.text('Kept so far'), findsOneWidget);
    await tester.fling(find.text('Money in'), const Offset(300, 0), 1000);
    await tester.pumpAndSettle();
    expect(find.text('September 2026'), findsOneWidget);
    expect(find.text('This month'), findsNothing);

    // A flow row opens that month's transactions of its type.
    await scrollAndTap(tester, find.text('Money out'));
    await tester.pumpAndSettle();
    final uri = _location(tester);
    expect(uri.queryParameters['type'], 'expense');
    expect(uri.queryParameters['month'], isNotNull);
    expect(tester.takeException(), isNull);
  });
}
