import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/di/core_providers.dart';
import '../../../app/di/data_providers.dart';
import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/result/result.dart';
import '../../../core/time/dates.dart';
import '../../../kit/kit.dart';
import '../../../shared/presentation/action_runner.dart';
import '../../accounts/presentation/widgets/account_picker_field.dart';
import '../../accounts/presentation/widgets/channel_field.dart';
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
  // Null until picked: the form shows the default account and sends it.
  String? _accountId;
  String? _channel;
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
    _amount.text = k != LoanPaymentKind.principal && next != null
        ? MoneyFormatter.editable(next.payment)
        : '';
  });

  LoanPaymentInput _input(LoanState s, LoanPaymentKind kind, DateTime today) {
    final note = _note.text.trim();
    return LoanPaymentInput(
      loanId: s.loan.id,
      kind: kind,
      amount: LedgerAmountField.parse(_amount.text) ?? Money.zero,
      date: _date ?? today,
      accountId: _recordCash ? (_accountId ?? ref.read(defaultAccountProvider).value?.id) : null,
      channel: _recordCash ? _channel : null,
      recordCashMovement: _recordCash,
      note: note.isEmpty ? null : note,
    );
  }

  Future<void> _submit(LoanState s, LoanPaymentKind kind) async {
    final amount = LedgerAmountField.parse(_amount.text);
    if (amount == null || !amount.isPositive) {
      setState(
        () => _errors = {'amount': 'Enter an amount greater than zero.'},
      );
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
    if (result != null) Navigator.of(context).maybePop(true);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(loanStateProvider(widget.loanId)).value;
    final snapshot = ref.watch(financeSnapshotProvider).value;
    if (s == null || snapshot == null) {
      return const FinnSheetScaffold(
        title: 'Record payment',
        child: _FormSkeleton(),
      );
    }
    if (s.isClosed) return _Closed(state: s);

    final today = ref.watch(todayProvider);
    final t = context.type;
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
    final entered = LedgerAmountField.parse(_amount.text);
    final split = entered == null || !entered.isPositive
        ? null
        : const RecordLoanPaymentAction().split(
            _input(s, kind, today),
            snapshot,
          );

    return FinnSheetScaffold(
      title: borrowed ? 'Record payment' : 'Record money received',
      description: '${l.name} · ${l.direction.sentence(l.counterparty)}',
      footer: LedgerButton(
        label: borrowed ? 'Record payment' : 'Record receipt',
        expand: true,
        loading: _busy,
        onPressed: _busy ? null : () => _submit(s, kind),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LedgerAmountField(
            hero: true,
            label: borrowed ? 'Amount paid' : 'Amount received',
            controller: _amount,
            errorText: _errors['amount'],
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: Sp.md),
          LedgerPanel(
            children: [
              LedgerFact(
                label: 'Outstanding principal',
                value: AmountText(s.outstanding, style: t.bodyStrong),
              ),
              LedgerFact(
                label: next == null
                    ? 'Next payment'
                    : '${loanDueName(l, next)} #${next.number}',
                text: next == null
                    ? 'Nothing scheduled'
                    : '${maskedAmount(context, next.payment)} ${DateFormats.dueIn(next.dueDate, s.today)}',
              ),
            ],
          ),
          if (split != null) ...[
            const SizedBox(height: Sp.md),
            _SplitPreview(result: split, borrowed: borrowed),
          ],
          const SizedBox(height: LedgerForm.groupGap),
          LedgerField(
            label: 'Payment type',
            helper: kind == LoanPaymentKind.principal
                ? (l.isAmortizing
                      ? 'Part-prepayment: ${l.prepaymentStrategy.description.toLowerCase()}.'
                      : 'Repays part or all of the principal. Future interest goes down.')
                : 'Interest due is covered first; any extra reduces the principal.',
            child: LedgerSegmented<LoanPaymentKind>(
              segments: [
                LedgerSegment(
                  scheduled,
                  next == null
                      ? (l.isAmortizing ? 'EMI' : 'Interest')
                      : loanDueName(l, next),
                ),
                const LedgerSegment(
                  LoanPaymentKind.principal,
                  'Principal only',
                ),
              ],
              selected: kind,
              onChanged: (k) => _selectKind(s, k),
            ),
          ),
          const SizedBox(height: LedgerForm.gap),
          LedgerDateField(
            label: borrowed ? 'Paid on' : 'Received on',
            value: _date ?? today,
            firstDate: l.startDate,
            lastDate: today,
            errorText: _errors['date'],
            onChanged: (d) => setState(() => _date = d),
          ),
          const SizedBox(height: LedgerForm.gap),
          LedgerSwitchRow(
            title: 'Record as cash movement',
            subtitle: _recordCash
                ? (borrowed
                      ? 'Adds an expense and lowers your balance.'
                      : 'Adds income and raises your balance.')
                : 'Off: paid outside FiNN. The loan updates; balance unchanged.',
            value: _recordCash,
            onChanged: (b) => setState(() => _recordCash = b),
          ),
          if (_recordCash) ...[
            const SizedBox(height: LedgerForm.gap),
            AccountPickerField(
              label: borrowed ? 'Paid from' : 'Received in',
              value: _accountId ?? ref.watch(defaultAccountProvider).value?.id,
              errorText: _errors['accountId'],
              onChanged: (id) => setState(() {
                _accountId = id;
                _errors = Map.of(_errors)..remove('accountId');
              }),
            ),
            const SizedBox(height: LedgerForm.gap),
            ChannelField(
              value: _channel,
              errorText: _errors['channel'],
              onChanged: (v) => _channel = v,
            ),
          ],
          const SizedBox(height: LedgerForm.gap),
          LedgerTextField(
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
            LedgerSkeleton(height: 104),
            SizedBox(height: LedgerForm.gap),
            LedgerSkeleton(height: 52),
          ],
        ),
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
    final t = context.type;
    final r = result;
    if (r case Err(:final failure)) {
      return LedgerNote(tone: NoteTone.caution, text: failure.message);
    }
    final p = (r as Ok<LoanPaymentPreview>).value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LedgerPanel(
          children: [
            LedgerFact(
              label: 'Towards interest',
              value: AmountText(p.interestPortion, style: t.bodyStrong),
            ),
            LedgerFact(
              label: 'Towards principal',
              value: AmountText(p.principalPortion, style: t.bodyStrong),
            ),
            LedgerFact(
              label: 'Outstanding after',
              value: AmountText(p.outstandingAfter, style: t.bodyStrong),
            ),
          ],
        ),
        if (p.closesLoan ||
            (p.includesPrepayment && p.kind != LoanPaymentKind.principal)) ...[
          const SizedBox(height: Sp.sm),
          Text(
            p.closesLoan
                ? (borrowed
                      ? 'This payment closes the loan.'
                      : 'This repayment settles the loan in full.')
                : 'More than scheduled: the extra reduces the principal.',
            style: t.small,
          ),
        ],
      ],
    );
  }
}

class _Closed extends StatelessWidget {
  const _Closed({required this.state});

  final LoanState state;

  @override
  Widget build(BuildContext context) => FinnSheetScaffold(
    title: 'Fully repaid',
    child: LedgerEmpty(
      icon: LucideIcons.circleCheck,
      title: 'Nothing left to pay',
      message:
          '${state.loan.name} is fully repaid. No further payments can be recorded.',
      actionLabel: 'Close',
      onAction: () => Navigator.of(context).maybePop(),
    ),
  );
}
