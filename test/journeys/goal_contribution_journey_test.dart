import 'package:finn/core/money/money.dart';
import 'package:finn/design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_app.dart';
import 'journey_helpers.dart';

void main() {
  testWidgets('contributing to a goal earmarks money without changing cash or net worth', (tester) async {
    final env = await TestEnv.create();
    final before = await env.snapshot();
    const goalId = 'goal_seed_macbook';
    const amount = Money.rupees(5000);
    final savedBefore = before.goal(goalId)!.saved;

    await env.pumpApp(tester);
    await tester.pumpAndSettle();
    expect(inHero(rupees(before.balance.available)), findsOneWidget);
    expect(inHero(rupees(before.balance.cash)), findsOneWidget);
    expect(inHero(rupees(before.balance.earmarked)), findsOneWidget);

    // More tab: note the net worth shown before.
    await tapTab(tester, 'More');
    expect(find.text(rupees(before.netWorth.netWorth)), findsOneWidget);

    // Goals tab → MacBook Pro → Add money.
    await tapTab(tester, 'Goals');
    await scrollAndTap(tester, find.descendant(of: find.byKey(const ValueKey(goalId)), matching: find.text('MacBook Pro')));
    expect(find.text('MacBook Pro'), findsWidgets);
    await tapButton(tester, 'Add money');
    await tester.pumpAndSettle();
    expect(find.text('Add money to MacBook Pro'), findsOneWidget);
    await enterAmount(tester, '5000');
    await tapButton(tester, 'Add money');
    await confirmReview(tester);
    expect(find.text('Add money to MacBook Pro'), findsNothing, reason: 'the sheet closes after saving');

    final after = await env.snapshot();
    expect(after.goal(goalId)!.saved, savedBefore + amount);
    expect(after.balance.cash, before.balance.cash, reason: 'earmarking is not spending');
    expect(after.balance.earmarked, before.balance.earmarked + amount);
    expect(after.balance.available, before.balance.available - amount);
    expect(after.netWorth.netWorth, before.netWorth.netWorth);
    expect(after.transactions.length, before.transactions.length, reason: 'no transaction is created');

    // Goal detail reflects the new saved amount.
    expect(find.text(AmountText.formatted(after.goal(goalId)!.saved)), findsWidgets);

    // Home: available down, set aside up, cash unchanged.
    await tapTab(tester, 'Home');
    expect(inHero(rupees(after.balance.available)), findsOneWidget);
    expect(inHero(rupees(after.balance.earmarked)), findsOneWidget);
    expect(inHero(rupees(before.balance.cash)), findsOneWidget);
    expect(inHero(rupees(before.balance.available)), findsNothing);

    // More tab: net worth unchanged.
    await tapTab(tester, 'More');
    expect(find.text(rupees(before.netWorth.netWorth)), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
