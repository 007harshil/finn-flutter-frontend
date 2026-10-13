import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/di/core_providers.dart';
import '../../../app/di/data_providers.dart';
import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/presentation/action_runner.dart';

/// Shared presentation pieces for earmarked savings (goals and the
/// emergency fund).

/// Money as text, respecting "hide balances".
String savingsMoney(BuildContext context, Money m, {SignDisplay sign = SignDisplay.auto}) =>
    AmountVisibility.hiddenOf(context) ? MoneyFormatter.masked : m.format(sign: sign);

/// "2.4 months" / "1 month".
String coverageLabel(double months) {
  final s = months.toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '');
  return '$s month${months == 1 ? '' : 's'}';
}

/// Values captured by [SavingsMovementForm].
@immutable
class SavingsMovementDraft {
  const SavingsMovementDraft({required this.amount, required this.date, this.note});
  final Money amount;
  final DateTime date;
  final String? note;
}

/// Submits a draft; returns true on success. Field errors are reported via
/// [onFieldErrors].
typedef SavingsMovementSubmit = Future<bool> Function(
  SavingsMovementDraft draft,
  String idempotencyKey,
  void Function(Map<String, String> errors) onFieldErrors,
);

/// Sheet body for adding to / withdrawing from an earmarked pot, with quick
/// amounts and a live preview of "available to spend".
class SavingsMovementForm extends ConsumerStatefulWidget {
  const SavingsMovementForm({
    super.key,
    required this.withdraw,
    required this.potName,
    required this.saved,
    required this.target,
    required this.onSubmit,
    this.disabledReason,
  });

  final bool withdraw;

  /// e.g. "Japan trip" or "emergency fund".
  final String potName;
  final Money saved;
  final Money target;
  final SavingsMovementSubmit onSubmit;

  /// When set, the form is read-only and explains why.
  final String? disabledReason;

  @override
  ConsumerState<SavingsMovementForm> createState() => _SavingsMovementFormState();
}

class _SavingsMovementFormState extends ConsumerState<SavingsMovementForm> {
  final _key = newIdempotencyKey();
  final _amount = TextEditingController();
  final _note = TextEditingController();
  late DateTime _date = ref.read(todayProvider);
  Money? _value;
  Map<String, String> _errors = const {};
  bool _submitting = false;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  void _setAmount(Money m) {
    _amount.text = MoneyFormatter.editable(m);
    _amount.selection = TextSelection.collapsed(offset: _amount.text.length);
    setState(() {
      _value = m;
      _errors = {..._errors}..remove('amount');
    });
  }

  Future<void> _submit() async {
    final amount = AmountField.parse(_amount.text);
    if (amount == null || !amount.isPositive) {
      setState(() => _errors = {'amount': 'Enter an amount greater than zero.'});
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _errors = const {};
    });
    final note = _note.text.trim();
    final ok = await widget.onSubmit(
      SavingsMovementDraft(amount: amount, date: _date, note: note.isEmpty ? null : note),
      _key,
      (e) {
        if (mounted) setState(() => _errors = e);
      },
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (ok) await Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final w = widget;
    final available = ref.watch(balanceProvider.select((b) => b.value?.available));
    final today = ref.watch(todayProvider);
    final amount = _value ?? Money.zero;
    final remaining = Money.max(w.target - w.saved, Money.zero);
    final disabled = w.disabledReason != null;
    final quick = <(String, Money)>[
      ('₹1,000', const Money.rupees(1000)),
      ('₹5,000', const Money.rupees(5000)),
      ('₹10,000', const Money.rupees(10000)),
      if (!w.withdraw && remaining.isPositive) ('Remaining', remaining),
      if (w.withdraw && w.saved.isPositive) ('All', w.saved),
    ];
    final savedAfter = w.withdraw ? w.saved - amount : w.saved + amount;
    final availAfter = available == null ? null : (w.withdraw ? available + amount : available - amount);
    return FinnSheetScaffold(
      title: w.withdraw ? 'Withdraw from ${w.potName}' : 'Add money to ${w.potName}',
      description: w.withdraw
          ? 'Moves earmarked money back to your available balance. It is not income.'
          : 'Sets aside money you already have. It is not spending, and your net worth stays the same.',
      footer: FinnButton(
        label: w.withdraw ? 'Withdraw' : 'Add money',
        icon: w.withdraw ? LucideIcons.arrowUpRight : LucideIcons.arrowDownLeft,
        expand: true,
        size: FinnButtonSize.lg,
        variant: w.withdraw ? FinnButtonVariant.primary : FinnButtonVariant.positive,
        loading: _submitting,
        onPressed: _submitting || disabled ? null : _submit,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (disabled) ...[
            InfoBanner(message: w.disabledReason!, tone: FinnTone.info),
            const SizedBox(height: Space.x4),
          ],
          AmountField(
            controller: _amount,
            label: 'Amount',
            autofocus: !disabled,
            enabled: !disabled,
            errorText: _errors['amount'],
            onChanged: (m) => setState(() {
              _value = m;
              if (_errors.containsKey('amount')) _errors = {..._errors}..remove('amount');
            }),
          ),
          const SizedBox(height: Space.x3),
          Wrap(
            spacing: Space.x2,
            runSpacing: Space.x2,
            children: [
              for (final (label, value) in quick)
                ActionChip(
                  label: Text(label),
                  onPressed: disabled ? null : () => _setAmount(value),
                  tooltip: label == 'Remaining' || label == 'All' ? savingsMoney(context, value) : null,
                ),
            ],
          ),
          const SizedBox(height: Space.x4),
          FinnCard(
            variant: FinnCardVariant.muted,
            padding: const EdgeInsets.symmetric(horizontal: Space.x4, vertical: Space.x2),
            child: Column(
              children: [
                KeyValueRow(
                  label: 'Available to spend',
                  value: available == null
                      ? '—'
                      : '${savingsMoney(context, available)}  →  ${savingsMoney(context, availAfter!)}',
                  valueColor: availAfter != null && availAfter.isNegative ? c.negative : null,
                ),
                KeyValueRow(
                  label: w.withdraw ? 'Left in ${w.potName}' : 'Saved in ${w.potName}',
                  value: '${savingsMoney(context, w.saved)}  →  ${savingsMoney(context, savedAfter)}',
                  valueColor: savedAfter.isNegative ? c.negative : null,
                ),
              ],
            ),
          ),
          if (!w.withdraw && available != null && amount > available) ...[
            const SizedBox(height: Space.x2),
            Text(
              'That is more than your available ${savingsMoney(context, available)}.',
              style: t.caption.copyWith(color: c.negative),
            ),
          ],
          if (w.withdraw && amount > w.saved) ...[
            const SizedBox(height: Space.x2),
            Text(
              'Only ${savingsMoney(context, w.saved)} is saved here.',
              style: t.caption.copyWith(color: c.negative),
            ),
          ],
          const SizedBox(height: Space.x4),
          DateField(
            label: 'Date',
            value: _date,
            firstDate: DateTime(today.year - 2, today.month, today.day),
            lastDate: today,
            errorText: _errors['date'],
            enabled: !disabled,
            onChanged: (d) => setState(() => _date = d),
          ),
          const SizedBox(height: Space.x4),
          FinnTextField(
            controller: _note,
            label: 'Note (optional)',
            hint: w.withdraw ? 'e.g. Visa fee' : 'e.g. Diwali bonus',
            errorText: _errors['note'],
            enabled: !disabled,
            maxLength: 200,
            textCapitalization: TextCapitalization.sentences,
          ),
        ],
      ),
    );
  }
}
