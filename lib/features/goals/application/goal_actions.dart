import '../../../actions/action.dart';
import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/result/result.dart';
import '../../../core/time/dates.dart';
import '../../../finance/finance_snapshot.dart';
import '../../savings/application/set_aside.dart';
import '../domain/goal.dart';

class GoalInput extends ActionInput {
  const GoalInput({
    required this.name,
    required this.category,
    required this.target,
    required this.colorIndex,
    this.targetDate,
    this.plannedMonthlyContribution,
    this.initialAllocation,
    this.accountId,
    this.note,
  });

  final String name;
  final GoalCategory category;
  final Money target;
  final int colorIndex;
  final DateTime? targetDate;
  final Money? plannedMonthlyContribution;

  /// Optional amount to earmark immediately from available cash (create only).
  final Money? initialAllocation;

  /// Account the starting amount is set aside on (default account when null).
  final String? accountId;
  final String? note;

  factory GoalInput.fromJson(Map<String, Object?> j) => GoalInput(
    name: In.str(j, 'name'),
    category: In.enumOpt(j, 'category', GoalCategory.values) ?? GoalCategory.other,
    target: In.money(j, 'target'),
    colorIndex: In.intOpt(j, 'colorIndex') ?? 5,
    targetDate: In.dateOpt(j, 'targetDate'),
    plannedMonthlyContribution: In.moneyOpt(j, 'plannedMonthlyContribution'),
    initialAllocation: In.moneyOpt(j, 'initialAllocation'),
    accountId: In.strOpt(j, 'accountId'),
    note: In.strOpt(j, 'note'),
  );

  @override
  Map<String, Object?> toJson() => {
    'name': name,
    'category': category.name,
    'target': Out.money(target),
    'colorIndex': colorIndex,
    'targetDate': Out.dateOpt(targetDate),
    'plannedMonthlyContribution': Out.moneyOpt(plannedMonthlyContribution),
    'initialAllocation': Out.moneyOpt(initialAllocation),
    'accountId': accountId,
    'note': note,
  };
}

Map<String, String> _validateGoal(GoalInput i, FinanceSnapshot s, {String? exceptId}) {
  final e = <String, String>{};
  final name = i.name.trim();
  if (name.isEmpty) e['name'] = 'Give your goal a name.';
  if (name.length > 50) e['name'] = 'Keep the name under 50 characters.';
  if (s.goals.any(
    (g) => g.id != exceptId && g.status == GoalStatus.active && g.name.toLowerCase() == name.toLowerCase(),
  )) {
    e['name'] = 'You already have an active goal with this name.';
  }
  if (!i.target.isPositive) e['target'] = 'Enter a target greater than zero.';
  if (i.target > const Money.rupees(1000000000)) e['target'] = 'That target looks too large. Please check it.';
  if (i.targetDate != null && !i.targetDate!.dateOnly.isAfter(s.today)) e['targetDate'] = 'Pick a date in the future.';
  if (i.plannedMonthlyContribution != null && i.plannedMonthlyContribution!.isNegative) {
    e['plannedMonthlyContribution'] = 'Enter a positive amount.';
  }
  final init = i.initialAllocation;
  if (init != null && init.isPositive) {
    final here = resolveSetAside(s, i.accountId);
    if (here.failure != null) {
      e.addAll(here.failure!.fieldErrors);
    } else if (init > here.target!.available) {
      e['initialAllocation'] = notEnoughOn(here.target!.account, here.target!.available);
    }
  }
  return e;
}

class CreateGoalAction extends FinancialAction<GoalInput, SavingsGoal> {
  const CreateGoalAction();

  @override
  ActionDescriptor get descriptor => const ActionDescriptor(
    id: 'goals.create',
    module: 'goals',
    title: 'Create a savings goal',
    description: 'Creates a goal. An optional starting amount is earmarked from available cash (not spent).',
    risk: ActionRisk.low,
    fields: [
      ActionFieldSpec('name', FieldKind.string, 'Goal name'),
      ActionFieldSpec('category', FieldKind.enumeration, 'Goal type', required: false),
      ActionFieldSpec('target', FieldKind.money, 'Target amount'),
      ActionFieldSpec('targetDate', FieldKind.date, 'Target date', required: false),
      ActionFieldSpec('plannedMonthlyContribution', FieldKind.money, 'Planned monthly amount', required: false),
      ActionFieldSpec('initialAllocation', FieldKind.money, 'Amount to set aside now', required: false),
      ActionFieldSpec(
        'accountId',
        FieldKind.id,
        'Account the starting amount is set aside on (default account when omitted)',
        required: false,
      ),
    ],
  );

  @override
  GoalInput decode(Map<String, Object?> json) => GoalInput.fromJson(json);

  @override
  Result<ActionPreview> prepare(GoalInput input, FinanceSnapshot s, ActionEnvironment env) {
    final e = _validateGoal(input, s);
    if (e.isNotEmpty) return Result.err(AppFailure.validation(e.values.first, fields: e));
    final init = input.initialAllocation ?? Money.zero;
    final here = init.isPositive ? resolveSetAside(s, input.accountId).target : null;
    return Result.ok(
      preview(
        input,
        title: 'Create ${input.name.trim()}',
        summary: 'New goal: ${input.name.trim()} · ${input.target.format()}',
        lines: [
          PreviewLine('Target', input.target.format(), emphasis: true),
          if (input.targetDate != null) PreviewLine('By', DateFormats.monthYear.format(input.targetDate!)),
          if (init.isPositive) PreviewLine('Set aside now', init.format()),
          if (init.isPositive) PreviewLine('Set aside on', here!.account.name),
          if (init.isPositive)
            PreviewLine(
              'Free to spend in ${here!.account.name}',
              '${here.available.format()} → ${(here.available - init).format()}',
            ),
          if (init.isPositive)
            PreviewLine(
              'Available to spend (total)',
              '${s.balance.available.format()} → ${(s.balance.available - init).format()}',
            ),
        ],
        requiresConfirmation: init.isPositive,
      ),
    );
  }

  @override
  Future<Result<SavingsGoal>> execute(GoalInput input, FinanceSnapshot s, ActionEnvironment env) async {
    final now = env.clock.now();
    final goal = SavingsGoal(
      id: env.ids.next('goal'),
      name: input.name.trim(),
      category: input.category,
      target: input.target,
      targetDate: input.targetDate?.dateOnly,
      plannedMonthlyContribution: input.plannedMonthlyContribution,
      colorIndex: input.colorIndex,
      note: input.note,
      createdAt: now,
      updatedAt: now,
    );
    await env.repos.goals.save(goal);
    final init = input.initialAllocation;
    if (init != null && init.isPositive) {
      final here = resolveSetAside(s, input.accountId).target!;
      await env.repos.savingsMovements.save(
        SavingsMovement(
          id: env.ids.next('sv'),
          bucketType: SavingsBucketType.goal,
          bucketId: goal.id,
          kind: SavingsMovementKind.contribution,
          amount: init,
          accountId: here.account.id,
          date: s.today,
          note: 'Starting amount',
          createdAt: now,
        ),
      );
    }
    return Result.ok(goal);
  }
}

class UpdateGoalInput extends ActionInput {
  const UpdateGoalInput({required this.id, required this.expectedVersion, required this.data});
  final String id;
  final int expectedVersion;
  final GoalInput data;

  @override
  Map<String, Object?> toJson() => {'id': id, 'expectedVersion': expectedVersion, ...data.toJson()};
}

class UpdateGoalAction extends FinancialAction<UpdateGoalInput, SavingsGoal> {
  const UpdateGoalAction();

  @override
  ActionDescriptor get descriptor => const ActionDescriptor(
    id: 'goals.update',
    module: 'goals',
    title: 'Edit a goal',
    description: 'Changes goal details. The saved amount only changes through contributions and withdrawals.',
    risk: ActionRisk.low,
    fields: [
      ActionFieldSpec('id', FieldKind.id, 'Goal id'),
      ActionFieldSpec('expectedVersion', FieldKind.integer, 'Version read'),
    ],
  );

  @override
  UpdateGoalInput decode(Map<String, Object?> json) => UpdateGoalInput(
    id: In.str(json, 'id'),
    expectedVersion: In.integer(json, 'expectedVersion'),
    data: GoalInput.fromJson(json),
  );

  @override
  Result<ActionPreview> prepare(UpdateGoalInput input, FinanceSnapshot s, ActionEnvironment env) {
    final g = s.goal(input.id);
    if (g == null) return const Result.err(AppFailure.notFound('This goal no longer exists.'));
    if (g.goal.version != input.expectedVersion) {
      return const Result.err(
        AppFailure(FailureCode.staleData, 'This goal changed since you opened it. Reload and try again.'),
      );
    }
    final data = GoalInput(
      name: input.data.name,
      category: input.data.category,
      target: input.data.target,
      colorIndex: input.data.colorIndex,
      targetDate: input.data.targetDate,
      plannedMonthlyContribution: input.data.plannedMonthlyContribution,
      note: input.data.note,
    );
    final e = _validateGoal(data, s, exceptId: input.id);
    if (e.isNotEmpty) return Result.err(AppFailure.validation(e.values.first, fields: e));
    return Result.ok(preview(input, title: 'Save changes', summary: 'Update ${g.goal.name}'));
  }

  @override
  Future<Result<SavingsGoal>> execute(UpdateGoalInput input, FinanceSnapshot s, ActionEnvironment env) async {
    final g = s.goal(input.id)!.goal;
    final d = input.data;
    final updated = g.copyWith(
      name: d.name.trim(),
      category: d.category,
      target: d.target,
      targetDate: () => d.targetDate?.dateOnly,
      plannedMonthlyContribution: () => d.plannedMonthlyContribution,
      colorIndex: d.colorIndex,
      note: () => d.note,
      updatedAt: env.clock.now(),
      version: g.version + 1,
    );
    await env.repos.goals.save(updated);
    return Result.ok(updated);
  }
}

class GoalMovementInput extends ActionInput {
  const GoalMovementInput({required this.goalId, required this.amount, required this.date, this.accountId, this.note});
  final String goalId;
  final Money amount;

  /// Account set aside on / released from; null = default account when
  /// adding, the accounts holding the most when releasing.
  final String? accountId;
  final DateTime date;
  final String? note;

  factory GoalMovementInput.fromJson(Map<String, Object?> j) => GoalMovementInput(
    goalId: In.str(j, 'goalId'),
    amount: In.money(j, 'amount'),
    accountId: In.strOpt(j, 'accountId'),
    date: In.date(j, 'date'),
    note: In.strOpt(j, 'note'),
  );

  @override
  Map<String, Object?> toJson() => {
    'goalId': goalId,
    'amount': Out.money(amount),
    'accountId': accountId,
    'date': Out.date(date),
    'note': note,
  };
}

const _movementFields = [
  ActionFieldSpec('goalId', FieldKind.id, 'Goal id'),
  ActionFieldSpec('amount', FieldKind.money, 'Amount in rupees'),
  ActionFieldSpec(
    'accountId',
    FieldKind.id,
    'Account the money is set aside on (contribution: default account when omitted) or released from (withdrawal: the accounts holding the most when omitted)',
    required: false,
  ),
  ActionFieldSpec('date', FieldKind.date, 'Date'),
  ActionFieldSpec('note', FieldKind.string, 'Note', required: false),
];

/// Contribution or withdrawal for a goal (an internal allocation).
class GoalMovementAction extends FinancialAction<GoalMovementInput, SavingsMovement> {
  const GoalMovementAction.contribute() : kind = SavingsMovementKind.contribution;
  const GoalMovementAction.withdraw() : kind = SavingsMovementKind.withdrawal;

  final SavingsMovementKind kind;
  bool get _isContribution => kind == SavingsMovementKind.contribution;

  @override
  ActionDescriptor get descriptor => _isContribution
      ? const ActionDescriptor(
          id: 'goals.contribute',
          module: 'goals',
          title: 'Add money to a goal',
          description:
              'Sets money aside for a goal on an account. Not an expense: the account balance and net worth are unchanged, but the money can no longer be spent.',
          risk: ActionRisk.consequential,
          fields: _movementFields,
        )
      : const ActionDescriptor(
          id: 'goals.withdraw',
          module: 'goals',
          title: 'Withdraw from a goal',
          description: 'Releases money set aside for a goal back to spendable. Not income.',
          risk: ActionRisk.consequential,
          fields: _movementFields,
        );

  @override
  GoalMovementInput decode(Map<String, Object?> json) => GoalMovementInput.fromJson(json);

  @override
  Result<ActionPreview> prepare(GoalMovementInput input, FinanceSnapshot s, ActionEnvironment env) {
    final g = s.goal(input.goalId);
    if (g == null) return const Result.err(AppFailure.notFound('This goal no longer exists.'));
    if (g.goal.status != GoalStatus.active) return const Result.err(AppFailure.validation('This goal is archived.'));
    final e = <String, String>{};
    if (!input.amount.isPositive) e['amount'] = 'Enter an amount greater than zero.';
    if (input.date.dateOnly.isAfter(s.today)) e['date'] = 'The date cannot be in the future.';
    final planned = planAccounts(
      s: s,
      isContribution: _isContribution,
      amount: input.amount,
      accountId: input.accountId,
      saved: g.saved,
      type: SavingsBucketType.goal,
      bucketId: input.goalId,
      savedMessage: 'Only ${g.saved.format()} is saved in this goal.',
      errors: e,
    );
    if (planned.failure != null) return Result.err(planned.failure!);
    if (e.isNotEmpty) return Result.err(AppFailure.validation(e.values.first, fields: e));
    final savedAfter = _isContribution ? g.saved + input.amount : g.saved - input.amount;
    final availAfter = _isContribution ? s.balance.available - input.amount : s.balance.available + input.amount;
    return Result.ok(
      preview(
        input,
        title: _isContribution ? 'Add to ${g.goal.name}' : 'Withdraw from ${g.goal.name}',
        summary: _isContribution
            ? 'Set aside ${input.amount.format()} for ${g.goal.name}'
            : 'Release ${input.amount.format()} from ${g.goal.name}',
        lines: [
          PreviewLine('Amount', input.amount.format(), emphasis: true),
          for (final l in planned.plan.lines) PreviewLine(l.$1, l.$2),
          PreviewLine('Saved in goal', '${g.saved.format()} → ${savedAfter.format()}'),
          PreviewLine('Available to spend (total)', '${s.balance.available.format()} → ${availAfter.format()}'),
          const PreviewLine('Net worth', 'Unchanged'),
        ],
        warnings: [if (_isContribution && savedAfter >= g.goal.target && !g.isAchieved) 'This completes your goal!'],
        basis: {'v': g.goal.version, 'saved': g.saved.paise},
      ),
    );
  }

  @override
  Future<Result<SavingsMovement>> execute(GoalMovementInput input, FinanceSnapshot s, ActionEnvironment env) async {
    final g = s.goal(input.goalId)!;
    final planned = planAccounts(
      s: s,
      isContribution: _isContribution,
      amount: input.amount,
      accountId: input.accountId,
      saved: g.saved,
      type: SavingsBucketType.goal,
      bucketId: input.goalId,
      savedMessage: '',
      errors: {},
    );
    SavingsMovement? first;
    for (final r in planned.plan.releases) {
      final m = SavingsMovement(
        id: env.ids.next('sv'),
        bucketType: SavingsBucketType.goal,
        bucketId: input.goalId,
        kind: kind,
        amount: r.amount,
        accountId: r.accountId,
        date: input.date.dateOnly,
        note: input.note,
        createdAt: env.clock.now(),
      );
      await env.repos.savingsMovements.save(m);
      first ??= m;
    }
    return Result.ok(first!);
  }
}

class GoalIdInput extends ActionInput {
  const GoalIdInput({required this.id});
  final String id;

  @override
  Map<String, Object?> toJson() => {'id': id};
}

/// Archives (or restores) a goal. Saved money stays earmarked.
class ArchiveGoalAction extends FinancialAction<GoalIdInput, SavingsGoal> {
  const ArchiveGoalAction();

  @override
  ActionDescriptor get descriptor => const ActionDescriptor(
    id: 'goals.toggleArchive',
    module: 'goals',
    title: 'Archive or restore a goal',
    description: 'Hides a goal from the active list (or restores it). Earmarked money is unaffected.',
    risk: ActionRisk.low,
    fields: [ActionFieldSpec('id', FieldKind.id, 'Goal id')],
  );

  @override
  GoalIdInput decode(Map<String, Object?> json) => GoalIdInput(id: In.str(json, 'id'));

  @override
  Result<ActionPreview> prepare(GoalIdInput input, FinanceSnapshot s, ActionEnvironment env) {
    final g = s.goal(input.id);
    if (g == null) return const Result.err(AppFailure.notFound('This goal no longer exists.'));
    final archiving = g.goal.status == GoalStatus.active;
    return Result.ok(
      preview(
        input,
        title: archiving ? 'Archive ${g.goal.name}?' : 'Restore ${g.goal.name}?',
        summary: '${archiving ? 'Archive' : 'Restore'} ${g.goal.name}',
      ),
    );
  }

  @override
  Future<Result<SavingsGoal>> execute(GoalIdInput input, FinanceSnapshot s, ActionEnvironment env) async {
    final g = s.goal(input.id)!.goal;
    final updated = g.copyWith(
      status: g.status == GoalStatus.active ? GoalStatus.archived : GoalStatus.active,
      updatedAt: env.clock.now(),
      version: g.version + 1,
    );
    await env.repos.goals.save(updated);
    return Result.ok(updated);
  }
}

/// Deletes a goal, first releasing any saved money back to available cash.
class DeleteGoalAction extends FinancialAction<GoalIdInput, SavingsGoal> {
  const DeleteGoalAction();

  @override
  ActionDescriptor get descriptor => const ActionDescriptor(
    id: 'goals.delete',
    module: 'goals',
    title: 'Delete a goal',
    description: 'Deletes a goal. Any saved amount is released back to available cash.',
    risk: ActionRisk.consequential,
    reversible: false,
    fields: [ActionFieldSpec('id', FieldKind.id, 'Goal id')],
  );

  @override
  GoalIdInput decode(Map<String, Object?> json) => GoalIdInput(id: In.str(json, 'id'));

  @override
  Result<ActionPreview> prepare(GoalIdInput input, FinanceSnapshot s, ActionEnvironment env) {
    final g = s.goal(input.id);
    if (g == null) return const Result.err(AppFailure.notFound('This goal no longer exists.'));
    return Result.ok(
      preview(
        input,
        title: 'Delete ${g.goal.name}?',
        summary: 'Delete ${g.goal.name}',
        lines: [if (g.saved.isPositive) PreviewLine('Returned to available cash', g.saved.format(), emphasis: true)],
        warnings: const ['Contribution history for this goal will be removed.'],
        basis: {'v': g.goal.version, 'saved': g.saved.paise},
      ),
    );
  }

  @override
  Future<Result<SavingsGoal>> execute(GoalIdInput input, FinanceSnapshot s, ActionEnvironment env) async {
    final g = s.goal(input.id)!;
    // All movements of this bucket, including any dated after today (which
    // GoalProgress.movements excludes), so no orphaned earmark remains.
    final own = s.savingsMovements.where((m) => m.bucketType == SavingsBucketType.goal && m.bucketId == g.goal.id);
    for (final m in own) {
      await env.repos.savingsMovements.delete(m.id);
    }
    await env.repos.goals.delete(g.goal.id);
    return Result.ok(g.goal);
  }
}
