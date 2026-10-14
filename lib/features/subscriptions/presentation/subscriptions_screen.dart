import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/router/routes.dart';
import '../../../core/money/money_format.dart';
import '../../../core/time/dates.dart';
import '../../../design_system/design_system.dart';
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
  static const _upcomingLimit = 5;
  SubscriptionStatus _tab = SubscriptionStatus.active;

  @override
  Widget build(BuildContext context) {
    final overview = ref.watch(subscriptionsOverviewProvider);
    return Scaffold(
      appBar: AppBar(
        actions: [
          FinnIconButton(
            icon: LucideIcons.plus,
            tooltip: 'Add a subscription',
            variant: FinnIconButtonVariant.filled,
            onPressed: () => context.push(AppRoutes.newSubscription),
          ),
          const SizedBox(width: Space.x3),
        ],
      ),
      body: AsyncView<SubscriptionsOverview>(
        value: overview,
        loading: const _Skeleton(),
        builder: (context, o) {
          final items = switch (_tab) {
            SubscriptionStatus.active => o.active,
            SubscriptionStatus.paused => o.paused,
            SubscriptionStatus.cancelled => o.cancelled,
          };
          return CustomScrollView(
            key: const PageStorageKey('subscriptions-list'),
            slivers: [
              _boxed(const StaggeredEntrance(child: _Header())),
              if (o.isEmpty)
                _boxed(Padding(
                  padding: const EdgeInsets.only(top: Space.x6),
                  child: EmptyState(
                    icon: LucideIcons.repeat,
                    title: 'No subscriptions yet',
                    message: 'Add OTT, music, phone, gym or cloud plans to see your monthly commitment '
                        'and get reminded before each renewal.',
                    actionLabel: 'Add a subscription',
                    actionIcon: LucideIcons.plus,
                    onAction: () => context.push(AppRoutes.newSubscription),
                  ),
                ))
              else ...[
                _boxed(StaggeredEntrance(index: 1, child: _Hero(overview: o))),
                if (o.overdueCount > 0)
                  _boxed(Padding(
                    padding: const EdgeInsets.only(top: Space.x3),
                    child: InfoBanner(
                      tone: FinnTone.warning,
                      icon: LucideIcons.triangleAlert,
                      message: o.overdueCount == 1
                          ? 'One renewal is past its due date and not marked as paid. Your balance has not changed.'
                          : '${o.overdueCount} renewals are past their due date and not marked as paid. '
                              'Your balance has not changed.',
                    ),
                  )),
                _boxed(StaggeredEntrance(
                  index: 2,
                  child: _Upcoming(overview: o, limit: _upcomingLimit),
                )),
                _boxed(Padding(
                  padding: const EdgeInsets.only(top: Space.section, bottom: Space.x1),
                  child: SegmentedTabs<SubscriptionStatus>(
                    items: [
                      SegmentItem(SubscriptionStatus.active, 'Active', count: o.active.length),
                      SegmentItem(SubscriptionStatus.paused, 'Paused', count: o.paused.length),
                      SegmentItem(SubscriptionStatus.cancelled, 'Cancelled', count: o.cancelled.length),
                    ],
                    selected: _tab,
                    onChanged: (s) => setState(() => _tab = s),
                  ),
                )),
                if (items.isEmpty)
                  _boxed(Padding(
                    padding: const EdgeInsets.only(top: Space.x6),
                    child: _EmptyTab(tab: _tab),
                  ))
                else
                  SliverList.builder(
                    itemCount: items.length,
                    itemBuilder: (context, i) {
                      final s = items[i];
                      final due = s.isActive && !s.nextDueDate.isAfter(o.today);
                      return ResponsiveCenter(
                        key: ValueKey(s.id),
                        padding: const EdgeInsets.fromLTRB(Space.gutter, Space.x2, Space.gutter, 0),
                        child: SubscriptionTile(
                          subscription: s,
                          today: o.today,
                          onTap: () => context.push(AppRoutes.subscription(s.id)),
                          onMarkPaid: due ? () => markSubscriptionPaid(context, ref, s) : null,
                        ),
                      );
                    },
                  ),
              ],
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
          Semantics(header: true, child: Text('Subscriptions', style: t.pageTitle)),
          const SizedBox(height: Space.x1),
          Text('Recurring costs. Upcoming charges are expected, not paid — mark each renewal when it is charged.',
              style: t.caption),
        ],
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.overview});

  final SubscriptionsOverview overview;

  @override
  Widget build(BuildContext context) {
    final t = context.text;
    final c = context.colors;
    final o = overview;
    final white70 = Colors.white.withValues(alpha: 0.75);
    final impact = o.incomeImpact;
    final share = o.incomeShareBps;
    return GradientHeroCard(
      watermark: LucideIcons.repeat,
      semanticLabel: 'Monthly commitment ${MoneyFormatter.spoken(o.monthly)}, '
          '${o.active.length} active subscriptions${impact == null ? '' : ', income impact ${impact.label}'}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('MONTHLY COMMITMENT', style: t.eyebrow.copyWith(color: white70)),
          const SizedBox(height: Space.x1),
          AnimatedAmount(o.monthly, style: t.amountHero.copyWith(color: Colors.white), fit: true),
          Text(
            '${o.active.length} active · monthly equivalent of every plan',
            style: t.caption.copyWith(color: white70),
          ),
          const SizedBox(height: Space.x4),
          Row(
            children: [
              Expanded(
                child: _HeroFigure(
                  label: 'Per year',
                  value: AmountText(o.annual, style: t.amountSmall.copyWith(color: Colors.white)),
                ),
              ),
              Expanded(
                child: _HeroFigure(
                  label: 'Next 30 days',
                  value: AmountText(o.upcomingTotal, style: t.amountSmall.copyWith(color: Colors.white)),
                ),
              ),
            ],
          ),
          if (impact != null && share != null) ...[
            const SizedBox(height: Space.x4),
            Row(
              children: [
                Icon(LucideIcons.chartPie, size: 14, color: white70),
                const SizedBox(width: Space.x1_5),
                Expanded(child: Text('Share of last month\'s income', style: t.label.copyWith(color: Colors.white))),
                StatusPill(label: impact.label, color: Colors.white, icon: impact.icon),
              ],
            ),
            const SizedBox(height: Space.x2),
            FinnProgressBar(
              value: math.min(share, 10000) / 10000,
              color: impact.color(c),
              trackColor: Colors.white.withValues(alpha: 0.18),
              semanticsLabel: 'Share of income',
            ),
            const SizedBox(height: Space.x1_5),
            Text(
              '${(share / 100).toStringAsFixed(1)}% of income · ${impact.description}',
              style: t.micro.copyWith(color: white70),
            ),
          ],
        ],
      ),
    );
  }
}

class _HeroFigure extends StatelessWidget {
  const _HeroFigure({required this.label, required this.value});

  final String label;
  final Widget value;

  @override
  Widget build(BuildContext context) => MergeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label.toUpperCase(), style: context.text.eyebrow.copyWith(color: Colors.white.withValues(alpha: 0.7))),
            const SizedBox(height: 2),
            value,
          ],
        ),
      );
}

/// Expected charges in the next 30 days (projections, not payments).
class _Upcoming extends StatelessWidget {
  const _Upcoming({required this.overview, required this.limit});

  final SubscriptionsOverview overview;
  final int limit;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final o = overview;
    final shown = o.upcoming.take(limit).toList();
    final hidden = AmountVisibility.hiddenOf(context);
    return Padding(
      padding: const EdgeInsets.only(top: Space.section),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            icon: LucideIcons.calendarClock,
            title: 'Expected renewals',
            subtitle: o.upcoming.isEmpty
                ? 'Nothing in the next 30 days'
                : 'Next 30 days · ${o.upcoming.length} ${o.upcoming.length == 1 ? 'charge' : 'charges'}'
                    '${hidden ? '' : ' · ${MoneyFormatter.format(o.upcomingTotal)}'}',
            tileColor: c.accentSubscriptions,
          ),
          const SizedBox(height: Space.x2),
          if (shown.isEmpty)
            FinnCard(
              variant: FinnCardVariant.muted,
              child: Text('No renewals are expected in the next 30 days.', style: t.caption),
            )
          else
            FinnCard(
              padding: const EdgeInsets.symmetric(horizontal: Space.x4, vertical: Space.x1),
              child: Column(
                children: [
                  for (var i = 0; i < shown.length; i++) ...[
                    if (i > 0) const FinnDivider(),
                    _UpcomingRow(
                      key: ValueKey('${shown[i].subscription.id}-${shown[i].date}'),
                      charge: shown[i],
                      today: o.today,
                    ),
                  ],
                  if (o.upcoming.length > shown.length) ...[
                    const FinnDivider(),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: Space.x2_5),
                      child: Text('+ ${o.upcoming.length - shown.length} more expected', style: t.caption),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _UpcomingRow extends StatelessWidget {
  const _UpcomingRow({super.key, required this.charge, required this.today});

  final ExpectedCharge charge;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final t = context.text;
    final s = charge.subscription;
    return InkWell(
      onTap: () => context.push(AppRoutes.subscription(s.id)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: Dimens.minTouch),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.x2),
          child: Row(
            children: [
              SubscriptionAvatar(categoryId: s.categoryId, size: 32),
              const SizedBox(width: Space.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.bodyStrong),
                    Text(
                      '${DateFormats.relativeDay(charge.date, today)} · expected',
                      style: t.caption,
                    ),
                  ],
                ),
              ),
              AmountText(s.amount, style: t.amountSmall),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyTab extends StatelessWidget {
  const _EmptyTab({required this.tab});

  final SubscriptionStatus tab;

  @override
  Widget build(BuildContext context) => switch (tab) {
        SubscriptionStatus.active => EmptyState(
            icon: LucideIcons.listX,
            title: 'No active subscriptions',
            message: 'Paused and cancelled plans do not count towards your monthly commitment.',
            actionLabel: 'Add a subscription',
            actionIcon: LucideIcons.plus,
            onAction: () => context.push(AppRoutes.newSubscription),
          ),
        SubscriptionStatus.paused => const EmptyState(
            icon: LucideIcons.pause,
            title: 'Nothing paused',
            message: 'Pause a plan you are taking a break from. It stops counting until you resume it.',
          ),
        SubscriptionStatus.cancelled => const EmptyState(
            icon: LucideIcons.circleX,
            title: 'Nothing cancelled',
            message: 'Cancelled plans stay here with their payment history.',
          ),
      };
}

class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) => const SkeletonPulse(
        child: Padding(
          padding: EdgeInsets.all(Space.gutter),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 180, height: 28),
              SizedBox(height: Space.x5),
              CardSkeleton(height: 200),
              SizedBox(height: Space.x5),
              CardSkeleton(height: 180),
              SizedBox(height: Space.x5),
              SkeletonBox(height: 44, radius: Radii.full),
              SizedBox(height: Space.x4),
              CardSkeleton(height: 84),
              SizedBox(height: Space.x2),
              CardSkeleton(height: 84),
            ],
          ),
        ),
      );
}
