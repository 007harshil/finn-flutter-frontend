import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/di/data_providers.dart';
import '../../../app/router/routes.dart';
import '../../../core/money/money_format.dart';
import '../../../kit/kit.dart';
import '../../home/application/home_overview.dart';
import '../../profile/presentation/profile_entry_card.dart';

/// Opens a menu destination. The side drawer closes itself first.
typedef MoreOpen = void Function(BuildContext context, String route);

void _push(BuildContext context, String route) => context.push(route);

/// Full-screen version of the menu at `/more` (deep links). The main entry
/// point is the side drawer ([MoreDrawer]) opened from each tab's header.
class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: context.ink.paper,
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          key: const PageStorageKey<String>('more'),
          slivers: [
            PageBlock(top: Sp.lg, bottom: Sp.xxl, child: const MoreMenu()),
          ],
        ),
      ),
    );
  }
}

/// Aligns row hairlines with the text (16 pad + 36 well + 14 gap).
const double _indent = Sp.lg + 36 + Sp.md + 2;

/// Profile, money modules, insights, then account settings.
/// Shared by [MoreScreen] and the drawer.
class MoreMenu extends StatelessWidget {
  const MoreMenu({super.key, this.open = _push});

  final MoreOpen open;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final t = context.type;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ProfileEntryCard(onTap: () => open(context, AppRoutes.account)),
        const SizedBox(height: Sp.xl),
        LedgerSection(
          title: 'Money',
          child: LedgerPanel(
            dividerIndent: _indent,
            children: [
              _Item(icon: LucideIcons.landmark, title: 'Loans & EMIs', route: AppRoutes.loans, open: open),
              _Item(icon: LucideIcons.handCoins, title: 'Pending payments', route: AppRoutes.pending, open: open),
              _SubscriptionsItem(open: open),
            ],
          ),
        ),
        const SizedBox(height: Sp.xl),
        LedgerSection(
          title: 'Insights',
          child: LedgerPanel(
            dividerIndent: _indent,
            children: [
              _NetWorthItem(open: open),
              _Item(icon: LucideIcons.chartColumnIncreasing, title: 'Insights', route: AppRoutes.analytics, open: open),
            ],
          ),
        ),
        const SizedBox(height: Sp.xl),
        LedgerSection(
          title: 'Account',
          child: LedgerPanel(
            dividerIndent: _indent,
            children: [
              _Item(icon: LucideIcons.settings, title: 'Settings', route: AppRoutes.settings, open: open),
              _Item(icon: LucideIcons.tags, title: 'Categories', route: AppRoutes.categories, open: open),
              _Item(icon: LucideIcons.download, title: 'Export data', route: AppRoutes.export, open: open),
            ],
          ),
        ),
        const SizedBox(height: Sp.lg),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.lock, size: 13, color: c.inkSoft),
            const SizedBox(width: Sp.xs + 2),
            Flexible(child: Text('Your data stays on this device', style: t.small, textAlign: TextAlign.center)),
          ],
        ),
      ],
    );
  }
}

class _Item extends StatelessWidget {
  const _Item({
    required this.icon,
    required this.title,
    required this.route,
    required this.open,
    this.subtitle,
    this.trailing,
    this.semanticLabel,
  });

  final IconData icon;
  final String title;
  final String route;
  final MoreOpen open;
  final String? subtitle;
  final Widget? trailing;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return LedgerRow(
      leading: IconWell(icon: icon, size: 36),
      title: title,
      subtitle: subtitle,
      trailing: trailing,
      chevron: true,
      semanticLabel: semanticLabel,
      onTap: () => open(context, route),
    );
  }
}

class _NetWorthItem extends ConsumerWidget {
  const _NetWorthItem({required this.open});
  final MoreOpen open;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nw = ref.watch(netWorthProvider).value;
    return _Item(
      icon: LucideIcons.scale,
      title: 'Net worth',
      route: AppRoutes.netWorth,
      open: open,
      semanticLabel: 'Net worth. Open details',
      trailing: nw == null
          ? null
          : AmountText(nw.netWorth, style: context.type.figure, decimals: DecimalDisplay.none),
    );
  }
}

class _SubscriptionsItem extends ConsumerWidget {
  const _SubscriptionsItem({required this.open});
  final MoreOpen open;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(subscriptionOverviewProvider).value;
    final String? summary;
    if (AmountVisibility.hiddenOf(context) || s == null) {
      summary = null;
    } else if (s.activeCount == 0) {
      summary = 'No active subscriptions';
    } else {
      summary = '${s.monthlyCommitment.format(decimals: DecimalDisplay.none)}/month · ${s.activeCount} active';
    }
    return _Item(
      icon: LucideIcons.repeat,
      title: 'Subscriptions',
      route: AppRoutes.subscriptions,
      open: open,
      subtitle: summary,
    );
  }
}
