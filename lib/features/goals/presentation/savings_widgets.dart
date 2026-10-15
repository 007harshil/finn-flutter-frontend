import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/core_providers.dart';
import '../../../app/di/data_providers.dart';
import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../kit/kit.dart';
import '../../../shared/presentation/action_runner.dart';

/// Shared presentation pieces for earmarked savings (goals and the
/// emergency fund).

/// Money as text, respecting "hide balances".
String savingsMoney(
  BuildContext context,
  Money m, {
  SignDisplay sign = SignDisplay.auto,
}) => AmountVisibility.hiddenOf(context)
    ? MoneyFormatter.masked
    : m.format(sign: sign);

/// "2.4 months" / "1 month".
String coverageLabel(double months) {
  final s = months.toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '');
  return '$s month${months == 1 ? '' : 's'}';
}

/// Values captured by [SavingsMovementForm].
@immutable
class SavingsMovementDraft {
  const SavingsMovementDraft({
    required this.amount,
    required this.date,
    this.note,
  });
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
  ConsumerState<SavingsMovementForm> createState() =>
      _SavingsMovementFormState();
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
    final amount = LedgerAmountField.parse(_amount.text);
    if (amount == null || !amount.isPositive) {
      setState(
        () => _errors = {'amount': 'Enter an amount greater than zero.'},
      );
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _errors = const {};
    });
    final note = _note.text.trim();
    final ok = await widget.onSubmit(
      SavingsMovementDraft(
        amount: amount,
        date: _date,
        note: note.isEmpty ? null : note,
      ),
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
    final c = context.ink;
    final t = context.type;
    final w = widget;
    final available = ref.watch(
      balanceProvider.select((b) => b.value?.available),
    );
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
    final availAfter = available == null
        ? null
        : (w.withdraw ? available + amount : available - amount);
    final overAvailable =
        !w.withdraw && available != null && amount > available;
    final overSaved = w.withdraw && amount > w.saved;
    return FinnSheetScaffold(
      title: w.withdraw
          ? 'Withdraw from ${w.potName}'
          : 'Add money to ${w.potName}',
      footer: LedgerButton(
        label: w.withdraw ? 'Withdraw' : 'Add money',
        expand: true,
        loading: _submitting,
        onPressed: _submitting || disabled ? null : _submit,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (disabled) ...[
            LedgerNote(text: w.disabledReason!),
            const SizedBox(height: LedgerForm.gap),
          ],
          LedgerAmountField(
            hero: true,
            controller: _amount,
            label: 'Amount',
            autofocus: !disabled,
            enabled: !disabled,
            errorText:
                _errors['amount'] ??
                (overAvailable
                    ? 'More than the ${savingsMoney(context, available)} available.'
                    : overSaved
                    ? 'Only ${savingsMoney(context, w.saved)} is saved here.'
                    : null),
            onChanged: (m) => setState(() {
              _value = m;
              if (_errors.containsKey('amount'))
                _errors = {..._errors}..remove('amount');
            }),
          ),
          const SizedBox(height: Sp.md),
          Wrap(
            spacing: Sp.sm,
            runSpacing: Sp.sm,
            children: [
              for (final (label, value) in quick)
                LedgerChip(
                  label: label,
                  onTap: disabled ? null : () => _setAmount(value),
                  semanticLabel: label == 'Remaining' || label == 'All'
                      ? '$label, ${savingsMoney(context, value)}'
                      : null,
                ),
            ],
          ),
          const SizedBox(height: LedgerForm.gap),
          LedgerPanel(
            children: [
              LedgerFact(
                label: 'Available',
                text: available == null
                    ? '—'
                    : '${savingsMoney(context, available)}  →  ${savingsMoney(context, availAfter!)}',
              ),
              LedgerFact(
                label: w.withdraw ? 'Left here' : 'Saved here',
                value: Text(
                  '${savingsMoney(context, w.saved)}  →  ${savingsMoney(context, savedAfter)}',
                  style: t.body.copyWith(
                    color: savedAfter.isNegative ? c.red : null,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: LedgerForm.gap),
          LedgerDateField(
            label: 'Date',
            value: _date,
            firstDate: DateTime(today.year - 2, today.month, today.day),
            lastDate: today,
            errorText: _errors['date'],
            enabled: !disabled,
            onChanged: (d) => setState(() => _date = d),
          ),
          const SizedBox(height: LedgerForm.gap),
          LedgerTextField(
            controller: _note,
            label: 'Note (optional)',
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

/// Loading placeholder for the movement sheets.
class SavingsMovementSkeleton extends StatelessWidget {
  const SavingsMovementSkeleton({super.key});

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Loading',
    child: const ExcludeSemantics(
      child: Column(
        children: [
          LedgerSkeleton(height: 44),
          SizedBox(height: LedgerForm.gap),
          LedgerSkeleton(height: 96),
          SizedBox(height: LedgerForm.gap),
          LedgerSkeleton(height: 52),
        ],
      ),
    ),
  );
}
