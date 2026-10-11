import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/di/core_providers.dart';
import '../../../app/di/data_providers.dart';
import '../../../app/router/routes.dart';
import '../../../core/money/money_format.dart';
import '../../../core/result/result.dart';
import '../../../design_system/design_system.dart';
import '../../../features/transactions/domain/transaction.dart';
import '../../../shared/presentation/action_runner.dart';
import '../../../shared/presentation/category_icons.dart';
import '../../categories/domain/category.dart';
import '../application/transaction_actions.dart';
import '../application/transaction_form_support.dart';

/// Create or edit a manual transaction.
///
/// Editing loads the transaction first; linked transactions (created by
/// loans, subscriptions or settlements) cannot be edited here.
class TransactionFormSheet extends ConsumerWidget {
  const TransactionFormSheet({super.key, this.transactionId, this.initialType = TransactionType.expense});

  final String? transactionId;
  final TransactionType initialType;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = transactionId;
    if (id == null) return _TransactionForm(initial: null, initialType: initialType);

    const title = 'Edit transaction';
    final value = ref.watch(transactionByIdProvider(id));
    if (value.hasError && !value.hasValue) {
      final e = value.error;
      return FinnSheetScaffold(
        title: title,
        child: ErrorState(
          title: 'Could not load this transaction',
          message: e is AppFailure ? e.message : 'Please try again.',
          onRetry: () => refreshFinanceData(ref),
        ),
      );
    }
    if (!value.hasValue) {
      return const FinnSheetScaffold(
        title: title,
        child: SkeletonPulse(
          child: Column(
            children: [
              SkeletonBox(height: 56, radius: Radii.lg),
              SizedBox(height: Space.x4),
              SkeletonBox(height: 200, radius: Radii.lg),
            ],
          ),
        ),
      );
    }
    final tx = value.requireValue;
    if (tx == null) {
      return const FinnSheetScaffold(
        title: title,
        child: EmptyState(
          icon: LucideIcons.searchX,
          title: 'Transaction not found',
          message: 'It may have been deleted. Nothing to edit.',
        ),
      );
    }
    if (tx.isLinked) {
      return FinnSheetScaffold(
        title: title,
        child: InfoBanner(
          title: 'Created by ${tx.origin.label}',
          message: 'This transaction is linked to another record. Change or reverse it from there so your '
              'balances stay accurate.',
          icon: LucideIcons.link2,
        ),
      );
    }
    return _TransactionForm(key: ValueKey(tx.id), initial: tx, initialType: tx.type);
  }
}

class _TransactionForm extends ConsumerStatefulWidget {
  const _TransactionForm({super.key, required this.initial, required this.initialType});

  final Transaction? initial;
  final TransactionType initialType;

  @override
  ConsumerState<_TransactionForm> createState() => _TransactionFormState();
}

class _TransactionFormState extends ConsumerState<_TransactionForm> {
  /// One key per form session: a double tap can never record twice.
  final String _key = newIdempotencyKey();
  final _amount = TextEditingController();
  final _counterparty = TextEditingController();
  final _note = TextEditingController();

  late TransactionType _type;
  String? _categoryId;
  late DateTime _date;
  PaymentMethod? _method;
  bool _methodTouched = false;

  /// Shown when an edited transaction's category can no longer be used.
  String? _retiredCategoryName;
  Map<String, String> _errors = const {};
  bool _submitting = false;

  bool get _editing => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final t = widget.initial;
    _type = widget.initialType;
    _date = ref.read(todayProvider);
    if (t != null) {
      _type = t.type;
      _amount.text = MoneyFormatter.editable(t.amount);
      _date = t.date;
      _method = t.paymentMethod;
      _methodTouched = true;
      _counterparty.text = t.counterparty ?? '';
      _note.text = t.note ?? '';
      final pickable = ref.read(pickableCategoriesProvider(t.type)).value;
      final usable = pickable == null || pickable.any((c) => c.id == t.categoryId);
      if (usable) {
        _categoryId = t.categoryId;
      } else {
        _retiredCategoryName = ref.read(categoryProvider(t.categoryId))?.name ?? 'The previous category';
      }
    } else {
      _method = ref.read(lastPaymentMethodProvider)[_type] ?? defaultPaymentMethod(_type);
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _counterparty.dispose();
    _note.dispose();
    super.dispose();
  }

  void _setType(TransactionType type) {
    setState(() {
      _type = type;
      final current = _categoryId == null ? null : ref.read(categoryProvider(_categoryId!));
      if (current != null && current.type != type) _categoryId = null;
      if (!_methodTouched) {
        _method = ref.read(lastPaymentMethodProvider)[type] ?? defaultPaymentMethod(type);
      }
      _errors = Map.of(_errors)..remove('categoryId');
    });
  }

  void _clearError(String field) {
    if (!_errors.containsKey(field)) return;
    setState(() => _errors = Map.of(_errors)..remove(field));
  }

  Future<void> _createCategory() async {
    final created = await context.push<Object?>(AppRoutes.newCategory(type: _type));
    if (!mounted || created is! String) return;
    setState(() {
      _categoryId = created;
      _errors = Map.of(_errors)..remove('categoryId');
    });
  }

  String? _trimmed(TextEditingController c) {
    final v = c.text.trim();
    return v.isEmpty ? null : v;
  }

  Future<void> _submit() async {
    if (_submitting) return;
    FocusScope.of(context).unfocus();
    final amount = AmountField.parse(_amount.text);
    final local = <String, String>{
      if (amount == null || !amount.isPositive) 'amount': 'Enter an amount greater than zero.',
      if (_categoryId == null) 'categoryId': 'Choose a category.',
    };
    if (local.isNotEmpty) {
      setState(() => _errors = local);
      if (ref.read(settingsProvider).hapticsEnabled) HapticFeedback.heavyImpact();
      return;
    }
    setState(() {
      _errors = const {};
      _submitting = true;
    });

    final data = TransactionInput(
      type: _type,
      amount: amount!,
      categoryId: _categoryId!,
      date: _date,
      paymentMethod: _method,
      counterparty: _trimmed(_counterparty),
      note: _trimmed(_note),
    );
    final categoryName = ref.read(categoryProvider(_categoryId!))?.name;
    void onErrors(Map<String, String> e) => setState(() => _errors = e);

    final initial = widget.initial;
    final Transaction? saved;
    if (initial == null) {
      saved = await runAction(
        context,
        ref,
        action: const CreateTransactionAction(),
        input: data,
        idempotencyKey: _key,
        successTitle: '${_type.label} recorded',
        successSubtitle: [amount.format(), ?categoryName].join(' · '),
        onFieldErrors: onErrors,
      );
    } else {
      saved = await runAction(
        context,
        ref,
        action: const UpdateTransactionAction(),
        input: UpdateTransactionInput(id: initial.id, expectedVersion: initial.version, data: data),
        idempotencyKey: _key,
        successTitle: 'Changes saved',
        successSubtitle: [amount.format(), ?categoryName].join(' · '),
        onFieldErrors: onErrors,
      );
    }
    if (!mounted) return;
    if (saved == null) {
      setState(() => _submitting = false);
      return;
    }
    ref.read(lastPaymentMethodProvider.notifier).remember(_type, _method);
    await Navigator.of(context).maybePop(saved.id);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final today = ref.watch(todayProvider);
    final income = _type.isIncome;
    final categories = ref.watch(pickableCategoriesProvider(_type));
    final submitLabel = _editing ? 'Save changes' : 'Record ${_type.label.toLowerCase()}';

    return FinnSheetScaffold(
      title: _editing ? 'Edit transaction' : 'Record transaction',
      description: _editing
          ? 'Balances, budgets and insights update automatically.'
          : 'Money that has already moved in or out.',
      footer: FinnButton(
        label: submitLabel,
        icon: LucideIcons.check,
        size: FinnButtonSize.lg,
        expand: true,
        loading: _submitting,
        variant: income ? FinnButtonVariant.positive : FinnButtonVariant.primary,
        onPressed: _submit,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedTabs<TransactionType>(
            items: const [
              SegmentItem(TransactionType.expense, 'Expense'),
              SegmentItem(TransactionType.income, 'Income'),
            ],
            selected: _type,
            onChanged: _submitting ? (_) {} : _setType,
          ),
          const SizedBox(height: Space.x5),
          AmountField(
            label: 'Amount',
            controller: _amount,
            autofocus: !_editing,
            errorText: _errors['amount'],
            textInputAction: TextInputAction.next,
            onChanged: (_) => _clearError('amount'),
          ),
          const SizedBox(height: Space.x5),
          Text('Category', style: t.label),
          const SizedBox(height: Space.x1_5),
          if (_retiredCategoryName != null && _categoryId == null) ...[
            InfoBanner(
              tone: FinnTone.warning,
              message: '$_retiredCategoryName is no longer available. Choose another category to save changes.',
            ),
            const SizedBox(height: Space.x2),
          ],
          switch (categories) {
            AsyncValue(:final value?) => _CategoryPicker(
                categories: value,
                selectedId: _categoryId,
                onSelected: (id) => setState(() {
                  _categoryId = id;
                  _errors = Map.of(_errors)..remove('categoryId');
                }),
              ),
            AsyncValue(hasError: true) => Text('Categories could not be loaded.', style: t.caption),
            _ => const SkeletonBox(height: 160, radius: Radii.lg),
          },
          if (_errors['categoryId'] != null)
            Padding(
              padding: const EdgeInsets.only(top: Space.x1_5, left: Space.x1),
              child: Text(_errors['categoryId']!, style: t.caption.copyWith(color: c.negative)),
            ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: _submitting ? null : _createCategory,
              icon: const Icon(LucideIcons.plus, size: 16),
              label: const Text('Create a category'),
            ),
          ),
          const SizedBox(height: Space.x3),
          DateField(
            label: 'Date',
            value: _date,
            firstDate: DateTime(2000),
            lastDate: today,
            errorText: _errors['date'],
            onChanged: (d) => setState(() {
              _date = d;
              _errors = Map.of(_errors)..remove('date');
            }),
          ),
          const SizedBox(height: Space.x5),
          Text(income ? 'Received via' : 'Paid via', style: t.label),
          const SizedBox(height: Space.x1),
          FilterChipBar<PaymentMethod>(
            padding: EdgeInsets.zero,
            multiSelect: false,
            items: [for (final m in PaymentMethod.values) FilterChipItem(m, m.label, icon: _methodIcon(m))],
            selected: {?_method},
            onChanged: (s) => setState(() {
              _method = s.isEmpty ? null : s.first;
              _methodTouched = true;
            }),
          ),
          const SizedBox(height: Space.x5),
          FinnTextField(
            label: income ? 'Received from' : 'Paid to',
            hint: income ? 'e.g. Employer, client, Priya' : 'e.g. Swiggy, DMart, landlord',
            controller: _counterparty,
            prefixIcon: income ? LucideIcons.user : LucideIcons.store,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            errorText: _errors['counterparty'],
            onChanged: (_) => _clearError('counterparty'),
          ),
          const SizedBox(height: Space.x5),
          FinnTextField(
            label: 'Note (optional)',
            hint: 'Anything to remember about this',
            controller: _note,
            minLines: 2,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            errorText: _errors['note'],
            onChanged: (_) => _clearError('note'),
          ),
        ],
      ),
    );
  }
}

IconData _methodIcon(PaymentMethod m) => switch (m) {
      PaymentMethod.upi => LucideIcons.smartphone,
      PaymentMethod.card => LucideIcons.creditCard,
      PaymentMethod.cash => LucideIcons.banknote,
      PaymentMethod.bankTransfer => LucideIcons.landmark,
      PaymentMethod.wallet => LucideIcons.wallet,
      PaymentMethod.other => LucideIcons.circleDot,
    };

/// Searchable grid of category tiles.
class _CategoryPicker extends StatefulWidget {
  const _CategoryPicker({required this.categories, required this.selectedId, required this.onSelected});

  final List<TransactionCategory> categories;
  final String? selectedId;
  final ValueChanged<String> onSelected;

  @override
  State<_CategoryPicker> createState() => _CategoryPickerState();
}

class _CategoryPickerState extends State<_CategoryPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final visible = q.isEmpty
        ? widget.categories
        : widget.categories
            .where((c) => c.name.toLowerCase().contains(q) || c.description.toLowerCase().contains(q))
            .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.categories.length > 8) ...[
          FinnSearchField(
            hint: 'Search categories',
            debounce: Duration.zero,
            onChanged: (v) => setState(() => _query = v),
          ),
          const SizedBox(height: Space.x2),
        ],
        if (visible.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.x6),
            child: Text('No matching categories', textAlign: TextAlign.center, style: context.text.caption),
          )
        else
          LayoutBuilder(
            builder: (context, box) {
              const gap = Space.x2;
              final cols = math.max(3, (box.maxWidth / 92).floor());
              final width = (box.maxWidth - gap * (cols - 1)) / cols;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final cat in visible)
                    SizedBox(
                      key: ValueKey(cat.id),
                      width: width,
                      child: _CategoryTile(
                        category: cat,
                        selected: cat.id == widget.selectedId,
                        onTap: () => widget.onSelected(cat.id),
                      ),
                    ),
                ],
              );
            },
          ),
      ],
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.category, required this.selected, required this.onTap});

  final TransactionCategory category;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      selected: selected,
      label: category.name,
      excludeSemantics: true,
      child: InkWell(
        borderRadius: Radii.rLg,
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: AnimatedContainer(
          duration: context.motion.fast,
          constraints: const BoxConstraints(minHeight: 88),
          padding: const EdgeInsets.symmetric(horizontal: Space.x1, vertical: Space.x2),
          decoration: BoxDecoration(
            color: selected ? c.surfaceMuted : c.surface,
            borderRadius: Radii.rLg,
            border: Border.all(color: selected ? c.primary : c.border, width: selected ? 2 : 1),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  CategoryAvatar(category: category, size: 36),
                  if (selected)
                    Positioned(
                      right: -6,
                      top: -6,
                      child: Container(
                        decoration: BoxDecoration(color: c.surface, shape: BoxShape.circle),
                        child: Icon(LucideIcons.circleCheck, size: 16, color: c.primary),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: Space.x1_5),
              Text(
                category.name,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: context.text.micro.copyWith(
                  color: c.textPrimary,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
