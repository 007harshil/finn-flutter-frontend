import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/router/routes.dart';
import '../../../design_system/design_system.dart';
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
    final overview = ref.watch(loansOverviewProvider);
    return Scaffold(
      appBar: AppBar(
        actions: [
          FinnIconButton(
            icon: LucideIcons.plus,
            tooltip: 'Add a loan',
            variant: FinnIconButtonVariant.filled,
            onPressed: () => context.push(AppRoutes.newLoan),
          ),
          const SizedBox(width: Space.x3),
        ],
      ),
      body: AsyncView<LoansOverview>(
        value: overview,
        loading: const _LoansSkeleton(),
        builder: (context, o) {
          final items = _tab == _Tab.active ? o.active : o.closed;
          return CustomScrollView(
            key: const PageStorageKey('loans-list'),
            slivers: [
              _boxed(const StaggeredEntrance(child: _Header())),
              if (!o.isEmpty) ...[
                _boxed(StaggeredEntrance(index: 1, child: _SummaryRow(overview: o))),
                if (o.overdueCount > 0)
                  _boxed(Padding(
                    padding: const EdgeInsets.only(top: Space.x3),
                    child: InfoBanner(
                      tone: FinnTone.warning,
                      icon: LucideIcons.triangleAlert,
                      message: o.overdueCount == 1
                          ? 'One loan has a payment past its due date. Record it once it is paid.'
                          : '${o.overdueCount} loans have payments past their due date. Record them once they are paid.',
                    ),
                  )),
                _boxed(Padding(
                  padding: const EdgeInsets.only(top: Space.x5, bottom: Space.x1),
                  child: SegmentedTabs<_Tab>(
                    items: [
                      SegmentItem(_Tab.active, _Tab.active.label, count: o.active.length),
                      SegmentItem(_Tab.closed, _Tab.closed.label, count: o.closed.length),
                    ],
                    selected: _tab,
                    onChanged: (t) => setState(() => _tab = t),
                  ),
                )),
              ],
              if (items.isEmpty)
                _boxed(Padding(
                  padding: const EdgeInsets.only(top: Space.x6),
                  child: o.isEmpty || _tab == _Tab.active
                      ? EmptyState(
                          icon: LucideIcons.landmark,
                          title: o.isEmpty ? 'No loans yet' : 'No active loans',
                          message: 'Add a bank loan with EMIs, or money borrowed from or lent to family and friends. '
                              'FiNN tracks what is left and what is due next.',
                          actionLabel: 'Add a loan',
                          actionIcon: LucideIcons.plus,
                          onAction: () => context.push(AppRoutes.newLoan),
                        )
                      : const EmptyState(
                          icon: LucideIcons.circleCheck,
                          title: 'No closed loans',
                          message: 'Loans you repay in full appear here with their history.',
                        ),
                ))
              else
                SliverList.builder(
                  itemCount: items.length,
                  itemBuilder: (context, i) => _LoanRow(state: items[i]),
                ),
              SliverPadding(padding: EdgeInsets.only(bottom: context.bottomClearance)),
            ],
          );
        },
      ),
    );
  }
}

Widget _boxed(Widget child) => SliverToBoxAdapter(
      child: ResponsiveCenter(padding: const EdgeInsets.symmetric(horizontal: Space.gutter), child: child),
    );

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final t = context.text;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.x4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(header: true, child: Text('Loans', style: t.pageTitle)),
          const SizedBox(height: Space.x1),
          Text('What you have borrowed and lent. Your balance changes only when you record a payment.',
              style: t.caption),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.overview});

  final LoansOverview overview;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final o = overview;
    final borrowed = o.active.where((l) => l.loan.isBorrowed).length;
    final lent = o.active.length - borrowed;
    String count(int n) => n == 0 ? 'None active' : '$n active';
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: StatTile(
              label: 'I owe',
              icon: LucideIcons.landmark,
              accent: c.negative,
              value: AmountText(o.borrowedOutstanding, style: t.amountMedium.copyWith(color: c.negative), fit: true),
              caption: count(borrowed),
            ),
          ),
          const SizedBox(width: Space.x2),
          Expanded(
            child: StatTile(
              label: 'Owed to me',
              icon: LucideIcons.handCoins,
              accent: c.positive,
              value: AmountText(o.lentOutstanding, style: t.amountMedium.copyWith(color: c.positive), fit: true),
              caption: count(lent),
            ),
          ),
          const SizedBox(width: Space.x2),
          Expanded(
            child: StatTile(
              label: 'Due in 30 days',
              icon: LucideIcons.calendarClock,
              accent: o.overdueCount > 0 ? c.attention : c.info,
              value: AmountText(o.dueIn30Days, style: t.amountMedium, fit: true),
              caption: o.dueIn30DaysCount == 0
                  ? 'Nothing due'
                  : 'Projected · ${o.dueIn30DaysCount} ${o.dueIn30DaysCount == 1 ? 'payment' : 'payments'}',
            ),
          ),
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
    final id = state.loan.id;
    final days = state.daysUntilNextDue;
    final showPay = !state.isClosed && days != null && days <= 7;
    return ResponsiveCenter(
      key: ValueKey(id),
      padding: const EdgeInsets.fromLTRB(Space.gutter, Space.x2, Space.gutter, 0),
      child: LoanCard(
        state: state,
        onTap: () => context.push(AppRoutes.loan(id)),
        onPay: showPay ? () => context.push(AppRoutes.payLoan(id)) : null,
      ),
    );
  }
}

class _LoansSkeleton extends StatelessWidget {
  const _LoansSkeleton();

  @override
  Widget build(BuildContext context) => const SkeletonPulse(
        child: Padding(
          padding: EdgeInsets.all(Space.gutter),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 120, height: 28),
              SizedBox(height: Space.x5),
              Row(children: [
                Expanded(child: CardSkeleton(height: 104)),
                SizedBox(width: Space.x2),
                Expanded(child: CardSkeleton(height: 104)),
                SizedBox(width: Space.x2),
                Expanded(child: CardSkeleton(height: 104)),
              ]),
              SizedBox(height: Space.x5),
              SkeletonBox(height: 44, radius: Radii.full),
              SizedBox(height: Space.x4),
              CardSkeleton(height: 132),
              SizedBox(height: Space.x2),
              CardSkeleton(height: 132),
            ],
          ),
        ),
      );
}
