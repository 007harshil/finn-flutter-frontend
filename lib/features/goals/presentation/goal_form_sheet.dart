import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/core_providers.dart';
import '../../../app/di/data_providers.dart';
import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../kit/kit.dart';
import '../../../shared/presentation/action_runner.dart';
import '../../../shared/presentation/category_icons.dart';
import '../application/goal_actions.dart';
import '../domain/goal.dart';
import 'savings_widgets.dart' show savingsMoney;

/// Create or edit a savings goal.
class GoalFormSheet extends ConsumerStatefulWidget {
  const GoalFormSheet({super.key, this.goalId});

  final String? goalId;

  @override
  ConsumerState<GoalFormSheet> createState() => _GoalFormSheetState();
}

class _GoalFormSheetState extends ConsumerState<GoalFormSheet> {
  final _key = newIdempotencyKey();
  final _name = TextEditingController();
  final _target = TextEditingController();
  final _monthly = TextEditingController();
  final _starting = TextEditingController();
  GoalCategory _category = GoalCategory.travel;
  DateTime? _targetDate;

  /// Kept as stored (new goals get the default); the ledger UI does not
  /// colour goals, so there is no picker for it.
  int _colorIndex = 5;
  Money? _startingValue;
  Map<String, String> _errors = const {};
  bool _submitting = false;
  bool _loaded = false;
  SavingsGoal? _existing;

  bool get _isEdit => widget.goalId != null;

  @override
  void dispose() {
    _name.dispose();
    _target.dispose();
    _monthly.dispose();
    _starting.dispose();
    super.dispose();
  }

  void _load(GoalProgress? g) {
    if (_loaded) return;
    _loaded = true;
    if (g == null) return;
    final goal = g.goal;
    _existing = goal;
    _name.text = goal.name;
    _target.text = MoneyFormatter.editable(goal.target);
    final plan = goal.plannedMonthlyContribution;
    if (plan != null) _monthly.text = MoneyFormatter.editable(plan);
    _category = goal.category;
    _targetDate = goal.targetDate;
    _colorIndex = goal.colorIndex;
  }

  void _clearError(String field) {
    if (_errors.containsKey(field)) setState(() => _errors = {..._errors}..remove(field));
  }

  Future<void> _submit() async {
    final target = LedgerAmountField.parse(_target.text);
    final monthly = _monthly.text.trim().isEmpty ? null : LedgerAmountField.parse(_monthly.text);
    final starting = _starting.text.trim().isEmpty ? null : LedgerAmountField.parse(_starting.text);
    final available = ref.read(balanceProvider).value?.available;
    final local = <String, String>{
      if (_name.text.trim().isEmpty) 'name': 'Give your goal a name.',
      if (target == null || !target.isPositive) 'target': 'Enter a target greater than zero.',
      if (_monthly.text.trim().isNotEmpty && monthly == null) 'plannedMonthlyContribution': 'Enter a valid amount.',
      if (!_isEdit && starting != null && available != null && starting > available)
        'initialAllocation': 'Only ${available.format()} is available to set aside.',
    };
    if (local.isNotEmpty) {
      setState(() => _errors = local);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _errors = const {};
    });
    void onErrors(Map<String, String> e) {
      if (mounted) setState(() => _errors = e);
    }

    final data = GoalInput(
      name: _name.text.trim(),
      category: _category,
      target: target!,
      colorIndex: _colorIndex,
      targetDate: _targetDate,
      plannedMonthlyContribution: monthly != null && monthly.isPositive ? monthly : null,
      initialAllocation: _isEdit || starting == null || !starting.isPositive ? null : starting,
      note: _existing?.note,
    );
    final existing = _existing;
    final SavingsGoal? result;
    if (existing == null) {
      result = await runAction(
        context,
        ref,
        action: const CreateGoalAction(),
        input: data,
        idempotencyKey: _key,
        successTitle: 'Goal created',
        successSubtitle: data.name,
        onFieldErrors: onErrors,
      );
    } else {
      result = await runAction(
        context,
        ref,
        action: const UpdateGoalAction(),
        input: UpdateGoalInput(id: existing.id, expectedVersion: existing.version, data: data),
        idempotencyKey: _key,
        successTitle: 'Goal updated',
        onFieldErrors: onErrors,
      );
    }
    if (!mounted) return;
    setState(() => _submitting = false);
    if (result != null) await Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final goalValue = _isEdit ? ref.watch(goalProgressProvider(widget.goalId!)) : null;
    final ready = goalValue == null || goalValue.hasValue;
    if (ready) _load(goalValue?.value);
    final missing = _isEdit && ready && _existing == null;
    return FinnSheetScaffold(
      title: _isEdit ? 'Edit goal' : 'New goal',
      footer: LedgerButton(
        label: _isEdit ? 'Save changes' : 'Create goal',
        expand: true,
        loading: _submitting,
        onPressed: _submitting || !ready || missing ? null : _submit,
      ),
      child: !ready
          ? const _FormSkeleton()
          : missing
          ? const LedgerEmpty(title: 'Goal not found', message: 'It may have been deleted.')
          : _form(context),
    );
  }

  Widget _form(BuildContext context) {
    final today = ref.watch(todayProvider);
    final available = ref.watch(balanceProvider.select((b) => b.value?.available));
    final startingTooHigh = _startingValue != null && available != null && _startingValue! > available;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LedgerAmountField(
          hero: true,
          controller: _target,
          label: 'Target',
          errorText: _errors['target'],
          textInputAction: TextInputAction.next,
          onChanged: (_) => _clearError('target'),
        ),
        const SizedBox(height: LedgerForm.gap),
        LedgerTextField(
          controller: _name,
          label: 'Name',
          hint: 'e.g. Goa trip with friends',
          errorText: _errors['name'],
          maxLength: 50,
          textCapitalization: TextCapitalization.sentences,
          textInputAction: TextInputAction.next,
          onChanged: (_) => _clearError('name'),
        ),
        const SizedBox(height: LedgerForm.gap),
        LedgerField(
          label: 'Type',
          child: LedgerChoiceChips<GoalCategory>(
            options: [
              for (final cat in GoalCategory.values) LedgerOption(cat, cat.label, icon: CategoryIcons.of(cat.iconKey)),
            ],
            selected: _category,
            onChanged: (v) => setState(() => _category = v),
          ),
        ),
        const SizedBox(height: LedgerForm.groupGap),
        LedgerDateField(
          label: 'Target date (optional)',
          hint: 'No deadline',
          value: _targetDate,
          firstDate: today.add(const Duration(days: 1)),
          lastDate: DateTime(today.year + 40, today.month, today.day),
          errorText: _errors['targetDate'],
          onClear: () => setState(() => _targetDate = null),
          onChanged: (d) => setState(() {
            _targetDate = d;
            _errors = {..._errors}..remove('targetDate');
          }),
        ),
        const SizedBox(height: LedgerForm.gap),
        LedgerAmountField(
          controller: _monthly,
          label: 'Monthly plan (optional)',
          helper: "Used to estimate when you'll get there.",
          errorText: _errors['plannedMonthlyContribution'],
          onChanged: (_) => _clearError('plannedMonthlyContribution'),
        ),
        if (!_isEdit) ...[
          const SizedBox(height: LedgerForm.gap),
          LedgerAmountField(
            controller: _starting,
            label: 'Set aside now (optional)',
            helper: available == null
                ? 'Moves money from your balance into this goal.'
                : 'Available: ${savingsMoney(context, available)}',
            errorText:
                _errors['initialAllocation'] ??
                (startingTooHigh ? 'More than the ${savingsMoney(context, available)} you have available.' : null),
            onChanged: (m) => setState(() {
              _startingValue = m;
              _errors = {..._errors}..remove('initialAllocation');
            }),
          ),
        ],
      ],
    );
  }
}

class _FormSkeleton extends StatelessWidget {
  const _FormSkeleton();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading',
      child: const ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LedgerSkeleton(width: 80, height: 14),
            SizedBox(height: Sp.sm),
            LedgerSkeleton(width: 200, height: 44),
            SizedBox(height: LedgerForm.gap),
            LedgerSkeleton(height: 52),
            SizedBox(height: LedgerForm.gap),
            LedgerSkeleton(height: 52),
            SizedBox(height: LedgerForm.gap),
            LedgerSkeleton(height: 52),
          ],
        ),
      ),
    );
  }
}
