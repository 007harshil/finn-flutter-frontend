import '../../../actions/action.dart';
import '../../../core/result/result.dart';
import '../../../finance/finance_snapshot.dart';
import '../../transactions/domain/transaction.dart';
import '../domain/category.dart';

/// Number of colour swatches a category can use (`AccentSwatches`).
const int categoryColorCount = 14;
const int categoryNameMin = 2;
const int categoryNameMax = 30;
const int categoryDescriptionMax = 120;

/// Input for creating or updating a category.
class CategoryInput extends ActionInput {
  const CategoryInput({
    required this.name,
    required this.type,
    required this.iconKey,
    required this.colorIndex,
    this.description = '',
    this.isEssential = false,
  });

  final String name;
  final TransactionType type;
  final String iconKey;
  final int colorIndex;
  final String description;
  final bool isEssential;

  factory CategoryInput.fromJson(Map<String, Object?> j) => CategoryInput(
    name: In.str(j, 'name'),
    type: In.enumeration(j, 'type', TransactionType.values),
    iconKey: In.str(j, 'iconKey'),
    colorIndex: In.integer(j, 'colorIndex'),
    description: In.strOpt(j, 'description') ?? '',
    isEssential: In.boolean(j, 'isEssential', fallback: false),
  );

  @override
  Map<String, Object?> toJson() => {
    'name': name,
    'type': type.name,
    'iconKey': iconKey,
    'colorIndex': colorIndex,
    'description': description,
    'isEssential': isEssential,
  };
}

const _fields = [
  ActionFieldSpec('name', FieldKind.string, 'Category name, 2–30 characters, unique per type'),
  ActionFieldSpec('type', FieldKind.enumeration, 'income or expense', allowedValues: ['income', 'expense']),
  ActionFieldSpec('iconKey', FieldKind.string, 'Icon key, e.g. utensils'),
  ActionFieldSpec('colorIndex', FieldKind.integer, 'Colour swatch index, 0–13'),
  ActionFieldSpec('description', FieldKind.string, 'What belongs here', required: false),
  ActionFieldSpec(
    'isEssential',
    FieldKind.boolean,
    'Essential spending (used for the emergency-fund suggestion)',
    required: false,
  ),
];

/// How often a category is referenced elsewhere.
class CategoryUsage {
  const CategoryUsage({required this.transactions, required this.budgets, required this.subscriptions});

  final int transactions;
  final int budgets;
  final int subscriptions;

  bool get isInUse => transactions > 0 || budgets > 0 || subscriptions > 0;

  @override
  bool operator ==(Object other) =>
      other is CategoryUsage &&
      other.transactions == transactions &&
      other.budgets == budgets &&
      other.subscriptions == subscriptions;

  @override
  int get hashCode => Object.hash(transactions, budgets, subscriptions);

  /// "12 transactions, 1 budget".
  String describe() {
    String n(int count, String word) => '$count $word${count == 1 ? '' : 's'}';
    return [
      if (transactions > 0) n(transactions, 'transaction'),
      if (budgets > 0) n(budgets, 'budget'),
      if (subscriptions > 0) n(subscriptions, 'subscription'),
    ].join(', ');
  }
}

CategoryUsage categoryUsage(String categoryId, FinanceSnapshot s) => CategoryUsage(
  transactions: s.transactions.where((t) => t.categoryId == categoryId).length,
  budgets: s.budgets.where((b) => b.categoryId == categoryId).length,
  subscriptions: s.subscriptions.where((x) => x.categoryId == categoryId).length,
);

/// Field validation shared by create and update. [selfId] is excluded from
/// the uniqueness check when editing.
Map<String, String> validateCategory(CategoryInput i, FinanceSnapshot s, {String? selfId}) {
  final errors = <String, String>{};
  final name = i.name.trim();
  if (name.length < categoryNameMin || name.length > categoryNameMax) {
    errors['name'] = 'Use $categoryNameMin to $categoryNameMax characters.';
  } else {
    final clash = s.categories.where(
      (c) => c.id != selfId && c.type == i.type && c.name.trim().toLowerCase() == name.toLowerCase(),
    );
    if (clash.isNotEmpty) {
      final existing = clash.first;
      errors['name'] = existing.isArchived
          ? 'An archived ${i.type.label.toLowerCase()} category is called "${existing.name}". Restore it instead.'
          : 'You already have ${_withArticle(i.type.label.toLowerCase())} category called "${existing.name}".';
    }
  }
  if (i.iconKey.trim().isEmpty) errors['iconKey'] = 'Choose an icon.';
  if (i.colorIndex < 0 || i.colorIndex >= categoryColorCount) errors['colorIndex'] = 'Choose a colour.';
  if (i.description.length > categoryDescriptionMax) {
    errors['description'] = 'Keep this under $categoryDescriptionMax characters.';
  }
  return errors;
}

List<PreviewLine> _lines(CategoryInput i) => [
  PreviewLine('Name', i.name.trim()),
  PreviewLine('Type', i.type.label),
  if (i.type == TransactionType.expense) PreviewLine('Essential', i.isEssential ? 'Yes' : 'No'),
];

class CreateCategoryAction extends FinancialAction<CategoryInput, TransactionCategory> {
  const CreateCategoryAction();

  @override
  ActionDescriptor get descriptor => const ActionDescriptor(
    id: 'categories.create',
    module: 'categories',
    title: 'Create a category',
    description: 'Adds a custom income or expense category. Does not move money.',
    risk: ActionRisk.low,
    fields: _fields,
  );

  @override
  CategoryInput decode(Map<String, Object?> json) => CategoryInput.fromJson(json);

  @override
  Result<ActionPreview> prepare(CategoryInput input, FinanceSnapshot s, ActionEnvironment env) {
    final errors = validateCategory(input, s);
    if (errors.isNotEmpty) return Result.err(AppFailure.validation(errors.values.first, fields: errors));
    return Result.ok(
      preview(
        input,
        title: 'Create category',
        summary: 'Category "${input.name.trim()}" created',
        lines: _lines(input),
      ),
    );
  }

  @override
  Future<Result<TransactionCategory>> execute(CategoryInput input, FinanceSnapshot s, ActionEnvironment env) async {
    final c = TransactionCategory(
      id: env.ids.next('cat'),
      name: input.name.trim(),
      type: input.type,
      iconKey: input.iconKey,
      colorIndex: input.colorIndex,
      description: input.description.trim(),
      isEssential: input.type == TransactionType.expense && input.isEssential,
    );
    await env.repos.categories.save(c);
    return Result.ok(c);
  }
}

class UpdateCategoryInput extends ActionInput {
  const UpdateCategoryInput({required this.id, required this.expectedVersion, required this.data});
  final String id;

  /// Version the user edited; a mismatch means it changed meanwhile.
  final int expectedVersion;
  final CategoryInput data;

  @override
  Map<String, Object?> toJson() => {'id': id, 'expectedVersion': expectedVersion, ...data.toJson()};
}

class UpdateCategoryAction extends FinancialAction<UpdateCategoryInput, TransactionCategory> {
  const UpdateCategoryAction();

  @override
  ActionDescriptor get descriptor => const ActionDescriptor(
    id: 'categories.update',
    module: 'categories',
    title: 'Edit a category',
    description: 'Renames or restyles a category. System categories only allow icon and colour changes.',
    risk: ActionRisk.low,
    fields: [
      ActionFieldSpec('id', FieldKind.id, 'Category id'),
      ActionFieldSpec('expectedVersion', FieldKind.integer, 'Version that was read'),
      ..._fields,
    ],
  );

  @override
  UpdateCategoryInput decode(Map<String, Object?> json) => UpdateCategoryInput(
    id: In.str(json, 'id'),
    expectedVersion: In.integer(json, 'expectedVersion'),
    data: CategoryInput.fromJson(json),
  );

  @override
  Result<ActionPreview> prepare(UpdateCategoryInput input, FinanceSnapshot s, ActionEnvironment env) {
    final existing = s.category(input.id);
    if (existing == null) return const Result.err(AppFailure.notFound('This category no longer exists.'));
    if (existing.version != input.expectedVersion) {
      return const Result.err(
        AppFailure(FailureCode.staleData, 'This category changed since you opened it. Reload and try again.'),
      );
    }
    final d = input.data;
    if (existing.isSystem) {
      final changed =
          d.name.trim() != existing.name ||
          d.type != existing.type ||
          d.description.trim() != existing.description ||
          d.isEssential != existing.isEssential;
      if (changed) {
        return const Result.err(
          AppFailure(
            FailureCode.notPermitted,
            'This category is managed automatically. Only its icon and colour can change.',
          ),
        );
      }
    }
    final errors = validateCategory(d, s, selfId: existing.id);
    if (d.type != existing.type) {
      final usage = categoryUsage(existing.id, s);
      if (usage.isInUse) {
        errors['type'] = 'This category is used by ${usage.describe()}, so its type cannot change.';
      }
    }
    if (errors.isNotEmpty) return Result.err(AppFailure.validation(errors.values.first, fields: errors));
    return Result.ok(
      preview(input, title: 'Save changes', summary: 'Category "${d.name.trim()}" updated', lines: _lines(d)),
    );
  }

  @override
  Future<Result<TransactionCategory>> execute(
    UpdateCategoryInput input,
    FinanceSnapshot s,
    ActionEnvironment env,
  ) async {
    final existing = s.category(input.id)!;
    final d = input.data;
    final updated = existing.copyWith(
      name: d.name.trim(),
      type: d.type,
      iconKey: d.iconKey,
      colorIndex: d.colorIndex,
      description: d.description.trim(),
      isEssential: d.type == TransactionType.expense && d.isEssential,
      version: existing.version + 1,
    );
    await env.repos.categories.save(updated);
    return Result.ok(updated);
  }
}

class CategoryIdInput extends ActionInput {
  const CategoryIdInput({required this.id});
  final String id;

  @override
  Map<String, Object?> toJson() => {'id': id};
}

class ArchiveCategoryAction extends FinancialAction<CategoryIdInput, TransactionCategory> {
  const ArchiveCategoryAction();

  @override
  ActionDescriptor get descriptor => const ActionDescriptor(
    id: 'categories.toggleArchive',
    module: 'categories',
    title: 'Archive or restore a category',
    description: 'Hides a category from pickers (or restores it). Past transactions keep their category.',
    risk: ActionRisk.low,
    fields: [ActionFieldSpec('id', FieldKind.id, 'Category id')],
  );

  @override
  CategoryIdInput decode(Map<String, Object?> json) => CategoryIdInput(id: In.str(json, 'id'));

  @override
  Result<ActionPreview> prepare(CategoryIdInput input, FinanceSnapshot s, ActionEnvironment env) {
    final c = s.category(input.id);
    if (c == null) return const Result.err(AppFailure.notFound('This category no longer exists.'));
    if (c.isSystem) {
      return const Result.err(
        AppFailure(FailureCode.notPermitted, 'System categories are always available and cannot be archived.'),
      );
    }
    final archiving = !c.isArchived;
    final warnings = <String>[];
    if (archiving) {
      final budgets = s.budgets.where((b) => b.categoryId == c.id).length;
      final subs = s.subscriptions.where((x) => x.categoryId == c.id && x.isActive).length;
      if (budgets > 0)
        warnings.add('$budgets budget${budgets == 1 ? '' : 's'} still track${budgets == 1 ? 's' : ''} this category.');
      if (subs > 0) warnings.add('$subs active subscription${subs == 1 ? '' : 's'} still use this category.');
    }
    return Result.ok(
      preview(
        input,
        title: archiving ? 'Archive ${c.name}?' : 'Restore ${c.name}?',
        summary: archiving ? '${c.name} archived' : '${c.name} restored',
        warnings: warnings,
      ),
    );
  }

  @override
  Future<Result<TransactionCategory>> execute(CategoryIdInput input, FinanceSnapshot s, ActionEnvironment env) async {
    final c = s.category(input.id)!;
    final updated = c.copyWith(isArchived: !c.isArchived, version: c.version + 1);
    await env.repos.categories.save(updated);
    return Result.ok(updated);
  }
}

class DeleteCategoryAction extends FinancialAction<CategoryIdInput, TransactionCategory> {
  const DeleteCategoryAction();

  @override
  ActionDescriptor get descriptor => const ActionDescriptor(
    id: 'categories.delete',
    module: 'categories',
    title: 'Delete a category',
    description: 'Permanently removes a category that no transaction, budget or subscription uses.',
    risk: ActionRisk.consequential,
    reversible: false,
    fields: [ActionFieldSpec('id', FieldKind.id, 'Category id')],
  );

  @override
  CategoryIdInput decode(Map<String, Object?> json) => CategoryIdInput(id: In.str(json, 'id'));

  @override
  Result<ActionPreview> prepare(CategoryIdInput input, FinanceSnapshot s, ActionEnvironment env) {
    final c = s.category(input.id);
    if (c == null) return const Result.err(AppFailure.notFound('This category no longer exists.'));
    if (c.isSystem) {
      return const Result.err(AppFailure(FailureCode.notPermitted, 'System categories cannot be deleted.'));
    }
    final usage = categoryUsage(c.id, s);
    if (usage.isInUse) {
      return Result.err(
        AppFailure(
          FailureCode.conflict,
          '${c.name} is used by ${usage.describe()}. Archive it instead to hide it from pickers.',
        ),
      );
    }
    return Result.ok(
      preview(
        input,
        title: 'Delete ${c.name}?',
        summary: '${c.name} deleted',
        lines: [PreviewLine('Type', c.type.label)],
        warnings: const ['This cannot be undone.'],
      ),
    );
  }

  @override
  Future<Result<TransactionCategory>> execute(CategoryIdInput input, FinanceSnapshot s, ActionEnvironment env) async {
    final c = s.category(input.id)!;
    await env.repos.categories.delete(c.id);
    return Result.ok(c);
  }
}

String _withArticle(String word) => '${'aeiou'.contains(word[0]) ? 'an' : 'a'} $word';
