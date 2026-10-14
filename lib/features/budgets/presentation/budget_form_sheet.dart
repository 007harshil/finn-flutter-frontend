import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/di/core_providers.dart';
import '../../../app/di/data_providers.dart';
import '../../../core/money/money_format.dart';
import '../../../core/time/dates.dart';
import '../../../design_system/design_system.dart';
import '../../../finance/finance_snapshot.dart';
import '../../../shared/presentation/action_runner.dart';
import '../../../shared/presentation/category_icons.dart';
import '../../categories/domain/category.dart';
import '../../transactions/domain/transaction.dart';
import '../application/budget_actions.dart';
import '../application/budget_history.dart';
import '../domain/budget.dart';

/// Create or edit a budget. Budgets are freely editable.
class BudgetFormSheet extends ConsumerStatefulWidget {
  const BudgetFormSheet({super.key, this.budgetId});

  final String? budgetId;

  @override
  ConsumerState<BudgetFormSheet> createState() => _BudgetFormSheetState();
}

class _BudgetFormSheetState extends ConsumerState<BudgetFormSheet> {
  final _key = newIdempotencyKey();
  final _limit = TextEditingController();
  final _note = TextEditingController();
  String? _categoryId;
  int _warningBps = defaultBudgetWarningBps;
  Map<String, String> _errors = const {};
  bool _submitting = false;
  bool _loaded = false;
  Budget? _existing;

  bool get _isEdit => widget.budgetId != null;

  @override
  void dispose() {
    _limit.dispose();
    _note.dispose();
    super.dispose();
  }

  void _load(FinanceSnapshot s) {
    if (_loaded) return;
    _loaded = true;
    _warningBps = ref.read(settingsProvider).defaultBudgetWarningBps.clamp(minBudgetWarningBps, maxBudgetWarningBps);
    final b = s.budgets.where((x) => x.id == widget.budgetId).firstOrNull;
    if (b == null) return;
    _existing = b;
    _categoryId = b.categoryId;
    _limit.text = MoneyFormatter.editable(b.limit);
    _warningBps = b.warningThresholdBps;
    _note.text = b.note ?? '';
  }

  Future<void> _submit() async {
    final limit = AmountField.parse(_limit.text);
    final local = <String, String>{
      if (_categoryId == null) 'categoryId': 'Choose a category.',
      if (limit == null || !limit.isPositive) 'limit': 'Enter a limit greater than zero.',
    };
    if (local.isNotEmpty) {
      setState(() => _errors = local);
      return;
    }
    final note = _note.text.trim();
    final data = BudgetInput(
      categoryId: _categoryId!,
      limit: limit!,
      warningThresholdBps: _warningBps,
      note: note.isEmpty ? null : note,
    );
    setState(() {
      _submitting = true;
      _errors = const {};
    });
    void onErrors(Map<String, String> e) {
      if (mounted) setState(() => _errors = e);
    }

    final existing = _existing;
    final Budget? result;
    if (existing == null) {
      result = await runAction(
        context,
        ref,
        action: const CreateBudgetAction(),
        input: data,
        idempotencyKey: _key,
        successTitle: 'Budget created',
        onFieldErrors: onErrors,
      );
    } else {
      result = await runAction(
        context,
        ref,
        action: const UpdateBudgetAction(),
        input: UpdateBudgetInput(id: existing.id, expectedVersion: existing.version, data: data),
        idempotencyKey: _key,
        successTitle: 'Budget updated',
        onFieldErrors: onErrors,
      );
    }
    if (!mounted) return;
    setState(() => _submitting = false);
    if (result != null) await Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = ref.watch(financeSnapshotProvider);
    final s = snapshot.value;
    if (s != null) _load(s);
    return FinnSheetScaffold(
      title: _isEdit ? 'Edit budget' : 'New budget',
      description: 'A spending limit for one category. Spending is tracked from your transactions.',
      footer: FinnButton(
        label: _isEdit ? 'Save changes' : 'Create budget',
        icon: LucideIcons.check,
        expand: true,
        size: FinnButtonSize.lg,
        loading: _submitting,
        onPressed: _submitting || s == null || (_isEdit && _existing == null) ? null : _submit,
      ),
      child: s == null
          ? const SkeletonPulse(child: ListSkeleton(count: 4, padding: EdgeInsets.zero))
          : (_isEdit && _existing == null)
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: Space.x6),
                  child: ErrorState(title: 'Budget not found', message: 'It may have been deleted.'),
                )
              : _form(context, s),
    );
  }

  Widget _form(BuildContext context, FinanceSnapshot s) {
    final c = context.colors;
    final t = context.text;
    final categories = s.categories
        .where((x) => x.type == TransactionType.expense && (!x.isArchived || x.id == _categoryId))
        .toList();
    final budgeted = ref.watch(budgetedCategoryIdsProvider);
    final selfCategory = _existing?.categoryId;
    final suggestion = _categoryId == null ? null : ref.watch(budgetLimitSuggestionProvider(_categoryId!));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Category', style: t.label),
        const SizedBox(height: Space.x2),
        Wrap(
          spacing: Space.x2,
          runSpacing: Space.x2,
          children: [
            for (final cat in categories)
              _CategoryChoice(
                key: ValueKey(cat.id),
                category: cat,
                selected: cat.id == _categoryId,
                hasBudget: budgeted.contains(cat.id) && cat.id != selfCategory,
                onTap: () => setState(() {
                  _categoryId = cat.id;
                  _errors = {..._errors}..remove('categoryId');
                }),
              ),
          ],
        ),
        if (_errors['categoryId'] != null) ...[
          const SizedBox(height: Space.x1_5),
          Text(_errors['categoryId']!, style: t.caption.copyWith(color: c.negative)),
        ],
        if (budgeted.isNotEmpty) ...[
          const SizedBox(height: Space.x1_5),
          Text('Categories marked with a check already have a monthly budget.', style: t.caption),
        ],
        const SizedBox(height: Space.x5),
        AmountField(
            prominent: true,
          controller: _limit,
          label: 'Spending limit',
          errorText: _errors['limit'],
          textInputAction: TextInputAction.next,
          onChanged: (_) {
            if (_errors.containsKey('limit')) setState(() => _errors = {..._errors}..remove('limit'));
          },
        ),
        if (suggestion != null) ...[
          const SizedBox(height: Space.x2),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: _SuggestionChip(
              text: 'Last month you spent about ${AmountVisibility.hiddenOf(context) ? MoneyFormatter.masked : suggestion.format()} here — use this',
              onTap: () => setState(() {
                _limit.text = MoneyFormatter.editable(suggestion);
                _errors = {..._errors}..remove('limit');
              }),
            ),
          ),
        ],
        const SizedBox(height: Space.x5),
        _MonthlyNote(
          period: s.currentBudgetPeriod,
          categoryName: s.category(_categoryId ?? '')?.name,
          editing: _isEdit,
        ),
        const SizedBox(height: Space.x5),
        Row(
          children: [
            Expanded(child: Text('Warn me at', style: t.label)),
            Text(formatBps(_warningBps, decimals: 0), style: t.bodyStrong),
          ],
        ),
        Slider(
          value: _warningBps / 100,
          min: minBudgetWarningBps / 100,
          max: maxBudgetWarningBps / 100,
          divisions: (maxBudgetWarningBps - minBudgetWarningBps) ~/ 500,
          label: formatBps(_warningBps, decimals: 0),
          semanticFormatterCallback: (v) => 'Warn at ${v.round()} percent',
          onChanged: (v) {
            final bps = (v.round() * 100).clamp(minBudgetWarningBps, maxBudgetWarningBps);
            if (bps != _warningBps) {
              if (ref.read(settingsProvider).hapticsEnabled) HapticFeedback.selectionClick();
              setState(() => _warningBps = bps);
            }
          },
        ),
        Text('We\'ll mark the budget "Near limit" once you\'ve used this much.', style: t.caption),
        if (_errors['warningThresholdBps'] != null)
          Text(_errors['warningThresholdBps']!, style: t.caption.copyWith(color: c.negative)),
        const SizedBox(height: Space.x5),
        FinnTextField(
          controller: _note,
          label: 'Note (optional)',
          hint: 'e.g. Includes weekend dining',
          errorText: _errors['note'],
          maxLength: 200,
          textCapitalization: TextCapitalization.sentences,
        ),
      ],
    );
  }
}

class _CategoryChoice extends StatelessWidget {
  const _CategoryChoice({
    super.key,
    required this.category,
    required this.selected,
    required this.hasBudget,
    required this.onTap,
  });

  final TransactionCategory category;
  final bool selected;
  final bool hasBudget;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    return Semantics(
      button: true,
      selected: selected,
      label: '${category.name}${hasBudget ? ', already has a monthly budget' : ''}',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: context.motion.fast,
          constraints: const BoxConstraints(minHeight: Dimens.minTouch),
          padding: const EdgeInsets.fromLTRB(Space.x1_5, Space.x1_5, Space.x3, Space.x1_5),
          decoration: BoxDecoration(
            color: selected ? c.primary.withValues(alpha: 0.08) : c.surface,
            borderRadius: Radii.rFull,
            border: Border.all(color: selected ? c.primary : c.border, width: selected ? 2 : 1.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CategoryAvatar(category: category, size: 28),
              const SizedBox(width: Space.x2),
              Text(category.name, style: t.label.copyWith(color: c.textPrimary, fontWeight: FontWeight.w700)),
              if (hasBudget) ...[
                const SizedBox(width: Space.x1_5),
                Icon(LucideIcons.circleCheck, size: 14, color: c.textTertiary),
              ],
              if (selected) ...[
                const SizedBox(width: Space.x1_5),
                Icon(LucideIcons.check, size: 14, color: c.primary),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  const _SuggestionChip({required this.text, required this.onTap});

  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: text,
      excludeSemantics: true,
      child: InkWell(
        borderRadius: Radii.rLg,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 40),
          padding: const EdgeInsets.symmetric(horizontal: Space.x3, vertical: Space.x2),
          decoration: BoxDecoration(color: c.infoSoft, borderRadius: Radii.rLg),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.lightbulb, size: 14, color: c.info),
              const SizedBox(width: Space.x1_5),
              Flexible(
                child: Text(text, style: context.text.label.copyWith(color: c.textPrimary, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Budgets are always monthly: this explains what that means for the
/// month the budget is created in and for expenses.
class _MonthlyNote extends StatelessWidget {
  const _MonthlyNote({required this.period, required this.categoryName, required this.editing});

  final DateRange period;
  final String? categoryName;

  /// Editing an existing budget: a new limit applies from this month on.
  final bool editing;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final range = '${DateFormats.dayMonth.format(period.start)} – ${DateFormats.dayMonth.format(period.end)}';
    Widget line(IconData icon, String text) => Padding(
          padding: const EdgeInsets.only(top: Space.x1_5),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 14, color: c.textSecondary),
              const SizedBox(width: Space.x2),
              Expanded(child: Text(text, style: t.caption)),
            ],
          ),
        );
    return Container(
      key: const ValueKey('budget-monthly-note'),
      padding: const EdgeInsets.fromLTRB(Space.x3, Space.x1_5, Space.x3, Space.x2_5),
      decoration: BoxDecoration(color: c.surfaceMuted, borderRadius: Radii.rLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          line(LucideIcons.calendarRange, 'Monthly. Covers all of this month ($range), whatever day you create it, '
              'and renews every month.'),
          line(LucideIcons.zap, 'Every expense in ${categoryName ?? 'this category'} counts automatically — '
              'nothing to add by hand.'),
          if (editing)
            line(LucideIcons.history, 'A new limit applies from this month. Earlier months keep the limit they had.'),
        ],
      ),
    );
  }
}
