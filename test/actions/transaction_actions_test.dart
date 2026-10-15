import 'package:finn/actions/action.dart';
import 'package:finn/actions/dispatcher.dart';
import 'package:finn/core/money/money.dart';
import 'package:finn/core/result/result.dart';
import 'package:finn/data/mock/seed_data.dart';
import 'package:finn/features/categories/domain/category.dart';
import 'package:finn/features/transactions/application/transaction_actions.dart';
import 'package:finn/features/transactions/domain/transaction.dart';
import 'package:flutter_test/flutter_test.dart';

import 'action_harness.dart';

TransactionInput expense(int rupees, {String category = SeedCategoryIds.food, DateTime? date, String? counterparty}) =>
    TransactionInput(
      type: TransactionType.expense,
      amount: Money.rupees(rupees),
      categoryId: category,
      date: date ?? DateTime(2026, 10, 9),
      channel: 'UPI',
      counterparty: counterparty,
    );

TransactionInput income(int rupees, {String category = SeedCategoryIds.salary}) => TransactionInput(
      type: TransactionType.income,
      amount: Money.rupees(rupees),
      categoryId: category,
      date: DateTime(2026, 10, 1),
    );

void main() {
  late ActionHarness h;
  setUp(() async => h = await ActionHarness.create());

  group('transactions.create', () {
    test('records income and expenses against cash; low risk, no review needed', () async {
      final out = await h.dispatcher.dispatch(const CreateTransactionAction(), income(50000), idempotencyKey: 'i');
      expect(out, isA<ActionCompleted<Transaction>>());
      final spent = await h.run(const CreateTransactionAction(), expense(1200, counterparty: 'Swiggy'));
      expect(spent.id, 'tx_2');
      expect(spent.origin, TransactionOrigin.manual);
      expect(spent.version, 1);
      expect(spent.createdAt, harnessNow);
      final s = await h.snapshot();
      expect(s.balance.cash, harnessOpening + const Money.rupees(50000 - 1200));
      expect(s.monthSummary(s.currentMonth).expense, const Money.rupees(1200));
    });

    test('an entry dated before tracking start moves the start back so it counts in cash', () async {
      final profile = h.store.profile.current!;
      await h.store.profile.set(profile.copyWith(openingDate: DateTime(2026, 10, 9)));
      await h.run(const CreateTransactionAction(), expense(700, date: DateTime(2026, 10, 5)));
      final s = await h.snapshot();
      expect(s.profile!.openingDate, DateTime(2026, 10, 5));
      expect(s.profile!.openingBalance, harnessOpening);
      expect(s.balance.cash, harnessOpening - const Money.rupees(700));
      // A later entry leaves the start alone.
      await h.run(const CreateTransactionAction(), expense(100, date: DateTime(2026, 10, 9)));
      expect((await h.snapshot()).profile!.openingDate, DateTime(2026, 10, 5));
    });

    test('dates are stored as calendar dates', () async {
      final t = await h.run(
        const CreateTransactionAction(),
        TransactionInput(
            type: TransactionType.expense, amount: const Money.rupees(1), categoryId: SeedCategoryIds.food, date: DateTime(2026, 10, 9, 22, 15)),
      );
      expect(t.date, DateTime(2026, 10, 9));
    });

    test('validation', () async {
      Future<Map<String, String>> errors(TransactionInput i) async =>
          (await h.reject(const CreateTransactionAction(), i)).fieldErrors;
      expect((await errors(expense(0))).keys, ['amount']);
      expect((await errors(expense(100000001))).keys, ['amount']);
      expect((await errors(expense(10, date: DateTime(2026, 10, 11)))).keys, ['date']);
      expect((await errors(expense(10, category: SeedCategoryIds.salary)))['categoryId'], 'This category is for income.');
      expect((await errors(expense(10, category: 'cat_missing'))).keys, ['categoryId']);
      expect((await errors(expense(10, category: SystemCategories.loanEmi)))['categoryId'],
          'This category is managed automatically. Choose another.');
      expect((await errors(expense(10, counterparty: 'x' * 81))).keys, ['counterparty']);
      // The "Other" system categories stay available for manual entries.
      await h.run(const CreateTransactionAction(), expense(10, category: SystemCategories.uncategorizedExpense));
      await h.run(const CreateTransactionAction(), income(10, category: SystemCategories.uncategorizedIncome));
    });

    test('archived categories cannot be used', () async {
      final food = (await h.snapshot()).category(SeedCategoryIds.food)!;
      await h.repos.categories.save(food.copyWith(isArchived: true));
      expect((await h.reject(const CreateTransactionAction(), expense(10))).fieldErrors.keys, ['categoryId']);
    });

    test('warns, without blocking, when an expense exceeds the available balance', () async {
      final preview = (await h.dispatcher.preview(const CreateTransactionAction(), expense(150000))).valueOrNull!;
      expect(preview.warnings.single, startsWith('This is more than your available balance'));
      await h.run(const CreateTransactionAction(), expense(150000));
      expect((await h.snapshot()).balance.cash, const Money.rupees(-50000));
    });

    test('JSON round trip through decode', () {
      final input = expense(1250, counterparty: 'Zomato');
      final decoded = const CreateTransactionAction().decode(input.toJson());
      expect(decoded.toJson(), input.toJson());
      expect(fingerprintOf('transactions.create', decoded), fingerprintOf('transactions.create', input));
    });
  });

  group('transactions.update', () {
    late Transaction original;
    setUp(() async => original = await h.run(const CreateTransactionAction(), expense(500)));

    test('changes the record, bumps the version and recalculates balances', () async {
      final updated = await h.run(
        const UpdateTransactionAction(),
        UpdateTransactionInput(id: original.id, expectedVersion: 1, data: expense(800, category: SeedCategoryIds.groceries)),
      );
      expect(updated.version, 2);
      expect(updated.categoryId, SeedCategoryIds.groceries);
      expect(updated.createdAt, original.createdAt);
      final s = await h.snapshot();
      expect(s.transactions.length, 1);
      expect(s.balance.cash, harnessOpening - const Money.rupees(800));
    });

    test('a stale version is rejected', () async {
      final input = UpdateTransactionInput(id: original.id, expectedVersion: 1, data: expense(800));
      await h.run(const UpdateTransactionAction(), input);
      final f = await h.reject(const UpdateTransactionAction(),
          UpdateTransactionInput(id: original.id, expectedVersion: 1, data: expense(900)));
      expect(f.code, FailureCode.staleData);
    });

    test('linked transactions can only be changed from their module', () async {
      final linked = Transaction(
        id: 'tx_linked',
        type: TransactionType.expense,
        amount: const Money.rupees(12602),
        categoryId: SystemCategories.loanEmi,
        accountId: 'acc_cash',
        date: DateTime(2026, 10, 5),
        origin: TransactionOrigin.loanRepayment,
        originRefId: 'loan_1',
        createdAt: harnessNow,
        updatedAt: harnessNow,
      );
      await h.repos.transactions.save(linked);
      final u = await h.reject(const UpdateTransactionAction(),
          UpdateTransactionInput(id: linked.id, expectedVersion: 1, data: expense(1)));
      expect(u.code, FailureCode.notPermitted);
      final d = await h.reject(const DeleteTransactionAction(), const DeleteTransactionInput(id: 'tx_linked'));
      expect(d.code, FailureCode.notPermitted);
    });

    test('missing records', () async {
      expect((await h.reject(const UpdateTransactionAction(),
                  UpdateTransactionInput(id: 'nope', expectedVersion: 1, data: expense(1))))
              .code,
          FailureCode.notFound);
      expect((await h.reject(const DeleteTransactionAction(), const DeleteTransactionInput(id: 'nope'))).code,
          FailureCode.notFound);
    });
  });

  group('transactions.delete', () {
    test('is consequential: previews the balance effect, then reverses it', () async {
      final t = await h.run(const CreateTransactionAction(), expense(500));
      final out = await h.dispatcher.dispatch(const DeleteTransactionAction(), DeleteTransactionInput(id: t.id), idempotencyKey: 'd');
      final preview = (out as ActionNeedsConfirmation<Transaction>).preview;
      expect(preview.lines.firstWhere((l) => l.label == 'Balance effect').value, startsWith('+'));
      expect(preview.warnings, contains('This cannot be undone.'));
      expect((await h.snapshot()).transactions, isNotEmpty);

      await h.run(const DeleteTransactionAction(), DeleteTransactionInput(id: t.id));
      final s = await h.snapshot();
      expect(s.transactions, isEmpty);
      expect(s.balance.cash, harnessOpening);
    });
  });
}
