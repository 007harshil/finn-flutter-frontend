import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/router/routes.dart';
import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/time/dates.dart';
import '../../../kit/kit.dart';
import '../../../shared/presentation/async_view.dart';
import '../domain/subscription.dart';
import 'subscription_ui.dart';

/// Recurring costs. Upcoming charges are projections: nothing is paid or
/// deducted until the user marks a renewal as paid.
class SubscriptionsScreen extends ConsumerStatefulWidget {
  const SubscriptionsScreen({super.key});

  @override
  ConsumerState<SubscriptionsScreen> createState() => _SubscriptionsScreenState();
}

class _SubscriptionsScreenState extends ConsumerState<SubscriptionsScreen> {
  SubscriptionStatus _tab = SubscriptionStatus.active;

  @override
  Widget build(BuildContext context) {
    final header = PageHeader(
      title: 'Subscriptions',
      actions: [
        Tooltip(
          message: 'Add a subscription',
          child: LedgerButton(
            label: 'Add',
            icon: LucideIcons.plus,
            small: true,
            onPressed: () => context.push(AppRoutes.newSubscription),
          ),
        ),
      ],
    );
    return AsyncView<SubscriptionsOverview>(
      value: ref.watch(subscriptionsOverviewProvider),
      loading: Scaffold(backgroundColor: context.ink.paper, body: const SafeArea(child: LedgerPageSkeleton())),
      builder: (context, o) {
        final tab =
            (_tab == SubscriptionStatus.paused && o.paused.isEmpty) ||
                (_tab == SubscriptionStatus.cancelled && o.cancelled.isEmpty)
            ? SubscriptionStatus.active
            : _tab;
        final soon = [
          for (final s in o.active)
            if (subscriptionIsDueSoon(s, o.today)) s,
        ];
        final rest = [
          for (final s in o.active)
            if (!subscriptionIsDueSoon(s, o.today)) s,
        ];
        final hasInactive = o.paused.isNotEmpty || o.cancelled.isNotEmpty;
        return LedgerPage(
          storageKey: 'subscriptions',
          slivers: [
            PageBlock(child: header),
            if (o.isEmpty)
              PageBlock(
                top: Sp.xl,
                child: LedgerEmpty(
                  title: 'No subscriptions yet',
                  actionLabel: 'Add a subscription',
                  onAction: () => context.push(AppRoutes.newSubscription),
                ),
              )
            else ...[
              if (o.active.isNotEmpty) PageBlock(top: Sp.xxl, child: _Hero(overview: o)),
              if (hasInactive)
                PageBlock(
                  top: o.active.isNotEmpty ? Sp.section : Sp.xl,
                  child: LedgerSegmented<SubscriptionStatus>(
                    selected: tab,
                    onChanged: (s) => setState(() => _tab = s),
                    segments: [
                      LedgerSegment(SubscriptionStatus.active, 'Active', count: o.active.length),
                      if (o.paused.isNotEmpty)
                        LedgerSegment(SubscriptionStatus.paused, 'Paused', count: o.paused.length),
                      if (o.cancelled.isNotEmpty)
                        LedgerSegment(SubscriptionStatus.cancelled, 'Cancelled', count: o.cancelled.length),
                    ],
                  ),
                ),
              if (tab == SubscriptionStatus.active) ...[
                if (o.active.isEmpty)
                  PageBlock(
                    top: Sp.md,
                    child: LedgerEmpty(
                      title: 'No active subscriptions',
                      actionLabel: 'Add a subscription',
                      onAction: () => context.push(AppRoutes.newSubscription),
                    ),
                  ),
                if (soon.isNotEmpty)
                  PageBlock(
                    top: hasInactive ? Sp.xl : Sp.section,
                    child: LedgerSection(
                      title: 'Due soon',
                      count: soon.length,
                      child: _List(items: soon, today: o.today),
                    ),
                  ),
                if (rest.isNotEmpty)
                  PageBlock(
                    top: soon.isNotEmpty || !hasInactive ? Sp.section : Sp.xl,
                    child: LedgerSection(
                      title: soon.isEmpty ? 'Active' : 'Later',
                      count: rest.length,
                      child: _List(items: rest, today: o.today),
                    ),
                  ),
              ] else
                PageBlock(
                  top: Sp.xl,
                  child: _List(items: tab == SubscriptionStatus.paused ? o.paused : o.cancelled, today: o.today),
                ),
            ],
          ],
        );
      },
    );
  }
}

/// Monthly cost of every active plan as the one number, the yearly cost
/// and the next 30 days beneath, and what share of income it takes.
class _Hero extends StatelessWidget {
  const _Hero({required this.overview});

  final SubscriptionsOverview overview;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final t = context.type;
    final o = overview;
    final share = o.incomeShareBps;
    final impact = o.incomeImpact;
    final hidden = AmountVisibility.hiddenOf(context);
    // Biggest plans first, by price per charge.
    final plans = [...o.active]..sort((x, y) => y.amount.paise.compareTo(x.amount.paise));
    final top = plans.take(4).toList();
    final rest = plans.skip(4).fold<int>(0, (sum, x) => sum + x.amount.paise);
    final hues = [for (var i = 0; i < top.length; i++) c.tint(i * 3 + 2).$1];
    // Next 30 days in four weeks.
    final weeks = List<int>.filled(4, 0);
    for (final e in o.upcoming) {
      final w = (daysBetween(o.today, e.date) ~/ 7).clamp(0, 3);
      weeks[w] += e.subscription.amount.paise;
    }
    final peak = weeks.indexOf(weeks.reduce((x, y) => x > y ? x : y));
    return KhataPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MergeSemantics(
            child: Row(
              children: [
                KhataDonut(
                  size: 112,
                  stroke: 15,
                  parts: [
                    for (var i = 0; i < top.length; i++) BarPart(top[i].amount.paise.toDouble(), hues[i]),
                    if (rest > 0) BarPart(rest.toDouble(), c.lineStrong),
                  ],
                  center: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('${o.active.length}', style: t.figure.copyWith(fontSize: 22)),
                      Text(o.active.length == 1 ? 'plan' : 'plans', style: t.small),
                    ],
                  ),
                ),
                const SizedBox(width: Sp.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Per month', style: t.label),
                      const SizedBox(height: 2),
                      AnimatedAmount(
                        o.monthly,
                        style: t.figureL,
                        decimals: DecimalDisplay.none,
                        fit: true,
                        animateOnMount: true,
                      ),
                      const SizedBox(height: Sp.xs),
                      _Figure(label: 'Per year', amount: o.annual),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Sp.md),
          for (var i = 0; i < top.length; i++)
            KhataKey(
              color: hues[i],
              label: top[i].name,
              value: AmountText(top[i].amount, style: t.figureSmall.copyWith(color: c.ink), decimals: DecimalDisplay.none),
            ),
          if (o.upcoming.isNotEmpty) ...[
            const SizedBox(height: Sp.lg),
            Row(
              children: [
                Expanded(child: Text('Next 30 days', style: t.labelStrong)),
                AmountText(o.upcomingTotal, style: t.figureSmall.copyWith(color: c.ink), decimals: DecimalDisplay.none),
              ],
            ),
            const SizedBox(height: Sp.sm),
            KhataColumns(
              height: 72,
              semanticLabel: hidden ? null : 'Charges in each of the next four weeks',
              columns: [
                for (var w = 0; w < 4; w++)
                  KhataColumn(w == 0 ? 'This week' : 'Week ${w + 1}', weeks[w].toDouble(), highlight: w == peak),
              ],
            ),
          ],
          if (share != null && impact != null) ...[
            const SizedBox(height: Sp.md),
            Text(
              "${(share / 100).toStringAsFixed(1)}% of last month's income",
              style: t.label.copyWith(color: impact.color(c)),
            ),
          ],
        ],
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.amount});

  final String label;
  final Money amount;

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: t.label),
        const SizedBox(height: 2),
        AmountText(amount, style: t.figure, decimals: DecimalDisplay.none),
      ],
    );
  }
}

class _List extends ConsumerWidget {
  const _List({required this.items, required this.today});

  final List<Subscription> items;
  final DateTime today;

  @override
  Widget build(BuildContext context, WidgetRef ref) => LedgerPanel(
    dividerIndent: Sp.lg + 40 + Sp.md + 2,
    children: [
      for (final s in items)
        KeyedSubtree(
          key: ValueKey(s.id),
          child: SubscriptionTile(
            subscription: s,
            today: today,
            onTap: () => context.push(AppRoutes.subscription(s.id)),
            onMarkPaid: s.isActive && subscriptionDaysUntil(s, today) <= 0
                ? () => markSubscriptionPaid(context, ref, s)
                : null,
          ),
        ),
    ],
  );
}
