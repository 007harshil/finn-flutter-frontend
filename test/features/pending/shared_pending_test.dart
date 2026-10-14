import 'package:finn/actions/action.dart';
import 'package:finn/actions/dispatcher.dart';
import 'package:finn/app/di/action_providers.dart';
import 'package:finn/core/money/money.dart';
import 'package:finn/core/result/result.dart';
import 'package:finn/features/alerts/domain/alert.dart';
import 'package:finn/features/pending/application/pending_actions.dart';
import 'package:finn/features/pending/domain/pending_payment.dart';
import 'package:finn/features/pending/presentation/pending_detail_screen.dart';
import 'package:finn/features/pending/presentation/pending_form_sheet.dart';
import 'package:finn/features/settings/domain/app_settings.dart';
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

  Future<MirrorEntry?> mirrorFor(PendingPayment p) =>
      env.store.sharedLedger.getById(MirrorEntry.keyOf(p.link!.userId, p.link!.sharedId));

  group('double entry', () {
    test('sharing with a FiNN user creates the mirrored entry in their account', () async {
      final outcome = await _run(
        container,
        const CreatePendingAction(),
        PendingInput(
          counterparty: 'ramesh',
          direction: PendingDirection.iOwe,
          kind: PendingKind.borrowed,
          amount: const Money.rupees(1000),
          purpose: 'Train tickets',
          createdDate: testNow,
          linkedUserId: 'u_ramesh',
        ),
        key: 'share',
      );
      final mine = (outcome as ActionCompleted<PendingPayment>).value;
      expect(mine.counterparty, 'Ramesh Kumar', reason: 'name comes from the directory');
      expect(mine.link!.createdByMe, isTrue);

      final theirs = (await mirrorFor(mine))!;
      expect(theirs.ownerId, 'u_ramesh');
      expect(theirs.payment.direction, PendingDirection.owedToMe, reason: 'my "I owe" is their "owed to me"');
      expect(theirs.payment.kind, PendingKind.lent);
      expect(theirs.payment.counterparty, 'Aarav');
      expect(theirs.payment.originalAmount, const Money.rupees(1000));
      expect(theirs.payment.link!.createdByMe, isFalse);
      expect(theirs.payment.link!.sharedId, mine.link!.sharedId);
    });

    test('a private name stays private', () async {
      final outcome = await _run(
        container,
        const CreatePendingAction(),
        PendingInput(
          counterparty: 'Dhobi',
          direction: PendingDirection.iOwe,
          kind: PendingKind.other,
          amount: const Money.rupees(200),
          purpose: 'Ironing',
          createdDate: testNow,
        ),
        key: 'private',
      );
      expect((outcome as ActionCompleted<PendingPayment>).value.link, isNull);
    });

    test('unknown or self links are rejected', () async {
      final outcome = await _run(
        container,
        const CreatePendingAction(),
        PendingInput(
          counterparty: 'x',
          direction: PendingDirection.iOwe,
          kind: PendingKind.other,
          amount: const Money.rupees(200),
          purpose: 'x',
          createdDate: testNow,
          linkedUserId: 'u_nobody',
        ),
        key: 'bad',
      );
      expect((outcome as ActionRejected).failure.fieldErrors.keys, contains('linkedUserId'));
    });

    test('a settlement on one side shows on the other, without touching their cash', () async {
      final goa = await item('Goa trip hotel share'); // shared with Priya
      await _run(
        container,
        const SettlePendingAction(),
        SettlePendingInput(pendingId: goa.payment.id, amount: const Money.rupees(2500), date: testNow),
        key: 'settle',
      );
      final theirs = (await mirrorFor(goa.payment))!.view(testNow);
      expect(theirs.outstanding, const Money.rupees(4000));
      expect(theirs.settlements.single.transactionId, isNull);
      expect((await item('Goa trip hotel share')).outstanding, theirs.outstanding);
    });

    test('only the creator edits or deletes; only the person owed writes off', () async {
      final concert = await item('Concert tickets'); // Rahul added it; I owe him
      final p = concert.payment;
      final edit = await _run(
        container,
        const UpdatePendingAction(),
        UpdatePendingInput(
          id: p.id,
          expectedVersion: p.version,
          data: PendingInput(
            counterparty: p.counterparty,
            direction: p.direction,
            kind: p.kind,
            amount: const Money.rupees(1500),
            purpose: p.purpose,
            createdDate: p.createdDate,
          ),
        ),
        key: 'edit',
      );
      expect((edit as ActionRejected).failure.code, FailureCode.notPermitted);

      final off = await _run(container, const CancelPendingAction(), PendingIdInput(id: p.id), key: 'off');
      expect((off as ActionRejected).failure.code, FailureCode.notPermitted);

      final ananya = await item('Emergency cash'); // I created it, she owes me
      final ok = await _run(container, const CancelPendingAction(), PendingIdInput(id: ananya.payment.id), key: 'off2');
      expect(ok, isA<ActionCompleted<PendingPayment>>());
      expect((await mirrorFor(ananya.payment))!.view(testNow).status, PendingStatus.cancelled);
    });

    test('deleting a shared item removes it from both accounts', () async {
      final created = await _run(
        container,
        const CreatePendingAction(),
        PendingInput(
          counterparty: 'Karan',
          direction: PendingDirection.owedToMe,
          kind: PendingKind.sharedExpense,
          amount: const Money.rupees(600),
          purpose: 'Movie',
          createdDate: testNow,
          linkedUserId: 'u_karan',
        ),
        key: 'mk',
      );
      final p = (created as ActionCompleted<PendingPayment>).value;
      expect(await mirrorFor(p), isNotNull);
      await _run(container, const DeletePendingAction(), PendingIdInput(id: p.id), key: 'del');
      expect(await mirrorFor(p), isNull);
    });

    test('seeded shared items already match their mirrors', () async {
      for (final v in (await env.snapshot()).pendingViews.where((v) => v.payment.isShared)) {
        final theirs = (await mirrorFor(v.payment))!.view(testNow);
        expect(theirs.outstanding, v.outstanding, reason: v.payment.purpose);
      }
    });
  });

  test('saved alert preferences from the old due-date names still load', () {
    final s = AppSettings.fromJson({
      'disabledAlertTypes': ['pendingOverdue', 'collectDue'],
    });
    expect(s.disabledAlertTypes, {AlertType.pendingOwed, AlertType.collectOwed});
  });

  group('screens', () {
    testWidgets('typing a name searches FiNN users after a pause and links the pick', (tester) async {
      tester.view.physicalSize = const Size(400, 900) * tester.view.devicePixelRatio;
      addTearDown(tester.view.resetPhysicalSize);
      await env.pumpWidget(tester, const PendingFormSheet());
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'rame');
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const ValueKey('finn-user:u_ramesh')), findsNothing, reason: 'debounced');
      expect(find.textContaining('Searching FiNN'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('finn-user:u_ramesh')), findsOneWidget);
      expect(find.byKey(const ValueKey('finn-user:u_ramesh_iyer')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('finn-user:u_ramesh')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pending-linked-user')), findsOneWidget);
      expect(find.textContaining('also shows in Ramesh’s FiNN'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('detail of a shared item shows the other side and that both match', (tester) async {
      tester.view.physicalSize = const Size(400, 900) * tester.view.devicePixelRatio;
      addTearDown(tester.view.resetPhysicalSize);
      final v = await item('Concert tickets');
      await env.pumpWidget(tester, PendingDetailScreen(id: v.payment.id));
      await tester.pumpAndSettle();
      final card = find.byKey(const ValueKey('pending-shared-card'));
      await tester.scrollUntilVisible(card, 300, scrollable: find.byType(Scrollable).first);
      expect(find.text('ADDED BY RAHUL'), findsOneWidget);
      expect(find.text('Aarav owes you'), findsOneWidget, reason: 'Rahul sees me owing him');
      expect(find.text('Both sides match'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
