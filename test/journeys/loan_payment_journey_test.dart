import 'package:finn/design_system/design_system.dart';
import 'package:finn/features/transactions/domain/transaction.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_app.dart';
import 'journey_helpers.dart';

void main() {
  testWidgets('recording an EMI lowers the outstanding, logs the payment and records one expense', (tester) async {
    final env = await TestEnv.create();
    const loanId = 'loan_seed_car';
    final before = await env.snapshot();
    final loanBefore = before.loan(loanId)!;
    final emi = loanBefore.nextDue!.payment;
    final paymentIdsBefore = loanBefore.payments.map((p) => p.id).toSet();

    await env.pumpApp(tester);
    await tester.pumpAndSettle();

    // Home quick access → Loans & EMIs → Car loan.
    await scrollAndTap(tester, find.byKey(const ValueKey('quick-tile:Loans')));
    await scrollAndTap(tester, find.descendant(of: find.byKey(const ValueKey(loanId)), matching: find.text('Car loan')));
    expect(find.text(AmountText.formatted(loanBefore.outstanding)), findsWidgets);

    // Record the scheduled EMI (pre-filled) and approve the review.
    await tapButton(tester, 'Record a payment');
    await tester.pumpAndSettle();
    expect(find.text('TOWARDS PRINCIPAL'), findsOneWidget);
    await tapButton(tester, 'Record payment to HDFC Bank');
    await confirmReview(tester);
    expect(find.text('TOWARDS PRINCIPAL'), findsNothing, reason: 'the sheet closes after saving');

    final after = await env.snapshot();
    final loanAfter = after.loan(loanId)!;
    final payment = loanAfter.payments.singleWhere((p) => !paymentIdsBefore.contains(p.id));
    expect(payment.interestComponent + payment.principalComponent, emi);
    expect(payment.principalComponent.isPositive, isTrue);
    expect(loanAfter.outstanding, loanBefore.outstanding - payment.principalComponent);

    // Exactly one linked expense for the EMI.
    final linked = after.linkedTransactions(loanId).where((t) => t.id == payment.transactionId).toList();
    expect(linked, hasLength(1));
    expect(linked.single.type, TransactionType.expense);
    expect(linked.single.origin, TransactionOrigin.loanRepayment);
    expect(linked.single.amount, emi);
    expect(after.transactions.length, before.transactions.length + 1);
    expect(after.balance.available, before.balance.available - emi);

    // Loan detail: new outstanding in the hero, payment in the history.
    await scrollTo(tester, find.text('You owe HDFC Bank'), up: true);
    expect(find.text(AmountText.formatted(loanAfter.outstanding)), findsOneWidget);
    expect(find.text(AmountText.formatted(loanBefore.outstanding)), findsNothing);
    await scrollTo(tester, find.text('Payments'));
    expect(loanAfter.payments.length, loanBefore.payments.length + 1);
    final row = find.byKey(ValueKey(payment.id));
    await scrollTo(tester, row);
    expect(row, findsOneWidget);

    // Activity shows the linked transaction; home balance drops by the EMI.
    await tapTab(tester, 'Activity');
    final txRow = find.byKey(ValueKey<String>(payment.transactionId!));
    await scrollTo(tester, txRow);
    expect(txRow, findsOneWidget);
    // Loans opened from Home, so the first tap restores that stack; the
    // second returns to the Home root.
    await tapTab(tester, 'Home');
    await tapTab(tester, 'Home');
    expect(inHero(rupees(after.balance.available)), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
