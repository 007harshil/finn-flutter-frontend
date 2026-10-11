import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/di/core_providers.dart';
import '../../../app/di/data_providers.dart';
import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/presentation/action_runner.dart';
import '../../../shared/presentation/category_icons.dart';
import '../application/goal_actions.dart';
import '../domain/goal.dart';
import 'savings_widgets.dart';

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
    final target = AmountField.parse(_target.text);
    final monthly = _monthly.text.trim().isEmpty ? null : AmountField.parse(_monthly.text);
    final starting = _starting.text.trim().isEmpty ? null : AmountField.parse(_starting.text);
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
      description: 'Something you\'re saving towards. Money you add is set aside, not spent.',
      footer: FinnButton(
        label: _isEdit ? 'Save changes' : 'Create goal',
        icon: LucideIcons.check,
        expand: true,
        size: FinnButtonSize.lg,
        loading: _submitting,
        onPressed: _submitting || !ready || missing ? null : _submit,
      ),
      child: !ready
          ? const SkeletonPulse(child: ListSkeleton(count: 4, padding: EdgeInsets.zero))
          : missing
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: Space.x6),
                  child: ErrorState(title: 'Goal not found', message: 'It may have been deleted.'),
                )
              : _form(context),
    );
  }

  Widget _form(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final today = ref.watch(todayProvider);
    final available = ref.watch(balanceProvider.select((b) => b.value?.available));
    final startingTooHigh = _startingValue != null && available != null && _startingValue! > available;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FinnTextField(
          controller: _name,
          label: 'Goal name',
          hint: 'e.g. Goa trip with friends',
          errorText: _errors['name'],
          maxLength: 50,
          textCapitalization: TextCapitalization.sentences,
          textInputAction: TextInputAction.next,
          onChanged: (_) => _clearError('name'),
        ),
        const SizedBox(height: Space.x3),
        Text('Type', style: t.label),
        const SizedBox(height: Space.x2),
        FilterChipBar<GoalCategory>(
          padding: EdgeInsets.zero,
          multiSelect: false,
          items: [
            for (final cat in GoalCategory.values)
              FilterChipItem(cat, cat.label, icon: CategoryIcons.of(cat.iconKey)),
          ],
          selected: {_category},
          onChanged: (s) => setState(() => _category = s.first),
        ),
        const SizedBox(height: Space.x5),
        AmountField(
          controller: _target,
          label: 'Target amount',
          errorText: _errors['target'],
          textInputAction: TextInputAction.next,
          onChanged: (_) => _clearError('target'),
        ),
        const SizedBox(height: Space.x5),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: DateField(
                label: 'Target date (optional)',
                hint: 'No deadline',
                value: _targetDate,
                firstDate: today.add(const Duration(days: 1)),
                lastDate: DateTime(today.year + 40, today.month, today.day),
                errorText: _errors['targetDate'],
                onChanged: (d) => setState(() {
                  _targetDate = d;
                  _errors = {..._errors}..remove('targetDate');
                }),
              ),
            ),
            if (_targetDate != null) ...[
              const SizedBox(width: Space.x2),
              FinnIconButton(
                icon: LucideIcons.x,
                tooltip: 'Clear target date',
                onPressed: () => setState(() => _targetDate = null),
              ),
            ],
          ],
        ),
        const SizedBox(height: Space.x5),
        AmountField(
          controller: _monthly,
          label: 'Monthly plan (optional)',
          hint: 'How much you plan to add each month',
          errorText: _errors['plannedMonthlyContribution'],
          onChanged: (_) => _clearError('plannedMonthlyContribution'),
        ),
        const SizedBox(height: Space.x1_5),
        Text('Used to estimate when you\'ll reach your goal.', style: t.caption),
        const SizedBox(height: Space.x5),
        Text('Colour', style: t.label),
        const SizedBox(height: Space.x2),
        Wrap(
          spacing: Space.x2,
          runSpacing: Space.x2,
          children: [
            for (var i = 0; i < AccentSwatches.gradients.length; i++)
              _Swatch(
                key: ValueKey('swatch-$i'),
                index: i,
                selected: i == _colorIndex,
                onTap: () => setState(() => _colorIndex = i),
              ),
          ],
        ),
        if (!_isEdit) ...[
          const SizedBox(height: Space.x5),
          AmountField(
            controller: _starting,
            label: 'Starting amount (optional)',
            hint: 'Set aside now',
            errorText: _errors['initialAllocation'],
            onChanged: (m) => setState(() {
              _startingValue = m;
              _errors = {..._errors}..remove('initialAllocation');
            }),
          ),
          const SizedBox(height: Space.x1_5),
          Text(
            available == null
                ? 'Moves money from your available balance into this goal.'
                : 'Available to set aside: ${savingsMoney(context, available)}',
            style: t.caption.copyWith(color: startingTooHigh ? c.negative : null),
          ),
          if (startingTooHigh)
            Text('That is more than you have available.', style: t.caption.copyWith(color: c.negative)),
        ],
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({super.key, required this.index, required this.selected, required this.onTap});

  final int index;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      selected: selected,
      label: 'Colour ${index + 1}',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox.square(
          dimension: Dimens.minTouch,
          child: Center(
            child: AnimatedContainer(
              duration: context.motion.fast,
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                gradient: AccentSwatches.gradient(index),
                shape: BoxShape.circle,
                border: Border.all(color: selected ? c.textPrimary : c.surface, width: selected ? 3 : 2),
              ),
              child: selected ? const Icon(LucideIcons.check, size: 16, color: Colors.white) : null,
            ),
          ),
        ),
      ),
    );
  }
}
