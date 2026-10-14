import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/di/data_providers.dart';
import '../../../app/router/routes.dart';
import '../../../core/money/money_format.dart';
import '../../../core/time/dates.dart';
import '../../../design_system/design_system.dart';
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
    return Scaffold(
      appBar: AppBar(
        title: Text(s?.loan.name ?? 'Loan'),
        actions: [
          if (s != null) FinnIconButton(icon: LucideIcons.ellipsisVertical, tooltip: 'More actions', onPressed: () => _menu(s)),
          const SizedBox(width: Space.x2),
        ],
      ),
      body: AsyncView<LoanState?>(
        value: value,
        loading: const SkeletonPulse(
          child: Padding(
            padding: EdgeInsets.all(Space.gutter),
            child: Column(children: [CardSkeleton(height: 220), SizedBox(height: Space.x4), CardSkeleton(height: 240)]),
          ),
        ),
        builder: (context, s) {
          if (s == null) {
            return Center(
              child: EmptyState(
                icon: LucideIcons.searchX,
                title: 'This loan no longer exists',
                message: 'It may have been deleted.',
                actionLabel: 'Back to loans',
                onAction: () => context.go(AppRoutes.loans),
              ),
            );
          }
          return _Body(state: s);
        },
      ),
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
    final c = context.colors;
    final t = context.text;
    final s = widget.state;
    final l = s.loan;
    final next = s.nextDue;
    final schedule = _showAllSchedule ? s.schedule : s.schedule.take(_collapsedRows).toList();
    final sections = <Widget>[
      _Hero(state: s),
      if (!s.isClosed) ...[
        const SizedBox(height: Space.x3),
        FinnButton(
          label: l.isBorrowed ? 'Record a payment' : 'Record money received',
          icon: LucideIcons.circleCheck,
          expand: true,
          size: FinnButtonSize.lg,
          onPressed: () => context.push(AppRoutes.payLoan(l.id)),
        ),
      ],
      if (s.warning != null) ...[
        const SizedBox(height: Space.x3),
        InfoBanner(tone: FinnTone.warning, icon: LucideIcons.triangleAlert, message: s.warning!),
      ],
      if (next != null) ...[
        const SizedBox(height: Space.x4),
        _NextDueCard(state: s, row: next),
      ],
      const SizedBox(height: Space.section),
      SectionHeader(icon: LucideIcons.fileText, title: 'Terms', tileColor: c.accentLoans),
      const SizedBox(height: Space.x2),
      FinnCard(
        padding: const EdgeInsets.symmetric(horizontal: Space.x4, vertical: Space.x1),
        child: Column(
          children: [
            KeyValueRow(label: l.isBorrowed ? 'Lender' : 'Borrower', value: l.counterparty),
            KeyValueRow(label: 'Type', value: l.structure.label),
            KeyValueRow(label: 'Principal', valueWidget: AmountText(l.principal, style: t.bodyStrong)),
            KeyValueRow(label: 'Interest rate', value: '${l.rate.label} p.a.'),
            KeyValueRow(label: 'Repayment', value: l.frequency.label),
            KeyValueRow(
              label: l.isAmortizing ? 'Current EMI' : 'Interest per ${l.frequency.unit}',
              valueWidget: AmountText(s.currentInstallment, style: t.bodyStrong),
            ),
            KeyValueRow(label: 'Started', value: DateFormats.dayMonthYear.format(l.startDate)),
            if (l.isAmortizing) ...[
              KeyValueRow(label: 'Tenure', value: '${l.tenureInstallments ?? 0} instalments'),
              KeyValueRow(label: 'Paid', value: '${s.periodsPaid} instalments'),
              if (!s.isClosed && s.remainingInstallments != null)
                KeyValueRow(label: 'Remaining', value: '${s.remainingInstallments} instalments (projected)'),
              KeyValueRow(label: 'After a prepayment', value: l.prepaymentStrategy.label),
            ],
            if (s.projectedEndDate != null && !s.isClosed)
              KeyValueRow(
                label: l.isAmortizing ? 'Projected end' : 'Principal due',
                value: DateFormats.dayMonthYear.format(s.projectedEndDate!),
              ),
            if (!l.isAmortizing && l.maturityDate == null)
              const KeyValueRow(label: 'Principal due', value: 'No fixed date'),
            KeyValueRow(
              label: l.isBorrowed ? 'Interest paid' : 'Interest received',
              valueWidget: AmountText(s.interestPaid, style: t.bodyStrong),
            ),
            if (l.isAmortizing && !s.isClosed)
              KeyValueRow(
                label: 'Total interest cost',
                valueWidget: AmountText(s.totalInterestCost, style: t.bodyStrong),
              ),
            if (l.note != null && l.note!.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Space.x2_5),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('NOTES', style: t.eyebrow),
                    const SizedBox(height: Space.x1),
                    SizedBox(width: double.infinity, child: Text(l.note!, style: t.body)),
                  ],
                ),
              ),
          ],
        ),
      ),
      if (s.schedule.isNotEmpty && !s.isClosed) ...[
        const SizedBox(height: Space.section),
        SectionHeader(
          icon: LucideIcons.listOrdered,
          title: 'Upcoming schedule',
          subtitle: l.isAmortizing
              ? 'Projected · ${s.schedule.length} left · interest ${maskedAmount(context, s.projectedInterest)}'
              : 'Projected · next ${s.schedule.length} ${l.frequency.unit}s',
          tileColor: c.info,
        ),
        const SizedBox(height: Space.x2),
        FinnCard(
          padding: const EdgeInsets.symmetric(horizontal: Space.x4, vertical: Space.x1),
          child: Column(
            children: [
              for (var i = 0; i < schedule.length; i++) ...[
                if (i > 0) const FinnDivider(),
                _ScheduleRowTile(key: ValueKey('row-${schedule[i].number}'), row: schedule[i], today: s.today),
              ],
            ],
          ),
        ),
        if (s.schedule.length > _collapsedRows)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: () => setState(() => _showAllSchedule = !_showAllSchedule),
              icon: Icon(_showAllSchedule ? LucideIcons.chevronUp : LucideIcons.chevronDown, size: 16),
              label: Text(_showAllSchedule ? 'Show less' : 'Show all ${s.schedule.length}'),
            ),
          ),
      ],
      const SizedBox(height: Space.section),
      SectionHeader(
        icon: LucideIcons.history,
        title: l.isBorrowed ? 'Payments' : 'Repayments received',
        subtitle: s.payments.isEmpty ? null : '${s.payments.length} recorded',
        tileColor: c.positive,
      ),
      const SizedBox(height: Space.x2),
      if (s.payments.isEmpty)
        FinnCard(
          variant: FinnCardVariant.muted,
          child: Text(
            l.isBorrowed
                ? 'No payments recorded yet. Record each EMI or repayment when you make it.'
                : 'Nothing received yet. Record repayments as they come in.',
            style: t.caption,
          ),
        )
      else
        FinnCard(
          padding: const EdgeInsets.symmetric(horizontal: Space.x4, vertical: Space.x1),
          child: Column(
            children: [
              for (var i = 0; i < s.payments.length; i++) ...[
                if (i > 0) const FinnDivider(),
                _PaymentRow(key: ValueKey(s.payments[i].id), payment: s.payments[i], loan: l),
              ],
            ],
          ),
        ),
      if (s.payments.isNotEmpty) ...[
        const SizedBox(height: Space.x3),
        Text('Loans with payments cannot be deleted, and their terms are locked, so your history stays accurate.',
            style: t.micro),
      ],
    ];
    return ListView(
      key: PageStorageKey('loan-${l.id}'),
      padding: EdgeInsets.fromLTRB(0, Space.x2, 0, context.bottomClearance),
      children: [
        for (var i = 0; i < sections.length; i++)
          ResponsiveCenter(
            padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
            child: i == 0 ? StaggeredEntrance(child: sections[i]) : sections[i],
          ),
      ],
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.state});

  final LoanState state;

  @override
  Widget build(BuildContext context) {
    final t = context.text;
    final s = state;
    final l = s.loan;
    final white70 = Colors.white.withValues(alpha: 0.75);
    final due = loanDueLabel(context, s);
    return GradientHeroCard(
      watermark: l.direction.icon,
      semanticLabel: '${l.direction.sentence(l.counterparty)}. Outstanding ${MoneyFormatter.spoken(s.outstanding)}. ${due.label}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(child: LoanDirectionPill(direction: l.direction, onGradient: true)),
              const SizedBox(width: Space.x2),
              StatusPill(label: due.label, color: Colors.white, icon: due.icon),
            ],
          ),
          const SizedBox(height: Space.x3),
          Text(l.direction.sentence(l.counterparty), style: t.bodyStrong.copyWith(color: Colors.white)),
          const SizedBox(height: Space.x1),
          AnimatedAmount(s.outstanding, style: t.amountHero.copyWith(color: Colors.white), fit: true),
          Text(s.isClosed ? 'Fully repaid' : 'outstanding principal', style: t.caption.copyWith(color: white70)),
          const SizedBox(height: Space.x4),
          FinnProgressBar(
            value: s.repaidBps / 10000,
            color: Colors.white,
            trackColor: Colors.white.withValues(alpha: 0.18),
            semanticsLabel: 'Principal ${l.direction.repaidVerb.toLowerCase()} so far',
          ),
          const SizedBox(height: Space.x3),
          Row(
            children: [
              Expanded(
                child: _HeroFigure(
                  label: 'Principal',
                  amount: AmountText(l.principal, style: t.amountSmall.copyWith(color: Colors.white)),
                ),
              ),
              Expanded(
                child: _HeroFigure(
                  label: l.direction.repaidVerb,
                  amount: AmountText(s.principalRepaid, style: t.amountSmall.copyWith(color: Colors.white)),
                ),
              ),
              Expanded(
                child: _HeroFigure(
                  label: 'Interest',
                  amount: AmountText(s.interestPaid, style: t.amountSmall.copyWith(color: Colors.white)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroFigure extends StatelessWidget {
  const _HeroFigure({required this.label, required this.amount});

  final String label;
  final Widget amount;

  @override
  Widget build(BuildContext context) => MergeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label.toUpperCase(), style: context.text.eyebrow.copyWith(color: Colors.white.withValues(alpha: 0.7))),
            const SizedBox(height: 2),
            amount,
          ],
        ),
      );
}

class _NextDueCard extends StatelessWidget {
  const _NextDueCard({required this.state, required this.row});

  final LoanState state;
  final ScheduleRow row;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final l = state.loan;
    final due = loanDueLabel(context, state);
    final title = l.isAmortizing ? 'Next EMI · #${row.number}' : (row.isFinal ? 'Final payment' : 'Next interest · #${row.number}');
    return FinnCard(
      variant: FinnCardVariant.outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconTile(icon: LucideIcons.calendarClock, background: c.infoSoft, foreground: c.info, size: 36, iconSize: 18),
              const SizedBox(width: Space.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: t.bodyStrong),
                    Text(
                      '${DateFormats.dayMonthYear.format(row.dueDate)} · ${DateFormats.dueIn(row.dueDate, state.today)}',
                      style: t.caption,
                    ),
                  ],
                ),
              ),
              AmountText(row.payment, style: t.amountMedium),
            ],
          ),
          const SizedBox(height: Space.x3),
          Wrap(
            spacing: Space.x2,
            runSpacing: Space.x1,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              StatusPill(label: due.label, color: due.color, icon: due.icon),
              Text(
                'Projected · ${maskedAmount(context, row.interest)} interest + ${maskedAmount(context, row.principal)} principal',
                style: t.micro,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ScheduleRowTile extends StatelessWidget {
  const _ScheduleRowTile({super.key, required this.row, required this.today});

  final ScheduleRow row;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final overdue = row.dueDate.isBefore(today);
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.x2_5),
        child: Row(
          children: [
            SizedBox(
              width: 36,
              child: Text('#${row.number}', style: t.caption.copyWith(fontWeight: FontWeight.w700)),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: Space.x1_5,
                    runSpacing: Space.x0_5,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(DateFormats.dayMonthYear.format(row.dueDate), style: t.bodyStrong),
                      if (overdue) StatusPill(label: 'Overdue', color: c.negative, icon: LucideIcons.triangleAlert),
                    ],
                  ),
                  Text(
                    '${maskedAmount(context, row.interest)} interest · ${maskedAmount(context, row.principal)} principal',
                    style: t.micro,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text('Balance after ${maskedAmount(context, row.balanceAfter)}', style: t.micro),
                ],
              ),
            ),
            const SizedBox(width: Space.x2),
            AmountText(row.payment, style: t.amountSmall),
          ],
        ),
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
    final c = context.colors;
    final t = context.text;
    final p = payment;
    final txId = p.transactionId;
    final split = [
      if (p.interestComponent.isPositive) '${maskedAmount(context, p.interestComponent)} interest',
      if (p.principalComponent.isPositive) '${maskedAmount(context, p.principalComponent)} principal',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.x2_5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconTile(icon: LucideIcons.circleCheck, background: c.positiveSoft, foreground: c.positive, size: 32, iconSize: 16),
              const SizedBox(width: Space.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${p.kind.label}${p.periodNumber != null ? ' #${p.periodNumber}' : ''}', style: t.bodyStrong),
                    Text(
                      [DateFormats.dayMonthYear.format(p.date), if (split.isNotEmpty) split].join(' · '),
                      style: t.caption,
                      maxLines: 2,
                    ),
                  ],
                ),
              ),
              AmountText(p.total, style: t.amountSmall),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 44, top: Space.x1),
            child: txId == null
                ? Row(children: [
                    Icon(LucideIcons.circleSlash, size: 13, color: c.textTertiary),
                    const SizedBox(width: Space.x1),
                    Flexible(child: Text('Not recorded as a cash movement', style: t.micro)),
                  ])
                : Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton.icon(
                      onPressed: () => context.push(AppRoutes.transaction(txId)),
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(Dimens.minTouch, 36),
                        foregroundColor: c.info,
                        textStyle: t.label.copyWith(fontWeight: FontWeight.w800),
                      ),
                      icon: const Icon(LucideIcons.link2, size: 14),
                      label: const Text('View linked transaction'),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
