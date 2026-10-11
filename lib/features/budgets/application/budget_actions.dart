import '../../../actions/action.dart';
import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/result/result.dart';
import '../../../core/time/dates.dart';
import '../../../finance/finance_snapshot.dart';
import '../../transactions/domain/transaction.dart';
import '../domain/budget.dart';

/// Default warning threshold when none is supplied (80%).
const int defaultBudgetWarningBps = 8000;
const int minBudgetWarningBps = 5000;
const int maxBudgetWarningBps = 9500;

/// Largest budget limit accepted (₹10 crore) — guards against typos.
const Money maxBudgetLimit = Money.rupees(100000000);

/// Input for creating or editing a budget. Budgets are always monthly and
/// hold no money: they are spending limits, and spending is always derived
/// from expenses in the category.
class BudgetInput extends ActionInput {
  const BudgetInput({
    required this.categoryId,
    required this.limit,
    this.warningThresholdBps,
    this.note,
  });

  final String categoryId;
  final Money limit;

  /// 5000–9500 basis points. Null → [defaultBudgetWarningBps].
  final int? warningThresholdBps;
  final String? note;

  factory BudgetInput.fromJson(Map<String, Object?> j) => BudgetInput(
        categoryId: In.str(j, 'categoryId'),
        limit: In.money(j, 'limit'),
        warningThresholdBps: In.intOpt(j, 'warningThresholdBps'),
        note: In.strOpt(j, 'note'),
      );

  @override
  Map<String, Object?> toJson() => {
        'categoryId': categoryId,
        'limit': Out.money(limit),
        'warningThresholdBps': warningThresholdBps,
        'note': note,
      };
}

const _budgetFields = [
  ActionFieldSpec('categoryId', FieldKind.id, 'Expense category id'),
  ActionFieldSpec('limit', FieldKind.money, 'Monthly spending limit in rupees, greater than zero'),
  ActionFieldSpec('warningThresholdBps', FieldKind.integer, 'Warning threshold in basis points (5000–9500)',
      required: false),
  ActionFieldSpec('note', FieldKind.string, 'Note', required: false),
];

/// An active budget (other than [exceptId]) for [categoryId], if any.
Budget? conflictingMonthlyBudget(FinanceSnapshot s, String categoryId, {String? exceptId}) => s.budgets
    .where((b) => b.id != exceptId && b.categoryId == categoryId && b.status == BudgetStatus.active)
    .firstOrNull;

Map<String, String> validateBudget(BudgetInput i, FinanceSnapshot s, {String? exceptId, bool active = true}) {
  final e = <String, String>{};
  final cat = s.category(i.categoryId);
  if (cat == null || cat.isArchived) {
    e['categoryId'] = 'Choose a category.';
  } else if (cat.type != TransactionType.expense) {
    e['categoryId'] = 'Budgets work with spending categories only.';
  } else if (active && conflictingMonthlyBudget(s, i.categoryId, exceptId: exceptId) != null) {
    e['categoryId'] = '${cat.name} already has a monthly budget. Edit that one instead.';
  }
  if (!i.limit.isPositive) e['limit'] = 'Enter a limit greater than zero.';
  if (i.limit > maxBudgetLimit) e['limit'] = 'That limit looks too large. Please check it.';
  final w = i.warningThresholdBps;
  if (w != null && (w < minBudgetWarningBps || w > maxBudgetWarningBps)) {
    e['warningThresholdBps'] = 'Choose a warning level between 50% and 95%.';
  }
  if ((i.note?.length ?? 0) > 200) e['note'] = 'Keep the note under 200 characters.';
  return e;
}

/// "Every month, from 1 Oct 2026".
String _periodLabel(FinanceSnapshot s) =>
    'Every month, from ${DateFormats.dayMonthYear.format(s.currentBudgetPeriod.start)}';

/// [b]'s limit history after changing its limit to [next] today: months
/// before this one keep the old limit, this month onwards uses [next].
List<BudgetLimitChange> limitHistoryAfterEdit(Budget b, Money next, FinanceSnapshot s) {
  final current = s.currentBudgetMonth;
  final started = FinanceSnapshot.budgetCalc.monthOf(b.createdAt, s.monthStartDay);
  final until = current.previous;
  if (next == b.limit || started > until) return b.previousLimits;
  // Already recorded for last month (e.g. a second edit this month).
  if (b.previousLimits.any((c) => c.until >= until)) return b.previousLimits;
  return [...b.previousLimits, BudgetLimitChange(until: until, limit: b.limit)];
}

List<PreviewLine> _lines(BudgetInput i, FinanceSnapshot s) => [
      PreviewLine('Category', s.category(i.categoryId)?.name ?? '—'),
      PreviewLine('Limit', i.limit.format(), emphasis: true),
      PreviewLine('Period', _periodLabel(s)),
      PreviewLine('Warn at', formatBps(i.warningThresholdBps ?? defaultBudgetWarningBps, decimals: 0)),
    ];

class CreateBudgetAction extends FinancialAction<BudgetInput, Budget> {
  const CreateBudgetAction();

  @override
  ActionDescriptor get descriptor => const ActionDescriptor(
        id: 'budgets.create',
        module: 'budgets',
        title: 'Create a budget',
        description: 'Sets a spending limit for an expense category. Budgets hold no money; '
            'spending is derived from transactions.',
        risk: ActionRisk.low,
        fields: _budgetFields,
      );

  @override
  BudgetInput decode(Map<String, Object?> json) => BudgetInput.fromJson(json);

  @override
  Result<ActionPreview> prepare(BudgetInput input, FinanceSnapshot s, ActionEnvironment env) {
    final e = validateBudget(input, s);
    if (e.isNotEmpty) return Result.err(AppFailure.validation(e.values.first, fields: e));
    final name = s.category(input.categoryId)?.name ?? 'category';
    return Result.ok(preview(
      input,
      title: 'Create budget',
      summary: 'Budget for $name · ${input.limit.format()}',
      lines: _lines(input, s),
    ));
  }

  @override
  Future<Result<Budget>> execute(BudgetInput input, FinanceSnapshot s, ActionEnvironment env) async {
    final now = env.clock.now();
    final budget = Budget(
      id: env.ids.next('bud'),
      categoryId: input.categoryId,
      limit: input.limit,
      warningThresholdBps: input.warningThresholdBps ?? defaultBudgetWarningBps,
      note: input.note,
      createdAt: now,
      updatedAt: now,
    );
    await env.repos.budgets.save(budget);
    return Result.ok(budget);
  }
}

class UpdateBudgetInput extends ActionInput {
  const UpdateBudgetInput({required this.id, required this.expectedVersion, required this.data});
  final String id;

  /// Version the user edited; a mismatch means it changed elsewhere.
  final int expectedVersion;
  final BudgetInput data;

  @override
  Map<String, Object?> toJson() => {'id': id, 'expectedVersion': expectedVersion, ...data.toJson()};
}

class UpdateBudgetAction extends FinancialAction<UpdateBudgetInput, Budget> {
  const UpdateBudgetAction();

  @override
  ActionDescriptor get descriptor => const ActionDescriptor(
        id: 'budgets.update',
        module: 'budgets',
        title: 'Edit a budget',
        description: 'Changes a budget\'s category, monthly limit or warning level. '
            'Earlier months keep the limit they had.',
        risk: ActionRisk.low,
        fields: [
          ActionFieldSpec('id', FieldKind.id, 'Budget id'),
          ActionFieldSpec('expectedVersion', FieldKind.integer, 'Version that was read'),
          ..._budgetFields,
        ],
      );

  @override
  UpdateBudgetInput decode(Map<String, Object?> json) => UpdateBudgetInput(
        id: In.str(json, 'id'),
        expectedVersion: In.integer(json, 'expectedVersion'),
        data: BudgetInput.fromJson(json),
      );

  @override
  Result<ActionPreview> prepare(UpdateBudgetInput input, FinanceSnapshot s, ActionEnvironment env) {
    final b = s.budgets.where((x) => x.id == input.id).firstOrNull;
    if (b == null) return const Result.err(AppFailure.notFound('This budget no longer exists.'));
    if (b.version != input.expectedVersion) {
      return const Result.err(
          AppFailure(FailureCode.staleData, 'This budget changed since you opened it. Reload and try again.'));
    }
    final e = validateBudget(input.data, s, exceptId: b.id, active: !b.isPaused);
    if (e.isNotEmpty) return Result.err(AppFailure.validation(e.values.first, fields: e));
    final name = s.category(input.data.categoryId)?.name ?? 'category';
    return Result.ok(preview(
      input,
      title: 'Save changes',
      summary: 'Update $name budget to ${input.data.limit.format()}',
      lines: _lines(input.data, s),
    ));
  }

  @override
  Future<Result<Budget>> execute(UpdateBudgetInput input, FinanceSnapshot s, ActionEnvironment env) async {
    final b = s.budgets.firstWhere((x) => x.id == input.id);
    final d = input.data;
    final updated = b.copyWith(
      categoryId: d.categoryId,
      limit: d.limit,
      previousLimits: limitHistoryAfterEdit(b, d.limit, s),
      warningThresholdBps: d.warningThresholdBps ?? b.warningThresholdBps,
      note: () => d.note,
      updatedAt: env.clock.now(),
      version: b.version + 1,
    );
    await env.repos.budgets.save(updated);
    return Result.ok(updated);
  }
}

class SetBudgetPausedInput extends ActionInput {
  const SetBudgetPausedInput({required this.id, required this.paused});
  final String id;
  final bool paused;

  @override
  Map<String, Object?> toJson() => {'id': id, 'paused': paused};
}

/// Pauses a budget (no warnings or alerts) or resumes it.
class SetBudgetPausedAction extends FinancialAction<SetBudgetPausedInput, Budget> {
  const SetBudgetPausedAction();

  @override
  ActionDescriptor get descriptor => const ActionDescriptor(
        id: 'budgets.setPaused',
        module: 'budgets',
        title: 'Pause or resume a budget',
        description: 'A paused budget keeps its settings but stops tracking warnings and alerts.',
        risk: ActionRisk.low,
        fields: [
          ActionFieldSpec('id', FieldKind.id, 'Budget id'),
          ActionFieldSpec('paused', FieldKind.boolean, 'true to pause, false to resume'),
        ],
      );

  @override
  SetBudgetPausedInput decode(Map<String, Object?> json) =>
      SetBudgetPausedInput(id: In.str(json, 'id'), paused: In.boolean(json, 'paused'));

  @override
  Result<ActionPreview> prepare(SetBudgetPausedInput input, FinanceSnapshot s, ActionEnvironment env) {
    final b = s.budgets.where((x) => x.id == input.id).firstOrNull;
    if (b == null) return const Result.err(AppFailure.notFound('This budget no longer exists.'));
    final name = s.category(b.categoryId)?.name ?? 'Budget';
    if (!input.paused &&
        conflictingMonthlyBudget(s, b.categoryId, exceptId: b.id) != null) {
      return Result.err(AppFailure(FailureCode.conflict,
          '$name already has an active monthly budget. Pause or delete it first.'));
    }
    return Result.ok(preview(
      input,
      title: input.paused ? 'Pause budget' : 'Resume budget',
      summary: input.paused ? '$name budget paused' : '$name budget resumed',
    ));
  }

  @override
  Future<Result<Budget>> execute(SetBudgetPausedInput input, FinanceSnapshot s, ActionEnvironment env) async {
    final b = s.budgets.firstWhere((x) => x.id == input.id);
    final target = input.paused ? BudgetStatus.paused : BudgetStatus.active;
    if (b.status == target) return Result.ok(b);
    final updated = b.copyWith(status: target, updatedAt: env.clock.now(), version: b.version + 1);
    await env.repos.budgets.save(updated);
    return Result.ok(updated);
  }
}

class BudgetIdInput extends ActionInput {
  const BudgetIdInput({required this.id});
  final String id;

  @override
  Map<String, Object?> toJson() => {'id': id};
}

/// Deletes a budget. Budgets hold no money, so nothing moves; transactions
/// are untouched. Still confirmed because the settings are lost.
class DeleteBudgetAction extends FinancialAction<BudgetIdInput, Budget> {
  const DeleteBudgetAction();

  @override
  ActionDescriptor get descriptor => const ActionDescriptor(
        id: 'budgets.delete',
        module: 'budgets',
        title: 'Delete a budget',
        description: 'Removes a spending limit. Transactions and balances are not affected.',
        risk: ActionRisk.consequential,
        reversible: false,
        fields: [ActionFieldSpec('id', FieldKind.id, 'Budget id')],
      );

  @override
  BudgetIdInput decode(Map<String, Object?> json) => BudgetIdInput(id: In.str(json, 'id'));

  @override
  Result<ActionPreview> prepare(BudgetIdInput input, FinanceSnapshot s, ActionEnvironment env) {
    final b = s.budgets.where((x) => x.id == input.id).firstOrNull;
    if (b == null) return const Result.err(AppFailure.notFound('This budget no longer exists.'));
    final name = s.category(b.categoryId)?.name ?? 'this category';
    return Result.ok(preview(
      input,
      title: 'Delete budget?',
      summary: 'Delete the $name budget',
      lines: [
        PreviewLine('Category', name),
        PreviewLine('Limit', b.limit.format(), emphasis: true),
        const PreviewLine('Period', 'Monthly'),
      ],
      warnings: const ['Your transactions stay exactly as they are. Only the limit is removed.'],
    ));
  }

  @override
  Future<Result<Budget>> execute(BudgetIdInput input, FinanceSnapshot s, ActionEnvironment env) async {
    final b = s.budgets.firstWhere((x) => x.id == input.id);
    await env.repos.budgets.delete(b.id);
    return Result.ok(b);
  }
}
