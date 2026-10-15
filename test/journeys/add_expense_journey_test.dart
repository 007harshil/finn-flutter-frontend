import 'package:finn/core/money/money.dart';
import 'package:finn/core/money/money_format.dart';
import 'package:finn/data/mock/seed_data.dart';
import 'package:finn/design_system/design_system.dart';
import 'package:finn/features/transactions/domain/transaction.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_app.dart';
import 'journey_helpers.dart';

void main() {
  testWidgets('adding an expense updates the list, the home balance and its budget', (tester) async {
    final env = await TestEnv.create();
    final before = await env.snapshot();
    final foodBefore = before.budgetUsages.firstWhere((u) => u.budget.categoryId == SeedCategoryIds.food);
    const spent = Money.rupees(1234);

    await env.pumpApp(tester);
    await tester.pumpAndSettle();
    expect(inHero(rupees(before.balance.available)), findsOneWidget);

    // Record the expense from the floating "add" button.
    await tester.tap(find.byTooltip('Add transaction'));
    await tester.pumpAndSettle();
    expect(find.text('Record transaction'), findsOneWidget);
    await enterAmount(tester, '1234');
    await tester.tap(find.text('Choose a category'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey(SeedCategoryIds.food)));
    await tester.pumpAndSettle();
    await enterField(tester, 'Paid to', 'Journey Cafe');
    await tapButton(tester, 'Record expense');
    await settle(tester);
    expect(find.text('Record transaction'), findsNothing, reason: 'the sheet closes after saving');

    final after = await env.snapshot();
    final tx = after.transactions.singleWhere((t) => t.counterparty == 'Journey Cafe');
    expect(tx.type, TransactionType.expense);
    expect(tx.amount, spent);
    expect(tx.categoryId, SeedCategoryIds.food);
    expect(tx.date, testNow.dateOnlyForTest);
    expect(after.balance.available, before.balance.available - spent);
    expect(after.balance.cash, before.balance.cash - spent);

    // Home hero shows the lower balance.
    expect(inHero(rupees(after.balance.available)), findsOneWidget);
    expect(inHero(rupees(before.balance.available)), findsNothing);

    // Activity list shows the new row.
    await tapTab(tester, 'Activity');
    final row = find.byKey(ValueKey(tx.id));
    await scrollTo(tester, row);
    expect(find.descendant(of: row, matching: find.text('Journey Cafe')), findsOneWidget);
    expect(find.descendant(of: row, matching: find.text(AmountText.formatted(-spent, sign: SignDisplay.always))),
        findsOneWidget);

    // The Food budget card counts it.
    final foodAfter = after.budgetUsage(foodBefore.budget.id)!;
    expect(foodAfter.spent, foodBefore.spent + spent);
    await tapTab(tester, 'Budgets');
    final card = find.byKey(ValueKey(foodBefore.budget.id));
    await scrollTo(tester, card);
    expect(find.descendant(of: card, matching: find.text(AmountText.formatted(foodAfter.spent))), findsOneWidget);
    expect(find.descendant(of: card, matching: find.text(AmountText.formatted(foodBefore.spent))), findsNothing);

    // And back home the figure is still consistent.
    await tapTab(tester, 'Home');
    await showHero(tester);
    expect(inHero(rupees(after.balance.available)), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

extension on DateTime {
  DateTime get dateOnlyForTest => DateTime(year, month, day);
}
