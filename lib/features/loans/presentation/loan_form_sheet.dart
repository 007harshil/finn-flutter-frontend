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
import '../../../design_system/luxe/luxe.dart';
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
  Widget build(BuildContext context) => LuxeScope(paint: true, child: Builder(builder: _buildSheet));

  Widget _buildSheet(BuildContext context) {
    final today = ref.watch(todayProvider);
    if (_editing && !_loaded) {
      final s = ref.watch(loanStateProvider(widget.loanId!)).value;
      if (s != null) _load(s);
    }
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

    final p = context.vault;
    final vt = context.vt;
    var section = 0;

    return FinnSheetScaffold(
      eyebrow: borrowed ? 'Money owed by you' : 'Money owed to you',
      title: _editing ? 'Edit loan' : 'Add a loan',
      description: _editing ? _existing!.loan.name : 'An EMI loan, or money between you and someone you know.',
      footer: FinnButton(
        label: _editing ? 'Save changes' : 'Add loan',
        icon: _editing ? LucideIcons.check : LucideIcons.plus,
        size: FinnButtonSize.lg,
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
              title: 'Terms are locked',
              message: 'Payments are recorded on this loan, so its amount, rate, dates and tenure stay as they are. '
                  'Name, lender, notes and prepayment preference can still change.',
            ),
            const SizedBox(height: 20),
          ],
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
          const SizedBox(height: 10),
          Center(
            child: VaultSwap(
              alignment: Alignment.topCenter,
              child: Text(
                borrowed ? 'You repay this. It counts as debt.' : 'Someone repays you. It counts as money owed to you.',
                key: ValueKey(borrowed),
                textAlign: TextAlign.center,
                style: vt.caption,
              ),
            ),
          ),
          const SizedBox(height: 24),
          AmountField(
            label: borrowed ? 'Amount borrowed' : 'Amount lent',
            controller: _principal,
            prominent: true,
            errorText: _errors['principal'],
            enabled: !locked,
            textInputAction: TextInputAction.next,
            onChanged: (_) => setState(() {}),
          ),
          VaultSection(index: ++section, title: 'Who & what'),
          FinnTextField(
            label: 'Loan name',
            hint: borrowed ? 'Car loan' : 'Bike down payment',
            controller: _name,
            prefixIcon: LucideIcons.tag,
            errorText: _errors['name'],
            maxLength: 60,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),
          FinnTextField(
            label: borrowed ? 'Lender' : 'Borrower',
            hint: borrowed ? 'Bank or person, e.g. HDFC Bank' : 'Name',
            controller: _counterparty,
            prefixIcon: borrowed ? LucideIcons.landmark : LucideIcons.user,
            errorText: _errors['counterparty'],
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
          ),
          VaultSection(index: ++section, title: 'Terms', hint: 'How it is repaid'),
          SegmentedTabs<LoanStructure>(
            items: const [
              SegmentItem(LoanStructure.amortizing, 'EMI loan'),
              SegmentItem(LoanStructure.interestOnly, 'Interest-only'),
            ],
            selected: _structure,
            onChanged: locked ? (_) {} : (s) => setState(() => _structure = s),
          ),
          const SizedBox(height: 8),
          VaultSwap(child: Text(_structure.description, key: ValueKey(_structure), style: vt.caption)),
          const SizedBox(height: 16),
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
                const SizedBox(width: 10),
                Expanded(
                  child: FinnTextField(
                    label: 'Instalments',
                    hint: '60',
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
          const SizedBox(height: 18),
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
          VaultFieldError(_errors['frequency']),
          VaultSection(index: ++section, title: 'Schedule'),
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
              const SizedBox(width: 10),
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
            const SizedBox(height: 12),
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
            const SizedBox(height: 18),
            MotionAnimatedSize(child: _QuoteCard(quote: quote, frequency: _frequency)),
          ],
          VaultSection(index: ++section, title: 'Preferences'),
          if (amortizing) ...[
            const LoanFieldLabel('If you prepay'),
            SegmentedTabs<PrepaymentStrategy>(
              items: [for (final s in PrepaymentStrategy.values) SegmentItem(s, s.label)],
              selected: _prepayment,
              onChanged: (s) => setState(() => _prepayment = s),
            ),
            const SizedBox(height: 8),
            VaultSwap(child: Text(_prepayment.description, key: ValueKey(_prepayment), style: vt.caption)),
            const SizedBox(height: 16),
          ],
          if (!_editing) ...[
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
            const SizedBox(height: 12),
          ],
          FinnTextField(
            label: 'Notes (optional)',
            hint: 'Account number, terms, anything to remember',
            controller: _note,
            prefixIcon: LucideIcons.notebookPen,
            errorText: _errors['note'],
            maxLines: 3,
            minLines: 2,
            textCapitalization: TextCapitalization.sentences,
          ),
          SizedBox(height: p.isDark ? 4 : 0),
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
    final p = context.vault;
    final t = context.vt;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 16, 12),
      decoration: BoxDecoration(color: p.well, borderRadius: BorderRadius.circular(999)),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: t.heading.copyWith(fontSize: 14.5))),
          Icon(LucideIcons.lock, size: 13, color: p.inkMute),
          const SizedBox(width: 5),
          Text('Locked', style: t.caption),
        ],
      ),
    );
  }
}

/// Live estimate of the regular payment, set on an obsidian slip so it
/// reads as the outcome of everything above it. Figures roll to their new
/// value as terms change.
class _QuoteCard extends StatelessWidget {
  const _QuoteCard({required this.quote, required this.frequency});

  final LoanQuote quote;
  final Frequency frequency;

  @override
  Widget build(BuildContext context) {
    final p = context.vault;
    final t = context.vt;
    final q = quote;
    if (q.neverRepays) {
      return const InfoBanner(
        tone: FinnTone.warning,
        icon: LucideIcons.triangleAlert,
        message: 'At this rate and tenure the EMI would not cover the interest. Try more instalments or check the rate.',
      );
    }
    final amortizing = q.structure == LoanStructure.amortizing;
    const onDark = Color(0xFFF6F1E7);
    const onDarkSoft = Color(0xFFB4AA99);
    final soft = t.caption.vc(onDarkSoft);
    Widget fact(String label, Widget value) => Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          Expanded(child: Text(label, style: soft)),
          DefaultTextStyle.merge(style: t.number.vc(onDark), child: value),
        ],
      ),
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(VaultShape.group),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2A2621), Color(0xFF151311), Color(0xFF0E0D0B)],
        ),
        border: Border.all(color: p.accent.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(LucideIcons.sparkles, size: 14, color: p.accent),
              const SizedBox(width: 8),
              Text('ESTIMATE', style: t.eyebrow.vc(p.accent)),
            ],
          ),
          const SizedBox(height: 12),
          Text(amortizing ? '${frequency.label} EMI' : 'Interest per ${frequency.unit}', style: soft),
          const SizedBox(height: 4),
          VaultCount(
            value: q.installment.paise.toDouble(),
            builder: (context, v) => AmountText(
              Money.fromPaise(v.round()),
              style: t.hero.copyWith(fontSize: 40, color: onDark),
            ),
          ),
          const SizedBox(height: 6),
          Container(height: 1, color: onDark.withValues(alpha: 0.1)),
          if (q.totalInterest != null) fact('Total interest', AmountText(q.totalInterest!, style: t.number.vc(onDark))),
          if (q.totalPayable != null) fact('Total repayable', AmountText(q.totalPayable!, style: t.number.vc(onDark))),
          if (q.lastDueDate != null) fact('Last EMI', Text(DateFormats.dayMonthYear.format(q.lastDueDate!))),
          const SizedBox(height: 12),
          Text(
            amortizing
                ? 'EMI rounded up to the next rupee; the last instalment is adjusted.'
                : 'Principal is repaid separately, in one go or in parts.',
            style: t.caption.copyWith(fontSize: 11.5).vc(onDarkSoft),
          ),
        ],
      ),
    );
  }
}
