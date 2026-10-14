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
import '../../../design_system/design_system.dart';
import '../../../shared/presentation/action_runner.dart';
import '../application/loan_actions.dart';
import '../application/loan_quote.dart';
import '../domain/loan.dart';
import '../domain/loan_calculator.dart';
import 'loan_ui.dart';

const _frequencies = [Frequency.monthly, Frequency.quarterly, Frequency.halfYearly, Frequency.yearly];

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

  DateTime _firstDueOr(DateTime today) => _firstDue ?? _frequency.next(_startOr(today));

  /// Current form values; unparsable numbers become zero / null.
  LoanInput _input(DateTime today) {
    final note = _note.text.trim();
    return LoanInput(
      name: _name.text.trim(),
      counterparty: _counterparty.text.trim(),
      direction: _direction,
      structure: _structure,
      principal: AmountField.parse(_principal.text) ?? Money.zero,
      rate: InterestRate.tryParse(_rate.text) ?? const InterestRate(-1),
      startDate: _startOr(today),
      firstDueDate: _firstDueOr(today),
      frequency: _frequency,
      tenureInstallments: _structure == LoanStructure.amortizing ? int.tryParse(_tenure.text.trim()) : null,
      maturityDate: _structure == LoanStructure.interestOnly ? _maturity : null,
      prepaymentStrategy: _prepayment,
      recordDisbursement: !_editing && _recordDisbursement,
      note: note.isEmpty ? null : note,
    );
  }

  Future<void> _submit() async {
    final today = ref.read(todayProvider);
    final local = <String, String>{
      if ((AmountField.parse(_principal.text) ?? Money.zero).isZero) 'principal': 'Enter the loan amount.',
      if (InterestRate.tryParse(_rate.text) == null) 'rate': 'Enter the annual rate, e.g. 10.5 (0 if interest-free).',
      if (_structure == LoanStructure.amortizing && int.tryParse(_tenure.text.trim()) == null)
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
        ? await runAction(context, ref,
            action: const CreateLoanAction(),
            input: input,
            idempotencyKey: _key,
            successTitle: '${input.name} added',
            onFieldErrors: onErrors)
        : await runAction(context, ref,
            action: const UpdateLoanAction(),
            input: UpdateLoanInput(id: existing.loan.id, expectedVersion: existing.loan.version, data: input),
            idempotencyKey: _key,
            onFieldErrors: onErrors);
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
    final t = context.text;
    final c = context.colors;
    if (_editing && _existing == null) {
      return const FinnSheetScaffold(
        title: 'Edit loan',
        child: SkeletonPulse(child: Column(children: [CardSkeleton(height: 60), SizedBox(height: Space.x4), CardSkeleton(height: 280)])),
      );
    }
    final locked = _termsLocked;
    final borrowed = _direction == LoanDirection.borrowed;
    final amortizing = _structure == LoanStructure.amortizing;
    final start = _startOr(today);
    final firstDue = _firstDueOr(today);
    final quote = LoanQuote.of(_input(today));

    return FinnSheetScaffold(
      title: _editing ? 'Edit loan' : 'Add a loan',
      description: _editing
          ? _existing!.loan.name
          : 'Track an EMI loan or money borrowed from or lent to someone you know.',
      footer: FinnButton(
        label: _editing ? 'Save changes' : 'Add loan',
        icon: _editing ? LucideIcons.check : LucideIcons.plus,
        expand: true,
        loading: _busy,
        onPressed: _busy ? null : _submit,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (locked) ...[
            const InfoBanner(
              icon: LucideIcons.lock,
              message: 'Payments are recorded on this loan, so its amount, rate, dates and tenure are locked. '
                  'You can still edit the name, lender, notes and prepayment preference.',
            ),
            const SizedBox(height: Space.x5),
          ],
          const LoanFieldLabel('Direction'),
          if (_editing)
            _LockedValue(icon: _direction.icon, color: _direction.color(c), label: _direction.pill)
          else
            SegmentedTabs<LoanDirection>(
              items: const [
                SegmentItem(LoanDirection.borrowed, 'I borrowed'),
                SegmentItem(LoanDirection.lent, 'I lent'),
              ],
              selected: _direction,
              onChanged: (d) => setState(() => _direction = d),
            ),
          const SizedBox(height: Space.x1_5),
          Text(
            borrowed ? 'You repay this loan. It counts as debt.' : 'Someone repays you. It counts as money owed to you.',
            style: t.micro,
          ),
          const SizedBox(height: Space.x5),
          FinnTextField(
            label: 'Loan name',
            hint: borrowed ? 'e.g. Car loan' : 'e.g. Bike down payment',
            controller: _name,
            prefixIcon: LucideIcons.tag,
            errorText: _errors['name'],
            maxLength: 60,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: Space.x3),
          FinnTextField(
            label: borrowed ? 'Lender' : 'Borrower',
            hint: borrowed ? 'Bank or person, e.g. HDFC Bank' : 'Name',
            controller: _counterparty,
            prefixIcon: borrowed ? LucideIcons.landmark : LucideIcons.user,
            errorText: _errors['counterparty'],
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: Space.x5),
          const LoanFieldLabel('Repayment type'),
          SegmentedTabs<LoanStructure>(
            items: const [
              SegmentItem(LoanStructure.amortizing, 'EMI loan'),
              SegmentItem(LoanStructure.interestOnly, 'Interest-only'),
            ],
            selected: _structure,
            onChanged: locked ? (_) {} : (s) => setState(() => _structure = s),
          ),
          const SizedBox(height: Space.x1_5),
          Text(_structure.description, style: t.micro),
          const SizedBox(height: Space.x5),
          AmountField(
            label: borrowed ? 'Amount borrowed' : 'Amount lent',
            controller: _principal,
            errorText: _errors['principal'],
            enabled: !locked,
            textInputAction: TextInputAction.next,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: Space.x3),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: FinnTextField(
                  label: 'Interest rate (% p.a.)',
                  hint: '0 if interest-free',
                  controller: _rate,
                  prefixIcon: LucideIcons.percent,
                  errorText: _errors['rate'],
                  enabled: !locked,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                  textInputAction: TextInputAction.next,
                  onChanged: (_) => setState(() {}),
                ),
              ),
              if (amortizing) ...[
                const SizedBox(width: Space.x3),
                Expanded(
                  child: FinnTextField(
                    label: 'Instalments',
                    hint: 'e.g. 60',
                    controller: _tenure,
                    prefixIcon: LucideIcons.listOrdered,
                    errorText: _errors['tenureInstallments'],
                    enabled: !locked,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)],
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: Space.x5),
          LoanFieldLabel(amortizing ? 'EMI frequency' : 'Interest paid'),
          IgnorePointer(
            ignoring: locked,
            child: Opacity(
              opacity: locked ? 0.6 : 1,
              child: FilterChipBar<Frequency>(
                padding: EdgeInsets.zero,
                multiSelect: false,
                items: [for (final f in _frequencies) FilterChipItem(f, f.label)],
                selected: {_frequency},
                onChanged: (s) => setState(() => _frequency = s.first),
              ),
            ),
          ),
          if (_errors['frequency'] != null) ...[
            const SizedBox(height: Space.x1),
            Text(_errors['frequency']!, style: t.micro.copyWith(color: c.negative)),
          ],
          const SizedBox(height: Space.x5),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: DateField(
                  label: borrowed ? 'Received on' : 'Given on',
                  value: start,
                  firstDate: DateTime(today.year - 40),
                  lastDate: today,
                  enabled: !locked,
                  errorText: _errors['startDate'],
                  onChanged: (d) => setState(() {
                    _start = d;
                    if (_firstDue != null && _firstDue!.isBefore(d)) _firstDue = null;
                  }),
                ),
              ),
              const SizedBox(width: Space.x3),
              Expanded(
                child: DateField(
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
            const SizedBox(height: Space.x3),
            DateField(
              label: 'Principal due (optional)',
              hint: 'No fixed date',
              value: _maturity,
              firstDate: firstDue,
              lastDate: DateTime(today.year + 40),
              errorText: _errors['maturityDate'],
              onChanged: (d) => setState(() => _maturity = d),
            ),
            if (_maturity != null)
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton.icon(
                  onPressed: () => setState(() => _maturity = null),
                  icon: const Icon(LucideIcons.x, size: 14),
                  label: const Text('Clear date'),
                ),
              ),
          ],
          if (quote != null) ...[
            const SizedBox(height: Space.x4),
            _QuoteCard(quote: quote, frequency: _frequency),
          ],
          if (amortizing) ...[
            const SizedBox(height: Space.x5),
            const LoanFieldLabel('If you prepay'),
            SegmentedTabs<PrepaymentStrategy>(
              items: [for (final p in PrepaymentStrategy.values) SegmentItem(p, p.label)],
              selected: _prepayment,
              onChanged: (p) => setState(() => _prepayment = p),
            ),
            const SizedBox(height: Space.x1_5),
            Text(_prepayment.description, style: t.micro),
          ],
          if (!_editing) ...[
            const SizedBox(height: Space.x5),
            LoanSwitchCard(
              title: borrowed ? 'Record money received' : 'Record money given',
              message: _recordDisbursement
                  ? (borrowed
                      ? 'Adds the amount to your balance once, as loan money received.'
                      : 'Takes the amount out of your balance once, as money lent.')
                  : 'Off: for a loan from before you used FiNN. Your balance stays the same.',
              value: _recordDisbursement,
              onChanged: (b) => setState(() => _recordDisbursement = b),
            ),
          ],
          const SizedBox(height: Space.x4),
          FinnTextField(
            label: 'Notes (optional)',
            hint: 'Account number, terms, anything to remember',
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

class _LockedValue extends StatelessWidget {
  const _LockedValue({required this.icon, required this.color, required this.label});

  final IconData icon;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    return FinnCard(
      variant: FinnCardVariant.muted,
      padding: const EdgeInsets.all(Space.x3),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: Space.x2),
          Expanded(child: Text(label, style: t.bodyStrong)),
          Icon(LucideIcons.lock, size: 14, color: c.textTertiary),
          const SizedBox(width: Space.x1),
          Text('Locked', style: t.micro),
        ],
      ),
    );
  }
}

/// Live estimate of the regular payment (projected, from the calculator).
class _QuoteCard extends StatelessWidget {
  const _QuoteCard({required this.quote, required this.frequency});

  final LoanQuote quote;
  final Frequency frequency;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final q = quote;
    if (q.neverRepays) {
      return const InfoBanner(
        tone: FinnTone.warning,
        icon: LucideIcons.triangleAlert,
        message: 'At this rate and tenure the EMI would not cover the interest. Try more instalments or check the rate.',
      );
    }
    final amortizing = q.structure == LoanStructure.amortizing;
    return FinnCard(
      variant: FinnCardVariant.muted,
      padding: const EdgeInsets.symmetric(horizontal: Space.x4, vertical: Space.x3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(LucideIcons.calculator, size: 16, color: c.textSecondary),
              const SizedBox(width: Space.x2),
              Text('ESTIMATE', style: t.eyebrow),
            ],
          ),
          const SizedBox(height: Space.x2),
          KeyValueRow(
            label: amortizing ? '${frequency.label} EMI' : 'Interest per ${frequency.unit}',
            valueWidget: AmountText(q.installment, style: t.bodyStrong),
            padding: const EdgeInsets.symmetric(vertical: Space.x1),
          ),
          if (q.totalInterest != null)
            KeyValueRow(
              label: 'Total interest',
              valueWidget: AmountText(q.totalInterest!, style: t.bodyStrong),
              padding: const EdgeInsets.symmetric(vertical: Space.x1),
            ),
          if (q.totalPayable != null)
            KeyValueRow(
              label: 'Total repayable',
              valueWidget: AmountText(q.totalPayable!, style: t.bodyStrong),
              padding: const EdgeInsets.symmetric(vertical: Space.x1),
            ),
          if (q.lastDueDate != null)
            KeyValueRow(
              label: 'Last EMI',
              value: DateFormats.dayMonthYear.format(q.lastDueDate!),
              padding: const EdgeInsets.symmetric(vertical: Space.x1),
            ),
          const SizedBox(height: Space.x1),
          Text(
            amortizing
                ? 'EMI rounded up to the next rupee; the last instalment is adjusted.'
                : 'Principal is repaid separately, in one go or in parts.',
            style: t.micro,
          ),
        ],
      ),
    );
  }
}
