import 'package:finn/actions/dispatcher.dart';
import 'package:finn/core/money/money.dart';
import 'package:finn/core/result/result.dart';
import 'package:finn/core/time/dates.dart';
import 'package:finn/data/mock/seed_data.dart';
import 'package:finn/features/budgets/application/budget_actions.dart';
import 'package:finn/features/budgets/domain/budget.dart';
import 'package:finn/features/transactions/application/transaction_actions.dart';
import 'package:finn/features/transactions/domain/transaction.dart';
import 'package:flutter_test/flutter_test.dart';

import 'action_harness.dart';

BudgetInput monthly(int limit, {String category = SeedCategoryIds.food, int? warn}) =>
    BudgetInput(categoryId: category, limit: Money.rupees(limit), warningThresholdBps: warn);

BudgetInput custom(DateTime? start, DateTime? end, {int limit = 50000}) => BudgetInput(
      categoryId: SeedCategoryIds.travel,
      limit: Money.rupees(limit),
      periodType: BudgetPeriodType.custom,
      customStart: start,
      customEnd: end,
    );

void main() {
  late ActionHarness h;
  setUp(() async => h = await ActionHarness.create());

  group('budgets.create', () {
    test('a monthly budget with the default warning level; holds no money', () async {
      final out = await h.dispatcher.dispatch(const CreateBudgetAction(), monthly(8000), idempotencyKey: 'k');
      final b = (out as ActionCompleted<Budget>).value;
      expect(b.warningThresholdBps, defaultBudgetWarningBps);
      expect(b.customRange, isNull);
      expect(out.preview.summary, 'Budget for Food & Dining · ₹8,000');
      final s = await h.snapshot();
      expect(s.balance.available, harnessOpening);
      expect(s.budgetUsage(b.id)!.period, MonthKey(2026, 10).range);
    });

    test('spending is derived from transactions', () async {
      final b = await h.run(const CreateBudgetAction(), monthly(1000));
      await h.run(
        const CreateTransactionAction(),
        TransactionInput(type: TransactionType.expense, amount: const Money.rupees(850), categoryId: SeedCategoryIds.food, date: DateTime(2026, 10, 3)),
      );
      final u = (await h.snapshot()).budgetUsage(b.id)!;
      expect(u.spent, const Money.rupees(850));
      expect(u.health, BudgetHealth.warning);
    });

    test('one active monthly budget per category', () async {
      await h.run(const CreateBudgetAction(), monthly(8000));
      final f = await h.reject(const CreateBudgetAction(), monthly(9000));
      expect(f.fieldErrors['categoryId'], 'Food & Dining already has a monthly budget. Edit that one instead.');
      await h.run(const CreateBudgetAction(), monthly(9000, category: SeedCategoryIds.groceries));
    });

    test('custom periods need valid dates of at most 366 days', () async {
      final b = await h.run(const CreateBudgetAction(), custom(DateTime(2026, 12, 20), DateTime(2027, 1, 5)));
      expect(b.customRange, DateRange(DateTime(2026, 12, 20), DateTime(2027, 1, 5)));
      Future<Iterable<String>> fields(BudgetInput i) async => (await h.reject(const CreateBudgetAction(), i)).fieldErrors.keys;
      expect(await fields(custom(null, DateTime(2027, 1, 5))), ['customRange']);
      expect(await fields(custom(DateTime(2027, 1, 5), DateTime(2027, 1, 4))), ['customRange']);
      expect(await fields(custom(DateTime(2026, 1, 1), DateTime(2027, 1, 2))), ['customRange']);
      await h.run(const CreateBudgetAction(), custom(DateTime(2026, 1, 1), DateTime(2027, 1, 1)));
    });

    test('field validation', () async {
      Future<Iterable<String>> fields(BudgetInput i) async => (await h.reject(const CreateBudgetAction(), i)).fieldErrors.keys;
      expect(await fields(monthly(0)), ['limit']);
      expect(await fields(monthly(100000001)), ['limit']);
      expect(await fields(monthly(100, category: SeedCategoryIds.salary)), ['categoryId']);
      expect(await fields(monthly(100, category: 'nope')), ['categoryId']);
      expect(await fields(monthly(100, warn: 4999)), ['warningThresholdBps']);
      expect(await fields(monthly(100, warn: 9501)), ['warningThresholdBps']);
      await h.run(const CreateBudgetAction(), monthly(100, warn: 9500));
    });
  });

  group('budgets.update / setPaused / delete', () {
    late Budget food;
    setUp(() async => food = await h.run(const CreateBudgetAction(), monthly(8000)));

    test('update keeps its own category without a self-conflict and bumps the version', () async {
      final u = await h.run(const UpdateBudgetAction(), UpdateBudgetInput(id: food.id, expectedVersion: 1, data: monthly(9000)));
      expect(u.limit, const Money.rupees(9000));
      expect(u.version, 2);
      expect(u.warningThresholdBps, 8000, reason: 'unchanged when not supplied');
      final stale = await h.reject(const UpdateBudgetAction(), UpdateBudgetInput(id: food.id, expectedVersion: 1, data: monthly(1)));
      expect(stale.code, FailureCode.staleData);
    });

    test('a paused budget frees the category; resuming then conflicts', () async {
      final paused = await h.run(const SetBudgetPausedAction(), SetBudgetPausedInput(id: food.id, paused: true));
      expect(paused.status, BudgetStatus.paused);
      expect((await h.snapshot()).budgetUsage(food.id)!.health, BudgetHealth.paused);
      final again = await h.run(const SetBudgetPausedAction(), SetBudgetPausedInput(id: food.id, paused: true));
      expect(again.version, paused.version, reason: 'no-op when already paused');

      await h.run(const CreateBudgetAction(), monthly(5000));
      final resume = await h.reject(const SetBudgetPausedAction(), SetBudgetPausedInput(id: food.id, paused: false));
      expect(resume.code, FailureCode.conflict);
    });

    test('delete is reviewed and leaves transactions alone', () async {
      await h.run(
        const CreateTransactionAction(),
        TransactionInput(type: TransactionType.expense, amount: const Money.rupees(100), categoryId: SeedCategoryIds.food, date: DateTime(2026, 10, 3)),
      );
      final asked = await h.dispatcher.dispatch(const DeleteBudgetAction(), BudgetIdInput(id: food.id), idempotencyKey: 'd');
      expect(asked, isA<ActionNeedsConfirmation<Budget>>());
      await h.run(const DeleteBudgetAction(), BudgetIdInput(id: food.id));
      final s = await h.snapshot();
      expect(s.budgets, isEmpty);
      expect(s.transactions.length, 1);
      expect((await h.reject(const DeleteBudgetAction(), BudgetIdInput(id: food.id))).code, FailureCode.notFound);
    });
  });
}
