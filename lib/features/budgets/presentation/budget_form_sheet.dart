import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/core_providers.dart';
import '../../../app/di/data_providers.dart';
import '../../../core/money/money_format.dart';
import '../../../kit/kit.dart';
import '../../../finance/finance_snapshot.dart';
import '../../../shared/presentation/action_runner.dart';
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
    _warningBps = ref
        .read(settingsProvider)
        .defaultBudgetWarningBps
        .clamp(minBudgetWarningBps, maxBudgetWarningBps);
    final b = s.budgets.where((x) => x.id == widget.budgetId).firstOrNull;
    if (b == null) return;
    _existing = b;
    _categoryId = b.categoryId;
    _limit.text = MoneyFormatter.editable(b.limit);
    _warningBps = b.warningThresholdBps;
    _note.text = b.note ?? '';
  }

  Future<void> _submit() async {
    final limit = LedgerAmountField.parse(_limit.text);
    final local = <String, String>{
      if (_categoryId == null) 'categoryId': 'Choose a category.',
      if (limit == null || !limit.isPositive)
        'limit': 'Enter a limit greater than zero.',
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
        input: UpdateBudgetInput(
          id: existing.id,
          expectedVersion: existing.version,
          data: data,
        ),
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
      footer: LedgerButton(
        label: _isEdit ? 'Save changes' : 'Create budget',
        expand: true,
        loading: _submitting,
        onPressed: _submitting || s == null || (_isEdit && _existing == null)
            ? null
            : _submit,
      ),
      child: s == null
          ? const Column(
              children: [
                LedgerSkeleton(height: 44),
                SizedBox(height: LedgerForm.gap),
                LedgerSkeleton(height: 52),
                SizedBox(height: LedgerForm.gap),
                LedgerSkeleton(height: 52),
              ],
            )
          : (_isEdit && _existing == null)
          ? const LedgerEmpty(
              title: 'Budget not found',
              message: 'It may have been deleted.',
            )
          : _form(context, s),
    );
  }

  Widget _form(BuildContext context, FinanceSnapshot s) {
    final c = context.ink;
    final t = context.type;
    final categories = s.categories
        .where(
          (x) =>
              x.type == TransactionType.expense &&
              (!x.isArchived || x.id == _categoryId),
        )
        .toList();
    final budgeted = ref.watch(budgetedCategoryIdsProvider);
    final selfCategory = _existing?.categoryId;
    final suggestion = _categoryId == null
        ? null
        : ref.watch(budgetLimitSuggestionProvider(_categoryId!));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LedgerAmountField(
          hero: true,
          controller: _limit,
          label: 'Monthly limit',
          helper: _isEdit
              ? 'Applies from this month. Earlier months keep their limit.'
              : 'Renews every month.',
          errorText: _errors['limit'],
          textInputAction: TextInputAction.next,
          onChanged: (_) {
            if (_errors.containsKey('limit'))
              setState(() => _errors = {..._errors}..remove('limit'));
          },
        ),
        const SizedBox(height: LedgerForm.gap),
        LedgerPickerField<String>(
          label: 'Category',
          hint: 'Choose a category',
          searchHint: 'Search categories',
          value: _categoryId,
          errorText: _errors['categoryId'],
          options: [
            for (final cat in categories)
              LedgerOption(
                cat.id,
                cat.name,
                key: ValueKey(cat.id),
                leading: CategoryMark(category: cat),
                subtitle: budgeted.contains(cat.id) && cat.id != selfCategory
                    ? 'Already has a budget'
                    : null,
              ),
          ],
          onChanged: (id) => setState(() {
            _categoryId = id;
            _errors = {..._errors}..remove('categoryId');
          }),
        ),
        if (suggestion != null) ...[
          const SizedBox(height: Sp.sm),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: LedgerButton(
              label:
                  'Use ${AmountVisibility.hiddenOf(context) ? MoneyFormatter.masked : suggestion.format()}, last month\'s spend',
              variant: LedgerButtonVariant.secondary,
              small: true,
              onPressed: () => setState(() {
                _limit.text = MoneyFormatter.editable(suggestion);
                _errors = {..._errors}..remove('limit');
              }),
            ),
          ),
        ],
        const SizedBox(height: LedgerForm.groupGap),
        Row(
          children: [
            Expanded(
              child: Text('Warn me at', style: t.label.copyWith(color: c.ink)),
            ),
            Text(formatBps(_warningBps, decimals: 0), style: t.bodyStrong),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: c.ink,
            inactiveTrackColor: c.sunken,
            thumbColor: c.ink,
            overlayColor: c.ink.withValues(alpha: 0.08),
            valueIndicatorColor: c.ink,
            valueIndicatorTextStyle: t.label.copyWith(color: c.onInk),
          ),
          child: Slider(
            value: _warningBps / 100,
            min: minBudgetWarningBps / 100,
            max: maxBudgetWarningBps / 100,
            divisions: (maxBudgetWarningBps - minBudgetWarningBps) ~/ 500,
            label: formatBps(_warningBps, decimals: 0),
            semanticFormatterCallback: (v) => 'Warn at ${v.round()} percent',
            onChanged: (v) {
              final bps = (v.round() * 100).clamp(
                minBudgetWarningBps,
                maxBudgetWarningBps,
              );
              if (bps != _warningBps) {
                if (ref.read(settingsProvider).hapticsEnabled)
                  HapticFeedback.selectionClick();
                setState(() => _warningBps = bps);
              }
            },
          ),
        ),
        Text('Marked "Near limit" once you pass this.', style: t.label),
        if (_errors['warningThresholdBps'] != null)
          Text(
            _errors['warningThresholdBps']!,
            style: t.label.copyWith(color: c.red),
          ),
        const SizedBox(height: LedgerForm.groupGap),
        LedgerTextField(
          controller: _note,
          label: 'Note (optional)',
          errorText: _errors['note'],
          maxLength: 200,
          textCapitalization: TextCapitalization.sentences,
        ),
      ],
    );
  }
}
