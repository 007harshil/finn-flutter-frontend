import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/router/routes.dart';
import '../../../core/money/money_format.dart';
import '../../../core/time/dates.dart';
import '../../../kit/kit.dart';
import '../../../shared/presentation/async_view.dart';
import '../domain/loan_calculator.dart';
import 'loan_ui.dart';

enum _Tab {
  active('Active'),
  closed('Closed');

  const _Tab(this.label);
  final String label;
}

/// Loans the user has borrowed or lent, with their repayment progress.
/// Outstanding amounts are obligations; cash moves only when a payment is
/// recorded.
class LoansScreen extends ConsumerStatefulWidget {
  const LoansScreen({super.key});

  @override
  ConsumerState<LoansScreen> createState() => _LoansScreenState();
}

class _LoansScreenState extends ConsumerState<LoansScreen> {
  _Tab _tab = _Tab.active;

  @override
  Widget build(BuildContext context) {
    final header = PageHeader(
      title: 'Loans',
      actions: [
        LedgerButton(
          label: 'Add a loan',
          icon: LucideIcons.plus,
          small: true,
          onPressed: () => context.push(AppRoutes.newLoan),
        ),
      ],
    );
    return AsyncView<LoansOverview>(
      value: ref.watch(loansOverviewProvider),
      loading: Scaffold(backgroundColor: context.ink.paper, body: const SafeArea(child: LedgerPageSkeleton())),
      builder: (context, o) {
        final items = _tab == _Tab.active ? o.active : o.closed;
        return LedgerPage(
          storageKey: 'loans-list',
          slivers: [
            PageBlock(child: header),
            if (!o.isEmpty) ...[
              PageBlock(top: Sp.xxl, child: _Hero(overview: o)),
              if (o.overdueCount > 0)
                PageBlock(
                  top: Sp.lg,
                  child: LedgerNote(
                    icon: LucideIcons.triangleAlert,
                    tone: NoteTone.alert,
                    text: o.overdueCount == 1
                        ? 'One loan has a payment past its due date. Record it once it is paid.'
                        : '${o.overdueCount} loans have payments past their due date. Record them once they are paid.',
                  ),
                ),
              PageBlock(
                top: Sp.section,
                child: LedgerSegmented<_Tab>(
                  selected: _tab,
                  onChanged: (t) => setState(() => _tab = t),
                  segments: [
                    LedgerSegment(_Tab.active, _Tab.active.label, count: o.active.length),
                    LedgerSegment(_Tab.closed, _Tab.closed.label, count: o.closed.length),
                  ],
                ),
              ),
            ],
            if (items.isEmpty)
              PageBlock(
                top: Sp.xl,
                child: o.isEmpty || _tab == _Tab.active
                    ? LedgerEmpty(
                        title: o.isEmpty ? 'No loans yet' : 'No active loans',
                        message: 'Add a bank loan with EMIs, or money borrowed from or lent to family and friends. '
                            'FiNN tracks what is left and what is due next.',
                        actionLabel: 'Add a loan',
                        onAction: () => context.push(AppRoutes.newLoan),
                      )
                    : const LedgerEmpty(
                        title: 'No closed loans',
                        message: 'Loans you repay in full appear here with their history.',
                      ),
              )
            else
              ..._groups(items),
          ],
        );
      },
    );
  }

  /// Borrowed and lent loans in their own sections when both exist.
  List<Widget> _groups(List<LoanState> items) {
    final borrowed = [for (final l in items) if (l.loan.isBorrowed) l];
    final lent = [for (final l in items) if (!l.loan.isBorrowed) l];
    Widget panel(List<LoanState> list) => LedgerPanel(
      dividerIndent: Sp.lg + 40 + Sp.md + 2,
      children: [for (final l in list) _LoanRow(key: ValueKey(l.loan.id), state: l)],
    );
    if (borrowed.isEmpty || lent.isEmpty) {
      return [PageBlock(top: Sp.md, child: panel(items))];
    }
    return [
      PageBlock(
        top: Sp.xl,
        child: LedgerSection(title: 'I owe', count: borrowed.length, child: panel(borrowed)),
      ),
      PageBlock(
        top: Sp.section,
        child: LedgerSection(title: 'Owed to me', count: lent.length, child: panel(lent)),
      ),
    ];
  }
}

/// The one number: what is still owed (or, with only lent loans, what is
/// owed to you), with the other side and what is due soon beside it.
class _Hero extends StatelessWidget {
  const _Hero({required this.overview});

  final LoansOverview overview;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final t = context.type;
    final o = overview;
    final hasBorrowed = o.active.any((l) => l.loan.isBorrowed);
    final hasLent = o.active.any((l) => !l.loan.isBorrowed);
    final owe = hasBorrowed || !hasLent;
    final main = owe ? o.borrowedOutstanding : o.lentOutstanding;
    final stats = <Widget>[
      if (owe && hasLent)
        LedgerStat(
          label: 'Owed to me',
          value: AmountText(o.lentOutstanding, style: t.figure, decimals: DecimalDisplay.none),
        ),
      if (o.dueIn30DaysCount > 0)
        LedgerStat(
          label: 'Due in 30 days',
          value: AmountText(o.dueIn30Days, style: t.figure, decimals: DecimalDisplay.none),
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(owe ? 'I owe' : 'Owed to me', style: t.label),
        const SizedBox(height: Sp.xs),
        AnimatedAmount(main, style: t.figureXL, decimals: DecimalDisplay.none, fit: true, animateOnMount: true),
        if (stats.isNotEmpty) ...[
          const SizedBox(height: Sp.lg),
          Row(
            children: [
              for (var i = 0; i < stats.length; i++) ...[
                if (i > 0) const SizedBox(width: Sp.xl),
                stats[i],
              ],
            ],
          ),
        ] else if (o.active.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: Sp.md),
            child: Text('Nothing due in the next 30 days', style: t.label.copyWith(color: c.inkSoft)),
          ),
      ],
    );
  }
}

/// One loan: direction icon, name, next payment (red when overdue), what is
/// left, and a bar for how much of the principal is done.
class _LoanRow extends StatelessWidget {
  const _LoanRow({super.key, required this.state});

  final LoanState state;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final t = context.type;
    final s = state;
    final l = s.loan;
    final due = loanDueStatus(context, s);
    final next = s.nextDue;
    final String sub;
    if (s.isClosed) {
      sub = '${l.counterparty}, ${l.structure.label}';
    } else if (next == null) {
      sub = '${l.counterparty}, ${l.rate.label} p.a.';
    } else if (due.overdue) {
      sub = '${due.label}, ${DateFormats.dayMonth.format(next.dueDate)}';
    } else {
      sub = '${loanDueName(l, next)} ${maskedAmount(context, next.payment)} on ${DateFormats.dayMonth.format(next.dueDate)}';
    }
    final days = s.daysUntilNextDue;
    final showPay = !s.isClosed && days != null && days <= 7;
    final pct = s.repaidBps ~/ 100;
    return LedgerRow(
      leading: IconWell(icon: l.direction.icon),
      title: l.name,
      subtitle: sub,
      subtitleColor: due.overdue ? c.red : null,
      subtitleLines: 2,
      trailing: AmountText(
        s.outstanding,
        style: t.figure.copyWith(color: s.isClosed ? c.inkSoft : null),
        decimals: DecimalDisplay.none,
      ),
      trailingSub: Text('left', style: t.small),
      below: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LedgerBar(value: s.repaidBps / 10000, color: s.isClosed ? c.inkSoft : null),
          const SizedBox(height: Sp.xs),
          Row(
            children: [
              Expanded(
                child: Text(
                  showPay ? '$pct% ${l.direction.repaidVerb.toLowerCase()}' : '$pct% ${l.direction.repaidVerb.toLowerCase()} of ${maskedAmount(context, l.principal)}',
                  style: t.small,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (showPay)
                LedgerButton(
                  key: ValueKey('loan-pay:${l.id}'),
                  label: l.isBorrowed ? 'Record payment' : 'Record receipt',
                  small: true,
                  variant: LedgerButtonVariant.secondary,
                  onPressed: () => context.push(AppRoutes.payLoan(l.id)),
                ),
            ],
          ),
        ],
      ),
      semanticLabel: '${l.name}, ${l.direction.sentence(l.counterparty)}, '
          'outstanding ${AmountText.spokenLabel(s.outstanding)}, ${due.label}',
      onTap: () => context.push(AppRoutes.loan(l.id)),
    );
  }
}
