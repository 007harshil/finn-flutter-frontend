import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/di/data_providers.dart';
import '../../../app/router/routes.dart';
import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/time/dates.dart';
import '../../../kit/kit.dart';
import '../../../shared/presentation/action_runner.dart';
import '../../../shared/presentation/async_view.dart';
import '../application/loan_actions.dart';
import '../domain/loan.dart';
import '../domain/loan_calculator.dart';
import 'loan_ui.dart';

enum _Menu { edit, delete }

class LoanDetailScreen extends ConsumerStatefulWidget {
  const LoanDetailScreen({super.key, required this.id});

  final String id;

  @override
  ConsumerState<LoanDetailScreen> createState() => _LoanDetailScreenState();
}

class _LoanDetailScreenState extends ConsumerState<LoanDetailScreen> {
  final _key = newIdempotencyKey();

  Future<void> _menu(LoanState s) async {
    final hasPayments = s.payments.isNotEmpty;
    final choice = await showFinnActionMenu<_Menu>(
      context,
      title: s.loan.name,
      items: [
        const FinnMenuItem(value: _Menu.edit, label: 'Edit details', icon: LucideIcons.pencil),
        FinnMenuItem(
          value: _Menu.delete,
          label: hasPayments ? 'Delete — unavailable, payments exist' : 'Delete',
          icon: LucideIcons.trash2,
          destructive: true,
          enabled: !hasPayments,
        ),
      ],
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case _Menu.edit:
        context.push(AppRoutes.editLoan(s.loan.id));
      case _Menu.delete:
        final done = await runAction(context, ref,
            action: const DeleteLoanAction(), input: LoanIdInput(id: s.loan.id), idempotencyKey: '$_key-del');
        if (done != null && mounted) context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(loanStateProvider(widget.id));
    final s = value.value;
    return LedgerPage(
      appBar: LedgerAppBar(
        title: s?.loan.name ?? 'Loan',
        actions: [
          if (s != null)
            LedgerIconButton(icon: LucideIcons.ellipsisVertical, tooltip: 'More actions', onPressed: () => _menu(s)),
        ],
      ),
      storageKey: 'loan-${widget.id}',
      slivers: [
        SliverToBoxAdapter(
          child: AsyncView<LoanState?>(
            value: value,
            loading: const LedgerPageSkeleton(rows: 3),
            builder: (context, s) => s == null
                ? PageColumn(
                    top: Sp.xxl,
                    child: LedgerEmpty(
                      title: 'This loan no longer exists',
                      message: 'It may have been deleted.',
                      actionLabel: 'Back to loans',
                      onAction: () => context.go(AppRoutes.loans),
                    ),
                  )
                : _Body(state: s),
          ),
        ),
      ],
    );
  }
}

class _Body extends StatefulWidget {
  const _Body({required this.state});

  final LoanState state;

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  static const _collapsedRows = 6;
  bool _showAllSchedule = false;

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    final s = widget.state;
    final l = s.loan;
    final next = s.nextDue;
    final schedule = _showAllSchedule ? s.schedule : s.schedule.take(_collapsedRows).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageColumn(top: Sp.xl, child: _Hero(state: s)),
        if (s.warning != null)
          PageColumn(
            top: Sp.lg,
            child: LedgerNote(icon: LucideIcons.triangleAlert, tone: NoteTone.caution, text: s.warning!),
          ),
        if (next != null && !s.isClosed)
          PageColumn(
            top: Sp.section,
            child: LedgerSection(
              title: 'Next payment',
              child: LedgerPanel(children: [_NextDueRow(state: s, row: next)]),
            ),
          ),
        if (s.schedule.isNotEmpty && !s.isClosed)
          PageColumn(
            top: Sp.section,
            child: LedgerSection(
              title: 'Upcoming schedule',
              count: s.schedule.length,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LedgerPanel(
                    children: [
                      for (final r in schedule)
                        _ScheduleRowTile(key: ValueKey('row-${r.number}'), row: r, today: s.today),
                    ],
                  ),
                  if (s.schedule.length > _collapsedRows) ...[
                    const SizedBox(height: Sp.sm),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: LedgerButton(
                        label: _showAllSchedule ? 'Show less' : 'Show all ${s.schedule.length}',
                        icon: _showAllSchedule ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                        variant: LedgerButtonVariant.quiet,
                        small: true,
                        onPressed: () => setState(() => _showAllSchedule = !_showAllSchedule),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        PageColumn(
          top: Sp.section,
          child: LedgerSection(
            title: l.isBorrowed ? 'Payments' : 'Repayments received',
            count: s.payments.isEmpty ? null : s.payments.length,
            child: s.payments.isEmpty
                ? LedgerNote(
                    text: l.isBorrowed
                        ? 'No payments recorded yet. Record each EMI or repayment when you make it.'
                        : 'Nothing received yet. Record repayments as they come in.',
                  )
                : LedgerPanel(
                    children: [for (final p in s.payments) _PaymentRow(key: ValueKey(p.id), payment: p, loan: l)],
                  ),
          ),
        ),
        PageColumn(
          top: Sp.section,
          child: LedgerSection(title: 'Terms', child: LedgerPanel(children: _terms(context, s))),
        ),
        if (s.payments.isNotEmpty)
          PageColumn(
            top: Sp.lg,
            child: Text(
              'Loans with payments cannot be deleted, and their terms are locked, so your history stays accurate.',
              style: t.label,
            ),
          ),
      ],
    );
  }

  List<Widget> _terms(BuildContext context, LoanState s) {
    final l = s.loan;
    final t = context.type;
    Widget money(Money m) => AmountText(m, style: t.figure);
    Widget text(String v) => Text(v, style: t.body, textAlign: TextAlign.end);
    return [
      LedgerFact(label: l.isBorrowed ? 'Lender' : 'Borrower', value: text(l.counterparty)),
      LedgerFact(label: 'Type', value: text(l.structure.label)),
      LedgerFact(label: 'Principal', value: money(l.principal)),
      LedgerFact(label: 'Interest rate', value: text('${l.rate.label} p.a.')),
      LedgerFact(label: 'Repayment', value: text(l.frequency.label)),
      LedgerFact(
        label: l.isAmortizing ? 'Current EMI' : 'Interest per ${l.frequency.unit}',
        value: money(s.currentInstallment),
      ),
      LedgerFact(label: 'Started', value: text(DateFormats.dayMonthYear.format(l.startDate))),
      if (l.isAmortizing) ...[
        LedgerFact(label: 'Tenure', value: text('${l.tenureInstallments ?? 0} instalments')),
        LedgerFact(label: 'Paid', value: text('${s.periodsPaid} instalments')),
        if (!s.isClosed && s.remainingInstallments != null)
          LedgerFact(label: 'Remaining', value: text('${s.remainingInstallments} instalments (projected)')),
        LedgerFact(label: 'After a prepayment', value: text(l.prepaymentStrategy.label)),
      ],
      if (s.projectedEndDate != null && !s.isClosed)
        LedgerFact(
          label: l.isAmortizing ? 'Projected end' : 'Principal due',
          value: text(DateFormats.dayMonthYear.format(s.projectedEndDate!)),
        ),
      if (!l.isAmortizing && l.maturityDate == null) LedgerFact(label: 'Principal due', value: text('No fixed date')),
      LedgerFact(label: l.isBorrowed ? 'Interest paid' : 'Interest received', value: money(s.interestPaid)),
      if (l.isAmortizing && !s.isClosed) LedgerFact(label: 'Total interest cost', value: money(s.totalInterestCost)),
      if (l.note != null && l.note!.trim().isNotEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Sp.lg, vertical: Sp.md + 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Notes', style: t.label),
              const SizedBox(height: Sp.xs),
              Text(l.note!, style: t.body),
            ],
          ),
        ),
    ];
  }
}

/// Outstanding principal as the one number, how much is repaid, where the
/// next payment stands, and the primary action.
class _Hero extends StatelessWidget {
  const _Hero({required this.state});

  final LoanState state;

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    final s = state;
    final l = s.loan;
    final due = loanDueStatus(context, s);
    final pct = s.repaidBps ~/ 100;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l.direction.sentence(l.counterparty), style: t.label),
        const SizedBox(height: Sp.xs),
        AnimatedAmount(s.outstanding, style: t.figureXL, fit: true, animateOnMount: true),
        const SizedBox(height: Sp.xs),
        Text(s.isClosed ? 'Fully repaid' : 'Outstanding principal', style: t.label),
        const SizedBox(height: Sp.lg),
        LedgerBar(value: s.repaidBps / 10000, semanticLabel: '${l.direction.repaidVerb} $pct% of principal'),
        const SizedBox(height: Sp.md),
        Text('$pct% ${l.direction.repaidVerb.toLowerCase()} of ${maskedAmount(context, l.principal)}', style: t.label),
        const SizedBox(height: Sp.xs),
        Text(due.label, style: t.label.copyWith(color: due.color)),
        const SizedBox(height: Sp.lg),
        Row(
          children: [
            Expanded(
              child: LedgerStat(
                label: l.direction.repaidVerb,
                value: AmountText(s.principalRepaid, style: t.figure, decimals: DecimalDisplay.none),
              ),
            ),
            Expanded(
              child: LedgerStat(
                label: 'Interest',
                value: AmountText(s.interestPaid, style: t.figure, decimals: DecimalDisplay.none),
              ),
            ),
          ],
        ),
        if (!s.isClosed) ...[
          const SizedBox(height: Sp.xl),
          LedgerButton(
            label: l.isBorrowed ? 'Record a payment' : 'Record money received',
            icon: LucideIcons.circleCheck,
            expand: true,
            onPressed: () => context.push(AppRoutes.payLoan(l.id)),
          ),
        ],
      ],
    );
  }
}

class _NextDueRow extends StatelessWidget {
  const _NextDueRow({required this.state, required this.row});

  final LoanState state;
  final ScheduleRow row;

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    final c = context.ink;
    final l = state.loan;
    final due = loanDueStatus(context, state);
    final title = l.isAmortizing ? 'EMI #${row.number}' : (row.isFinal ? 'Final payment' : 'Interest #${row.number}');
    return LedgerRow(
      title: title,
      subtitle: '${DateFormats.dayMonthYear.format(row.dueDate)}, ${DateFormats.dueIn(row.dueDate, state.today)}\n'
          '${maskedAmount(context, row.interest)} interest, ${maskedAmount(context, row.principal)} principal',
      subtitleColor: due.overdue ? c.red : null,
      subtitleLines: 3,
      trailing: AmountText(row.payment, style: t.figure),
    );
  }
}

class _ScheduleRowTile extends StatelessWidget {
  const _ScheduleRowTile({super.key, required this.row, required this.today});

  final ScheduleRow row;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final t = context.type;
    final overdue = row.dueDate.isBefore(today);
    return LedgerRow(
      title: '${DateFormats.dayMonthYear.format(row.dueDate)}${overdue ? ', overdue' : ''}',
      subtitle:
          '#${row.number}, ${maskedAmount(context, row.interest)} interest, ${maskedAmount(context, row.principal)} principal',
      subtitleColor: overdue ? c.red : null,
      subtitleLines: 2,
      trailing: AmountText(row.payment, style: t.figure),
      trailingSub: Text('${maskedAmount(context, row.balanceAfter)} after', style: t.small),
    );
  }
}

class _PaymentRow extends StatelessWidget {
  const _PaymentRow({super.key, required this.payment, required this.loan});

  final LoanPayment payment;
  final Loan loan;

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    final p = payment;
    final txId = p.transactionId;
    final split = [
      if (p.interestComponent.isPositive) '${maskedAmount(context, p.interestComponent)} interest',
      if (p.principalComponent.isPositive) '${maskedAmount(context, p.principalComponent)} principal',
    ].join(', ');
    final title = '${p.kind.label}${p.periodNumber != null ? ' #${p.periodNumber}' : ''}';
    return LedgerRow(
      leading: const IconWell(icon: LucideIcons.circleCheck),
      title: title,
      subtitle: [
        DateFormats.dayMonthYear.format(p.date),
        if (split.isNotEmpty) split,
        if (txId == null) 'Not recorded as a cash movement',
      ].join(', '),
      subtitleLines: 3,
      trailing: AmountText(p.total, style: t.figure),
      chevron: txId != null,
      semanticLabel: txId == null ? null : '$title, ${AmountText.spokenLabel(p.total)}. View linked transaction',
      onTap: txId == null ? null : () => context.push(AppRoutes.transaction(txId)),
    );
  }
}
