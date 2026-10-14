import 'package:finn/core/money/money.dart';
import 'package:finn/data/local/local_data_store.dart';
import 'package:finn/data/mock/seed_data.dart';
import 'package:finn/features/transactions/domain/transaction.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_app.dart';
import 'journey_helpers.dart';

void main() {
  testWidgets('a new user onboards, sees empty states and records a first transaction', (tester) async {
    final env = await TestEnv.create(
      scenario: DataScenario.empty,
      onboarded: false,
      // Not onboarded yet, but keep animations reduced so frames settle.
      prefsValues: const {'finn.settings.v1': '{"onboardingComplete":false,"motion":"reduced"}'},
    );

    await env.pumpApp(tester);
    await tester.pumpAndSettle();

    // Onboarding: skip the intro, enter a name and an opening balance.
    expect(navTab('Home'), findsNothing, reason: 'redirected to onboarding');
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    await enterField(tester, 'What should we call you?', 'Meera');
    await enterAmount(tester, '25000');
    await tapButton(tester, 'Start fresh');
    await tester.pumpAndSettle();

    // Fresh home: welcome card, hero = opening balance.
    expect(navTab('Home'), findsOneWidget);
    expect(find.text('Welcome to FiNN'), findsOneWidget);
    expect(inHero('₹25,000'), findsWidgets);
    final fresh = await env.snapshot();
    expect(fresh.isFreshUser, isTrue);
    expect(fresh.balance.available, const Money.rupees(25000));

    // Empty states on the other tabs.
    await tapTab(tester, 'Activity');
    expect(find.textContaining(RegExp('nothing recorded', caseSensitive: false)), findsOneWidget);
    await tapTab(tester, 'Budgets');
    expect(find.text('No budgets yet'), findsOneWidget);
    await tapTab(tester, 'Goals');
    expect(find.text('Start your first goal'), findsOneWidget);

    // Record the first transaction from the welcome card.
    await tapTab(tester, 'Home');
    await tapButton(tester, 'Record first transaction');
    await tester.pumpAndSettle();
    expect(find.text('Record transaction'), findsOneWidget);
    await enterAmount(tester, '1500');
    await scrollAndTap(
        tester, find.descendant(of: find.byKey(const ValueKey(SeedCategoryIds.groceries)), matching: find.byType(InkWell)));
    await enterField(tester, 'Paid to', 'Corner kirana');
    await tapButton(tester, 'Record expense');
    await settle(tester);

    final after = await env.snapshot();
    final tx = after.transactions.single;
    expect(tx.type, TransactionType.expense);
    expect(tx.amount, const Money.rupees(1500));
    expect(after.balance.available, const Money.rupees(23500));
    expect(after.isFreshUser, isFalse);

    // Home switches to the full dashboard with the new balance.
    expect(find.text('Welcome to FiNN'), findsNothing);
    expect(inHero('₹23,500'), findsWidgets);

    // Activity now lists it instead of the empty state.
    await tapTab(tester, 'Activity');
    expect(find.textContaining(RegExp('nothing recorded', caseSensitive: false)), findsNothing);
    expect(find.descendant(of: find.byKey(ValueKey(tx.id)), matching: find.text('Corner kirana')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
