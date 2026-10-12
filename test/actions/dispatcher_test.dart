import 'package:finn/actions/action.dart';
import 'package:finn/actions/audit_log.dart';
import 'package:finn/actions/dispatcher.dart';
import 'package:finn/core/money/money.dart';
import 'package:finn/core/result/result.dart';
import 'package:finn/data/mock/seed_data.dart';
import 'package:finn/features/transactions/application/transaction_actions.dart';
import 'package:finn/features/transactions/domain/transaction.dart';
import 'package:finn/finance/finance_snapshot.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'action_harness.dart';

class ProbeInput extends ActionInput {
  const ProbeInput(this.value, {this.extra = const {}});
  final int value;
  final Map<String, Object?> extra;

  @override
  Map<String, Object?> toJson() => {'value': value, ...extra};
}

enum ProbeMode { ok, fail, throws }

/// A controllable action for exercising the dispatcher in isolation.
class ProbeAction extends FinancialAction<ProbeInput, int> {
  ProbeAction({this.id = 'probe.create', this.risk = ActionRisk.low});

  final String id;
  final ActionRisk risk;
  ProbeMode mode = ProbeMode.ok;
  Object? basis;
  int executions = 0;

  @override
  ActionDescriptor get descriptor => ActionDescriptor(
    id: id,
    module: 'probe',
    title: 'Probe',
    description: 'Test action',
    risk: risk,
    fields: const [],
  );

  @override
  ProbeInput decode(Map<String, Object?> json) => ProbeInput(In.integer(json, 'value'));

  @override
  Result<ActionPreview> prepare(ProbeInput input, FinanceSnapshot snapshot, ActionEnvironment env) {
    if (input.value < 0) {
      return const Result.err(AppFailure.validation('Must be positive', fields: {'value': 'Must be positive'}));
    }
    return Result.ok(preview(input, title: 'Probe', summary: 'Probe ${input.value}', basis: basis));
  }

  @override
  Future<Result<int>> execute(ProbeInput input, FinanceSnapshot snapshot, ActionEnvironment env) async {
    executions++;
    switch (mode) {
      case ProbeMode.ok:
        return Result.ok(input.value * 10);
      case ProbeMode.fail:
        return const Result.err(AppFailure(FailureCode.storage, 'Disk full'));
      case ProbeMode.throws:
        throw StateError('boom');
    }
  }
}

void main() {
  late ActionHarness h;
  late OperationDispatcher dispatcher;

  setUp(() async {
    h = await ActionHarness.create();
    dispatcher = h.dispatcher;
  });

  group('execution and audit', () {
    test('a low-risk UI action runs without confirmation and is audited', () async {
      final probe = ProbeAction();
      final out = await dispatcher.dispatch(probe, const ProbeInput(4), idempotencyKey: 'k');
      expect(out, isA<ActionCompleted<int>>());
      final done = out as ActionCompleted<int>;
      expect(done.value, 40);
      expect(done.replayed, isFalse);
      expect(done.preview.summary, 'Probe 4');
      final entry = dispatcher.audit.entries.single;
      expect(entry.actionId, 'probe.create');
      expect(entry.summary, 'Probe 4');
      expect(entry.channel, ActionChannel.ui);
      expect(entry.at, harnessNow);
      expect(entry.succeeded, isTrue);
      expect(entry.confirmedBy, isNull);
    });

    test('a failed execution is audited and may be retried with the same key', () async {
      final probe = ProbeAction()..mode = ProbeMode.fail;
      final out = await dispatcher.dispatch(probe, const ProbeInput(1), idempotencyKey: 'k');
      expect((out as ActionRejected<int>).failure.code, FailureCode.storage);
      final entry = dispatcher.audit.entries.single;
      expect(entry.succeeded, isFalse);
      expect(entry.failure, 'Disk full');

      probe.mode = ProbeMode.ok;
      final retry = await dispatcher.dispatch(probe, const ProbeInput(1), idempotencyKey: 'k');
      expect(retry, isA<ActionCompleted<int>>());
      expect((retry as ActionCompleted<int>).replayed, isFalse);
      expect(probe.executions, 2);
    });

    test('an unexpected exception becomes a retryable "nothing changed" failure', () async {
      final probe = ProbeAction()..mode = ProbeMode.throws;
      final logged = <String?>[];
      final original = debugPrint;
      debugPrint = (message, {wrapWidth}) => logged.add(message);
      addTearDown(() => debugPrint = original);
      final out = await dispatcher.dispatch(probe, const ProbeInput(1), idempotencyKey: 'k');
      final failure = (out as ActionRejected<int>).failure;
      expect(failure.code, FailureCode.unknown);
      expect(failure.retryable, isTrue);
      expect(failure.message, 'Something went wrong. Nothing was changed.');
      expect(logged.single, contains('Action probe.create failed'));
      probe.mode = ProbeMode.ok;
      expect(await dispatcher.dispatch(probe, const ProbeInput(1), idempotencyKey: 'k'), isA<ActionCompleted<int>>());
    });

    test('validation failures do not execute, are not audited and release the key', () async {
      final probe = ProbeAction();
      final out = await dispatcher.dispatch(probe, const ProbeInput(-1), idempotencyKey: 'k');
      final failure = (out as ActionRejected<int>).failure;
      expect(failure.code, FailureCode.validation);
      expect(failure.fieldErrors, {'value': 'Must be positive'});
      expect(probe.executions, 0);
      expect(dispatcher.audit.entries, isEmpty);
      // Corrected input under the same key is a new attempt, not a conflict.
      expect(await dispatcher.dispatch(probe, const ProbeInput(2), idempotencyKey: 'k'), isA<ActionCompleted<int>>());
    });

    test('preview validates without executing', () async {
      final probe = ProbeAction();
      final ok = await dispatcher.preview(probe, const ProbeInput(3));
      expect(ok.valueOrNull!.summary, 'Probe 3');
      expect((await dispatcher.preview(probe, const ProbeInput(-3))).failureOrNull!.code, FailureCode.validation);
      expect(probe.executions, 0);
    });

    test('audit log keeps the newest entries up to its capacity', () {
      final log = AuditLog(capacity: 2);
      for (var i = 0; i < 3; i++) {
        log.record(
          AuditEntry(actionId: 'a$i', summary: '', channel: ActionChannel.ui, at: harnessNow, succeeded: true),
        );
      }
      expect(log.entries.map((e) => e.actionId), ['a2', 'a1']);
    });
  });

  group('idempotency', () {
    test('a repeated key replays the result without executing again', () async {
      final probe = ProbeAction();
      await dispatcher.dispatch(probe, const ProbeInput(5), idempotencyKey: 'k');
      final again = await dispatcher.dispatch(probe, const ProbeInput(5), idempotencyKey: 'k');
      expect(again, isA<ActionCompleted<int>>());
      expect((again as ActionCompleted<int>).replayed, isTrue);
      expect(again.value, 50);
      expect(probe.executions, 1);
      expect(dispatcher.audit.entries.length, 1);
    });

    test('a key reused for different input or another action is a conflict', () async {
      final probe = ProbeAction();
      await dispatcher.dispatch(probe, const ProbeInput(5), idempotencyKey: 'k');
      final other = await dispatcher.dispatch(probe, const ProbeInput(6), idempotencyKey: 'k');
      expect((other as ActionRejected<int>).failure.code, FailureCode.conflict);
      final otherAction = await dispatcher.dispatch(
        ProbeAction(id: 'probe.other'),
        const ProbeInput(5),
        idempotencyKey: 'k',
      );
      expect((otherAction as ActionRejected<int>).failure.code, FailureCode.conflict);
      expect(probe.executions, 1);
    });

    test('a concurrent duplicate (double tap) is rejected while the first is in flight', () async {
      final probe = ProbeAction();
      final first = dispatcher.dispatch(probe, const ProbeInput(1), idempotencyKey: 'k');
      final second = dispatcher.dispatch(probe, const ProbeInput(1), idempotencyKey: 'k');
      final results = await Future.wait([first, second]);
      expect(results[0], isA<ActionCompleted<int>>());
      expect((results[1] as ActionRejected<int>).failure.code, FailureCode.duplicate);
      expect(probe.executions, 1);
    });

    test('a real double submit records one transaction', () async {
      final input = TransactionInput(
        type: TransactionType.expense,
        amount: const Money.rupees(250),
        categoryId: SeedCategoryIds.food,
        date: DateTime(2026, 10, 9),
      );
      await Future.wait([
        dispatcher.dispatch(const CreateTransactionAction(), input, idempotencyKey: 'same'),
        dispatcher.dispatch(const CreateTransactionAction(), input, idempotencyKey: 'same'),
      ]);
      await dispatcher.dispatch(const CreateTransactionAction(), input, idempotencyKey: 'same');
      expect((await h.snapshot()).transactions.length, 1);
    });

    test('only the most recent keys are remembered', () async {
      final d = OperationDispatcher(environment: h.env, maxRememberedKeys: 2);
      final probe = ProbeAction();
      for (final k in ['k1', 'k2', 'k3']) {
        await d.dispatch(probe, const ProbeInput(1), idempotencyKey: k);
      }
      expect(probe.executions, 3);
      expect(
        (await d.dispatch(probe, const ProbeInput(1), idempotencyKey: 'k3') as ActionCompleted<int>).replayed,
        isTrue,
      );
      expect(
        (await d.dispatch(probe, const ProbeInput(1), idempotencyKey: 'k1') as ActionCompleted<int>).replayed,
        isFalse,
      );
      expect(probe.executions, 4);
    });
  });

  group('confirmation', () {
    test('consequential actions need the exact previewed fingerprint', () async {
      final probe = ProbeAction(risk: ActionRisk.consequential);
      final first = await dispatcher.dispatch(probe, const ProbeInput(7), idempotencyKey: 'k');
      expect(first, isA<ActionNeedsConfirmation<int>>());
      final preview = (first as ActionNeedsConfirmation<int>).preview;
      expect(preview.requiresConfirmation, isTrue);
      expect(probe.executions, 0);

      final wrong = await dispatcher.dispatch(
        probe,
        const ProbeInput(7),
        idempotencyKey: 'k',
        confirmation: const ActionConfirmation('not-it'),
      );
      expect(wrong, isA<ActionNeedsConfirmation<int>>());

      final approvedOther = await dispatcher.dispatch(
        probe,
        const ProbeInput(8),
        idempotencyKey: 'k2',
        confirmation: ActionConfirmation(preview.fingerprint),
      );
      expect(approvedOther, isA<ActionNeedsConfirmation<int>>(), reason: 'approval was for different input');
      expect(probe.executions, 0);

      final ok = await dispatcher.dispatch(
        probe,
        const ProbeInput(7),
        idempotencyKey: 'k',
        confirmation: ActionConfirmation(preview.fingerprint, confirmedBy: 'Asha'),
      );
      expect(ok, isA<ActionCompleted<int>>());
      expect(dispatcher.audit.entries.single.confirmedBy, 'Asha');
    });

    test('an approval goes stale when the record it was computed from changes', () async {
      final probe = ProbeAction(risk: ActionRisk.consequential)..basis = {'v': 1};
      final asked = await dispatcher.dispatch(probe, const ProbeInput(1), idempotencyKey: 'k');
      final old = (asked as ActionNeedsConfirmation<int>).preview.fingerprint;
      probe.basis = {'v': 2};
      final stale = await dispatcher.dispatch(
        probe,
        const ProbeInput(1),
        idempotencyKey: 'k',
        confirmation: ActionConfirmation(old),
      );
      expect(stale, isA<ActionNeedsConfirmation<int>>());
      final fresh = (stale as ActionNeedsConfirmation<int>).preview.fingerprint;
      expect(fresh, isNot(old));
      final request = fingerprintOf('probe.create', const ProbeInput(1));
      expect(fingerprintMatchesRequest(old, request), isTrue);
      expect(fingerprintMatchesRequest(fresh, request), isTrue);
      expect(probe.executions, 0);
    });

    test('deleting a transaction edited after the review asks again', () async {
      final tx = await h.run(
        const CreateTransactionAction(),
        TransactionInput(
          type: TransactionType.expense,
          amount: const Money.rupees(500),
          categoryId: SeedCategoryIds.food,
          date: DateTime(2026, 10, 1),
        ),
      );
      final del = DeleteTransactionInput(id: tx.id);
      final asked = await dispatcher.dispatch(const DeleteTransactionAction(), del, idempotencyKey: 'del');
      final fp = (asked as ActionNeedsConfirmation<Transaction>).preview.fingerprint;

      await h.run(
        const UpdateTransactionAction(),
        UpdateTransactionInput(
          id: tx.id,
          expectedVersion: 1,
          data: TransactionInput(
            type: TransactionType.expense,
            amount: const Money.rupees(5000),
            categoryId: SeedCategoryIds.food,
            date: DateTime(2026, 10, 1),
          ),
        ),
      );
      final stale = await dispatcher.dispatch(
        const DeleteTransactionAction(),
        del,
        idempotencyKey: 'del',
        confirmation: ActionConfirmation(fp),
      );
      expect(stale, isA<ActionNeedsConfirmation<Transaction>>());
      expect((await h.snapshot()).transactionById[tx.id], isNotNull);
    });
  });

  group('policy', () {
    test('agent and voice channels confirm every action, even low-risk ones', () async {
      for (final channel in [ActionChannel.agent, ActionChannel.voice]) {
        final probe = ProbeAction();
        final out = await dispatcher.dispatch(
          probe,
          const ProbeInput(1),
          idempotencyKey: 'k-$channel',
          channel: channel,
        );
        expect(out, isA<ActionNeedsConfirmation<int>>());
        final fp = (out as ActionNeedsConfirmation<int>).preview.fingerprint;
        final done = await dispatcher.dispatch(
          probe,
          const ProbeInput(1),
          idempotencyKey: 'k-$channel',
          channel: channel,
          confirmation: ActionConfirmation(fp),
        );
        expect(done, isA<ActionCompleted<int>>());
        expect(dispatcher.audit.entries.first.channel, channel);
      }
    });

    test('agents and voice may never delete, even with a confirmation', () async {
      final probe = ProbeAction(id: 'probe.delete', risk: ActionRisk.consequential);
      final fp = previewFingerprintOf('probe.delete', const ProbeInput(1));
      for (final channel in [ActionChannel.agent, ActionChannel.voice]) {
        final out = await dispatcher.dispatch(
          probe,
          const ProbeInput(1),
          idempotencyKey: 'k-$channel',
          channel: channel,
          confirmation: ActionConfirmation(fp),
        );
        expect((out as ActionRejected<int>).failure.code, FailureCode.notPermitted);
        expect(
          (await dispatcher.preview(probe, const ProbeInput(1), channel: channel)).failureOrNull!.code,
          FailureCode.notPermitted,
        );
      }
      expect(probe.executions, 0);
      final ui = await dispatcher.dispatch(
        probe,
        const ProbeInput(1),
        idempotencyKey: 'ui',
        confirmation: ActionConfirmation(fp),
      );
      expect(ui, isA<ActionCompleted<int>>());
    });

    test('imports may only create', () async {
      final create = await dispatcher.dispatch(
        ProbeAction(),
        const ProbeInput(1),
        idempotencyKey: 'a',
        channel: ActionChannel.import,
      );
      expect(create, isA<ActionCompleted<int>>());
      final update = await dispatcher.dispatch(
        ProbeAction(id: 'probe.update'),
        const ProbeInput(1),
        idempotencyKey: 'b',
        channel: ActionChannel.import,
      );
      expect((update as ActionRejected<int>).failure.code, FailureCode.notPermitted);
    });

    test('the system channel behaves like the UI', () async {
      final out = await dispatcher.dispatch(
        ProbeAction(id: 'probe.delete'),
        const ProbeInput(1),
        idempotencyKey: 'k',
        channel: ActionChannel.system,
      );
      expect(out, isA<ActionCompleted<int>>());
    });
  });

  group('fingerprints', () {
    test('canonical: independent of JSON key order, sensitive to values', () {
      const a = ProbeInput(1, extra: {'b': 2, 'a': 1});
      const b = ProbeInput(1, extra: {'a': 1, 'b': 2});
      expect(fingerprintOf('x.create', a), fingerprintOf('x.create', b));
      expect(fingerprintOf('x.create', a), isNot(fingerprintOf('y.create', a)));
      expect(
        fingerprintOf('x.create', a),
        isNot(fingerprintOf('x.create', const ProbeInput(2, extra: {'b': 2, 'a': 1}))),
      );
    });

    test('preview fingerprint = request fingerprint [+ "." + state hash]', () {
      const input = ProbeInput(1);
      final request = fingerprintOf('x.create', input);
      expect(previewFingerprintOf('x.create', input), request);
      final withBasis = previewFingerprintOf('x.create', input, basis: {'v': 1});
      expect(withBasis, startsWith('$request.'));
      expect(previewFingerprintOf('x.create', input, basis: {'v': 1}), withBasis);
      expect(previewFingerprintOf('x.create', input, basis: {'v': 2}), isNot(withBasis));
      expect(fingerprintMatchesRequest(withBasis, request), isTrue);
      expect(fingerprintMatchesRequest(withBasis, fingerprintOf('x.create', const ProbeInput(2))), isFalse);
    });
  });
}
