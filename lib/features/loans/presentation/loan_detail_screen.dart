import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/di/data_providers.dart';
import '../../../app/router/routes.dart';
import '../../../core/money/money_format.dart';
import '../../../core/time/dates.dart';
import '../../../kit/kit.dart';
import '../../../shared/presentation/action_runner.dart';
import '../../../shared/presentation/async_view.dart';
import '../../../shared/presentation/push_then_leave.dart';
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

class _Body extends StatelessWidget {
  const _Body({required this.state});

  final LoanState state;

  @override
  Widget build(BuildContext context) {
    final s = state;
    final l = s.loan;
    final next = s.nextDue;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageColumn(top: Sp.lg, child: _Hero(state: s)),
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
              child: _NextDueCard(state: s, row: next),
            ),
          ),
        if (s.schedule.isNotEmpty && !s.isClosed)
          PageColumn(
            top: Sp.section,
            child: LedgerSection(
              title: 'Upcoming schedule',
              count: s.schedule.length,
              child: _ScheduleColumns(rows: s.schedule.take(12).toList()),
            ),
          ),
        PageColumn(
          top: Sp.section,
          child: LedgerSection(
            title: l.isBorrowed ? 'Payments' : 'Repayments received',
            count: s.payments.isEmpty ? null : s.payments.length,
            child: s.payments.isEmpty
                ? LedgerEmpty(
                    icon: LucideIcons.receipt,
                    title: l.isBorrowed ? 'No payments yet' : 'Nothing received yet',
                  )
                : LedgerPanel(
                    khata: true,
                    dividerIndent: Khata.textX,
                    children: [for (final p in s.payments) _PaymentRow(key: ValueKey(p.id), payment: p, loan: l)],
                  ),
          ),
        ),
        PageColumn(
          top: Sp.section,
          child: LedgerSection(title: 'Terms', child: _terms(context, s)),
        ),
      ],
    );
  }

  /// Tags for what the loan is, tiles for its numbers.
  Widget _terms(BuildContext context, LoanState s) {
    final l = s.loan;
    final c = context.ink;
    final end = s.projectedEndDate;
    final note = l.note?.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FactTags(
          tags: [
            '${l.isBorrowed ? 'Lender' : 'Borrower'}: ${l.counterparty}',
            l.structure.label,
            '${l.rate.label} p.a.',
            l.frequency.label,
            'Since ${DateFormats.dayMonthYear.format(l.startDate)}',
            if (l.isAmortizing) l.prepaymentStrategy.label,
          ],
        ),
        const SizedBox(height: Sp.md),
        StatGrid(
          tiles: [
            StatTile.money(label: 'Principal', amount: l.principal, icon: LucideIcons.landmark),
            StatTile.money(
              label: l.isAmortizing ? 'Current EMI' : 'Interest per ${l.frequency.unit}',
              amount: s.currentInstallment,
              icon: LucideIcons.calendarClock,
            ),
            if (l.isAmortizing) ...[
              StatTile.text(
                label: 'Paid',
                text: '${s.periodsPaid} of ${l.tenureInstallments ?? 0}',
                icon: LucideIcons.listChecks,
              ),
            ],
            if (end != null && !s.isClosed)
              StatTile.text(
                label: l.isAmortizing ? 'Projected end' : 'Principal due',
                text: DateFormats.dayMonthYear.format(end),
                icon: LucideIcons.flag,
              ),
            if (!l.isAmortizing && l.maturityDate == null)
              StatTile.text(label: 'Principal due', text: 'No fixed date', icon: LucideIcons.flag),
            StatTile.money(
              label: l.isBorrowed ? 'Interest paid' : 'Interest received',
              amount: s.interestPaid,
              icon: LucideIcons.percent,
              color: c.saffron,
            ),
            if (l.isAmortizing && !s.isClosed)
              StatTile.money(label: 'Total interest cost', amount: s.totalInterestCost, icon: LucideIcons.coins, color: c.saffron),
          ],
        ),
        if (note != null && note.isNotEmpty) ...[
          const SizedBox(height: Sp.md),
          LedgerNote(icon: LucideIcons.stickyNote, text: note),
        ],
      ],
    );
  }
}

/// Next instalments as stacked columns: principal (rain) under interest
/// (saffron), so the interest share shrinking over time is visible.
class _ScheduleColumns extends StatelessWidget {
  const _ScheduleColumns({required this.rows});

  final List<ScheduleRow> rows;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final t = context.type;
    if (rows.length < 2) return const SizedBox.shrink();
    final maxV = rows.fold<int>(0, (m, r) => math.max(m, r.payment.paise));
    if (maxV <= 0) return const SizedBox.shrink();
    return MonsoonCard(
      padding: const EdgeInsets.fromLTRB(Sp.md, Sp.md, Sp.md, Sp.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            label: 'Next ${rows.length} payments split into principal and interest',
            excludeSemantics: true,
            child: SizedBox(
              height: 96,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final r in rows)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: FractionallySizedBox(
                          heightFactor: (r.payment.paise / maxV).clamp(0.05, 1.0),
                          alignment: Alignment.bottomCenter,
                          child: ClipRRect(
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
                            child: Column(
                              children: [
                                Expanded(
                                  flex: math.max(1, r.interest.paise),
                                  child: Container(color: c.saffron),
                                ),
                                Expanded(
                                  flex: math.max(1, r.principal.paise),
                                  child: Container(color: c.rain),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: Sp.xs),
          Row(
            children: [
              Text(DateFormats.shortMonth.format(rows.first.dueDate), style: t.small),
              const Spacer(),
              Text(DateFormats.shortMonth.format(rows.last.dueDate), style: t.small),
            ],
          ),
          const SizedBox(height: Sp.xs),
          Wrap(
            spacing: Sp.lg,
            children: [
              ChartDot(color: c.rain, label: 'Principal'),
              ChartDot(color: c.saffron, label: 'Interest'),
            ],
          ),
        ],
      ),
    );
  }
}

/// Outstanding principal as the one number, how much is repaid, where the
/// next payment stands, and the primary action.
class _Hero extends StatelessWidget {
  const _Hero({required this.state});

  final LoanState state;

  @override
  Widget build(BuildContext context) {
    final s = state;
    final l = s.loan;
    final due = loanDueStatus(context, s);
    final pct = s.repaidBps ~/ 100;
    final total = s.principalRepaid.paise + s.outstanding.paise + s.interestPaid.paise;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BahiSlab(
          leading: LucideIcons.landmark,
          label: s.isClosed ? 'Fully repaid' : 'Outstanding principal',
          figure: SlabFigure(s.outstanding, decimals: DecimalDisplay.auto),
          caption: '${l.direction.sentence(l.counterparty)} · of ${maskedAmount(context, l.principal)}',
          stamp: SlabStamp(
            label: s.isClosed ? 'Closed' : (due.overdue ? 'Overdue' : 'Running'),
            tone: s.isClosed ? SlabTone.good : (due.overdue ? SlabTone.bad : SlabTone.neutral),
          ),
          visual: SlabRing(
            value: pct / 100,
            size: 96,
            color: Slab.good,
            top: '$pct%',
            bottom: l.direction.repaidVerb.toLowerCase(),
            semanticLabel: '${l.direction.repaidVerb} $pct% of principal',
          ),
          stats: [
            SlabStat.money(label: l.direction.repaidVerb, amount: s.principalRepaid, color: Slab.good),
            SlabStat.money(label: 'Interest', amount: s.interestPaid, color: Slab.warn),
          ],
          footer: total <= 0
              ? null
              : SlabBar(
                  parts: [
                    (s.principalRepaid.paise / total, Slab.good),
                    (s.interestPaid.paise / total, Slab.warn),
                    (s.outstanding.paise / total, Slab.lilac),
                  ],
                  semanticLabel: 'Repaid, interest and outstanding',
                ),
        ),
        if (!s.isClosed) ...[
          const SizedBox(height: Sp.md),
          LedgerButton(
            label: l.isBorrowed ? 'Record a payment' : 'Record money received',
            icon: LucideIcons.circleCheck,
            expand: true,
            onPressed: () => pushThenLeave(context, AppRoutes.payLoan(l.id)),
          ),
        ],
      ],
    );
  }
}

/// The next instalment: amount, due date tag, and its interest/principal
/// split as one bar.
class _NextDueCard extends StatelessWidget {
  const _NextDueCard({required this.state, required this.row});

  final LoanState state;
  final ScheduleRow row;

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    final c = context.ink;
    final l = state.loan;
    final due = loanDueStatus(context, state);
    final title = l.isAmortizing ? 'EMI #${row.number}' : (row.isFinal ? 'Final payment' : 'Interest #${row.number}');
    final total = row.interest.paise + row.principal.paise;
    return MonsoonCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: t.labelStrong)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: Sp.sm, vertical: 4),
                decoration: BoxDecoration(color: due.overdue ? c.redSoft : c.marigoldSoft, borderRadius: Rad.rChip),
                child: Text(
                  '${DateFormats.dayMonth.format(row.dueDate)} · ${DateFormats.dueIn(row.dueDate, state.today)}',
                  style: t.small.copyWith(color: due.overdue ? c.red : c.marigoldInk, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: Sp.sm),
          AmountText(row.payment, style: t.figureL.copyWith(fontSize: 30), decimals: DecimalDisplay.none),
          const SizedBox(height: Sp.md),
          LedgerStackBar(
            height: 10,
            parts: [
              BarPart(total <= 0 ? 0 : row.principal.paise / total, c.rain),
              BarPart(total <= 0 ? 0 : row.interest.paise / total, c.saffron),
            ],
            semanticLabel: '${maskedAmount(context, row.principal)} principal, ${maskedAmount(context, row.interest)} interest',
          ),
          const SizedBox(height: Sp.sm),
          Wrap(
            spacing: Sp.lg,
            runSpacing: Sp.xs,
            children: [
              ChartDot(color: c.rain, label: 'Principal ${maskedAmount(context, row.principal)}'),
              ChartDot(color: c.saffron, label: 'Interest ${maskedAmount(context, row.interest)}'),
            ],
          ),
        ],
      ),
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
