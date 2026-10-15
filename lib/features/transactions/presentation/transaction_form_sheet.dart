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
import '../../../kit/kit.dart';
import '../../../features/transactions/domain/transaction.dart';
import '../../accounts/presentation/widgets/account_picker_field.dart';
import '../../accounts/presentation/widgets/channel_field.dart';
import '../../../shared/presentation/action_runner.dart';
import '../application/transaction_actions.dart';
import '../application/transaction_form_support.dart';

/// Create or edit a manual transaction.
///
/// Editing loads the transaction first; linked transactions (created by
/// loans, subscriptions or settlements) cannot be edited here.
class TransactionFormSheet extends ConsumerWidget {
  const TransactionFormSheet({
    super.key,
    this.transactionId,
    this.initialType = TransactionType.expense,
  });

  final String? transactionId;
  final TransactionType initialType;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = transactionId;
    if (id == null)
      return _TransactionForm(initial: null, initialType: initialType);

    const title = 'Edit transaction';
    final value = ref.watch(transactionByIdProvider(id));
    if (value.hasError && !value.hasValue) {
      final e = value.error;
      return FinnSheetScaffold(
        title: title,
        child: LedgerEmpty(
          title: 'Could not load this transaction',
          message: e is AppFailure ? e.message : 'Please try again.',
          actionLabel: 'Try again',
          onAction: () => refreshFinanceData(ref),
        ),
      );
    }
    if (!value.hasValue) {
      return const FinnSheetScaffold(
        title: title,
        child: Column(
          children: [
            LedgerSkeleton(height: 56),
            SizedBox(height: LedgerForm.gap),
            LedgerSkeleton(height: 200),
          ],
        ),
      );
    }
    final tx = value.requireValue;
    if (tx == null) {
      return const FinnSheetScaffold(
        title: title,
        child: LedgerEmpty(
          title: 'Transaction not found',
          message: 'It may have been deleted.',
        ),
      );
    }
    if (tx.isLinked) {
      return FinnSheetScaffold(
        title: title,
        child: LedgerEmpty(
          title: 'Created by ${tx.origin.label}',
          message: 'Change or reverse it from the linked record to keep balances accurate.',
        ),
      );
    }
    return _TransactionForm(
      key: ValueKey(tx.id),
      initial: tx,
      initialType: tx.type,
    );
  }
}

class _TransactionForm extends ConsumerStatefulWidget {
  const _TransactionForm({
    super.key,
    required this.initial,
    required this.initialType,
  });

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
  // Null until picked: the form shows the default account and sends it.
  String? _accountId;
  String? _channel;

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
      _accountId = t.accountId;
      _channel = t.channel;
      _counterparty.text = t.counterparty ?? '';
      _note.text = t.note ?? '';
      final pickable = ref.read(pickableCategoriesProvider(t.type)).value;
      final usable =
          pickable == null || pickable.any((c) => c.id == t.categoryId);
      if (usable) {
        _categoryId = t.categoryId;
      } else {
        _retiredCategoryName =
            ref.read(categoryProvider(t.categoryId))?.name ??
            'The previous category';
      }
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
      final current = _categoryId == null
          ? null
          : ref.read(categoryProvider(_categoryId!));
      if (current != null && current.type != type) _categoryId = null;
      _errors = Map.of(_errors)..remove('categoryId');
    });
  }

  void _clearError(String field) {
    if (!_errors.containsKey(field)) return;
    setState(() => _errors = Map.of(_errors)..remove(field));
  }

  Future<void> _createCategory() async {
    final created = await context.push<Object?>(
      AppRoutes.newCategory(type: _type),
    );
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
    final amount = LedgerAmountField.parse(_amount.text);
    final local = <String, String>{
      if (amount == null || !amount.isPositive)
        'amount': 'Enter an amount greater than zero.',
      if (_categoryId == null) 'categoryId': 'Choose a category.',
    };
    if (local.isNotEmpty) {
      setState(() => _errors = local);
      if (ref.read(settingsProvider).hapticsEnabled)
        HapticFeedback.heavyImpact();
      return;
    }
    setState(() {
      _errors = const {};
      _submitting = true;
    });

    final accountId = _accountId ?? ref.read(defaultAccountProvider).value?.id;
    final data = TransactionInput(
      type: _type,
      amount: amount!,
      categoryId: _categoryId!,
      date: _date,
      accountId: accountId,
      channel: _channel,
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
        input: UpdateTransactionInput(
          id: initial.id,
          expectedVersion: initial.version,
          data: data,
        ),
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
    await Navigator.of(context).maybePop(saved.id);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    final today = ref.watch(todayProvider);
    final income = _type.isIncome;
    final categories = ref.watch(pickableCategoriesProvider(_type));

    return FinnSheetScaffold(
      title: _editing ? 'Edit transaction' : 'Record transaction',
      footer: LedgerButton(
        label: _editing
            ? 'Save changes'
            : 'Record ${_type.label.toLowerCase()}',
        expand: true,
        loading: _submitting,
        onPressed: _submit,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LedgerSegmented<TransactionType>(
            segments: const [
              LedgerSegment(TransactionType.expense, 'Expense'),
              LedgerSegment(TransactionType.income, 'Income'),
            ],
            selected: _type,
            onChanged: _submitting ? (_) {} : _setType,
          ),
          const SizedBox(height: LedgerForm.gap),
          LedgerAmountField(
            hero: true,
            label: 'Amount',
            controller: _amount,
            autofocus: !_editing,
            errorText: _errors['amount'],
            textInputAction: TextInputAction.next,
            onChanged: (_) => _clearError('amount'),
          ),
          const SizedBox(height: LedgerForm.gap),
          AccountPickerField(
            label: income ? 'Received in' : 'Paid from',
            value: _accountId ?? ref.watch(defaultAccountProvider).value?.id,
            errorText: _errors['accountId'],
            onChanged: (id) => setState(() {
              _accountId = id;
              _errors = Map.of(_errors)..remove('accountId');
            }),
          ),
          const SizedBox(height: LedgerForm.gap),
          if (_retiredCategoryName != null && _categoryId == null) ...[
            LedgerNote(
              tone: NoteTone.caution,
              text:
                  '$_retiredCategoryName is no longer available. Choose another category.',
            ),
            const SizedBox(height: Sp.sm),
          ],
          switch (categories) {
            AsyncValue(:final value?) => LedgerPickerField<String>(
              label: 'Category',
              hint: 'Choose a category',
              searchHint: 'Search categories',
              value: _categoryId,
              errorText: _errors['categoryId'],
              options: [
                for (final cat in value)
                  LedgerOption(
                    cat.id,
                    cat.name,
                    key: ValueKey(cat.id),
                    leading: CategoryMark(category: cat),
                  ),
              ],
              onChanged: (id) => setState(() {
                _categoryId = id;
                _errors = Map.of(_errors)..remove('categoryId');
              }),
            ),
            AsyncValue(hasError: true) => Text(
              'Categories could not be loaded.',
              style: t.label,
            ),
            _ => const LedgerSkeleton(height: 52),
          },
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: LedgerButton(
              label: 'New category',
              icon: LucideIcons.plus,
              variant: LedgerButtonVariant.quiet,
              small: true,
              onPressed: _submitting ? null : _createCategory,
            ),
          ),
          const SizedBox(height: Sp.sm),
          LedgerDateField(
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
          const SizedBox(height: LedgerForm.gap),
          ChannelField(
            value: _channel,
            errorText: _errors['channel'],
            onChanged: (v) {
              _channel = v;
              _clearError('channel');
            },
          ),
          const SizedBox(height: LedgerForm.gap),
          LedgerTextField(
            label: income ? 'Received from' : 'Paid to',
            hint: income
                ? 'e.g. Employer, client, Priya'
                : 'e.g. Swiggy, DMart, landlord',
            controller: _counterparty,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            errorText: _errors['counterparty'],
            onChanged: (_) => _clearError('counterparty'),
          ),
          const SizedBox(height: LedgerForm.gap),
          LedgerTextField(
            label: 'Note (optional)',
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
