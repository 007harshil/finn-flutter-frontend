import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/router/routes.dart';
import '../../../core/time/dates.dart';
import '../../../design_system/design_system.dart';
import '../../../design_system/luxe/luxe.dart';
import '../../../shared/presentation/luxe_async.dart';
import '../../../shared/presentation/luxe_page.dart';
import '../domain/subscription.dart';
import 'subscription_ui.dart';

/// Recurring costs. Upcoming charges are projections: nothing is paid or
/// deducted until the user marks a renewal as paid.
///
/// Top to bottom: the title; an obsidian card with the monthly commitment
/// and a 30-day renewal dial (each expected charge lands on the day it is
/// due, today at the top); the share of income it takes; what renews next;
/// Active / Paused / Cancelled; the plans themselves.
class SubscriptionsScreen extends ConsumerStatefulWidget {
  const SubscriptionsScreen({super.key});

  @override
  ConsumerState<SubscriptionsScreen> createState() => _SubscriptionsScreenState();
}

class _SubscriptionsScreenState extends ConsumerState<SubscriptionsScreen> {
  SubscriptionStatus _tab = SubscriptionStatus.active;

  @override
  Widget build(BuildContext context) {
    final overview = ref.watch(subscriptionsOverviewProvider);
    return LuxeDetailPage(
      title: 'Subscriptions',
      storageKey: 'subscriptions-list',
      actions: [
        LuxeIconButton(
          icon: LucideIcons.plus,
          tooltip: 'Add a subscription',
          style: LuxeIconStyle.ink,
          size: 40,
          onPressed: () => context.push(AppRoutes.newSubscription),
        ),
      ],
      slivers: [
        luxeBox(
          const Reveal(
            child: LuxePageTitle(
              eyebrow: 'Recurring',
              title: 'Subscriptions',
              subtitle: 'Renewals are expected, not paid — mark each one when it is charged.',
            ),
          ),
          top: 4,
          bottom: 22,
        ),
        SliverToBoxAdapter(
          child: LuxeAsync<SubscriptionsOverview>(
            value: overview,
            loading: const LuxePageSkeleton(title: false, hero: 260, rows: 3),
            errorTitle: 'Could not load your subscriptions',
            builder: (context, o) => _Body(
              overview: o,
              tab: _tab,
              onTab: (t) => setState(() => _tab = t),
              onMarkPaid: (s) => markSubscriptionPaid(context, ref, s),
            ),
          ),
        ),
      ],
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.overview, required this.tab, required this.onTab, required this.onMarkPaid});

  final SubscriptionsOverview overview;
  final SubscriptionStatus tab;
  final ValueChanged<SubscriptionStatus> onTab;
  final ValueChanged<Subscription> onMarkPaid;

  @override
  Widget build(BuildContext context) {
    final p = context.luxe;
    final o = overview;
    if (o.isEmpty) {
      return ResponsiveCenter(
        padding: const EdgeInsets.symmetric(horizontal: LuxeSpace.gutter),
        child: LuxeEmpty(
          icon: LucideIcons.repeat,
          title: 'No subscriptions yet',
          message:
              'Add OTT, music, phone, gym or cloud plans to see your monthly commitment '
              'and get reminded before each renewal.',
          actionLabel: 'Add a subscription',
          actionIcon: LucideIcons.plus,
          onAction: () => context.push(AppRoutes.newSubscription),
        ),
      );
    }
    final items = switch (tab) {
      SubscriptionStatus.active => o.active,
      SubscriptionStatus.paused => o.paused,
      SubscriptionStatus.cancelled => o.cancelled,
    };
    return ResponsiveCenter(
      padding: const EdgeInsets.symmetric(horizontal: LuxeSpace.gutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Reveal(index: 1, scale: 0.97, child: _Hero(overview: o)),
          if (o.overdueCount > 0) ...[
            const SizedBox(height: 14),
            Reveal(
              index: 2,
              child: LuxeNote(
                icon: LucideIcons.triangleAlert,
                tone: p.negative,
                message: o.overdueCount == 1
                    ? 'One renewal is past its due date and not marked as paid. Your balance has not changed.'
                    : '${o.overdueCount} renewals are past their due date and not marked as paid. '
                          'Your balance has not changed.',
              ),
            ),
          ],
          const SizedBox(height: LuxeSpace.section),
          Reveal(index: 3, child: _Upcoming(overview: o)),
          const SizedBox(height: LuxeSpace.section),
          Reveal(
            index: 4,
            child: LuxeSegmented<SubscriptionStatus>(
              segments: [
                LuxeSegment(SubscriptionStatus.active, 'Active', count: o.active.length),
                LuxeSegment(SubscriptionStatus.paused, 'Paused', count: o.paused.length),
                LuxeSegment(SubscriptionStatus.cancelled, 'Cancelled', count: o.cancelled.length),
              ],
              selected: tab,
              onChanged: onTab,
            ),
          ),
          const SizedBox(height: 16),
          AnimatedSwitcher(
            duration: context.reduceMotion ? Duration.zero : LuxeDurations.base,
            switchInCurve: LuxeCurves.arrive,
            switchOutCurve: LuxeCurves.leave,
            layoutBuilder: (current, previous) =>
                Stack(alignment: Alignment.topCenter, children: [...previous, ?current]),
            child: KeyedSubtree(
              key: ValueKey(tab),
              child: items.isEmpty
                  ? _EmptyTab(tab: tab)
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < items.length; i++)
                          Padding(
                            key: ValueKey(items[i].id),
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Reveal(
                              index: 5 + i,
                              child: SubscriptionTile(
                                subscription: items[i],
                                today: o.today,
                                onTap: () => context.push(AppRoutes.subscription(items[i].id)),
                                onMarkPaid: items[i].isActive && !items[i].nextDueDate.isAfter(o.today)
                                    ? () => onMarkPaid(items[i])
                                    : null,
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
          ),
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
    final p = context.luxe;
    final t = context.lt;
    final o = overview;
    final impact = o.incomeImpact;
    final share = o.incomeShareBps;
    final soft = p.onObsidianSoft;
    return LuxeObsidian(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: LuxeFigure(
                  label: 'Monthly commitment',
                  onDark: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LuxeAmount(
                        o.monthly,
                        countFromZero: true,
                        style: t.display.copyWith(fontSize: 40, color: p.onObsidian),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${o.active.length} active · each plan as a monthly cost',
                        maxLines: 2,
                        style: t.caption.c(soft),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _RenewalDial(overview: o),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(height: 1, child: ColoredBox(color: p.onObsidian.withValues(alpha: 0.1))),
          const SizedBox(height: 16),
          LuxeFigureRow(
            onDark: true,
            children: [
              LuxeFigure(label: 'Per year', onDark: true, child: LuxeFigureAmount(o.annual, onDark: true)),
              LuxeFigure(label: 'Next 30 days', onDark: true, child: LuxeFigureAmount(o.upcomingTotal, onDark: true)),
            ],
          ),
          if (impact != null && share != null) ...[
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(child: Text('Share of last month’s income', style: t.label.c(p.onObsidian))),
                LuxeStatus(label: impact.label, color: p.gold, icon: impact.icon),
              ],
            ),
            const SizedBox(height: 8),
            LuxeProgressLine(
              value: math.min(share, 10000) / 10000,
              color: impact == IncomeImpact.healthy ? p.gold : impact.tone(LuxePalette.dark),
              track: p.onObsidian.withValues(alpha: 0.1),
              height: 4,
            ),
            const SizedBox(height: 6),
            Text('${(share / 100).toStringAsFixed(1)}% of income · ${impact.description}', style: t.micro.c(soft)),
          ],
        ],
      ),
    );
  }
}

/// The next 30 days as a dial: today at twelve o'clock, time running
/// clockwise, one bead per expected charge (bigger for larger charges).
/// The beads land one after another; the count sits in the middle.
class _RenewalDial extends StatelessWidget {
  const _RenewalDial({required this.overview});

  final SubscriptionsOverview overview;

  @override
  Widget build(BuildContext context) {
    final p = context.luxe;
    final t = context.lt;
    final o = overview;
    final maxPaise = o.upcoming.fold<int>(1, (m, e) => math.max(m, e.subscription.amount.paise));
    final beads = [
      for (final e in o.upcoming)
        (
          day: daysBetween(o.today, e.date).clamp(0, 30) / 30.0,
          weight: 0.45 + 0.55 * (e.subscription.amount.paise / maxPaise),
        ),
    ];
    final n = o.upcoming.length;
    return Semantics(
      label: n == 0 ? 'No renewals in the next 30 days' : '$n renewals expected in the next 30 days',
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: 112,
        child: DrawIn(
          value: 1,
          delay: const Duration(milliseconds: 200),
          duration: const Duration(milliseconds: 1600),
          builder: (context, v) => CustomPaint(
            painter: _DialPainter(
              beads: beads,
              progress: v,
              track: p.onObsidian.withValues(alpha: 0.1),
              tick: p.onObsidian.withValues(alpha: 0.28),
              bead: p.gold,
              hand: p.onObsidian,
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('$n', style: t.figure.copyWith(fontSize: 28, color: p.onObsidian)),
                  Text('IN 30 DAYS', style: t.eyebrow.copyWith(fontSize: 8, color: p.onObsidianSoft)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DialPainter extends CustomPainter {
  _DialPainter({
    required this.beads,
    required this.progress,
    required this.track,
    required this.tick,
    required this.bead,
    required this.hand,
  });

  final List<({double day, double weight})> beads;
  final double progress;
  final Color track;
  final Color tick;
  final Color bead;
  final Color hand;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 8;
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = track,
    );
    Offset at(double f, double radius) {
      final a = -math.pi / 2 + f * math.pi * 2;
      return c + Offset(math.cos(a), math.sin(a)) * radius;
    }

    final tp = Paint()
      ..color = tick
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 30; i++) {
      final major = i % 7 == 0;
      tp.strokeWidth = major ? 1.4 : 0.8;
      canvas.drawLine(at(i / 30, r - (major ? 7 : 4)), at(i / 30, r - 1), tp);
    }
    // Sweep of time already "revealed" by the entrance.
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r),
      -math.pi / 2,
      math.pi * 2 * progress,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          transform: const GradientRotation(-math.pi / 2),
          colors: [bead.withValues(alpha: 0), bead.withValues(alpha: 0.7)],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );
    for (final b in beads) {
      if (b.day > progress) continue;
      final land = ((progress - b.day) * 8).clamp(0.0, 1.0);
      final pos = at(b.day, r);
      final radius = (2.4 + 3.2 * b.weight) * Curves.easeOutBack.transform(land);
      canvas.drawCircle(pos, radius + 4, Paint()..color = bead.withValues(alpha: 0.18 * land));
      canvas.drawCircle(pos, radius, Paint()..color = bead);
    }
    // Today marker.
    canvas.drawCircle(at(0, r), 3, Paint()..color = hand);
  }

  @override
  bool shouldRepaint(_DialPainter o) => o.progress != progress || o.beads.length != beads.length;
}

/// Expected charges in the next 30 days (projections, not payments), each
/// with a small calendar leaf.
class _Upcoming extends StatelessWidget {
  const _Upcoming({required this.overview});

  static const _limit = 5;

  final SubscriptionsOverview overview;

  @override
  Widget build(BuildContext context) {
    final t = context.lt;
    final o = overview;
    final shown = o.upcoming.take(_limit).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LuxeEyebrowHeader(
          label: 'Expected renewals',
          caption: o.upcoming.isEmpty
              ? 'Nothing in the next 30 days'
              : 'Next 30 days · ${o.upcoming.length} ${o.upcoming.length == 1 ? 'charge' : 'charges'}'
                    ' · ${maskedMoney(context, o.upcomingTotal)}',
        ),
        const SizedBox(height: 12),
        if (shown.isEmpty)
          Text('No renewals are expected in the next 30 days.', style: t.bodySoft)
        else
          LuxeCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: Column(
              children: [
                for (var i = 0; i < shown.length; i++) ...[
                  if (i > 0) const LuxeHairline(indent: 58),
                  _UpcomingRow(
                    key: ValueKey('${shown[i].subscription.id}-${shown[i].date}'),
                    charge: shown[i],
                    today: o.today,
                  ),
                ],
                if (o.upcoming.length > shown.length) ...[
                  const LuxeHairline(),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text('+ ${o.upcoming.length - shown.length} more expected', style: t.caption),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _UpcomingRow extends StatelessWidget {
  const _UpcomingRow({super.key, required this.charge, required this.today});

  final ExpectedCharge charge;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final p = context.luxe;
    final t = context.lt;
    final s = charge.subscription;
    final soon = daysBetween(today, charge.date) <= 3;
    return Squish(
      onTap: () => context.push(AppRoutes.subscription(s.id)),
      scale: 0.98,
      semanticLabel: '${s.name}, ${DateFormats.relativeDay(charge.date, today)}, expected',
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 60),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              _DateLeaf(date: charge.date, highlight: soon),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.label.w(700).c(p.ink)),
                    Text('${DateFormats.relativeDay(charge.date, today)} · expected', style: t.caption),
                  ],
                ),
              ),
              LuxeAmount(s.amount, fit: false, style: t.number.copyWith(fontSize: 14)),
            ],
          ),
        ),
      ),
    );
  }
}

/// A tiny calendar page: month on top, day in serif.
class _DateLeaf extends StatelessWidget {
  const _DateLeaf({required this.date, this.highlight = false});

  final DateTime date;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final p = context.luxe;
    final t = context.lt;
    return ExcludeSemantics(
      child: Container(
        width: 44,
        height: 46,
        decoration: BoxDecoration(
          color: highlight ? p.goldSoft : p.canvas,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: highlight ? p.gold.withValues(alpha: 0.5) : p.line),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              DateFormats.shortMonth.format(date).toUpperCase(),
              style: t.eyebrow.copyWith(fontSize: 8.5, color: highlight ? p.goldInk : p.inkMute),
            ),
            Text('${date.day}', style: t.figure.copyWith(fontSize: 20, height: 1.1)),
          ],
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
    SubscriptionStatus.active => LuxeEmpty(
      icon: LucideIcons.listX,
      title: 'No active subscriptions',
      message: 'Paused and cancelled plans do not count towards your monthly commitment.',
      actionLabel: 'Add a subscription',
      actionIcon: LucideIcons.plus,
      onAction: () => context.push(AppRoutes.newSubscription),
    ),
    SubscriptionStatus.paused => const LuxeEmpty(
      icon: LucideIcons.pause,
      title: 'Nothing paused',
      message: 'Pause a plan you are taking a break from. It stops counting until you resume it.',
    ),
    SubscriptionStatus.cancelled => const LuxeEmpty(
      icon: LucideIcons.circleX,
      title: 'Nothing cancelled',
      message: 'Cancelled plans stay here with their payment history.',
    ),
  };
}
