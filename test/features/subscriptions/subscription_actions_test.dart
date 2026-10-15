import 'package:finn/actions/action.dart';
import 'package:finn/actions/dispatcher.dart';
import 'package:finn/app/di/action_providers.dart';
import 'package:finn/core/money/money.dart';
import 'package:finn/core/result/result.dart';
import 'package:finn/core/time/dates.dart';
import 'package:finn/features/subscriptions/application/subscription_actions.dart';
import 'package:finn/features/subscriptions/domain/subscription.dart';
import 'package:finn/features/transactions/domain/transaction.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/test_app.dart';

/// Dispatches [action], approving the preview when confirmation is needed.
Future<ActionOutcome<O>> _run<I extends ActionInput, O>(
  ProviderContainer container,
  FinancialAction<I, O> action,
  I input, {
  required String key,
}) async {
  final dispatcher = container.read(actionDispatcherProvider);
  var outcome = await dispatcher.dispatch(action, input, idempotencyKey: key);
  if (outcome is ActionNeedsConfirmation<O>) {
    outcome = await dispatcher.dispatch(
      action,
      input,
      idempotencyKey: key,
      confirmation: ActionConfirmation(outcome.preview.fingerprint),
    );
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

  Future<Subscription> byName(String name) async =>
      (await env.snapshot()).subscriptions.firstWhere((s) => s.name == name);

  Future<List<Transaction>> linked(String id) async => (await env.snapshot()).linkedTransactions(id);

  test('markPaid creates exactly one linked expense and advances the due date by one cycle', () async {
    final sub = await byName('Netflix Premium');
    final before = await linked(sub.id);
    final txCountBefore = (await env.snapshot()).transactions.length;

    final outcome = await _run(
      container,
      const MarkSubscriptionPaidAction(),
      MarkSubscriptionPaidInput(subscriptionId: sub.id, cycleDate: sub.nextDueDate),
      key: 'pay-1',
    );

    expect(outcome, isA<ActionCompleted<Transaction>>());
    final tx = (outcome as ActionCompleted<Transaction>).value;
    expect(tx.type, TransactionType.expense);
    expect(tx.amount, sub.amount);
    expect(tx.categoryId, sub.categoryId);
    expect(tx.origin, TransactionOrigin.subscription);
    expect(tx.originRefId, sub.id);
    // Due date is in the future, so the payment date defaults to today.
    expect(tx.date, testNow.dateOnly);

    final snapshot = await env.snapshot();
    expect(snapshot.transactions.length, txCountBefore + 1);
    expect((await linked(sub.id)).length, before.length + 1);
    final updated = snapshot.subscriptions.firstWhere((s) => s.id == sub.id);
    expect(updated.nextDueDate, addMonthsClamped(sub.nextDueDate, 1));
  });

  test('a second markPaid for the same cycle is rejected and creates nothing', () async {
    final sub = await byName('Netflix Premium');
    final input = MarkSubscriptionPaidInput(subscriptionId: sub.id, cycleDate: sub.nextDueDate);
    await _run(container, const MarkSubscriptionPaidAction(), input, key: 'pay-a');
    final afterFirst = (await env.snapshot()).transactions.length;

    // A different request id (e.g. a stale second screen) for the same cycle.
    final second = await _run(container, const MarkSubscriptionPaidAction(), input, key: 'pay-b');

    expect(second, isA<ActionRejected<Transaction>>());
    expect((second as ActionRejected<Transaction>).failure.code, FailureCode.duplicate);
    expect((await env.snapshot()).transactions.length, afterFirst);
    expect((await byName('Netflix Premium')).nextDueDate, addMonthsClamped(sub.nextDueDate, 1));
  });

  test('markPaid rejects a cycle that already has a recorded payment', () async {
    final sub = await byName('Spotify Premium');
    // Simulate an earlier payment recorded for the current cycle.
    await env.repos.transactions.save(
      Transaction(
        id: 'tx_manual_dup',
        type: TransactionType.expense,
        amount: sub.amount,
        categoryId: sub.categoryId,
        accountId: 'acc_cash',
        date: testNow.dateOnly,
        origin: TransactionOrigin.subscription,
        originRefId: sub.id,
        note: SubscriptionSchedule.paymentNote(sub, sub.nextDueDate),
        createdAt: testNow,
        updatedAt: testNow,
      ),
    );

    final outcome = await _run(
      container,
      const MarkSubscriptionPaidAction(),
      MarkSubscriptionPaidInput(subscriptionId: sub.id),
      key: 'pay-dup',
    );

    expect(outcome, isA<ActionRejected<Transaction>>());
    expect((await byName('Spotify Premium')).nextDueDate, sub.nextDueDate);
  });

  test('skip advances the due date without creating a transaction', () async {
    final sub = await byName('YouTube Premium');
    final txCount = (await env.snapshot()).transactions.length;

    final outcome = await _run(
      container,
      const SkipSubscriptionCycleAction(),
      SkipSubscriptionCycleInput(subscriptionId: sub.id, cycleDate: sub.nextDueDate),
      key: 'skip',
    );

    expect(outcome, isA<ActionCompleted<Subscription>>());
    final snapshot = await env.snapshot();
    expect(snapshot.transactions.length, txCount);
    expect(snapshot.subscriptions.firstWhere((s) => s.id == sub.id).nextDueDate, addMonthsClamped(sub.nextDueDate, 1));
  });

  test('a due date passing never creates a transaction by itself', () async {
    final sub = await byName('Cult.fit Elite');
    expect(sub.nextDueDate.isBefore(testNow.dateOnly), isTrue, reason: 'seed has this one overdue');
    final before = await env.snapshot();

    // Weeks go by without the user marking anything as paid.
    env.clock.advance(const Duration(days: 45));
    final later = await env.snapshot();

    expect(later.transactions.length, before.transactions.length);
    expect(later.linkedTransactions(sub.id).length, before.linkedTransactions(sub.id).length);
    final same = later.subscriptions.firstWhere((s) => s.id == sub.id);
    expect(same.nextDueDate, sub.nextDueDate);
    expect(const SubscriptionCalculator().dueState(same, later.today), DueState.overdue);
  });

  test('paused subscriptions cannot be marked paid', () async {
    final sub = await byName('Disney+ Hotstar');
    final outcome = await _run(
      container,
      const MarkSubscriptionPaidAction(),
      MarkSubscriptionPaidInput(subscriptionId: sub.id, amount: const Money.rupees(299)),
      key: 'paused',
    );
    expect(outcome, isA<ActionRejected<Transaction>>());
  });
}
