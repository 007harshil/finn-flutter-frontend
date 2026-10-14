import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/router/routes.dart';
import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
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
                  message:
                      'Add OTT, music, phone, gym or cloud plans to see your monthly cost '
                      'and get reminded before each renewal.',
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
                      message: 'Paused and cancelled plans do not count towards your monthly cost.',
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
    return MergeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Per month', style: t.label),
          const SizedBox(height: Sp.xs),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: AnimatedAmount(
                  o.monthly,
                  style: t.figureXL,
                  decimals: DecimalDisplay.none,
                  fit: true,
                  animateOnMount: true,
                ),
              ),
              const SizedBox(width: Sp.sm),
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Text('${o.active.length} ${o.active.length == 1 ? 'plan' : 'plans'}', style: t.figureSmall),
              ),
            ],
          ),
          const SizedBox(height: Sp.lg),
          Row(
            children: [
              Expanded(child: _Figure(label: 'Per year', amount: o.annual)),
              Expanded(child: _Figure(label: 'Next 30 days', amount: o.upcomingTotal)),
            ],
          ),
          if (share != null && impact != null) ...[
            const SizedBox(height: Sp.lg),
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
