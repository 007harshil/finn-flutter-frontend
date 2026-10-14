import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/di/core_providers.dart';
import '../../../app/di/data_providers.dart';
import '../../../core/money/money_format.dart';
import '../../../core/time/frequency.dart';
import '../../../design_system/design_system.dart';
import '../../../design_system/luxe/luxe.dart';
import '../../../shared/presentation/action_runner.dart';
import '../../../shared/presentation/category_icons.dart';
import '../../categories/domain/category.dart';
import '../../transactions/domain/transaction.dart';
import '../application/subscription_actions.dart';
import '../domain/subscription.dart';
import 'subscription_ui.dart';

/// Expense categories a subscription can use (user categories plus
/// "Uncategorised"), "Subscriptions"-like ones first.
final _subscriptionCategoriesProvider = Provider<List<TransactionCategory>>((ref) {
  final all = ref.watch(categoriesByIdProvider).value?.values ?? const <TransactionCategory>[];
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
          int rank(TransactionCategory c) => c.name.toLowerCase().contains('subscription')
              ? 0
              : (c.id == SystemCategories.uncategorizedExpense ? 2 : 1);
          final r = rank(a).compareTo(rank(b));
          return r != 0 ? r : a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
  return list;
});

/// Add or edit a subscription. Saving never changes the cash balance.
class SubscriptionFormSheet extends ConsumerStatefulWidget {
  const SubscriptionFormSheet({super.key, this.subscriptionId});

  final String? subscriptionId;

  @override
  ConsumerState<SubscriptionFormSheet> createState() => _SubscriptionFormSheetState();
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
    final amount = AmountField.parse(_amount.text);
    if (amount == null || !amount.isPositive) {
      setState(() => _errors = {'amount': 'Enter an amount greater than zero.'});
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
            input: UpdateSubscriptionInput(id: existing.id, expectedVersion: existing.version, data: input),
            idempotencyKey: _key,
            onFieldErrors: onErrors,
          );
    if (!mounted) return;
    setState(() => _busy = false);
    if (result != null) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) => LuxeScope(paint: true, child: Builder(builder: _buildSheet));

  Widget _buildSheet(BuildContext context) {
    final today = ref.watch(todayProvider);
    if (_editing && !_loaded) {
      final s = ref.watch(subscriptionProvider(widget.subscriptionId!)).value;
      if (s != null) _load(s);
    }
    final t = context.text;
    final c = context.colors;
    if (_editing && _existing == null) {
      return const FinnSheetScaffold(
        title: 'Edit subscription',
        child: SkeletonPulse(
          child: Column(
            children: [
              CardSkeleton(height: 60),
              SizedBox(height: Space.x4),
              CardSkeleton(height: 240),
            ],
          ),
        ),
      );
    }
    final categories = ref.watch(_subscriptionCategoriesProvider);
    final categoryId = _categoryId ?? categories.firstOrNull?.id;
    final nextDue = _nextDue ?? today;
    final dueToday = nextDue.year == today.year && nextDue.month == today.month && nextDue.day == today.day;
    final pastDue = nextDue.isBefore(today);

    return FinnSheetScaffold(
      title: _editing ? 'Edit subscription' : 'Add a subscription',
      description: _editing ? _existing!.name : 'Track a recurring cost. Nothing is paid or deducted automatically.',
      footer: FinnButton(
        label: _editing ? 'Save changes' : 'Add subscription',
        icon: _editing ? LucideIcons.check : LucideIcons.plus,
        expand: true,
        loading: _busy,
        onPressed: _busy ? null : () => _submit(categoryId),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FinnTextField(
            label: 'Service name',
            hint: 'e.g. Netflix, Spotify, Jio Postpaid',
            controller: _name,
            prefixIcon: LucideIcons.repeat,
            errorText: _errors['name'],
            maxLength: 60,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: Space.x3),
          AmountField(
            prominent: true,
            label: 'Amount per renewal',
            controller: _amount,
            errorText: _errors['amount'],
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: Space.x5),
          const SubscriptionFieldLabel('Billed'),
          FilterChipBar<Frequency>(
            padding: EdgeInsets.zero,
            multiSelect: false,
            items: [for (final f in Frequency.values) FilterChipItem(f, f.label)],
            selected: {_frequency},
            onChanged: (s) => setState(() => _frequency = s.first),
          ),
          const SizedBox(height: Space.x5),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: DateField(
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
              const SizedBox(width: Space.x3),
              Expanded(
                child: DateField(
                  label: 'Started (optional)',
                  hint: 'Not set',
                  value: _start,
                  firstDate: DateTime(today.year - 30),
                  lastDate: nextDue,
                  errorText: _errors['startDate'],
                  onChanged: (d) => setState(() => _start = d),
                ),
              ),
            ],
          ),
          if (dueToday || pastDue) ...[
            const SizedBox(height: Space.x3),
            InfoBanner(
              tone: FinnTone.warning,
              icon: LucideIcons.bell,
              message: dueToday
                  ? 'A renewal is due today. It is not recorded automatically — mark it as paid once it is charged.'
                  : 'This renewal date has passed. It will show as overdue until you mark it as paid or skip it.',
            ),
          ],
          const SizedBox(height: Space.x5),
          const SubscriptionFieldLabel('Category'),
          if (categories.isEmpty)
            Text('No expense categories available.', style: t.caption)
          else
            FilterChipBar<String>(
              padding: EdgeInsets.zero,
              multiSelect: false,
              items: [
                for (final cat in categories) FilterChipItem(cat.id, cat.name, icon: CategoryIcons.of(cat.iconKey)),
              ],
              selected: {?categoryId},
              onChanged: (s) => setState(() => _categoryId = s.first),
            ),
          if (_errors['categoryId'] != null) ...[
            const SizedBox(height: Space.x1),
            Text(_errors['categoryId']!, style: t.micro.copyWith(color: c.negative)),
          ],
          const SizedBox(height: Space.x5),
          const SubscriptionFieldLabel('Usually paid by (optional)'),
          FilterChipBar<PaymentMethod>(
            padding: EdgeInsets.zero,
            multiSelect: false,
            items: [for (final m in PaymentMethod.values) FilterChipItem(m, m.label, icon: _methodIcon(m))],
            selected: {?_method},
            onChanged: (s) => setState(() => _method = s.first),
          ),
          const SizedBox(height: Space.x4),
          FinnCard(
            variant: FinnCardVariant.outlined,
            padding: const EdgeInsets.fromLTRB(Space.x4, Space.x2, Space.x2, Space.x2),
            child: MergeSemantics(
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Renews automatically', style: t.bodyStrong),
                        const SizedBox(height: 2),
                        Text(
                          _autoRenews
                              ? 'The provider charges you each cycle (e.g. card or UPI autopay).'
                              : 'You renew it yourself each time.',
                          style: t.caption,
                        ),
                      ],
                    ),
                  ),
                  Switch(value: _autoRenews, onChanged: (b) => setState(() => _autoRenews = b)),
                ],
              ),
            ),
          ),
          const SizedBox(height: Space.x4),
          FinnTextField(
            label: 'Note (optional)',
            hint: 'Plan, shared with family, anything to remember',
            controller: _note,
            errorText: _errors['note'],
            maxLines: 3,
            minLines: 2,
            maxLength: 500,
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: Space.x4),
          const InfoBanner(
            message:
                'Saving does not change your balance, and past renewals are not imported. '
                'Each renewal becomes an expense only when you mark it as paid.',
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
