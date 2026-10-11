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
    await tester.tap(inHero('SET ASIDE'));
    await tester.pumpAndSettle();
    expect(inHero('FOR GOALS'), findsOneWidget);
    expect(inHero(rupees(b.earmarkedGoals)), findsOneWidget);
    expect(inHero(rupees(b.earmarkedEmergency)), findsOneWidget);
    expect(inHero(rupees(b.cash)), findsNothing);
    await tester.tap(inHero('FOR GOALS'));
    await tester.pumpAndSettle();
    expect(inHero(rupees(b.cash)), findsOneWidget);

    // The current month is partial; swiping right goes to last month.
    expect(find.text('so far'), findsOneWidget);
    await tester.fling(find.text('Income'), const Offset(300, 0), 1000);
    await tester.pumpAndSettle();
    expect(find.text('full month'), findsOneWidget);
    expect(find.text('so far'), findsNothing);

    // A bar opens that month's transactions of its type.
    await tester.tap(find.text('Spent'));
    await tester.pumpAndSettle();
    final uri = _location(tester);
    expect(uri.queryParameters['type'], 'expense');
    expect(uri.queryParameters['month'], isNotNull);
    expect(tester.takeException(), isNull);
  });
}
