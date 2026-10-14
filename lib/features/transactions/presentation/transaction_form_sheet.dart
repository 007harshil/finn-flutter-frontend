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
import '../../../core/time/dates.dart';
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

  /// Set once saved, so the sheet can close without the discard prompt.
  bool _done = false;

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
    setState(() => _done = true);
    // `pop` (not `maybePop`): the discard guard has not rebuilt yet.
    Navigator.of(context).pop(saved.id);
  }

  Future<void> _pickDate(DateTime today) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date.isAfter(today) ? today : _date,
      firstDate: DateTime(2000),
      lastDate: today,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _date = picked.dateOnly;
      _errors = Map.of(_errors)..remove('date');
    });
  }

  void _setDate(DateTime d) => setState(() {
    _date = d;
    _errors = Map.of(_errors)..remove('date');
  });

  /// A new entry with something typed in would be lost by a stray swipe.
  bool get _dirty =>
      !_editing && !_done && (_amount.text.isNotEmpty || _counterparty.text.isNotEmpty || _note.text.isNotEmpty);

  Future<void> _confirmDiscard() async {
    final discard = await showFinnConfirm(
      context,
      title: 'Discard this entry?',
      message: 'What you typed will not be saved.',
      confirmLabel: 'Discard',
      cancelLabel: 'Keep editing',
      destructive: true,
    );
    if (!discard || !mounted) return;
    setState(() => _done = true);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_amount, _counterparty, _note]),
      builder: (context, child) => PopScope(
        canPop: !_dirty,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _confirmDiscard();
        },
        child: child!,
      ),
      child: Builder(builder: _buildForm),
    );
  }

  Widget _buildForm(BuildContext context) {
    final p = context.vault;
    final t = context.vt;
    final today = ref.watch(todayProvider);
    final income = _type.isIncome;
    final categories = ref.watch(pickableCategoriesProvider(_type));
    final submitLabel = _editing ? 'Save changes' : 'Record ${_type.label.toLowerCase()}';
    final yesterday = today.subtract(const Duration(days: 1));
    final customDate = !DateUtils.isSameDay(_date, today) && !DateUtils.isSameDay(_date, yesterday);

    return FinnSheetScaffold(
      eyebrow: _editing ? 'Editing' : 'New entry',
      title: _editing ? 'Edit transaction' : 'Record transaction',
      description: _editing ? 'Balances, budgets and insights update automatically.' : 'Money that has already moved.',
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
          // Direction first: it colours everything that follows.
          VaultSegmented<TransactionType>(
            values: const [TransactionType.expense, TransactionType.income],
            labels: const ['Expense', 'Income'],
            selected: _type,
            enabled: !_submitting,
            capsuleColor: income ? p.positive : p.ink,
            selectedTextColor: p.isDark ? p.surface : p.onInk,
            onChanged: _setType,
          ),
          const SizedBox(height: 26),
          AmountField(
            label: income ? 'Amount received' : 'Amount spent',
            controller: _amount,
            autofocus: !_editing,
            prominent: true,
            tone: income ? p.positive : null,
            errorText: _errors['amount'],
            textInputAction: TextInputAction.next,
            onChanged: (_) => _clearError('amount'),
          ),
          VaultSection(
            index: 1,
            title: 'Category',
            hint: income ? 'Where it came from' : 'What it was for',
            trailing: TextButton.icon(
              onPressed: _submitting ? null : _createCategory,
              icon: const Icon(LucideIcons.plus, size: 15),
              label: const Text('New'),
            ),
          ),
          if (_retiredCategoryName != null && _categoryId == null) ...[
            InfoBanner(
              tone: FinnTone.warning,
              message: '$_retiredCategoryName is no longer available. Choose another category to save changes.',
            ),
            const SizedBox(height: 12),
          ],
          VaultShake(
            trigger: _errors['categoryId'],
            child: switch (categories) {
              AsyncValue(:final value?) => _CategoryPicker(
                  categories: value,
                  selectedId: _categoryId,
                  accent: income ? p.positive : p.accent,
                  onSelected: (id) => setState(() {
                    _categoryId = id;
                    _errors = Map.of(_errors)..remove('categoryId');
                  }),
                ),
              AsyncValue(hasError: true) => VaultNote(
                  message: 'Categories could not be loaded. Close and reopen to try again.',
                  color: p.negative,
                  icon: LucideIcons.circleAlert,
                ),
              _ => const SkeletonBox(height: 180, radius: VaultShape.group),
            },
          ),
          VaultFieldError(_errors['categoryId']),
          const VaultSection(index: 2, title: 'When & how'),
          Semantics(
            label: 'Date',
            container: true,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                VaultChip(
                  label: 'Today',
                  icon: LucideIcons.sun,
                  selected: DateUtils.isSameDay(_date, today),
                  onTap: () => _setDate(today),
                ),
                VaultChip(
                  label: 'Yesterday',
                  icon: LucideIcons.history,
                  selected: DateUtils.isSameDay(_date, yesterday),
                  onTap: () => _setDate(yesterday),
                ),
                VaultChip(
                  label: customDate ? DateFormats.dayMonthYear.format(_date) : 'Pick a date',
                  icon: LucideIcons.calendarDays,
                  selected: customDate,
                  onTap: () => _pickDate(today),
                ),
              ],
            ),
          ),
          VaultFieldError(_errors['date']),
          const SizedBox(height: 22),
          Text(income ? 'Received via' : 'Paid via', style: t.label),
          const SizedBox(height: 10),
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
          const VaultSection(index: 3, title: 'Details', hint: 'Optional, but it sharpens search and insights'),
          FinnTextField(
            label: income ? 'Received from' : 'Paid to',
            hint: income ? 'Employer, client, Priya' : 'Swiggy, DMart, landlord',
            controller: _counterparty,
            prefixIcon: income ? LucideIcons.user : LucideIcons.store,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            errorText: _errors['counterparty'],
            onChanged: (_) => _clearError('counterparty'),
          ),
          const SizedBox(height: 12),
          FinnTextField(
            label: 'Note (optional)',
            hint: 'Anything to remember about this',
            controller: _note,
            prefixIcon: LucideIcons.notebookPen,
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
  const _CategoryPicker({
    required this.categories,
    required this.selectedId,
    required this.onSelected,
    required this.accent,
  });

  final List<TransactionCategory> categories;
  final String? selectedId;
  final ValueChanged<String> onSelected;
  final Color accent;

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
          const SizedBox(height: 12),
        ],
        if (visible.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 28),
            child: Text('No matching categories', textAlign: TextAlign.center, style: context.vt.caption),
          )
        else
          LayoutBuilder(
            builder: (context, box) {
              const gap = 6.0;
              final cols = math.max(4, (box.maxWidth / 84).floor());
              final width = (box.maxWidth - gap * (cols - 1)) / cols;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (var i = 0; i < visible.length; i++)
                    SizedBox(
                      key: ValueKey(visible[i].id),
                      width: width,
                      child: VaultRise(
                        index: i,
                        offset: 8,
                        duration: const Duration(milliseconds: 460),
                        child: _CategoryTile(
                          category: visible[i],
                          selected: visible[i].id == widget.selectedId,
                          accent: widget.accent,
                          onTap: () => widget.onSelected(visible[i].id),
                        ),
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

/// A category as an avatar that gains a ring (and a check that pops in)
/// when chosen, on a softly tinted plate.
class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.category, required this.selected, required this.onTap, required this.accent});

  final TransactionCategory category;
  final bool selected;
  final VoidCallback onTap;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final p = context.vault;
    final t = context.vt;
    final reduced = context.reduceMotion;
    final pop = reduced ? Duration.zero : const Duration(milliseconds: 420);
    return Semantics(
      button: true,
      selected: selected,
      label: category.name,
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          splashColor: accent.withValues(alpha: 0.08),
          highlightColor: Colors.transparent,
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: AnimatedContainer(
            duration: reduced ? Duration.zero : VaultMotion.state,
            curve: VaultMotion.settle,
            constraints: const BoxConstraints(minHeight: 92),
            padding: const EdgeInsets.fromLTRB(4, 10, 4, 8),
            decoration: BoxDecoration(
              color: selected ? p.tint(accent, 0.09) : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    AnimatedContainer(
                      duration: reduced ? Duration.zero : VaultMotion.state,
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: selected ? accent : Colors.transparent, width: 1.6),
                      ),
                      child: AnimatedScale(
                        scale: selected ? 1.0 : 0.94,
                        duration: pop,
                        curve: VaultMotion.pop,
                        child: CategoryAvatar(category: category, size: 40),
                      ),
                    ),
                    Positioned(
                      right: -4,
                      top: -4,
                      child: AnimatedScale(
                        scale: selected ? 1 : 0,
                        duration: pop,
                        curve: VaultMotion.pop,
                        child: Container(
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                            color: accent,
                            shape: BoxShape.circle,
                            border: Border.all(color: p.surface, width: 2),
                          ),
                          child: Icon(LucideIcons.check, size: 10, color: p.surface),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                Text(
                  category.name,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: t.caption
                      .copyWith(fontSize: 11.5, height: 1.25)
                      .vw(selected ? 720 : 580)
                      .vc(selected ? p.ink : p.inkSoft),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
