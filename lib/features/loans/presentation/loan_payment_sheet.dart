import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/di/core_providers.dart';
import '../../../app/di/data_providers.dart';
import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/result/result.dart';
import '../../../core/time/dates.dart';
import '../../../design_system/design_system.dart';
import '../../../design_system/luxe/luxe.dart';
import '../../../shared/presentation/action_runner.dart';
import '../../transactions/domain/transaction.dart';
import '../application/loan_actions.dart';
import '../domain/loan.dart';
import '../domain/loan_calculator.dart';
import 'loan_ui.dart';

/// Records an EMI, an interest payment or a principal repayment. Interest
/// due is paid first; the split shown is computed by the loan calculator.
class LoanPaymentSheet extends ConsumerStatefulWidget {
  const LoanPaymentSheet({super.key, required this.loanId});

  final String loanId;

  @override
  ConsumerState<LoanPaymentSheet> createState() => _LoanPaymentSheetState();
}

class _LoanPaymentSheetState extends ConsumerState<LoanPaymentSheet> {
  final _key = newIdempotencyKey();
  final _amount = TextEditingController();
  final _note = TextEditingController();
  LoanPaymentKind? _kind;
  DateTime? _date;
  PaymentMethod _method = PaymentMethod.bankTransfer;
  bool _recordCash = true;
  bool _busy = false;
  Map<String, String> _errors = const {};

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  static LoanPaymentKind _scheduledKind(Loan l) =>
      l.isAmortizing ? LoanPaymentKind.installment : LoanPaymentKind.interest;

  void _selectKind(LoanState s, LoanPaymentKind k) => setState(() {
    _kind = k;
    _errors = const {};
    final next = s.nextDue;
    _amount.text = k != LoanPaymentKind.principal && next != null ? MoneyFormatter.editable(next.payment) : '';
  });

  LoanPaymentInput _input(LoanState s, LoanPaymentKind kind, DateTime today) {
    final note = _note.text.trim();
    return LoanPaymentInput(
      loanId: s.loan.id,
      kind: kind,
      amount: AmountField.parse(_amount.text) ?? Money.zero,
      date: _date ?? today,
      method: _method,
      recordCashMovement: _recordCash,
      note: note.isEmpty ? null : note,
    );
  }

  Future<void> _submit(LoanState s, LoanPaymentKind kind) async {
    final amount = AmountField.parse(_amount.text);
    if (amount == null || !amount.isPositive) {
      setState(() => _errors = {'amount': 'Enter an amount greater than zero.'});
      return;
    }
    final input = _input(s, kind, ref.read(todayProvider));
    setState(() {
      _busy = true;
      _errors = const {};
    });
    final borrowed = s.loan.isBorrowed;
    final result = await runAction(
      context,
      ref,
      action: const RecordLoanPaymentAction(),
      input: input,
      idempotencyKey: _key,
      celebrate: true,
      successTitle: borrowed ? 'Payment recorded' : 'Repayment recorded',
      successSubtitle: s.loan.name,
      onFieldErrors: (e) => setState(() => _errors = e),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (result != null) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) => LuxeScope(paint: true, child: Builder(builder: _buildSheet));

  Widget _buildSheet(BuildContext context) {
    final s = ref.watch(loanStateProvider(widget.loanId)).value;
    final snapshot = ref.watch(financeSnapshotProvider).value;
    if (s == null || snapshot == null) {
      return const FinnSheetScaffold(
        title: 'Record a payment',
        child: SkeletonPulse(
          child: Column(
            children: [
              CardSkeleton(height: 120),
              SizedBox(height: Space.x4),
              CardSkeleton(height: 220),
            ],
          ),
        ),
      );
    }
    if (s.isClosed) return _Closed(state: s);

    final today = ref.watch(todayProvider);
    final t = context.text;
    final c = context.colors;
    final l = s.loan;
    final borrowed = l.isBorrowed;
    final next = s.nextDue;
    final scheduled = _scheduledKind(l);
    if (_kind == null) {
      // First build: default to the scheduled payment when one exists.
      _kind = next != null ? scheduled : LoanPaymentKind.principal;
      if (next != null) _amount.text = MoneyFormatter.editable(next.payment);
    }
    final kind = _kind!;
    final entered = AmountField.parse(_amount.text);
    final split = entered == null || !entered.isPositive
        ? null
        : const RecordLoanPaymentAction().split(_input(s, kind, today), snapshot);

    return FinnSheetScaffold(
      title: borrowed ? 'Record a payment' : 'Record money received',
      description: '${l.name} · ${l.direction.sentence(l.counterparty)}',
      footer: FinnButton(
        label: borrowed ? 'Record payment to ${l.counterparty}' : 'Record money from ${l.counterparty}',
        icon: LucideIcons.circleCheck,
        expand: true,
        loading: _busy,
        onPressed: _busy ? null : () => _submit(s, kind),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FinnCard(
            variant: FinnCardVariant.muted,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LoanDirectionPill(direction: l.direction),
                const SizedBox(height: Space.x2),
                Text('OUTSTANDING PRINCIPAL', style: t.eyebrow),
                const SizedBox(height: Space.x0_5),
                AmountText(s.outstanding, style: t.amountLarge.copyWith(color: l.direction.color(c)), fit: true),
                const SizedBox(height: Space.x1),
                Text(
                  next == null
                      ? 'Nothing scheduled right now'
                      : '${loanDueName(l, next)} #${next.number} of ${maskedAmount(context, next.payment)} '
                            '${DateFormats.dueIn(next.dueDate, s.today)} (${DateFormats.dayMonth.format(next.dueDate)})',
                  style: t.caption,
                ),
              ],
            ),
          ),
          const SizedBox(height: Space.x5),
          const LoanFieldLabel('What is this payment?'),
          SegmentedTabs<LoanPaymentKind>(
            items: [
              SegmentItem(scheduled, next == null ? (l.isAmortizing ? 'EMI' : 'Interest') : loanDueName(l, next)),
              const SegmentItem(LoanPaymentKind.principal, 'Principal only'),
            ],
            selected: kind,
            onChanged: (k) => _selectKind(s, k),
          ),
          const SizedBox(height: Space.x1_5),
          Text(
            kind == LoanPaymentKind.principal
                ? (l.isAmortizing
                      ? 'A part-prepayment. It reduces the principal: ${l.prepaymentStrategy.description.toLowerCase()}.'
                      : 'Repays part or all of the principal. Future interest goes down.')
                : 'Interest due is covered first; anything above the scheduled amount reduces the principal.',
            style: t.micro,
          ),
          const SizedBox(height: Space.x5),
          AmountField(
            label: borrowed ? 'Amount paid' : 'Amount received',
            controller: _amount,
            errorText: _errors['amount'],
            onChanged: (_) => setState(() {}),
          ),
          if (split != null) ...[const SizedBox(height: Space.x3), _SplitPreview(result: split, borrowed: borrowed)],
          const SizedBox(height: Space.x5),
          DateField(
            label: borrowed ? 'Paid on' : 'Received on',
            value: _date ?? today,
            firstDate: l.startDate,
            lastDate: today,
            errorText: _errors['date'],
            onChanged: (d) => setState(() => _date = d),
          ),
          const SizedBox(height: Space.x5),
          const LoanFieldLabel('Method'),
          LoanMethodChips(selected: _method, onChanged: (m) => setState(() => _method = m)),
          const SizedBox(height: Space.x4),
          LoanSwitchCard(
            title: 'Record as cash movement',
            message: _recordCash
                ? (borrowed
                      ? 'Adds an expense and lowers your balance once.'
                      : 'Adds income and raises your balance once.')
                : 'Off: paid outside your FiNN-tracked cash. The loan updates; your balance stays the same.',
            value: _recordCash,
            onChanged: (b) => setState(() => _recordCash = b),
          ),
          const SizedBox(height: Space.x4),
          FinnTextField(
            label: 'Note (optional)',
            hint: 'e.g. Ref no. 4821',
            controller: _note,
            maxLength: 120,
            errorText: _errors['note'],
          ),
        ],
      ),
    );
  }
}

/// How the entered amount will be applied (from the loan calculator).
class _SplitPreview extends StatelessWidget {
  const _SplitPreview({required this.result, required this.borrowed});

  final Result<LoanPaymentPreview> result;
  final bool borrowed;

  @override
  Widget build(BuildContext context) {
    final t = context.text;
    final c = context.colors;
    final r = result;
    if (r case Err(:final failure)) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(LucideIcons.info, size: 14, color: c.warning),
          const SizedBox(width: Space.x1_5),
          Expanded(
            child: Text(failure.message, style: t.micro.copyWith(color: c.textPrimary)),
          ),
        ],
      );
    }
    final p = (r as Ok<LoanPaymentPreview>).value;
    const pad = EdgeInsets.symmetric(vertical: Space.x1);
    return FinnCard(
      variant: FinnCardVariant.outlined,
      padding: const EdgeInsets.symmetric(horizontal: Space.x4, vertical: Space.x2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          KeyValueRow(
            label: 'Towards interest',
            valueWidget: AmountText(p.interestPortion, style: t.bodyStrong),
            padding: pad,
          ),
          KeyValueRow(
            label: 'Towards principal',
            valueWidget: AmountText(p.principalPortion, style: t.bodyStrong),
            padding: pad,
          ),
          KeyValueRow(
            label: 'Outstanding after',
            valueWidget: AmountText(p.outstandingAfter, style: t.bodyStrong),
            padding: pad,
          ),
          if (p.closesLoan || (p.includesPrepayment && p.kind != LoanPaymentKind.principal)) ...[
            const SizedBox(height: Space.x1),
            Row(
              children: [
                Icon(p.closesLoan ? LucideIcons.partyPopper : LucideIcons.trendingDown, size: 14, color: c.positive),
                const SizedBox(width: Space.x1_5),
                Expanded(
                  child: Text(
                    p.closesLoan
                        ? (borrowed ? 'This payment closes the loan.' : 'This repayment settles the loan in full.')
                        : 'More than the scheduled amount: the extra reduces the principal.',
                    style: t.micro,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Closed extends StatelessWidget {
  const _Closed({required this.state});

  final LoanState state;

  @override
  Widget build(BuildContext context) => FinnSheetScaffold(
    title: 'Fully repaid',
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.x6),
      child: EmptyState(
        icon: LucideIcons.circleCheck,
        title: 'Nothing left to pay',
        message: '${state.loan.name} is fully repaid. No further payments can be recorded.',
        actionLabel: 'Close',
        onAction: () => Navigator.of(context).maybePop(),
      ),
    ),
  );
}
