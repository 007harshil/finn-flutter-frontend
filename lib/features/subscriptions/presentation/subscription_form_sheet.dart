import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/di/core_providers.dart';
import '../../../app/di/data_providers.dart';
import '../../../core/money/money_format.dart';
import '../../../core/time/frequency.dart';
import '../../../kit/kit.dart';
import '../../../shared/presentation/action_runner.dart';
import '../../../shared/presentation/category_icons.dart';
import '../../categories/domain/category.dart';
import '../../transactions/domain/transaction.dart';
import '../application/subscription_actions.dart';
import '../domain/subscription.dart';

/// Expense categories a subscription can use (user categories plus
/// "Uncategorised"), "Subscriptions"-like ones first.
final _subscriptionCategoriesProvider = Provider<List<TransactionCategory>>((
  ref,
) {
  final all =
      ref.watch(categoriesByIdProvider).value?.values ??
      const <TransactionCategory>[];
  final list =
      all
          .where(
            (c) =>
                c.type == TransactionType.expense &&
                !c.isArchived &&
                (!c.isSystem || c.id == SystemCategories.uncategorizedExpense),
          )
          .toList()
        ..sort((a, b) {
          int rank(TransactionCategory c) =>
              c.name.toLowerCase().contains('subscription')
              ? 0
              : (c.id == SystemCategories.uncategorizedExpense ? 2 : 1);
          final r = rank(a).compareTo(rank(b));
          return r != 0
              ? r
              : a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
  return list;
});

/// Add or edit a subscription. Saving never changes the cash balance.
class SubscriptionFormSheet extends ConsumerStatefulWidget {
  const SubscriptionFormSheet({super.key, this.subscriptionId});

  final String? subscriptionId;

  @override
  ConsumerState<SubscriptionFormSheet> createState() =>
      _SubscriptionFormSheetState();
}

class _SubscriptionFormSheetState extends ConsumerState<SubscriptionFormSheet> {
  final _key = newIdempotencyKey();
  final _name = TextEditingController();
  final _amount = TextEditingController();
  final _note = TextEditingController();

  Frequency _frequency = Frequency.monthly;
  DateTime? _nextDue;
  DateTime? _start;
  String? _categoryId;
  PaymentMethod? _method;
  bool _autoRenews = true;
  Map<String, String> _errors = const {};
  bool _busy = false;
  bool _loaded = false;
  Subscription? _existing;

  bool get _editing => widget.subscriptionId != null;

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  void _load(Subscription s) {
    _existing = s;
    _name.text = s.name;
    _amount.text = MoneyFormatter.editable(s.amount);
    _note.text = s.note ?? '';
    _frequency = s.frequency;
    _nextDue = s.nextDueDate;
    _start = s.startDate;
    _categoryId = s.categoryId;
    _method = s.paymentMethod;
    _autoRenews = s.autoRenews;
    _loaded = true;
  }

  Future<void> _submit(String? categoryId) async {
    final today = ref.read(todayProvider);
    final amount = LedgerAmountField.parse(_amount.text);
    if (amount == null || !amount.isPositive) {
      setState(
        () => _errors = {'amount': 'Enter an amount greater than zero.'},
      );
      return;
    }
    final note = _note.text.trim();
    final input = SubscriptionInput(
      name: _name.text.trim(),
      amount: amount,
      categoryId: categoryId ?? '',
      frequency: _frequency,
      nextDueDate: _nextDue ?? today,
      startDate: _start,
      autoRenews: _autoRenews,
      paymentMethod: _method,
      note: note.isEmpty ? null : note,
    );
    setState(() {
      _busy = true;
      _errors = const {};
    });
    void onErrors(Map<String, String> e) => setState(() => _errors = e);
    final existing = _existing;
    final Object? result = existing == null
        ? await runAction(
            context,
            ref,
            action: const CreateSubscriptionAction(),
            input: input,
            idempotencyKey: _key,
            onFieldErrors: onErrors,
          )
        : await runAction(
            context,
            ref,
            action: const UpdateSubscriptionAction(),
            input: UpdateSubscriptionInput(
              id: existing.id,
              expectedVersion: existing.version,
              data: input,
            ),
            idempotencyKey: _key,
            onFieldErrors: onErrors,
          );
    if (!mounted) return;
    setState(() => _busy = false);
    if (result != null) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final today = ref.watch(todayProvider);
    if (_editing && !_loaded) {
      final s = ref.watch(subscriptionProvider(widget.subscriptionId!)).value;
      if (s != null) _load(s);
    }
    if (_editing && _existing == null) {
      return const FinnSheetScaffold(
        title: 'Edit subscription',
        child: _FormSkeleton(),
      );
    }
    final categories = ref.watch(_subscriptionCategoriesProvider);
    final categoryId = _categoryId ?? categories.firstOrNull?.id;
    final nextDue = _nextDue ?? today;
    final dueToday =
        nextDue.year == today.year &&
        nextDue.month == today.month &&
        nextDue.day == today.day;
    final pastDue = nextDue.isBefore(today);

    return FinnSheetScaffold(
      title: _editing ? 'Edit subscription' : 'New subscription',
      description: 'Saving never changes your balance. A renewal becomes an expense when you mark it paid.',
      footer: LedgerButton(
        label: _editing ? 'Save changes' : 'Add subscription',
        expand: true,
        loading: _busy,
        onPressed: _busy ? null : () => _submit(categoryId),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LedgerAmountField(
            hero: true,
            label: 'Amount per renewal',
            controller: _amount,
            errorText: _errors['amount'],
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: LedgerForm.gap),
          LedgerTextField(
            label: 'Name',
            hint: 'e.g. Netflix, Spotify',
            controller: _name,
            errorText: _errors['name'],
            maxLength: 60,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: LedgerForm.gap),
          LedgerField(
            label: 'Billed',
            child: LedgerChoiceChips<Frequency>(
              options: [
                for (final f in Frequency.values) LedgerOption(f, f.label),
              ],
              selected: _frequency,
              onChanged: (f) => setState(() => _frequency = f),
            ),
          ),
          const SizedBox(height: LedgerForm.gap),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: LedgerDateField(
                  label: 'Next renewal',
                  value: nextDue,
                  firstDate: DateTime(today.year - 1, today.month, today.day),
                  lastDate: DateTime(today.year + 2, today.month, today.day),
                  errorText: _errors['nextDueDate'],
                  onChanged: (d) => setState(() {
                    _nextDue = d;
                    if (_start != null && _start!.isAfter(d)) _start = null;
                  }),
                ),
              ),
              const SizedBox(width: Sp.md),
              Expanded(
                child: LedgerDateField(
                  label: 'Started (optional)',
                  hint: 'Not set',
                  value: _start,
                  firstDate: DateTime(today.year - 30),
                  lastDate: nextDue,
                  errorText: _errors['startDate'],
                  onClear: () => setState(() => _start = null),
                  onChanged: (d) => setState(() => _start = d),
                ),
              ),
            ],
          ),
          if (dueToday || pastDue) ...[
            const SizedBox(height: Sp.md),
            LedgerNote(
              tone: NoteTone.caution,
              icon: LucideIcons.bell,
              text: dueToday ? 'Due today. Mark it paid once it is charged.' : 'This date has passed. It shows as overdue until you mark it paid or skip it.',
            ),
          ],
          const SizedBox(height: LedgerForm.groupGap),
          LedgerPickerField<String>(
            label: 'Category',
            hint: categories.isEmpty ? 'No expense categories' : 'Choose',
            enabled: categories.isNotEmpty,
            value: categoryId,
            errorText: _errors['categoryId'],
            options: [
              for (final cat in categories)
                LedgerOption(
                  cat.id,
                  cat.name,
                  icon: CategoryIcons.of(cat.iconKey),
                ),
            ],
            onChanged: (id) => setState(() => _categoryId = id),
          ),
          const SizedBox(height: LedgerForm.gap),
          LedgerField(
            label: 'Usually paid by (optional)',
            child: LedgerChoiceChips<PaymentMethod>(
              options: [
                for (final m in PaymentMethod.values)
                  LedgerOption(m, m.label, icon: _methodIcon(m)),
              ],
              selected: _method,
              onChanged: (m) => setState(() => _method = m),
            ),
          ),
          const SizedBox(height: LedgerForm.gap),
          LedgerSwitchRow(
            title: 'Renews automatically',
            subtitle: _autoRenews
                ? 'The provider charges you each cycle.'
                : 'You renew it yourself each time.',
            value: _autoRenews,
            onChanged: (b) => setState(() => _autoRenews = b),
          ),
          const SizedBox(height: LedgerForm.gap),
          LedgerTextField(
            label: 'Note (optional)',
            controller: _note,
            errorText: _errors['note'],
            maxLines: 3,
            minLines: 2,
            maxLength: 500,
            textCapitalization: TextCapitalization.sentences,
          ),
        ],
      ),
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
            LedgerSkeleton(width: 200, height: 44),
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

IconData _methodIcon(PaymentMethod m) => switch (m) {
  PaymentMethod.upi => LucideIcons.smartphone,
  PaymentMethod.card => LucideIcons.creditCard,
  PaymentMethod.cash => LucideIcons.banknote,
  PaymentMethod.bankTransfer => LucideIcons.landmark,
  PaymentMethod.wallet => LucideIcons.wallet,
  PaymentMethod.other => LucideIcons.circleDot,
};
