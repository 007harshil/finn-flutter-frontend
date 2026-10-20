import 'package:finn/core/time/dates.dart';
import 'package:finn/features/subscriptions/application/subscription_actions.dart';
import 'package:finn/features/transactions/domain/transaction.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_app.dart';
import 'journey_helpers.dart';

void main() {
  testWidgets('marking an overdue subscription paid advances the renewal and records one expense', (tester) async {
    final env = await TestEnv.create();
    final before = await env.snapshot();
    final sub = before.subscriptions.singleWhere((s) => s.name == 'Cult.fit Elite'); // overdue by 2 days
    final expectedNext = SubscriptionSchedule.nextCycleAfterCurrent(sub);
    final linkedBefore = before.linkedTransactions(sub.id).map((t) => t.id).toSet();
    expect(sub.nextDueDate.isBefore(testNow), isTrue);

    await env.pumpApp(tester);
    await tester.pumpAndSettle();

    // Menu → Subscriptions → Cult.fit Elite.
    await openMenu(tester);
    await scrollAndTap(tester, inDrawer(find.text('Subscriptions')));
    await scrollAndTap(tester, find.descendant(of: find.byKey(ValueKey(sub.id)), matching: find.text(sub.name)));
    expect(find.textContaining(DateFormats.dayMonthYear.format(sub.nextDueDate)), findsWidgets);

    await tapButton(tester, 'Mark paid');
    await confirmReview(tester);

    final after = await env.snapshot();
    final updated = after.subscriptions.singleWhere((s) => s.id == sub.id);
    expect(updated.nextDueDate, expectedNext);
    expect(expectedNext.isAfter(sub.nextDueDate), isTrue);
    final newTx = after.linkedTransactions(sub.id).where((t) => !linkedBefore.contains(t.id)).toList();
    expect(newTx, hasLength(1), reason: 'exactly one payment is recorded');
    expect(newTx.single.type, TransactionType.expense);
    expect(newTx.single.origin, TransactionOrigin.subscription);
    expect(newTx.single.amount, sub.amount);
    // Seeded on the HDFC credit card: spending raises what is owed, cash is unchanged.
    expect(after.account(newTx.single.accountId)!.isLiability, isTrue);
    expect(after.balance.creditOwed, before.balance.creditOwed + sub.amount);
    expect(after.balance.available, before.balance.available);

    // Marking paid leaves the detail screen; open it again to see the new cycle.
    expect(find.text('Next renewal'), findsNothing);
    await scrollAndTap(tester, find.descendant(of: find.byKey(ValueKey(sub.id)), matching: find.text(sub.name)));
    await scrollTo(tester, find.text('Next renewal'), up: true);
    expect(find.textContaining(DateFormats.dayMonthYear.format(expectedNext)), findsOneWidget);
    final row = find.byKey(ValueKey(newTx.single.id));
    await scrollTo(tester, row);
    expect(row, findsOneWidget);

    // Activity shows it too, and home reflects the lower balance.
    await tapTab(tester, 'Activity');
    final txRow = find.byKey(ValueKey(newTx.single.id));
    await scrollTo(tester, txRow);
    expect(txRow, findsOneWidget);
    await tapTab(tester, 'Home');
    await showHero(tester);
    expect(inHero(rupees(after.balance.available)), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
