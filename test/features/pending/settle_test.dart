import 'package:finn/actions/action.dart';
import 'package:finn/actions/dispatcher.dart';
import 'package:finn/app/di/action_providers.dart';
import 'package:finn/core/money/money.dart';
import 'package:finn/core/result/result.dart';
import 'package:finn/features/pending/application/pending_actions.dart';
import 'package:finn/features/pending/domain/pending_payment.dart';
import 'package:finn/features/pending/presentation/pending_detail_screen.dart';
import 'package:finn/features/pending/presentation/pending_screen.dart';
import 'package:finn/features/pending/presentation/settle_pending_sheet.dart';
import 'package:finn/features/transactions/domain/transaction.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/test_app.dart';

Future<ActionOutcome<O>> _run<I extends ActionInput, O>(
  ProviderContainer container,
  FinancialAction<I, O> action,
  I input, {
  required String key,
}) async {
  final dispatcher = container.read(actionDispatcherProvider);
  var outcome = await dispatcher.dispatch(action, input, idempotencyKey: key);
  if (outcome is ActionNeedsConfirmation<O>) {
    outcome = await dispatcher.dispatch(action, input,
        idempotencyKey: key, confirmation: ActionConfirmation(outcome.preview.fingerprint));
  }
  return outcome;
}

void main() {
  late TestEnv env;
  late ProviderContainer container;

  setUp(() async {
    env = await TestEnv.create();
    container = env.container();
  });

  tearDown(() => container.dispose());

  Future<PendingView> item(String purpose) async =>
      (await env.snapshot()).pendingViews.firstWhere((v) => v.payment.purpose == purpose);

  test('a partial settlement keeps the item partially settled and records cash once', () async {
    final before = await item('Goa trip hotel share'); // ₹6,500 owed to me, nothing settled
    expect(before.status, PendingStatus.open);
    final txBefore = (await env.snapshot()).transactions.length;

    final outcome = await _run(
      container,
      const SettlePendingAction(),
      SettlePendingInput(pendingId: before.payment.id, amount: const Money.rupees(2500), date: testNow),
      key: 'partial',
    );

    expect(outcome, isA<ActionCompleted<PendingSettlement>>());
    final after = await item('Goa trip hotel share');
    expect(after.status, PendingStatus.partiallySettled);
    expect(after.outstanding, const Money.rupees(4000));
    final snapshot = await env.snapshot();
    expect(snapshot.transactions.length, txBefore + 1);
    final linked = snapshot.linkedTransactions(before.payment.id);
    expect(linked, hasLength(1));
    expect(linked.single.type, TransactionType.income);
    expect(linked.single.origin, TransactionOrigin.pendingSettlement);
  });

  test('settling more than the outstanding amount is rejected', () async {
    final v = await item('Concert tickets'); // ₹3,200 with ₹1,200 settled → ₹2,000 outstanding
    expect(v.outstanding, const Money.rupees(2000));
    final txBefore = (await env.snapshot()).transactions.length;

    final outcome = await _run(
      container,
      const SettlePendingAction(),
      SettlePendingInput(pendingId: v.payment.id, amount: const Money.rupees(2500), date: testNow),
      key: 'too-much',
    );

    expect(outcome, isA<ActionRejected<PendingSettlement>>());
    final failure = (outcome as ActionRejected<PendingSettlement>).failure;
    expect(failure.code, FailureCode.validation);
    expect(failure.fieldErrors.keys, contains('amount'));
    expect((await env.snapshot()).transactions.length, txBefore);
    expect((await item('Concert tickets')).outstanding, const Money.rupees(2000));
  });

  test('recordCashMovement false settles without creating a transaction', () async {
    final v = await item('Office lunch');
    final txBefore = (await env.snapshot()).transactions.length;
    final balanceBefore = (await env.snapshot()).balance.available;

    final outcome = await _run(
      container,
      const SettlePendingAction(),
      SettlePendingInput(pendingId: v.payment.id, amount: v.outstanding, date: testNow, recordCashMovement: false),
      key: 'offline',
    );

    expect(outcome, isA<ActionCompleted<PendingSettlement>>());
    expect((outcome as ActionCompleted<PendingSettlement>).value.transactionId, isNull);
    final snapshot = await env.snapshot();
    expect(snapshot.transactions.length, txBefore);
    expect(snapshot.balance.available, balanceBefore);
    expect((await item('Office lunch')).status, PendingStatus.settled);
  });

  group('screens', () {
    testWidgets('pending screen shows summary and grouped people without errors', (tester) async {
      tester.view.physicalSize = const Size(400, 900) * tester.view.devicePixelRatio;
      addTearDown(tester.view.resetPhysicalSize);
      await env.pumpWidget(tester, const PendingScreen());
      await tester.pumpAndSettle();
      expect(find.text('Money owed'), findsOneWidget);
      expect(find.text('2 items'), findsOneWidget); // Rahul has two items
      expect(tester.takeException(), isNull);
    });

    testWidgets('detail and settle sheet render', (tester) async {
      tester.view.physicalSize = const Size(400, 900) * tester.view.devicePixelRatio;
      addTearDown(tester.view.resetPhysicalSize);
      final v = await item('Concert tickets');
      await env.pumpWidget(tester, PendingDetailScreen(id: v.payment.id));
      await tester.pumpAndSettle();
      expect(find.text('You owe Rahul Verma'), findsOneWidget);
      expect(find.textContaining('Waiting 24 days'), findsOneWidget);
      expect(find.text('Settle up'), findsOneWidget);
      final left = find.textContaining('₹2,000 left');
      await tester.scrollUntilVisible(left, 300, scrollable: find.byType(Scrollable).first);
      expect(left, findsOneWidget, reason: 'remaining after the settlement');
      expect(tester.takeException(), isNull);

      await env.pumpWidget(tester, SettlePendingSheet(pendingId: v.payment.id));
      await tester.pumpAndSettle();
      expect(find.textContaining('Other open items with Rahul Verma'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
