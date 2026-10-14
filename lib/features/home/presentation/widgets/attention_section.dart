import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../app/di/data_providers.dart';
import '../../../../app/router/routes.dart';
import '../../../../core/money/money_format.dart';
import '../../../../design_system/design_system.dart';
import '../../../../shared/presentation/async_view.dart';
import '../../../alerts/domain/alert.dart';
import '../../../alerts/presentation/alert_card.dart';
import '../../application/upcoming.dart';
import 'home_common.dart';

/// Top alerts from the alert engine, most urgent first, as a horizontal
/// carousel. The next card peeks in from the edge so it is obvious there is
/// more; the header badge and dots say exactly how many.
class AttentionSection extends ConsumerWidget {
  const AttentionSection({super.key});

  static const maxShown = 6;

  /// "2 urgent · 1 soon · 3 FYI" for the header.
  static String breakdown(List<FinancialAlert> alerts) {
    final counts = <AlertSeverity, int>{};
    for (final a in alerts) {
      counts[a.severity] = (counts[a.severity] ?? 0) + 1;
    }
    return [
      for (final s in AlertSeverity.values)
        if (counts[s] != null) '${counts[s]} ${s.label.toLowerCase()}',
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final value = ref.watch(activeAlertsProvider);
    final loaded = value.value;
    return HomeSection(
      icon: LucideIcons.shieldAlert,
      title: 'What needs attention',
      subtitle: loaded == null || loaded.isEmpty ? null : breakdown(loaded),
      count: loaded == null || loaded.isEmpty ? null : loaded.length,
      tileColor: c.attention,
      onAction: () => context.push(AppRoutes.alerts),
      child: AsyncView<List<FinancialAlert>>(
        value: value,
        loading: const SkeletonPulse(child: CardSkeleton(height: 220)),
        builder: (context, alerts) {
          if (alerts.isEmpty) {
            return HomeNoteCard(
              icon: LucideIcons.circleCheck,
              color: c.positive,
              title: 'All clear',
              message: 'Nothing needs your attention right now. Anything important will show up here.',
            );
          }
          return _AlertCarousel(alerts: alerts);
        },
      ),
    );
  }
}

class _AlertCarousel extends StatefulWidget {
  const _AlertCarousel({required this.alerts});

  final List<FinancialAlert> alerts;

  @override
  State<_AlertCarousel> createState() => _AlertCarouselState();
}

class _AlertCarouselState extends State<_AlertCarousel> {
  final _controller = PageController(viewportFraction: 0.87);

  /// Drives only the dots, so a swipe never rebuilds the cards.
  final _page = ValueNotifier<int>(0);

  @override
  void dispose() {
    _controller.dispose();
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final alerts = widget.alerts;
    final shown = alerts.take(AttentionSection.maxShown).toList();
    final more = alerts.length - shown.length;
    final pages = shown.length + (more > 0 ? 1 : 0);
    // Grow with the text size so larger fonts never clip.
    final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
    final height = 220 + (scale - 1).clamp(0.0, 1.5) * 96;

    Widget card(int i) =>
        AlertCard(key: ValueKey(shown[i].key), alert: shown[i], position: i + 1, total: alerts.length, expand: true);

    if (pages == 1) return SizedBox(height: height, child: card(0));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: height,
          child: PageView.builder(
            controller: _controller,
            padEnds: false,
            clipBehavior: Clip.none,
            itemCount: pages,
            onPageChanged: (p) {
              HapticFeedback.selectionClick();
              _page.value = p;
            },
            itemBuilder: (context, i) => Padding(
              padding: const EdgeInsetsDirectional.only(end: Space.x2_5),
              child: i < shown.length ? card(i) : _MoreCard(count: more, onTap: () => context.push(AppRoutes.alerts)),
            ),
          ),
        ),
        const SizedBox(height: Space.x3),
        ValueListenableBuilder<int>(
          valueListenable: _page,
          builder: (context, page, _) => _PageDots(count: pages, index: math.min(page, pages - 1)),
        ),
      ],
    );
  }
}

/// Dot indicator; the active dot stretches into a pill.
class _PageDots extends StatelessWidget {
  const _PageDots({required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      label: 'Alert ${index + 1} of $count',
      excludeSemantics: true,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < count; i++)
            AnimatedContainer(
              duration: context.motion.normal,
              curve: context.motion.standard,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: i == index ? 20 : 6,
              height: 6,
              decoration: BoxDecoration(color: i == index ? c.attention : c.border, borderRadius: Radii.rFull),
            ),
        ],
      ),
    );
  }
}

/// Last carousel page when there are more alerts than fit.
class _MoreCard extends StatelessWidget {
  const _MoreCard({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    return FinnCard(
      variant: FinnCardVariant.muted,
      radius: Radii.xxl,
      onTap: onTap,
      semanticLabel: 'View $count more alerts',
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconTile(
              icon: LucideIcons.layers,
              background: c.attention.withValues(alpha: 0.14),
              foreground: c.attention,
              size: 52,
              radius: Radii.full,
              iconSize: 24,
            ),
            const SizedBox(height: Space.x3),
            Text('+$count more', style: t.title),
            const SizedBox(height: Space.x1),
            Text('See every alert', style: t.caption),
          ],
        ),
      ),
    );
  }
}

/// EMIs and subscriptions due in the next [UpcomingWindow.days] days, with
/// the total to keep ready. The list scrolls inside a fixed-height card so
/// a busy week never pushes the rest of the dashboard down.
class UpcomingSection extends ConsumerWidget {
  const UpcomingSection({super.key});

  /// Rows visible before the list starts scrolling.
  static const visibleRows = 4;

  /// Lets tests tell this nested list apart from the page scroll.
  static const listRestorationId = 'nested_upcoming_list';

  static String routeFor(UpcomingItem i) => switch (i.kind) {
    UpcomingKind.loanPayment || UpcomingKind.loanReceipt => AppRoutes.loan(i.recordId),
    UpcomingKind.subscription => AppRoutes.subscription(i.recordId),
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    const days = UpcomingWindow.days;
    return HomeSection(
      icon: LucideIcons.calendarClock,
      title: 'Coming up',
      subtitle: 'Next $days days · projected, not yet paid',
      tileColor: c.accentLoans,
      child: AsyncView<UpcomingOverview>(
        value: ref.watch(upcomingCommitmentsProvider),
        loading: const SkeletonPulse(child: CardSkeleton(height: 240)),
        builder: (context, o) {
          if (o.items.isEmpty) {
            return HomeNoteCard(
              icon: LucideIcons.calendar,
              color: c.info,
              title: 'Nothing due soon',
              message: 'No EMIs or subscriptions are due in the next $days days.',
            );
          }
          return FinnCard(
            padding: EdgeInsets.zero,
            child: Material(
              type: MaterialType.transparency,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _UpcomingTotal(overview: o),
                  const FinnDivider(),
                  _UpcomingList(items: o.items),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// "₹8,000 to keep ready" for the window, so the user can arrange it early.
class _UpcomingTotal extends StatelessWidget {
  const _UpcomingTotal({required this.overview});

  final UpcomingOverview overview;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final o = overview;
    final n = o.outflowCount;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.x4, Space.x3 + 2, Space.x4, Space.x3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Keep ready', style: t.caption),
                const SizedBox(height: Space.x0_5),
                AmountText(o.toArrange, decimals: DecimalDisplay.none, style: t.amountMedium),
                const SizedBox(height: Space.x0_5),
                Text(
                  n == 0
                      ? 'Nothing going out in the next ${UpcomingWindow.days} days'
                      : 'For ${n == 1 ? '1 payment' : '$n payments'} in the next ${UpcomingWindow.days} days',
                  style: t.caption,
                ),
              ],
            ),
          ),
          if (o.expectedIn.isPositive) ...[
            const SizedBox(width: Space.x3),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('Expected in', style: t.caption),
                const SizedBox(height: Space.x0_5),
                AmountText(
                  o.expectedIn,
                  sign: SignDisplay.always,
                  decimals: DecimalDisplay.none,
                  color: c.positive,
                  style: t.amountSmall,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Soonest first; scrolls once there are more than
/// [UpcomingSection.visibleRows] rows. Shrinks to fit when there are fewer.
class _UpcomingList extends StatelessWidget {
  const _UpcomingList({required this.items});

  final List<UpcomingItem> items;

  @override
  Widget build(BuildContext context) {
    // Grow with the text size so larger fonts still show the same rows.
    final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
    final rowHeight = 57 + (scale - 1).clamp(0.0, 1.5) * 24;
    final scrolls = items.length > UpcomingSection.visibleRows;
    // Half a row peeks at the bottom so it is obvious the list scrolls.
    final maxHeight = rowHeight * (UpcomingSection.visibleRows + 0.5);
    final list = ListView.separated(
      restorationId: UpcomingSection.listRestorationId,
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      physics: scrolls ? const ClampingScrollPhysics() : const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      separatorBuilder: (_, _) => const FinnDivider(indent: Space.x4, endIndent: Space.x4),
      itemBuilder: (context, n) {
        final i = items[n];
        return _UpcomingRow(key: ValueKey('${i.kind.name}_${i.recordId}_${i.date}'), item: i);
      },
    );
    if (!scrolls) return list;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Scrollbar(child: list),
    );
  }
}

class _UpcomingRow extends StatelessWidget {
  const _UpcomingRow({super.key, required this.item});

  final UpcomingItem item;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final i = item;
    final (icon, accent) = switch (i.kind) {
      UpcomingKind.loanPayment || UpcomingKind.loanReceipt => (LucideIcons.landmark, c.accentLoans),
      UpcomingKind.subscription => (LucideIcons.repeat, c.accentSubscriptions),
    };
    final due = relativeDue(i.daysUntil);
    return HomeRow(
      onTap: () => context.push(UpcomingSection.routeFor(i)),
      leading: IconTile(
        icon: icon,
        background: accent.withValues(alpha: c.isDark ? 0.2 : 0.12),
        foreground: accent,
        size: 36,
        radius: Radii.lg,
        iconSize: 17,
      ),
      title: i.title,
      subtitle: '${i.kind.label} · $due',
      subtitleColor: i.isOverdue ? c.negative : null,
      trailing: AmountText(
        i.isInflow ? i.amount : -i.amount,
        sign: SignDisplay.always,
        decimals: DecimalDisplay.none,
        color: i.isInflow ? c.positive : c.textPrimary,
        style: context.text.amountSmall,
      ),
    );
  }
}
