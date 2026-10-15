import 'package:finn/core/money/money_format.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_app.dart';
import 'journey_helpers.dart';

void main() {
  testWidgets('hiding balances in settings masks the home amounts until turned off', (tester) async {
    final env = await TestEnv.create();
    final b = (await env.snapshot()).balance;

    await env.pumpApp(tester);
    await tester.pumpAndSettle();
    expect(inHero(rupees(b.available)), findsOneWidget);
    expect(inHero(MoneyFormatter.masked), findsNothing);

    // Menu → Settings → Hide balances.
    await openMenu(tester);
    await scrollAndTap(tester, inDrawer(find.text('Settings')));
    await scrollAndTap(tester, find.byKey(const ValueKey('hide-balances')));
    expect(
      tester
          .widget<Switch>(
            find.descendant(of: find.byKey(const ValueKey('hide-balances')), matching: find.byType(Switch)),
          )
          .value,
      isTrue,
    );

    // Home: available, cash and set-aside are all masked.
    await tapTab(tester, 'Home');
    await showHero(tester);
    // Available, cash, set aside, and the credit card owed line.
    expect(inHero(MoneyFormatter.masked), findsNWidgets(4));
    expect(inHero(rupees(b.available)), findsNothing);
    expect(inHero(rupees(b.cash)), findsNothing);
    expect(find.text(rupees(b.available)), findsNothing, reason: 'nowhere on home');

    // The header shortcut turns them back on.
    await tester.tap(find.byTooltip('Show balances'));
    await tester.pumpAndSettle();
    expect(inHero(rupees(b.available)), findsOneWidget);
    expect(inHero(MoneyFormatter.masked), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
