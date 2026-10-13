import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/router/routes.dart';
import '../../../core/money/money_format.dart';
import '../../../design_system/design_system.dart' show AmountText, AnimatedAmount, BottomClearanceX;
import '../../../shared/presentation/async_view.dart';
import '../../../ui/ui.dart';
import '../domain/loan_calculator.dart';
import 'loan_ui.dart';

enum _Tab { active, closed }

/// Loans the user has borrowed or lent. One headline figure, then the
/// loans soonest-due first. Cash moves only when a payment is recorded.
class LoansScreen extends ConsumerStatefulWidget {
  const LoansScreen({super.key});

  @override
  ConsumerState<LoansScreen> createState() => _LoansScreenState();
}

class _LoansScreenState extends ConsumerState<LoansScreen> {
  _Tab _tab = _Tab.active;

  @override
  Widget build(BuildContext context) {
    return UiPage(
      title: 'Loans',
      actions: [
        UiIconButton(icon: LucideIcons.plus, tooltip: 'Add a loan', onPressed: () => context.push(AppRoutes.newLoan)),
      ],
      body: AsyncView<LoansOverview>(
        value: ref.watch(loansOverviewProvider),
        loading: const _Placeholder(),
        builder: (context, o) {
          if (o.isEmpty) {
            return Center(
              child: SingleChildScrollView(
                child: UiEmpty(
                  icon: LucideIcons.landmark,
                  title: 'No loans yet',
                  message: 'Track a bank loan, or money borrowed from or lent to someone.',
                  action: 'Add a loan',
                  onAction: () => context.push(AppRoutes.newLoan),
                ),
              ),
            );
          }
          final tab = o.closed.isEmpty ? _Tab.active : _tab;
          final items = tab == _Tab.active ? o.active : o.closed;
          return CustomScrollView(
            key: const PageStorageKey('loans-list'),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(UiSpace.gutter, UiSpace.sm, UiSpace.gutter, 0),
                sliver: SliverToBoxAdapter(
                  child: UiColumnWidth(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        UiReveal(index: 0, child: _Summary(overview: o)),
                        const SizedBox(height: UiSpace.section),
                        if (o.closed.isNotEmpty) ...[
                          UiSegmented<_Tab>(
                            segments: [
                              UiSegment(_Tab.active, 'Active', count: o.active.length),
                              UiSegment(_Tab.closed, 'Closed', count: o.closed.length),
                            ],
                            selected: tab,
                            onChanged: (t) => setState(() => _tab = t),
                          ),
                          const SizedBox(height: UiSpace.md),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              if (items.isEmpty)
                const SliverToBoxAdapter(
                  child: UiEmpty(icon: LucideIcons.circleCheck, title: 'No active loans', message: 'Everything is repaid.'),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: UiSpace.gutter),
                  sliver: SliverList.builder(
                    itemCount: items.length,
                    itemBuilder: (context, i) => UiColumnWidth(
                      key: ValueKey(items[i].loan.id),
                      child: UiPanelSlice(
                        first: i == 0,
                        last: i == items.length - 1,
                        child: _LoanRow(state: items[i]),
                      ),
                    ),
                  ),
                ),
              SliverPadding(padding: EdgeInsets.only(bottom: context.bottomClearance)),
            ],
          );
        },
      ),
    );
  }
}

/// What the user owes (or, with only lent loans, what is owed to them),
/// the other side and what falls due within 30 days.
class _Summary extends StatelessWidget {
  const _Summary({required this.overview});

  final LoansOverview overview;

  @override
  Widget build(BuildContext context) {
    final c = UiColors.of(context);
    final t = UiType.of(context);
    final o = overview;
    final owes = o.borrowedOutstanding.isPositive || !o.lentOutstanding.isPositive;
    final stats = <Widget>[
      if (owes && o.lentOutstanding.isPositive)
        UiStat(
          label: 'Owed to you',
          value: AmountText(o.lentOutstanding, style: t.figureSmall, decimals: DecimalDisplay.none),
        ),
      if (!owes && o.borrowedOutstanding.isPositive)
        UiStat(
          label: 'You owe',
          value: AmountText(o.borrowedOutstanding, style: t.figureSmall, decimals: DecimalDisplay.none),
        ),
      if (o.borrowedOutstanding.isPositive)
        UiStat(
          label: 'Due in 30 days',
          value: AmountText(o.dueIn30Days, style: t.figureSmall, decimals: DecimalDisplay.none),
        ),
    ];
    final overdue = o.overdueCount;
    return UiHero(
      label: owes ? 'You owe' : 'Owed to you',
      value: AnimatedAmount(
        owes ? o.borrowedOutstanding : o.lentOutstanding,
        style: t.amount,
        decimals: DecimalDisplay.none,
        fit: true,
        animateOnMount: true,
      ),
      caption: overdue == 0 ? null : (overdue == 1 ? '1 loan has a late payment' : '$overdue loans have late payments'),
      captionColor: c.negative,
      footer: stats.isEmpty
          ? null
          : Row(
              children: [
                for (var i = 0; i < stats.length; i++) ...[if (i > 0) const SizedBox(width: UiSpace.lg), Expanded(child: stats[i])],
              ],
            ),
    );
  }
}

class _LoanRow extends StatelessWidget {
  const _LoanRow({required this.state});

  final LoanState state;

  @override
  Widget build(BuildContext context) {
    final c = UiColors.of(context);
    final t = UiType.of(context);
    final s = state;
    final l = s.loan;
    final due = loanDueStatus(c, s);
    final next = s.nextDue;
    final days = s.daysUntilNextDue;
    final subtitle = s.isClosed || next == null
        ? '${due.label} · ${l.counterparty}'
        : '${loanDueName(l, next)} ${maskedAmount(context, next.payment)} · ${due.label}';
    final record = !s.isClosed && days != null && days <= 0;
    return UiListRow(
      leading: UiMark(icon: l.direction.icon),
      title: l.name,
      subtitle: subtitle,
      subtitleColor: due.color,
      semanticLabel:
          '${l.name}, ${l.direction.sentence(l.counterparty)}, '
          'outstanding ${AmountText.spokenLabel(s.outstanding)}, ${due.label}',
      chevron: !record,
      trailing: record
          ? UiChipButton(
              label: 'Record',
              semanticLabel: l.isBorrowed ? 'Record payment' : 'Record money received',
              onTap: () => context.push(AppRoutes.payLoan(l.id)),
            )
          : AmountText(
              s.outstanding,
              decimals: DecimalDisplay.none,
              style: t.figureSmall.copyWith(color: s.isClosed ? c.inkSoft : null),
            ),
      onTap: () => context.push(AppRoutes.loan(l.id)),
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
            UiPlaceholder(width: 80, height: 12),
            SizedBox(height: UiSpace.md),
            UiPlaceholder(width: 200, height: 40),
            SizedBox(height: UiSpace.section + UiSpace.lg),
            UiPlaceholder(height: 220, radius: UiRadius.panel),
          ],
        ),
      ),
    );
  }
}
