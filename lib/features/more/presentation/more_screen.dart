import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/di/data_providers.dart';
import '../../../app/router/routes.dart';
import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/presentation/async_view.dart';
import '../../home/application/home_overview.dart';
import '../../net_worth/domain/net_worth.dart';

/// Financial overview hub: net worth teaser, subscriptions, then app-level
/// settings.
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
                      // Other modules open from Home's quick-access grid;
                      // subscriptions have no tile there, so they live here.
                      const StaggeredEntrance(
                        index: 1,
                        child: _Group(title: 'Money', children: [_SubscriptionsTile()]),
                      ),
                      const SizedBox(height: Space.section),
                      StaggeredEntrance(
                        index: 2,
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

class _SubscriptionsTile extends ConsumerWidget {
  const _SubscriptionsTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(subscriptionOverviewProvider).value;
    final String summary;
    if (AmountVisibility.hiddenOf(context)) {
      summary = 'Recurring payments and renewals';
    } else if (s == null) {
      summary = ' ';
    } else if (s.activeCount == 0) {
      summary = 'No active subscriptions';
    } else {
      summary = '${s.monthlyCommitment.format(decimals: DecimalDisplay.none)}/month · ${s.activeCount} active';
    }
    return _ModuleTile(
      icon: LucideIcons.repeat,
      color: context.colors.accentSubscriptions,
      title: 'Subscriptions',
      route: AppRoutes.subscriptions,
      summary: Text(summary),
    );
  }
}
