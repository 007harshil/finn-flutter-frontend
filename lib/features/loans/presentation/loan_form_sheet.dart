import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/di/core_providers.dart';
import '../../../app/di/data_providers.dart';
import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/time/dates.dart';
import '../../../core/time/frequency.dart';
import '../../../kit/kit.dart';
import '../../../shared/presentation/action_runner.dart';
import '../application/loan_actions.dart';
import '../application/loan_quote.dart';
import '../domain/loan.dart';
import '../domain/loan_calculator.dart';
import 'loan_ui.dart';

const _frequencies = [
  Frequency.monthly,
  Frequency.quarterly,
  Frequency.halfYearly,
  Frequency.yearly,
];

/// Add or edit a loan. Terms are locked once payments are recorded.
class LoanFormSheet extends ConsumerStatefulWidget {
  const LoanFormSheet({super.key, this.loanId});

  final String? loanId;

  @override
  ConsumerState<LoanFormSheet> createState() => _LoanFormSheetState();
}

class _LoanFormSheetState extends ConsumerState<LoanFormSheet> {
  final _key = newIdempotencyKey();
  final _name = TextEditingController();
  final _counterparty = TextEditingController();
  final _principal = TextEditingController();
  final _rate = TextEditingController();
  final _tenure = TextEditingController();
  final _note = TextEditingController();

  LoanDirection _direction = LoanDirection.borrowed;
  LoanStructure _structure = LoanStructure.amortizing;
  Frequency _frequency = Frequency.monthly;
  PrepaymentStrategy _prepayment = PrepaymentStrategy.reduceTenure;
  DateTime? _start;
  DateTime? _firstDue;
  DateTime? _maturity;
  bool _recordDisbursement = false;
  Map<String, String> _errors = const {};
  bool _busy = false;
  bool _loaded = false;
  LoanState? _existing;

  bool get _editing => widget.loanId != null;

  /// Terms cannot change once payments exist.
  bool get _termsLocked => (_existing?.payments.isNotEmpty ?? false);

  @override
  void dispose() {
    _name.dispose();
    _counterparty.dispose();
    _principal.dispose();
    _rate.dispose();
    _tenure.dispose();
    _note.dispose();
    super.dispose();
  }

  void _load(LoanState s) {
    final l = s.loan;
    _existing = s;
    _direction = l.direction;
    _structure = l.structure;
    _frequency = l.frequency;
    _prepayment = l.prepaymentStrategy;
    _start = l.startDate;
    _firstDue = l.firstDueDate;
    _maturity = l.maturityDate;
    _name.text = l.name;
    _counterparty.text = l.counterparty;
    _principal.text = MoneyFormatter.editable(l.principal);
    _rate.text = l.rate.label.replaceAll('%', '');
    _tenure.text = l.tenureInstallments?.toString() ?? '';
    _note.text = l.note ?? '';
    _loaded = true;
  }

  DateTime _startOr(DateTime today) => _start ?? today;

  DateTime _firstDueOr(DateTime today) =>
      _firstDue ?? _frequency.next(_startOr(today));

  /// Current form values; unparsable numbers become zero / null.
  LoanInput _input(DateTime today) {
    final note = _note.text.trim();
    return LoanInput(
      name: _name.text.trim(),
      counterparty: _counterparty.text.trim(),
      direction: _direction,
      structure: _structure,
      principal: LedgerAmountField.parse(_principal.text) ?? Money.zero,
      rate: InterestRate.tryParse(_rate.text) ?? const InterestRate(-1),
      startDate: _startOr(today),
      firstDueDate: _firstDueOr(today),
      frequency: _frequency,
      tenureInstallments: _structure == LoanStructure.amortizing
          ? int.tryParse(_tenure.text.trim())
          : null,
      maturityDate: _structure == LoanStructure.interestOnly ? _maturity : null,
      prepaymentStrategy: _prepayment,
      recordDisbursement: !_editing && _recordDisbursement,
      note: note.isEmpty ? null : note,
    );
  }

  Future<void> _submit() async {
    final today = ref.read(todayProvider);
    final local = <String, String>{
      if ((LedgerAmountField.parse(_principal.text) ?? Money.zero).isZero)
        'principal': 'Enter the loan amount.',
      if (InterestRate.tryParse(_rate.text) == null)
        'rate': 'Enter the annual rate, e.g. 10.5 (0 if interest-free).',
      if (_structure == LoanStructure.amortizing &&
          int.tryParse(_tenure.text.trim()) == null)
        'tenureInstallments': 'Enter the number of instalments.',
    };
    if (local.isNotEmpty) {
      setState(() => _errors = local);
      return;
    }
    final input = _input(today);
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
            action: const CreateLoanAction(),
            input: input,
            idempotencyKey: _key,
            successTitle: '${input.name} added',
            onFieldErrors: onErrors,
          )
        : await runAction(
            context,
            ref,
            action: const UpdateLoanAction(),
            input: UpdateLoanInput(
              id: existing.loan.id,
              expectedVersion: existing.loan.version,
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
      final s = ref.watch(loanStateProvider(widget.loanId!)).value;
      if (s != null) _load(s);
    }
    if (_editing && _existing == null) {
      return const FinnSheetScaffold(
        title: 'Edit loan',
        child: _FormSkeleton(),
      );
    }
    final locked = _termsLocked;
    final borrowed = _direction == LoanDirection.borrowed;
    final amortizing = _structure == LoanStructure.amortizing;
    final start = _startOr(today);
    final firstDue = _firstDueOr(today);
    final quote = LoanQuote.of(_input(today));

    return FinnSheetScaffold(
      title: _editing ? 'Edit loan' : 'New loan',
      footer: LedgerButton(
        label: _editing ? 'Save changes' : 'Add loan',
        expand: true,
        loading: _busy,
        onPressed: _busy ? null : _submit,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (locked) ...[
            const LedgerNote(
              icon: LucideIcons.lock,
              text: 'Payments exist, so amount, rate, dates and tenure are locked.',
            ),
            const SizedBox(height: LedgerForm.groupGap),
          ],
          LedgerAmountField(
            hero: true,
            label: borrowed ? 'Amount borrowed' : 'Amount lent',
            controller: _principal,
            errorText: _errors['principal'],
            enabled: !locked,
            textInputAction: TextInputAction.next,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: LedgerForm.gap),
          LedgerField(
            label: 'Direction',
            helper: borrowed
                ? 'You repay this. It counts as debt.'
                : 'Someone repays you.',
            child: _editing
                ? _LockedValue(icon: _direction.icon, label: _direction.pill)
                : LedgerSegmented<LoanDirection>(
                    segments: const [
                      LedgerSegment(LoanDirection.borrowed, 'I borrowed'),
                      LedgerSegment(LoanDirection.lent, 'I lent'),
                    ],
                    selected: _direction,
                    onChanged: (d) => setState(() => _direction = d),
                  ),
          ),
          const SizedBox(height: LedgerForm.gap),
          LedgerTextField(
            label: 'Name',
            hint: borrowed ? 'e.g. Car loan' : 'e.g. Bike down payment',
            controller: _name,
            errorText: _errors['name'],
            maxLength: 60,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: LedgerForm.gap),
          LedgerTextField(
            label: borrowed ? 'Lender' : 'Borrower',
            hint: borrowed ? 'e.g. HDFC Bank' : 'Name',
            controller: _counterparty,
            errorText: _errors['counterparty'],
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: LedgerForm.groupGap),
          LedgerField(
            label: 'Repayment type',
            helper: _structure.description,
            child: IgnorePointer(
              ignoring: locked,
              child: Opacity(
                opacity: locked ? 0.6 : 1,
                child: LedgerSegmented<LoanStructure>(
                  segments: const [
                    LedgerSegment(LoanStructure.amortizing, 'EMI loan'),
                    LedgerSegment(LoanStructure.interestOnly, 'Interest-only'),
                  ],
                  selected: _structure,
                  onChanged: (s) => setState(() => _structure = s),
                ),
              ),
            ),
          ),
          const SizedBox(height: LedgerForm.gap),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: LedgerTextField(
                  label: 'Rate (% p.a.)',
                  hint: '0 if none',
                  controller: _rate,
                  prefixIcon: LucideIcons.percent,
                  errorText: _errors['rate'],
                  enabled: !locked,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  textInputAction: TextInputAction.next,
                  onChanged: (_) => setState(() {}),
                ),
              ),
              if (amortizing) ...[
                const SizedBox(width: Sp.md),
                Expanded(
                  child: LedgerTextField(
                    label: 'Instalments',
                    hint: 'e.g. 60',
                    controller: _tenure,
                    errorText: _errors['tenureInstallments'],
                    enabled: !locked,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(3),
                    ],
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: LedgerForm.gap),
          LedgerField(
            label: amortizing ? 'EMI frequency' : 'Interest paid',
            errorText: _errors['frequency'],
            child: LedgerChoiceChips<Frequency>(
              options: [for (final f in _frequencies) LedgerOption(f, f.label)],
              selected: _frequency,
              enabled: !locked,
              onChanged: (f) => setState(() => _frequency = f),
            ),
          ),
          const SizedBox(height: LedgerForm.gap),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: LedgerDateField(
                  label: borrowed ? 'Received on' : 'Given on',
                  value: start,
                  firstDate: DateTime(today.year - 40),
                  lastDate: today,
                  enabled: !locked,
                  errorText: _errors['startDate'],
                  onChanged: (d) => setState(() {
                    _start = d;
                    if (_firstDue != null && _firstDue!.isBefore(d))
                      _firstDue = null;
                  }),
                ),
              ),
              const SizedBox(width: Sp.md),
              Expanded(
                child: LedgerDateField(
                  label: amortizing ? 'First EMI due' : 'First interest due',
                  value: firstDue,
                  firstDate: start,
                  lastDate: DateTime(start.year + 5, start.month, start.day),
                  enabled: !locked,
                  errorText: _errors['firstDueDate'],
                  onChanged: (d) => setState(() => _firstDue = d),
                ),
              ),
            ],
          ),
          if (!amortizing) ...[
            const SizedBox(height: LedgerForm.gap),
            LedgerDateField(
              label: 'Principal due (optional)',
              hint: 'No fixed date',
              value: _maturity,
              firstDate: firstDue,
              lastDate: DateTime(today.year + 40),
              errorText: _errors['maturityDate'],
              onClear: () => setState(() => _maturity = null),
              onChanged: (d) => setState(() => _maturity = d),
            ),
          ],
          if (quote != null) ...[
            const SizedBox(height: LedgerForm.groupGap),
            _Quote(quote: quote, frequency: _frequency),
          ],
          if (amortizing) ...[
            const SizedBox(height: LedgerForm.groupGap),
            LedgerField(
              label: 'If you prepay',
              helper: _prepayment.description,
              child: LedgerSegmented<PrepaymentStrategy>(
                segments: [
                  for (final p in PrepaymentStrategy.values)
                    LedgerSegment(p, p.label),
                ],
                selected: _prepayment,
                onChanged: (p) => setState(() => _prepayment = p),
              ),
            ),
          ],
          if (!_editing) ...[
            const SizedBox(height: LedgerForm.gap),
            LedgerSwitchRow(
              title: borrowed ? 'Record money received' : 'Record money given',
              subtitle: _recordDisbursement
                  ? (borrowed
                        ? 'Adds the amount to your balance once.'
                        : 'Takes the amount out of your balance once.')
                  : 'Off for a loan from before FiNN. Balance unchanged.',
              value: _recordDisbursement,
              onChanged: (b) => setState(() => _recordDisbursement = b),
            ),
          ],
          const SizedBox(height: LedgerForm.gap),
          LedgerTextField(
            label: 'Notes (optional)',
            controller: _note,
            errorText: _errors['note'],
            maxLines: 3,
            minLines: 2,
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

class _LockedValue extends StatelessWidget {
  const _LockedValue({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final t = context.type;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Sp.lg - 2,
        vertical: Sp.md + 2,
      ),
      decoration: BoxDecoration(color: c.sunken, borderRadius: Rad.rMd),
      child: Row(
        children: [
          Icon(icon, size: 18, color: c.ink),
          const SizedBox(width: Sp.sm + 2),
          Expanded(child: Text(label, style: t.body)),
          Icon(LucideIcons.lock, size: 16, color: c.inkSoft),
        ],
      ),
    );
  }
}

/// Live estimate of the regular payment (projected, from the calculator).
class _Quote extends StatelessWidget {
  const _Quote({required this.quote, required this.frequency});

  final LoanQuote quote;
  final Frequency frequency;

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    final q = quote;
    if (q.neverRepays) {
      return const LedgerNote(
        tone: NoteTone.caution,
        icon: LucideIcons.triangleAlert,
        text: 'At this rate and tenure the EMI would not cover the interest. Try more instalments or check the rate.',
      );
    }
    final amortizing = q.structure == LoanStructure.amortizing;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const LedgerFieldLabel('Estimate'),
        LedgerPanel(
          children: [
            LedgerFact(
              label: amortizing
                  ? '${frequency.label} EMI'
                  : 'Interest per ${frequency.unit}',
              value: AmountText(q.installment, style: t.bodyStrong),
            ),
            if (q.totalInterest != null)
              LedgerFact(
                label: 'Total interest',
                value: AmountText(q.totalInterest!, style: t.bodyStrong),
              ),
            if (q.totalPayable != null)
              LedgerFact(
                label: 'Total repayable',
                value: AmountText(q.totalPayable!, style: t.bodyStrong),
              ),
            if (q.lastDueDate != null)
              LedgerFact(
                label: 'Last EMI',
                text: DateFormats.dayMonthYear.format(q.lastDueDate!),
              ),
          ],
        ),
        const SizedBox(height: Sp.xs + 2),
        Text(
          amortizing
              ? 'EMI rounded up to the next rupee; the last instalment is adjusted.'
              : 'Principal is repaid separately, in one go or in parts.',
          style: t.small,
        ),
      ],
    );
  }
}
