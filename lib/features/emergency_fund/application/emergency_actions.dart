import '../../../actions/action.dart';
import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/result/result.dart';
import '../../../core/time/dates.dart';
import '../../../finance/finance_snapshot.dart';
import '../../goals/domain/goal.dart';
import '../domain/emergency_fund.dart';

const int minEmergencyMonths = 1;
const int maxEmergencyMonths = 24;

/// Guards against typos (₹100 crore).
const Money maxEmergencyAmount = Money.rupees(1000000000);

class ConfigureEmergencyFundInput extends ActionInput {
  const ConfigureEmergencyFundInput({
    required this.essentialMonthlyExpenses,
    required this.targetMonths,
    this.targetOverride,
  });

  final Money essentialMonthlyExpenses;
  final int targetMonths;

  /// Optional explicit target replacing essentials × months.
  final Money? targetOverride;

  /// The target this input would produce.
  Money get target => targetOverride ?? essentialMonthlyExpenses.times(targetMonths);

  factory ConfigureEmergencyFundInput.fromJson(Map<String, Object?> j) => ConfigureEmergencyFundInput(
        essentialMonthlyExpenses: In.money(j, 'essentialMonthlyExpenses'),
        targetMonths: In.integer(j, 'targetMonths'),
        targetOverride: In.moneyOpt(j, 'targetOverride'),
      );

  @override
  Map<String, Object?> toJson() => {
        'essentialMonthlyExpenses': Out.money(essentialMonthlyExpenses),
        'targetMonths': targetMonths,
        'targetOverride': Out.moneyOpt(targetOverride),
      };
}

/// Sets (or changes) the emergency-fund plan. No money moves.
class ConfigureEmergencyFundAction extends FinancialAction<ConfigureEmergencyFundInput, EmergencyFundPlan> {
  const ConfigureEmergencyFundAction();

  @override
  ActionDescriptor get descriptor => const ActionDescriptor(
        id: 'emergencyFund.configure',
        module: 'emergencyFund',
        title: 'Set up the emergency fund plan',
        description: 'Sets essential monthly expenses and the months of cover to aim for. No money moves.',
        risk: ActionRisk.low,
        fields: [
          ActionFieldSpec('essentialMonthlyExpenses', FieldKind.money, 'Essential spending per month'),
          ActionFieldSpec('targetMonths', FieldKind.integer, 'Months of cover (1–24)'),
          ActionFieldSpec('targetOverride', FieldKind.money, 'Custom target amount', required: false),
        ],
      );

  @override
  ConfigureEmergencyFundInput decode(Map<String, Object?> json) => ConfigureEmergencyFundInput.fromJson(json);

  @override
  Result<ActionPreview> prepare(ConfigureEmergencyFundInput input, FinanceSnapshot s, ActionEnvironment env) {
    final e = <String, String>{};
    if (!input.essentialMonthlyExpenses.isPositive) {
      e['essentialMonthlyExpenses'] = 'Enter your essential monthly spending.';
    } else if (input.essentialMonthlyExpenses > maxEmergencyAmount) {
      e['essentialMonthlyExpenses'] = 'That amount looks too large. Please check it.';
    }
    if (input.targetMonths < minEmergencyMonths || input.targetMonths > maxEmergencyMonths) {
      e['targetMonths'] = 'Choose between $minEmergencyMonths and $maxEmergencyMonths months.';
    }
    final o = input.targetOverride;
    if (o != null && !o.isPositive) e['targetOverride'] = 'Enter a target greater than zero.';
    if (o != null && o > maxEmergencyAmount) e['targetOverride'] = 'That target looks too large. Please check it.';
    if (e.isNotEmpty) return Result.err(AppFailure.validation(e.values.first, fields: e));
    return Result.ok(preview(
      input,
      title: 'Save plan',
      summary: 'Emergency fund target ${input.target.format()}',
      lines: [
        PreviewLine('Essentials per month', input.essentialMonthlyExpenses.format()),
        PreviewLine('Months of cover', '${input.targetMonths}'),
        PreviewLine('Target', input.target.format(), emphasis: true),
      ],
    ));
  }

  @override
  Future<Result<EmergencyFundPlan>> execute(
      ConfigureEmergencyFundInput input, FinanceSnapshot s, ActionEnvironment env) async {
    final plan = EmergencyFundPlan(
      essentialMonthlyExpenses: input.essentialMonthlyExpenses,
      targetMonths: input.targetMonths,
      targetOverride: input.targetOverride,
      updatedAt: env.clock.now(),
    );
    await env.repos.emergencyPlan.set(plan);
    return Result.ok(plan);
  }
}

class EmergencyFundMovementInput extends ActionInput {
  const EmergencyFundMovementInput({required this.amount, required this.date, this.note});
  final Money amount;
  final DateTime date;
  final String? note;

  factory EmergencyFundMovementInput.fromJson(Map<String, Object?> j) => EmergencyFundMovementInput(
        amount: In.money(j, 'amount'),
        date: In.date(j, 'date'),
        note: In.strOpt(j, 'note'),
      );

  @override
  Map<String, Object?> toJson() => {'amount': Out.money(amount), 'date': Out.date(date), 'note': note};
}

const _movementFields = [
  ActionFieldSpec('amount', FieldKind.money, 'Amount in rupees'),
  ActionFieldSpec('date', FieldKind.date, 'Date (not in the future)'),
  ActionFieldSpec('note', FieldKind.string, 'Note', required: false),
];

/// Moves money between "available to spend" and the emergency fund. An
/// internal allocation: not income, not an expense; net worth unchanged.
class EmergencyFundMovementAction extends FinancialAction<EmergencyFundMovementInput, SavingsMovement> {
  const EmergencyFundMovementAction.contribute() : kind = SavingsMovementKind.contribution;
  const EmergencyFundMovementAction.withdraw() : kind = SavingsMovementKind.withdrawal;

  final SavingsMovementKind kind;
  bool get _isContribution => kind == SavingsMovementKind.contribution;

  @override
  ActionDescriptor get descriptor => _isContribution
      ? const ActionDescriptor(
          id: 'emergencyFund.contribute',
          module: 'emergencyFund',
          title: 'Add to the emergency fund',
          description: 'Earmarks available cash for emergencies. Not an expense; net worth is unchanged.',
          risk: ActionRisk.consequential,
          fields: _movementFields,
        )
      : const ActionDescriptor(
          id: 'emergencyFund.withdraw',
          module: 'emergencyFund',
          title: 'Withdraw from the emergency fund',
          description: 'Releases earmarked emergency money back to available cash. Not income.',
          risk: ActionRisk.consequential,
          fields: _movementFields,
        );

  @override
  EmergencyFundMovementInput decode(Map<String, Object?> json) => EmergencyFundMovementInput.fromJson(json);

  @override
  Result<ActionPreview> prepare(EmergencyFundMovementInput input, FinanceSnapshot s, ActionEnvironment env) {
    final saved = s.emergency.saved;
    final available = s.balance.available;
    final e = <String, String>{};
    if (!input.amount.isPositive) e['amount'] = 'Enter an amount greater than zero.';
    if (input.date.dateOnly.isAfter(s.today)) e['date'] = 'The date cannot be in the future.';
    if (_isContribution && input.amount > available) {
      e['amount'] = available.isPositive
          ? 'Only ${available.format()} is available to set aside.'
          : 'There is no available money to set aside right now.';
    }
    if (!_isContribution && input.amount > saved) {
      e['amount'] = 'Only ${saved.format()} is in your emergency fund.';
    }
    if ((input.note?.length ?? 0) > 200) e['note'] = 'Keep the note under 200 characters.';
    if (e.isNotEmpty) return Result.err(AppFailure.validation(e.values.first, fields: e));
    final savedAfter = _isContribution ? saved + input.amount : saved - input.amount;
    final availAfter = _isContribution ? available - input.amount : available + input.amount;
    final target = s.emergency.target;
    return Result.ok(preview(
      input,
      title: _isContribution ? 'Add to emergency fund' : 'Withdraw from emergency fund',
      summary: _isContribution
          ? 'Set aside ${input.amount.format()} for emergencies'
          : 'Release ${input.amount.format()} from your emergency fund',
      lines: [
        PreviewLine('Amount', input.amount.format(), emphasis: true),
        PreviewLine('Emergency fund', '${saved.format()} → ${savedAfter.format()}'),
        PreviewLine('Available to spend', '${available.format()} → ${availAfter.format()}'),
        PreviewLine('Date', DateFormats.dayMonthYear.format(input.date)),
        const PreviewLine('Net worth', 'Unchanged'),
      ],
      warnings: [
        if (_isContribution && target.isPositive && saved < target && savedAfter >= target)
          'This fully funds your emergency target!',
        if (!_isContribution) 'Using your safety net is okay — that is what it is for. You can top it up later.',
      ],
    ));
  }

  @override
  Future<Result<SavingsMovement>> execute(
      EmergencyFundMovementInput input, FinanceSnapshot s, ActionEnvironment env) async {
    final m = SavingsMovement(
      id: env.ids.next('sv'),
      bucketType: SavingsBucketType.emergencyFund,
      bucketId: SavingsMovement.emergencyFundBucketId,
      kind: kind,
      amount: input.amount,
      date: input.date.dateOnly,
      note: input.note,
      createdAt: env.clock.now(),
    );
    await env.repos.savingsMovements.save(m);
    return Result.ok(m);
  }
}
