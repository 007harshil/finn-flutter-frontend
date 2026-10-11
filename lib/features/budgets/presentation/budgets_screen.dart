import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/router/routes.dart';
import '../../../core/money/money_format.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/presentation/async_view.dart';
import '../application/budget_history.dart';
import 'budget_widgets.dart';

/// Budgets tab: summary of the current period and every budget, most
/// urgent first.
class BudgetsScreen extends ConsumerWidget {
  const BudgetsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(budgetsOverviewProvider);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: AsyncView<BudgetsOverview>(
          value: overview,
          loading: const _BudgetsSkeleton(),
          builder: (context, o) => _BudgetsBody(overview: o),
        ),
      ),
    );
  }
}

class _BudgetsBody extends StatelessWidget {
  const _BudgetsBody({required this.overview});

  final BudgetsOverview overview;

  @override
  Widget build(BuildContext context) {
    final o = overview;
    final c = context.colors;
    Widget box(Widget child, {double top = 0}) => SliverToBoxAdapter(
          child: ResponsiveCenter(
            padding: EdgeInsets.fromLTRB(Space.gutter, top, Space.gutter, 0),
            child: child,
          ),
        );
    return CustomScrollView(
      key: const PageStorageKey('budgets'),
      slivers: [
        box(const _Header(), top: Space.x4),
        if (o.isEmpty)
          box(
            EmptyState(
              icon: LucideIcons.chartPie,
              title: 'No budgets yet',
              message: 'Set a monthly limit for a category like Food or Shopping. '
                  'FiNN tracks spending against it automatically.',
              actionLabel: 'Create a budget',
              actionIcon: LucideIcons.plus,
              onAction: () => context.push(AppRoutes.newBudget),
            ),
            top: Space.x6,
          )
        else ...[
          if (o.totalLimit.isPositive) box(StaggeredEntrance(child: _SummaryCard(overview: o)), top: Space.x5),
          if (o.active.isNotEmpty)
            box(
              SectionHeader(
                icon: LucideIcons.gauge,
                title: 'Active budgets',
                subtitle: 'Most urgent first',
                tileColor: c.accentBudgets,
              ),
              top: Space.section,
            ),
          SliverList.builder(
            itemCount: o.active.length,
            itemBuilder: (context, i) {
              final u = o.active[i];
              return ResponsiveCenter(
                key: ValueKey(u.budget.id),
                padding: const EdgeInsets.fromLTRB(Space.gutter, Space.x3, Space.gutter, 0),
                child: StaggeredEntrance(index: i + 1, child: BudgetUsageCard(usage: u)),
              );
            },
          ),
          if (o.paused.isNotEmpty) ...[
            box(
              SectionHeader(
                icon: LucideIcons.circlePause,
                title: 'Paused',
                subtitle: 'Not tracking warnings until resumed',
                tileColor: c.textTertiary,
              ),
              top: Space.section,
            ),
            SliverList.builder(
              itemCount: o.paused.length,
              itemBuilder: (context, i) {
                final u = o.paused[i];
                return ResponsiveCenter(
                  key: ValueKey(u.budget.id),
                  padding: const EdgeInsets.fromLTRB(Space.gutter, Space.x3, Space.gutter, 0),
                  child: BudgetUsageCard(usage: u),
                );
              },
            ),
          ],
        ],
        SliverToBoxAdapter(child: SizedBox(height: context.bottomClearance)),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            child: Semantics(header: true, child: Text('Budgets', style: context.text.pageTitle)),
          ),
          FinnButton(
            label: 'New budget',
            icon: LucideIcons.plus,
            size: FinnButtonSize.sm,
            onPressed: () => context.push(AppRoutes.newBudget),
          ),
        ],
      );
}

/// Overall view of monthly budgets in the current period.
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.overview});

  final BudgetsOverview overview;

  @override
  Widget build(BuildContext context) {
    final o = overview;
    final t = context.text;
    final over = o.totalSpent > o.totalLimit;
    const soft = Color(0xD9FFFFFF);
    final eyebrow = t.eyebrow.copyWith(color: soft);
    final remainingText = over
        ? 'Over by ${budgetMoney(context, -o.totalRemaining)}'
        : '${budgetMoney(context, o.totalRemaining)} left';
    final alerts = <String>[
      if (o.breachedCount > 0) '${o.breachedCount} over limit',
      if (o.warningCount > 0) '${o.warningCount} near limit',
    ];
    return GradientHeroCard(
      watermark: LucideIcons.chartPie,
      semanticLabel: 'Monthly budgets: spent ${budgetMoney(context, o.totalSpent)} of '
          '${budgetMoney(context, o.totalLimit)}. $remainingText. ${daysLeftLabel(o.daysLeft)}.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('THIS MONTH · ${periodLabel(o.period).toUpperCase()}', style: eyebrow),
          const SizedBox(height: Space.x2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: AnimatedAmount(o.totalSpent, style: t.amountHero.copyWith(color: Colors.white), fit: true),
              ),
              const SizedBox(width: Space.x2),
              Padding(
                padding: const EdgeInsets.only(bottom: Space.x1_5),
                child: Text('of ${budgetMoney(context, o.totalLimit)}',
                    style: t.bodyStrong.copyWith(color: soft)),
              ),
            ],
          ),
          const SizedBox(height: Space.x3),
          FinnProgressBar(
            value: o.utilizationBps / 10000,
            color: Colors.white,
            trackColor: Colors.white24,
            height: 10,
            semanticsLabel: 'Monthly budgets used',
          ),
          const SizedBox(height: Space.x2_5),
          Row(
            children: [
              Icon(over ? LucideIcons.triangleAlert : LucideIcons.circleCheck, size: 14, color: Colors.white),
              const SizedBox(width: Space.x1),
              Expanded(
                child: Text(remainingText, style: t.bodyStrong.copyWith(color: Colors.white)),
              ),
              Icon(LucideIcons.clock, size: 14, color: soft),
              const SizedBox(width: Space.x1),
              Text(daysLeftLabel(o.daysLeft), style: t.label.copyWith(color: soft)),
            ],
          ),
          const SizedBox(height: Space.x2),
          Text(
            '${formatBps(o.elapsedBps, decimals: 0)} of month gone, '
            '${formatBps(o.utilizationBps, decimals: 0)} spent',
            style: t.caption.copyWith(color: soft),
          ),
          if (o.totalCommitted.isPositive) ...[
            const SizedBox(height: Space.x1),
            Text(
              '${budgetMoney(context, o.totalCommitted, sign: SignDisplay.always)} expected from upcoming subscriptions',
              style: t.caption.copyWith(color: soft),
            ),
          ],
          if (alerts.isNotEmpty) ...[
            const SizedBox(height: Space.x3),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: Space.x2_5, vertical: Space.x1_5),
              decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.18), borderRadius: Radii.rLg),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(LucideIcons.info, size: 13, color: Colors.white),
                  const SizedBox(width: Space.x1_5),
                  Flexible(
                    child: Text(alerts.join(' · '), style: t.label.copyWith(color: Colors.white)),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _BudgetsSkeleton extends StatelessWidget {
  const _BudgetsSkeleton();

  @override
  Widget build(BuildContext context) => const SkeletonPulse(
        child: ResponsiveCenter(
          padding: EdgeInsets.symmetric(horizontal: Space.gutter),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: Space.x4),
              SkeletonBox(width: 140, height: 28),
              SizedBox(height: Space.x5),
              CardSkeleton(height: 190, radius: Radii.xxxl),
              SizedBox(height: Space.section),
              CardSkeleton(height: 140),
              SizedBox(height: Space.x3),
              CardSkeleton(height: 140),
            ],
          ),
        ),
      );
}
