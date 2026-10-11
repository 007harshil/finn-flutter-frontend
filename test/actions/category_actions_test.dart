import 'package:finn/actions/dispatcher.dart';
import 'package:finn/core/money/money.dart';
import 'package:finn/core/result/result.dart';
import 'package:finn/data/mock/seed_data.dart';
import 'package:finn/features/budgets/application/budget_actions.dart';
import 'package:finn/features/categories/application/category_actions.dart';
import 'package:finn/features/categories/domain/category.dart';
import 'package:finn/features/transactions/application/transaction_actions.dart';
import 'package:finn/features/transactions/domain/transaction.dart';
import 'package:flutter_test/flutter_test.dart';

import 'action_harness.dart';

CategoryInput cat(String name,
        {TransactionType type = TransactionType.expense, int color = 3, bool essential = false, String icon = 'paw'}) =>
    CategoryInput(name: name, type: type, iconKey: icon, colorIndex: color, isEssential: essential);

void main() {
  late ActionHarness h;
  setUp(() async => h = await ActionHarness.create());

  group('categories.create', () {
    test('creates a custom category (low risk)', () async {
      final out = await h.dispatcher.dispatch(const CreateCategoryAction(), cat('  Pets ', essential: true), idempotencyKey: 'k');
      final c = (out as ActionCompleted<TransactionCategory>).value;
      expect(c.name, 'Pets');
      expect(c.isEssential, isTrue);
      expect(c.isSystem, isFalse);
      expect((await h.snapshot()).category(c.id), isNotNull);
    });

    test('income categories are never essential', () async {
      final c = await h.run(const CreateCategoryAction(), cat('Dividends', type: TransactionType.income, essential: true));
      expect(c.isEssential, isFalse);
    });

    test('names are unique per type, case-insensitively', () async {
      final f = await h.reject(const CreateCategoryAction(), cat('food & dining'));
      expect(f.fieldErrors['name'], contains('category called "Food & Dining"'));
      await h.run(const CreateCategoryAction(), cat('Food & Dining', type: TransactionType.income));
    });

    test('duplicate-name message uses the right article', () async {
      final f = await h.reject(const CreateCategoryAction(), cat('food & dining'));
      expect(f.fieldErrors['name'], 'You already have an expense category called "Food & Dining".');
    });

    test('an archived clash suggests restoring it', () async {
      await h.run(const ArchiveCategoryAction(), const CategoryIdInput(id: SeedCategoryIds.fitness));
      final f = await h.reject(const CreateCategoryAction(), cat('Fitness'));
      expect(f.fieldErrors['name'], contains('Restore it instead'));
    });

    test('field validation', () async {
      Future<Iterable<String>> fields(CategoryInput i) async => (await h.reject(const CreateCategoryAction(), i)).fieldErrors.keys;
      expect(await fields(cat('P')), ['name']);
      expect(await fields(cat('x' * 31)), ['name']);
      expect(await fields(cat('Pets', color: 14)), ['colorIndex']);
      expect(await fields(cat('Pets', color: -1)), ['colorIndex']);
      expect(await fields(cat('Pets', icon: ' ')), ['iconKey']);
      expect(await fields(CategoryInput(name: 'Pets', type: TransactionType.expense, iconKey: 'paw', colorIndex: 0, description: 'd' * 121)),
          ['description']);
    });
  });

  group('categories.update', () {
    test('renames and bumps the version; stale versions are rejected', () async {
      final c = await h.run(const CreateCategoryAction(), cat('Pets'));
      final u = await h.run(const UpdateCategoryAction(), UpdateCategoryInput(id: c.id, expectedVersion: 1, data: cat('Pet care')));
      expect(u.name, 'Pet care');
      expect(u.version, 2);
      expect((await h.reject(const UpdateCategoryAction(), UpdateCategoryInput(id: c.id, expectedVersion: 1, data: cat('X1'))))
          .code, FailureCode.staleData);
    });

    test('system categories only allow icon and colour changes', () async {
      final emi = (await h.snapshot()).category(SystemCategories.loanEmi)!;
      CategoryInput same({String? name, int color = 4}) => CategoryInput(
          name: name ?? emi.name, type: emi.type, iconKey: 'landmark', colorIndex: color, description: emi.description);
      final renamed = await h.reject(const UpdateCategoryAction(),
          UpdateCategoryInput(id: emi.id, expectedVersion: 1, data: same(name: 'EMIs')));
      expect(renamed.code, FailureCode.notPermitted);
      final restyled = await h.run(const UpdateCategoryAction(), UpdateCategoryInput(id: emi.id, expectedVersion: 1, data: same()));
      expect(restyled.colorIndex, 4);
      expect(restyled.iconKey, 'landmark');
      expect(restyled.isSystem, isTrue);
    });

    test('the type of a category in use cannot change', () async {
      final c = await h.run(const CreateCategoryAction(), cat('Pets'));
      await h.run(
        const CreateTransactionAction(),
        TransactionInput(type: TransactionType.expense, amount: const Money.rupees(10), categoryId: c.id, date: DateTime(2026, 10, 1)),
      );
      final f = await h.reject(const UpdateCategoryAction(),
          UpdateCategoryInput(id: c.id, expectedVersion: 1, data: cat('Pets', type: TransactionType.income)));
      expect(f.fieldErrors['type'], 'This category is used by 1 transaction, so its type cannot change.');
    });
  });

  group('archive and delete', () {
    test('archiving warns about budgets that still track the category; restoring works', () async {
      await h.run(const CreateBudgetAction(), BudgetInput(categoryId: SeedCategoryIds.food, limit: const Money.rupees(5000)));
      final asked = await h.dispatcher.preview(const ArchiveCategoryAction(), const CategoryIdInput(id: SeedCategoryIds.food));
      expect(asked.valueOrNull!.warnings.single, startsWith('1 budget still track'));
      final archived = await h.run(const ArchiveCategoryAction(), const CategoryIdInput(id: SeedCategoryIds.food));
      expect(archived.isArchived, isTrue);
      final restored = await h.run(const ArchiveCategoryAction(), const CategoryIdInput(id: SeedCategoryIds.food));
      expect(restored.isArchived, isFalse);
      expect(restored.version, 3);
    });

    test('archive warning agrees in number', () async {
      await h.run(const CreateBudgetAction(), BudgetInput(categoryId: SeedCategoryIds.food, limit: const Money.rupees(5000)));
      final asked = await h.dispatcher.preview(const ArchiveCategoryAction(), const CategoryIdInput(id: SeedCategoryIds.food));
      expect(asked.valueOrNull!.warnings, ['1 budget still tracks this category.']);
    });

    test('system categories cannot be archived or deleted', () async {
      expect((await h.reject(const ArchiveCategoryAction(), const CategoryIdInput(id: SystemCategories.loanEmi))).code,
          FailureCode.notPermitted);
      expect((await h.reject(const DeleteCategoryAction(), const CategoryIdInput(id: SystemCategories.loanEmi))).code,
          FailureCode.notPermitted);
    });

    test('a category in use cannot be deleted; an unused one can (after review)', () async {
      await h.run(const CreateBudgetAction(), BudgetInput(categoryId: SeedCategoryIds.food, limit: const Money.rupees(5000)));
      final inUse = await h.reject(const DeleteCategoryAction(), const CategoryIdInput(id: SeedCategoryIds.food));
      expect(inUse.code, FailureCode.conflict);
      expect(inUse.message, contains('1 budget'));

      final asked = await h.dispatcher.dispatch(const DeleteCategoryAction(), const CategoryIdInput(id: SeedCategoryIds.fitness),
          idempotencyKey: 'd');
      expect(asked, isA<ActionNeedsConfirmation<TransactionCategory>>());
      await h.run(const DeleteCategoryAction(), const CategoryIdInput(id: SeedCategoryIds.fitness));
      expect((await h.snapshot()).category(SeedCategoryIds.fitness), isNull);
    });
  });

  test('CategoryUsage.describe', () {
    expect(const CategoryUsage(transactions: 12, budgets: 1, subscriptions: 0).describe(), '12 transactions, 1 budget');
    expect(const CategoryUsage(transactions: 0, budgets: 0, subscriptions: 2).describe(), '2 subscriptions');
    expect(const CategoryUsage(transactions: 0, budgets: 0, subscriptions: 0).isInUse, isFalse);
  });
}
