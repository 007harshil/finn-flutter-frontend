import 'package:finn/features/pending/domain/pending_payment.dart';
import 'package:finn/features/transactions/domain/transaction.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_app.dart';
import 'journey_helpers.dart';

void main() {
  testWidgets('settling money owed to me in full removes it from active items and raises cash', (tester) async {
    final env = await TestEnv.create();
    final before = await env.snapshot();
    final view = before.pendingViews.singleWhere((v) => v.payment.purpose == 'Goa trip hotel share');
    final id = view.payment.id;
    final owed = view.outstanding; // ₹6,500 Priya owes me
    expect(view.payment.direction, PendingDirection.owedToMe);

    await env.pumpApp(tester);
    await tester.pumpAndSettle();

    // Home quick access → Pending payments → the item → Settle.
    await scrollAndTap(tester, find.byKey(const ValueKey('quick-tile:Pending payments')));
    final item = find.byKey(ValueKey(id));
    await scrollTo(tester, item);
    expect(item, findsOneWidget, reason: 'listed under Active before settling');
    await scrollAndTap(tester, find.descendant(of: item, matching: find.text('Priya Nair')));
    await tapButton(tester, 'Settle');
    await tester.pumpAndSettle();
    expect(find.text('OUTSTANDING'), findsOneWidget);
    await tapButton(tester, 'Record money from Priya Nair'); // "Full" is pre-selected
    await confirmReview(tester);

    final after = await env.snapshot();
    final settled = after.pendingView(id)!;
    expect(settled.status, PendingStatus.settled);
    expect(settled.outstanding.isZero, isTrue);
    final linked = after.linkedTransactions(id);
    expect(linked, hasLength(1));
    expect(linked.single.type, TransactionType.income);
    expect(linked.single.origin, TransactionOrigin.pendingSettlement);
    expect(linked.single.amount, owed);
    expect(after.balance.cash, before.balance.cash + owed, reason: 'money received raises cash');
    expect(after.pendingToCollect, before.pendingToCollect - owed);
    expect(after.netWorth.netWorth, before.netWorth.netWorth, reason: 'a receivable became cash');

    // Back to the list: no longer an active item.
    await tester.pageBack();
    await tester.pumpAndSettle();
    await scrollTo(tester, find.text('Money owed'), up: true);
    expect(find.text('Money owed'), findsOneWidget);
    expect(find.byKey(ValueKey(id)), findsNothing);
    expect(find.text('Priya Nair'), findsNothing, reason: 'Priya has no other open items');

    // Home hero shows the higher cash and available balance.
    await tapTab(tester, 'Home');
    await showHero(tester);
    expect(inHero(rupees(after.balance.cash)), findsOneWidget);
    expect(inHero(rupees(after.balance.available)), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
