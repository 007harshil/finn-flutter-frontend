import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/router/routes.dart';
import '../../../core/money/money_format.dart';
import '../../../design_system/design_system.dart' show AmountText, AmountVisibility, AnimatedAmount, BottomClearanceX;
import '../../../shared/presentation/async_view.dart';
import '../../../ui/ui.dart';
import '../domain/subscription.dart';
import 'subscription_ui.dart';

/// Recurring costs: the monthly total, then each plan soonest-renewing
/// first. Renewals are expected, not paid, until the user marks them.
class SubscriptionsScreen extends ConsumerStatefulWidget {
  const SubscriptionsScreen({super.key});

  @override
  ConsumerState<SubscriptionsScreen> createState() => _SubscriptionsScreenState();
}

class _SubscriptionsScreenState extends ConsumerState<SubscriptionsScreen> {
  SubscriptionStatus _tab = SubscriptionStatus.active;

  @override
  Widget build(BuildContext context) {
    return UiPage(
      title: 'Subscriptions',
      actions: [
        UiIconButton(
          icon: LucideIcons.plus,
          tooltip: 'Add a subscription',
          onPressed: () => context.push(AppRoutes.newSubscription),
        ),
      ],
      body: AsyncView<SubscriptionsOverview>(
        value: ref.watch(subscriptionsOverviewProvider),
        loading: const _Placeholder(),
        builder: (context, o) {
          if (o.isEmpty) {
            return Center(
              child: SingleChildScrollView(
                child: UiEmpty(
                  icon: LucideIcons.repeat,
                  title: 'No subscriptions yet',
                  message: 'Add streaming, phone, gym or cloud plans to see what they cost each month.',
                  action: 'Add a subscription',
                  onAction: () => context.push(AppRoutes.newSubscription),
                ),
              ),
            );
          }
          final tabs = [
            UiSegment(SubscriptionStatus.active, 'Active', count: o.active.length),
            if (o.paused.isNotEmpty) UiSegment(SubscriptionStatus.paused, 'Paused', count: o.paused.length),
            if (o.cancelled.isNotEmpty) UiSegment(SubscriptionStatus.cancelled, 'Cancelled', count: o.cancelled.length),
          ];
          final tab = tabs.any((s) => s.value == _tab) ? _tab : SubscriptionStatus.active;
          final items = switch (tab) {
            SubscriptionStatus.active => o.active,
            SubscriptionStatus.paused => o.paused,
            SubscriptionStatus.cancelled => o.cancelled,
          };
          return CustomScrollView(
            key: const PageStorageKey('subscriptions-list'),
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
                        if (tabs.length > 1) ...[
                          UiSegmented<SubscriptionStatus>(
                            segments: tabs,
                            selected: tab,
                            onChanged: (s) => setState(() => _tab = s),
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
                  child: UiEmpty(
                    icon: LucideIcons.listX,
                    title: 'No active subscriptions',
                    message: 'Paused and cancelled plans do not count towards the monthly total.',
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: UiSpace.gutter),
                  sliver: SliverList.builder(
                    itemCount: items.length,
                    itemBuilder: (context, i) => UiColumnWidth(
                      key: ValueKey(items[i].id),
                      child: UiPanelSlice(
                        first: i == 0,
                        last: i == items.length - 1,
                        child: _Row(subscription: items[i], today: o.today),
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

/// Monthly total, its share of income, the yearly cost and what is
/// expected over the next 30 days.
class _Summary extends StatelessWidget {
  const _Summary({required this.overview});

  final SubscriptionsOverview overview;

  @override
  Widget build(BuildContext context) {
    final c = UiColors.of(context);
    final t = UiType.of(context);
    final o = overview;
    final impact = o.incomeImpact;
    final share = o.incomeShareBps;
    final late = o.overdueCount;
    final caption = late > 0
        ? (late == 1 ? '1 renewal not marked paid' : '$late renewals not marked paid')
        : (share == null ? null : '${(share / 100).toStringAsFixed(share < 1000 ? 1 : 0)}% of last month’s income');
    return UiHero(
      label: 'Every month',
      value: AnimatedAmount(o.monthly, style: t.amount, decimals: DecimalDisplay.none, fit: true, animateOnMount: true),
      caption: caption,
      captionColor: late > 0 ? c.negative : impact?.color(c),
      footer: Row(
        children: [
          Expanded(
            child: UiStat(
              label: 'Every year',
              value: AmountText(o.annual, style: t.figureSmall, decimals: DecimalDisplay.none),
            ),
          ),
          const SizedBox(width: UiSpace.lg),
          Expanded(
            child: UiStat(
              label: 'Next 30 days',
              value: AmountText(o.upcomingTotal, style: t.figureSmall, decimals: DecimalDisplay.none),
            ),
          ),
        ],
      ),
    );
  }
}

class _Row extends ConsumerWidget {
  const _Row({required this.subscription, required this.today});

  final Subscription subscription;
  final DateTime today;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = UiColors.of(context);
    final t = UiType.of(context);
    final s = subscription;
    final due = subscriptionDue(c, s, today);
    final payable = s.isActive && !s.nextDueDate.isAfter(today);
    return UiListRow(
      leading: SubscriptionMark(categoryId: s.categoryId),
      title: s.name,
      subtitle: payable
          ? '${maskedSubscriptionAmount(context, s)} · ${due.label}'
          : (s.isActive ? '${s.frequency.label} · ${due.label}' : s.frequency.label),
      subtitleColor: due.color,
      semanticLabel: '${s.name}, ${AmountText.spokenLabel(s.amount)} ${s.frequency.label}, ${due.label}',
      chevron: !payable,
      trailing: payable
          ? UiChipButton(
              label: 'Mark paid',
              semanticLabel: 'Mark ${s.name} paid',
              onTap: () => markSubscriptionPaid(context, ref, s),
            )
          : AmountText(s.amount, style: t.figureSmall.copyWith(color: s.isActive ? null : c.inkSoft)),
      onTap: () => context.push(AppRoutes.subscription(s.id)),
    );
  }
}

/// "₹199" for inline copy, masked when balances are hidden.
String maskedSubscriptionAmount(BuildContext context, Subscription s) =>
    AmountVisibility.hiddenOf(context) ? MoneyFormatter.masked : AmountText.formatted(s.amount);

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
            UiPlaceholder(width: 90, height: 12),
            SizedBox(height: UiSpace.md),
            UiPlaceholder(width: 180, height: 40),
            SizedBox(height: UiSpace.section + UiSpace.lg),
            UiPlaceholder(height: 260, radius: UiRadius.panel),
          ],
        ),
      ),
    );
  }
}
