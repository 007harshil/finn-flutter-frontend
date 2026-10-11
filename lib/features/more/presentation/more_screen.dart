import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/di/core_providers.dart';
import '../../../app/di/data_providers.dart';
import '../../../app/router/routes.dart';
import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/time/dates.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/presentation/async_view.dart';
import '../../emergency_fund/domain/emergency_fund.dart';
import '../../home/application/home_overview.dart';
import '../../net_worth/domain/net_worth.dart';

/// Financial overview hub: net worth teaser and every module with a live
/// one-line summary, then app-level settings.
class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final t = context.text;
    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          key: const PageStorageKey<String>('more'),
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(Space.gutter, Space.x4, Space.gutter, context.bottomClearance),
              sliver: SliverToBoxAdapter(
                child: ResponsiveCenter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Semantics(header: true, child: Text('Financial overview', style: t.pageTitle)),
                      const SizedBox(height: Space.x1),
                      Text('Everything you own, owe and have planned, in one place.', style: t.caption),
                      const SizedBox(height: Space.x5),
                      const StaggeredEntrance(index: 0, child: _NetWorthTeaser()),
                      const SizedBox(height: Space.section),
                      const StaggeredEntrance(
                        index: 1,
                        child: _Group(
                          title: 'Money modules',
                          children: [
                            _LoansTile(),
                            _SubscriptionsTile(),
                            _PendingTile(),
                            _EmergencyTile(),
                          ],
                        ),
                      ),
                      const SizedBox(height: Space.section),
                      const StaggeredEntrance(
                        index: 2,
                        child: _Group(
                          title: 'Understand',
                          children: [_InsightsTile(), _NetWorthTile(), _TimelineTile()],
                        ),
                      ),
                      const SizedBox(height: Space.section),
                      StaggeredEntrance(
                        index: 3,
                        child: _Group(
                          title: 'App',
                          children: [
                            _ModuleTile(
                              icon: LucideIcons.settings,
                              color: c.accentTransactions,
                              title: 'Settings',
                              summary: const Text('Profile, privacy, alerts and appearance'),
                              route: AppRoutes.settings,
                            ),
                            _ModuleTile(
                              icon: LucideIcons.tags,
                              color: c.accentBudgets,
                              title: 'Categories',
                              summary: const Text('Organise how income and spending are grouped'),
                              route: AppRoutes.categories,
                            ),
                            _ModuleTile(
                              icon: LucideIcons.download,
                              color: c.accentNetWorth,
                              title: 'Export data',
                              summary: const Text('Download a copy of your records'),
                              route: AppRoutes.export,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: Space.x5),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(LucideIcons.lock, size: 12, color: c.textTertiary),
                          const SizedBox(width: Space.x1_5),
                          Text('Your data stays on this device', style: t.micro),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NetWorthTeaser extends ConsumerWidget {
  const _NetWorthTeaser();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncView<NetWorthSnapshot>(
      value: ref.watch(netWorthProvider),
      loading: const SkeletonPulse(child: CardSkeleton(height: 132)),
      builder: (context, nw) {
        final c = context.colors;
        final t = context.text;
        return FinnCard(
          onTap: () => context.push(AppRoutes.netWorth),
          semanticLabel: 'Net worth. Open details',
          padding: const EdgeInsets.all(Space.x5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconTile(
                    icon: LucideIcons.scale,
                    background: c.accentNetWorth,
                    foreground: Colors.white,
                    size: 28,
                    radius: Radii.md,
                    iconSize: 15,
                  ),
                  const SizedBox(width: Space.x2_5),
                  Expanded(child: Text('NET WORTH', style: t.sectionTitle)),
                  Icon(LucideIcons.chevronRight, size: 16, color: c.textTertiary),
                ],
              ),
              const SizedBox(height: Space.x3),
              AnimatedAmount(nw.netWorth, style: t.amountLarge, decimals: DecimalDisplay.none, fit: true),
              const SizedBox(height: Space.x2),
              Row(
                children: [
                  Expanded(child: _Mini(label: 'Own', amount: nw.totalAssets, color: c.positive)),
                  Expanded(child: _Mini(label: 'Owe', amount: nw.liabilities, color: c.negative)),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Mini extends StatelessWidget {
  const _Mini({required this.label, required this.amount, required this.color});

  final String label;
  final Money amount;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final t = context.text;
    return MergeSemantics(
      child: Row(
        children: [
          Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: Space.x1_5),
          Text('$label ', style: t.caption),
          Flexible(child: AmountText(amount, compact: true, style: t.amountSmall)),
        ],
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final t = context.text;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: Space.x1, bottom: Space.x2_5),
          child: Semantics(header: true, child: Text(title.toUpperCase(), style: t.eyebrow)),
        ),
        FinnCard(
          padding: EdgeInsets.zero,
          child: Material(
            type: MaterialType.transparency,
            child: Column(
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0) const FinnDivider(indent: 64),
                  children[i],
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// A module entry with its accent colour and a live summary line.
class _ModuleTile extends StatelessWidget {
  const _ModuleTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.summary,
    required this.route,
  });

  final IconData icon;
  final Color color;
  final String title;
  final Widget summary;
  final String route;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    return Semantics(
      button: true,
      child: InkWell(
        onTap: () => context.push(route),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.x4, vertical: Space.x3),
            child: Row(
              children: [
                IconTile(
                  icon: icon,
                  background: color.withValues(alpha: c.isDark ? 0.2 : 0.12),
                  foreground: color,
                  size: 36,
                  radius: Radii.lg,
                  iconSize: 18,
                ),
                const SizedBox(width: Space.x3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: t.bodyStrong),
                      const SizedBox(height: Space.x0_5),
                      DefaultTextStyle.merge(
                        style: t.caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        child: summary,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: Space.x2),
                Icon(LucideIcons.chevronRight, size: 16, color: c.textTertiary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Builds a summary line from an async value; blank while loading.
Widget _summary<T>(AsyncValue<T> v, String Function(T data) text) {
  final data = v.value;
  if (data == null) return Text(v.hasError ? 'Unavailable right now' : ' ');
  return Text(text(data));
}

String _amount(Money m) => m.format(decimals: DecimalDisplay.none);

class _LoansTile extends ConsumerWidget {
  const _LoansTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _ModuleTile(
      icon: LucideIcons.landmark,
      color: context.colors.accentLoans,
      title: 'Loans & EMIs',
      route: AppRoutes.loans,
      summary: _AmountAware(
        hiddenText: 'Loans and repayment schedules',
        child: _summary<DebtOverview>(ref.watch(debtOverviewProvider), (d) {
          if (!d.hasDebt) return 'No active loans';
          final next = d.nextDueDate;
          final due = next == null ? '' : ' · next EMI ${DateFormats.dayMonth.format(next)}';
          return '${_amount(d.totalOutstanding)} outstanding$due';
        }),
      ),
    );
  }
}

class _SubscriptionsTile extends ConsumerWidget {
  const _SubscriptionsTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _ModuleTile(
      icon: LucideIcons.repeat,
      color: context.colors.accentSubscriptions,
      title: 'Subscriptions',
      route: AppRoutes.subscriptions,
      summary: _AmountAware(
        hiddenText: 'Recurring payments and renewals',
        child: _summary<SubscriptionOverview>(ref.watch(subscriptionOverviewProvider), (s) {
          if (s.activeCount == 0) return 'No active subscriptions';
          return '${_amount(s.monthlyCommitment)}/month · ${s.activeCount} active';
        }),
      ),
    );
  }
}

class _PendingTile extends ConsumerWidget {
  const _PendingTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _ModuleTile(
      icon: LucideIcons.handCoins,
      color: context.colors.accentPending,
      title: 'Pending payments',
      route: AppRoutes.pending,
      summary: _AmountAware(
        hiddenText: 'Money you owe and are owed',
        child: _summary<PendingOverview>(ref.watch(pendingOverviewProvider), (p) {
          if (p.activeCount == 0) return 'All settled up';
          return 'To pay ${_amount(p.toPay)} · to collect ${_amount(p.toCollect)}';
        }),
      ),
    );
  }
}

class _EmergencyTile extends ConsumerWidget {
  const _EmergencyTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _ModuleTile(
      icon: LucideIcons.shieldCheck,
      color: context.colors.accentEmergency,
      title: 'Emergency fund',
      route: AppRoutes.emergencyFund,
      summary: _summary<EmergencyFundStatus>(ref.watch(emergencyStatusProvider), (s) {
        if (s.level == EmergencyFundLevel.notConfigured) return 'Not set up yet';
        final m = s.coverageMonths;
        return m == null ? s.level.label : '${m.toStringAsFixed(1)} months of essentials covered';
      }),
    );
  }
}

class _InsightsTile extends StatelessWidget {
  const _InsightsTile();

  @override
  Widget build(BuildContext context) => _ModuleTile(
        icon: LucideIcons.chartColumn,
        color: context.colors.accentAnalytics,
        title: 'Insights & analytics',
        route: AppRoutes.analytics,
        summary: const Text('Trends, categories and spending patterns'),
      );
}

class _NetWorthTile extends ConsumerWidget {
  const _NetWorthTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _ModuleTile(
      icon: LucideIcons.scale,
      color: context.colors.accentNetWorth,
      title: 'Net worth',
      route: AppRoutes.netWorth,
      summary: _AmountAware(
        hiddenText: 'Assets minus liabilities',
        child: _summary<NetWorthSnapshot>(ref.watch(netWorthProvider), (n) => '${_amount(n.netWorth)} · assets minus liabilities'),
      ),
    );
  }
}

class _TimelineTile extends ConsumerWidget {
  const _TimelineTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(todayProvider.select((d) => d.monthKey));
    return _ModuleTile(
      icon: LucideIcons.history,
      color: context.colors.accentGoals,
      title: 'Timeline',
      route: AppRoutes.timeline,
      summary: _summary(ref.watch(storyChapterProvider(month)), (ch) => 'This month: ${ch.name}'),
    );
  }
}

/// Swaps a summary containing amounts for neutral text when balances are hidden.
class _AmountAware extends StatelessWidget {
  const _AmountAware({required this.child, required this.hiddenText});

  final Widget child;
  final String hiddenText;

  @override
  Widget build(BuildContext context) => AmountVisibility.hiddenOf(context) ? Text(hiddenText) : child;
}
