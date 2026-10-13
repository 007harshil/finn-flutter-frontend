import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/di/data_providers.dart';
import '../../../app/router/routes.dart';
import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/time/dates.dart';
import '../../../design_system/design_system.dart'
    show AmountText, AmountVisibility, AnimatedAmount, BottomClearanceX, FinnMenuItem, showFinnActionMenu;
import '../../../shared/presentation/action_runner.dart';
import '../../../shared/presentation/async_view.dart';
import '../../../ui/ui.dart';
import '../application/loan_actions.dart';
import '../domain/loan.dart';
import '../domain/loan_calculator.dart';
import 'loan_ui.dart';

enum _Menu { edit, delete }

/// One loan: what is left, the action that moves it forward, what is due
/// next, the terms (the essentials first), and the payments made.
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
        final done = await runAction(
          context,
          ref,
          action: const DeleteLoanAction(),
          input: LoanIdInput(id: s.loan.id),
          idempotencyKey: '$_key-del',
        );
        if (done != null && mounted) context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(loanStateProvider(widget.id));
    final s = value.value;
    return UiPage(
      title: s?.loan.name ?? 'Loan',
      actions: [
        if (s != null) UiIconButton(icon: LucideIcons.ellipsis, tooltip: 'More actions', onPressed: () => _menu(s)),
      ],
      body: AsyncView<LoanState?>(
        value: value,
        loading: const _Placeholder(),
        builder: (context, s) {
          if (s == null) {
            return Center(
              child: UiEmpty(
                icon: LucideIcons.searchX,
                title: 'This loan no longer exists',
                action: 'Back to loans',
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

class _Body extends StatelessWidget {
  const _Body({required this.state});

  final LoanState state;

  @override
  Widget build(BuildContext context) {
    final c = UiColors.of(context);
    final s = state;
    final l = s.loan;
    final warning = s.warning;
    return ListView(
      key: PageStorageKey('loan-${l.id}'),
      padding: EdgeInsets.fromLTRB(UiSpace.gutter, UiSpace.sm, UiSpace.gutter, context.bottomClearance),
      children: [
        UiColumnWidth(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              UiReveal(index: 0, child: _Hero(state: s)),
              if (!s.isClosed) ...[
                const SizedBox(height: UiSpace.xl),
                UiPrimaryButton(
                  label: l.isBorrowed ? 'Record a payment' : 'Record money received',
                  onPressed: () => context.push(AppRoutes.payLoan(l.id)),
                ),
              ],
              if (warning != null) ...[
                const SizedBox(height: UiSpace.sm),
                UiNotice(icon: LucideIcons.triangleAlert, text: warning, color: c.warning),
              ],
              if (!s.isClosed && s.schedule.isNotEmpty) _Upcoming(state: s),
              _Terms(state: s),
              _Payments(state: s),
            ],
          ),
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
    final c = UiColors.of(context);
    final t = UiType.of(context);
    final s = state;
    final l = s.loan;
    final pct = s.repaidBps ~/ 100;
    return UiHero(
      label: l.direction.sentence(l.counterparty),
      value: AnimatedAmount(s.outstanding, style: t.amount, fit: true, animateOnMount: true),
      caption: s.isClosed ? (l.isBorrowed ? 'Fully repaid' : 'Fully received') : null,
      captionColor: c.positive,
      footer: UiProgressFooter(
        value: s.repaidBps / 10000,
        semanticsLabel: 'Principal ${l.direction.repaidVerb.toLowerCase()}',
        start: '$pct% ${l.direction.repaidVerb.toLowerCase()}',
        end: 'of ${maskedAmount(context, l.principal)}',
      ),
    );
  }
}

/// Next instalments (projected). The first is the one due now; the rest
/// fold away.
class _Upcoming extends StatefulWidget {
  const _Upcoming({required this.state});

  final LoanState state;

  @override
  State<_Upcoming> createState() => _UpcomingState();
}

class _UpcomingState extends State<_Upcoming> {
  static const _collapsed = 3;
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final c = UiColors.of(context);
    final t = UiType.of(context);
    final s = widget.state;
    final l = s.loan;
    final rows = _all ? s.schedule : s.schedule.take(_collapsed).toList();
    final more = s.schedule.length > _collapsed;
    return UiSection(
      title: 'Upcoming',
      action: more ? (_all ? 'Show less' : 'All ${s.schedule.length}') : null,
      onAction: more ? () => setState(() => _all = !_all) : null,
      child: UiPanelList(
        children: [
          for (var i = 0; i < rows.length; i++)
            Builder(
              key: ValueKey('row-${rows[i].number}'),
              builder: (context) {
                final r = rows[i];
                final late = r.dueDate.isBefore(s.today);
                final days = daysBetween(s.today, r.dueDate);
                final status = i == 0 ? loanDueStatus(c, s) : (label: 'In $days days', color: null);
                return UiListRow(
                  onTap: null,
                  title: '${loanDueName(l, r)} · ${DateFormats.dayMonthYear.format(r.dueDate)}',
                  subtitle: late ? 'Late · not recorded yet' : status.label,
                  subtitleColor: late ? c.negative : status.color,
                  trailing: AmountText(r.payment, style: t.figureSmall),
                );
              },
            ),
        ],
      ),
    );
  }
}

/// The terms people check most, then the rest on request.
class _Terms extends StatefulWidget {
  const _Terms({required this.state});

  final LoanState state;

  @override
  State<_Terms> createState() => _TermsState();
}

class _TermsState extends State<_Terms> {
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final t = UiType.of(context);
    final s = widget.state;
    final l = s.loan;
    Widget money(Money m) => AmountText(m, style: t.body);
    final end = s.projectedEndDate;
    final note = l.note?.trim() ?? '';
    final rows = <Widget>[
      UiDetailRow(label: l.isBorrowed ? 'Lender' : 'Borrower', value: l.counterparty),
      UiDetailRow(label: 'Interest', value: '${l.rate.label} a year'),
      UiDetailRow(
        label: l.isAmortizing ? 'EMI' : 'Interest per ${l.frequency.unit}',
        valueWidget: money(s.currentInstallment),
      ),
      UiDetailRow(label: 'Repayment', value: l.frequency.label),
      if (end != null && !s.isClosed)
        UiDetailRow(label: l.isAmortizing ? 'Ends' : 'Principal due', value: DateFormats.dayMonthYear.format(end))
      else if (!l.isAmortizing && l.maturityDate == null)
        const UiDetailRow(label: 'Principal due', value: 'No fixed date'),
      if (_all) ...[
        UiDetailRow(label: 'Type', value: l.structure.label),
        UiDetailRow(label: 'Principal', valueWidget: money(l.principal)),
        UiDetailRow(label: 'Started', value: DateFormats.dayMonthYear.format(l.startDate)),
        if (l.isAmortizing) ...[
          UiDetailRow(label: 'Instalments paid', value: '${s.periodsPaid} of ${l.tenureInstallments ?? 0}'),
          UiDetailRow(label: 'After a prepayment', value: l.prepaymentStrategy.label),
        ],
        UiDetailRow(label: l.isBorrowed ? 'Interest paid' : 'Interest received', valueWidget: money(s.interestPaid)),
        if (l.isAmortizing && !s.isClosed)
          UiDetailRow(label: 'Total interest cost', valueWidget: money(s.totalInterestCost)),
        if (note.isNotEmpty) UiNoteRow(label: 'Note', text: note),
      ],
    ];
    return UiSection(
      title: 'Terms',
      action: _all ? 'Less' : 'More',
      onAction: () => setState(() => _all = !_all),
      child: UiPanelList(children: rows),
    );
  }
}

/// Payments newest first; the latest few, the rest on request.
class _Payments extends StatefulWidget {
  const _Payments({required this.state});

  final LoanState state;

  @override
  State<_Payments> createState() => _PaymentsState();
}

class _PaymentsState extends State<_Payments> {
  static const _collapsed = 5;
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final t = UiType.of(context);
    final s = widget.state;
    final l = s.loan;
    final more = s.payments.length > _collapsed;
    final shown = _all ? s.payments : s.payments.take(_collapsed);
    return UiSection(
      title: l.isBorrowed ? 'Payments' : 'Received',
      trailing: s.payments.isEmpty || more
          ? null
          : Padding(
              padding: const EdgeInsets.only(right: UiSpace.sm),
              child: Text('${s.payments.length}', style: t.label),
            ),
      action: more ? (_all ? 'Show less' : 'All ${s.payments.length}') : null,
      onAction: more ? () => setState(() => _all = !_all) : null,
      child: s.payments.isEmpty
          ? Padding(
              padding: const EdgeInsets.only(left: UiSpace.xs),
              child: Text('None recorded yet', style: t.label),
            )
          : UiPanelList(
              ruleIndent: 64,
              children: [for (final p in shown) _PaymentRow(key: ValueKey(p.id), payment: p)],
            ),
    );
  }
}

class _PaymentRow extends StatelessWidget {
  const _PaymentRow({super.key, required this.payment});

  final LoanPayment payment;

  @override
  Widget build(BuildContext context) {
    final t = UiType.of(context);
    final p = payment;
    final txId = p.transactionId;
    final hidden = AmountVisibility.hiddenOf(context);
    final principal = p.principalComponent;
    return UiListRow(
      leading: const UiMark(icon: LucideIcons.check),
      title: '${p.kind.label}${p.periodNumber != null ? ' #${p.periodNumber}' : ''}',
      subtitle: [
        DateFormats.dayMonthYear.format(p.date),
        if (principal.isPositive && !hidden && p.interestComponent.isPositive)
          '${MoneyFormatter.format(principal, decimals: DecimalDisplay.none)} principal',
      ].join(' · '),
      trailing: AmountText(p.total, style: t.figureSmall),
      onTap: txId == null ? null : () => context.push(AppRoutes.transaction(txId)),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(UiSpace.gutter, UiSpace.lg, UiSpace.gutter, 0),
      child: UiColumnWidth(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            UiPlaceholder(width: 140, height: 12),
            SizedBox(height: UiSpace.md),
            UiPlaceholder(width: 200, height: 40),
            SizedBox(height: UiSpace.lg),
            UiPlaceholder(height: 6),
            SizedBox(height: UiSpace.xl),
            UiPlaceholder(height: 52, radius: UiRadius.control),
            SizedBox(height: UiSpace.section),
            UiPlaceholder(height: 180, radius: UiRadius.panel),
          ],
        ),
      ),
    );
  }
}
