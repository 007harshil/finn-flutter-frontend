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
import '../../../../design_system/luxe/luxe.dart';
import '../../../alerts/domain/alert.dart';
import '../../../alerts/presentation/alert_card.dart' show alertRoute;
import '../../application/upcoming.dart';

/// Severity → colour, icon and a short word (never colour alone).
extension _SeverityLuxe on AlertSeverity {
  Color tone(LuxePalette p) => switch (this) {
    AlertSeverity.critical => p.negative,
    AlertSeverity.warning => p.warning,
    AlertSeverity.info => p.info,
    AlertSeverity.positive => p.positive,
  };

  IconData get glyph => switch (this) {
    AlertSeverity.critical => LucideIcons.circleAlert,
    AlertSeverity.warning => LucideIcons.clock,
    AlertSeverity.info => LucideIcons.info,
    AlertSeverity.positive => LucideIcons.sparkles,
  };
}

/// Top alerts from the alert engine, most urgent first, as a deck of
/// notes you swipe through. The next note peeks in so it is obvious there
/// is more; the count and the progress hairline say exactly how many.
class AttentionSection extends ConsumerWidget {
  const AttentionSection({super.key});

  static const maxShown = 6;

  /// "2 urgent · 1 soon · 3 FYI".
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
    final value = ref.watch(activeAlertsProvider);
    final loaded = value.value;
    final p = context.luxe;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LuxeSectionHeader(
          title: 'Needs your attention',
          caption: loaded == null || loaded.isEmpty ? null : breakdown(loaded),
          count: loaded?.length,
          actionLabel: 'See all',
          onAction: () => context.push(AppRoutes.alerts),
        ),
        const SizedBox(height: 14),
        if (loaded == null)
          value.hasError
              ? LuxeCard(
                  child: LuxeError(title: 'Alerts unavailable', onRetry: () => refreshFinanceData(ref)),
                )
              : const LuxeShimmer(child: LuxeBone(height: 196, radius: LuxeSpace.rCard))
        else if (loaded.isEmpty)
          LuxeCard(
            child: Row(
              children: [
                LuxeRing(
                  value: 1,
                  color: p.positive,
                  size: 44,
                  stroke: 2,
                  child: Icon(LucideIcons.check, size: 18, color: p.positive),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('All clear', style: context.lt.title.copyWith(fontSize: 21)),
                      const SizedBox(height: 2),
                      Text(
                        'Nothing needs your attention right now. Anything important will show up here.',
                        style: context.lt.caption,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          )
        else
          _AlertDeck(alerts: loaded),
      ],
    );
  }
}

class _AlertDeck extends StatefulWidget {
  const _AlertDeck({required this.alerts});

  final List<FinancialAlert> alerts;

  @override
  State<_AlertDeck> createState() => _AlertDeckState();
}

class _AlertDeckState extends State<_AlertDeck> {
  final _controller = PageController(viewportFraction: 0.86);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final alerts = widget.alerts;
    final shown = alerts.take(AttentionSection.maxShown).toList();
    final more = alerts.length - shown.length;
    final pages = shown.length + (more > 0 ? 1 : 0);
    final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
    final height = 206 + (scale - 1).clamp(0.0, 1.5) * 96;

    Widget note(int i) =>
        _AlertNote(key: ValueKey(shown[i].key), alert: shown[i], position: i + 1, total: alerts.length);

    if (pages == 1) return SizedBox(height: height, child: note(0));

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
            onPageChanged: (_) => HapticFeedback.selectionClick(),
            itemBuilder: (context, i) => AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                // Neighbours recede slightly: depth without decoration.
                final page = _controller.hasClients && _controller.position.haveDimensions
                    ? (_controller.page ?? 0)
                    : 0.0;
                final d = (page - i).abs().clamp(0.0, 1.0);
                return Opacity(
                  opacity: 1 - d * 0.35,
                  child: Transform.scale(scale: 1 - d * 0.04, child: child),
                );
              },
              child: Padding(
                padding: const EdgeInsetsDirectional.only(end: 12),
                child: i < shown.length ? note(i) : _MoreNote(count: more, onTap: () => context.push(AppRoutes.alerts)),
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        _DeckProgress(controller: _controller, count: pages),
      ],
    );
  }
}

/// A hairline that fills as you move through the deck.
class _DeckProgress extends StatelessWidget {
  const _DeckProgress({required this.controller, required this.count});

  final PageController controller;
  final int count;

  @override
  Widget build(BuildContext context) {
    final p = context.luxe;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final page = controller.hasClients && controller.position.haveDimensions ? (controller.page ?? 0) : 0.0;
        final i = page.round().clamp(0, count - 1);
        return Semantics(
          label: 'Alert ${i + 1} of $count',
          excludeSemantics: true,
          child: Row(
            children: [
              Text('${i + 1}'.padLeft(2, '0'), style: context.lt.micro.w(700).c(p.ink)),
              const SizedBox(width: 10),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, box) {
                    final w = box.maxWidth;
                    final seg = w / count;
                    return SizedBox(
                      height: 2,
                      child: Stack(
                        children: [
                          Container(color: p.line),
                          Positioned(
                            left: (page.clamp(0.0, count - 1.0)) * seg,
                            width: seg,
                            top: 0,
                            bottom: 0,
                            child: Container(color: p.ink),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 10),
              Text('$count'.padLeft(2, '0'), style: context.lt.micro),
            ],
          ),
        );
      },
    );
  }
}

class _AlertNote extends StatelessWidget {
  const _AlertNote({super.key, required this.alert, required this.position, required this.total});

  final FinancialAlert alert;
  final int position;
  final int total;

  @override
  Widget build(BuildContext context) {
    final p = context.luxe;
    final t = context.lt;
    final a = alert;
    final tone = a.severity.tone(p);
    final amount = a.amount;
    return LuxeCard(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      onTap: () => context.push(alertRoute(a)),
      semanticLabel: '${a.severity.label}. ${a.title}. ${a.message} ${a.reason}. ${a.actionLabel}.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Flexible(
                child: LuxeStatus(label: a.severity.label, color: tone, icon: a.severity.glyph),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  a.type.label.toUpperCase(),
                  style: t.eyebrow.copyWith(fontSize: 10),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(a.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.title.copyWith(fontSize: 21)),
          const SizedBox(height: 6),
          Flexible(
            child: Text(a.message, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.caption),
          ),
          const Spacer(),
          Row(
            children: [
              if (amount != null)
                Expanded(
                  flex: 2,
                  child: AmountText(
                    amount,
                    decimals: DecimalDisplay.none,
                    fit: true,
                    style: t.figure.copyWith(fontSize: 22, color: p.ink),
                  ),
                )
              else
                const Spacer(),
              const SizedBox(width: 10),
              Flexible(
                flex: 3,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(color: p.ink, borderRadius: BorderRadius.circular(20)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          a.actionLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.micro.w(700).c(p.canvas),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(LucideIcons.arrowUpRight, size: 13, color: p.canvas),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MoreNote extends StatelessWidget {
  const _MoreNote({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.luxe;
    return LuxeCard(
      color: p.sunk,
      elevated: false,
      onTap: onTap,
      semanticLabel: 'View $count more alerts',
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('+$count', style: context.lt.display.copyWith(fontSize: 48)),
            const SizedBox(height: 4),
            Text('more to review', style: context.lt.caption),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Coming up
// ---------------------------------------------------------------------------

/// "in 3 days" / "today" / "2 days overdue".
String relativeDue(int days) {
  if (days < -1) return '${-days} days overdue';
  if (days == -1) return '1 day overdue';
  if (days == 0) return 'Due today';
  if (days == 1) return 'Due tomorrow';
  return 'In $days days';
}

/// EMIs and subscriptions due in the next [UpcomingWindow.days] days with
/// the cash to keep ready, as a calendar strip of dated rows. A busy week
/// scrolls inside the card so it never pushes the rest of Home down.
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
    const days = UpcomingWindow.days;
    final value = ref.watch(upcomingCommitmentsProvider);
    final o = value.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const LuxeSectionHeader(title: 'Coming up', caption: 'Next $days days · projected, not yet paid'),
        const SizedBox(height: 14),
        if (o == null)
          value.hasError
              ? LuxeCard(
                  child: LuxeError(title: 'Could not load what is due', onRetry: () => refreshFinanceData(ref)),
                )
              : const LuxeShimmer(child: LuxeBone(height: 240, radius: LuxeSpace.rCard))
        else if (o.items.isEmpty)
          LuxeCard(
            child: Row(
              children: [
                Icon(LucideIcons.calendarCheck, size: 22, color: context.luxe.inkSoft),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Nothing due soon', style: context.lt.heading),
                      const SizedBox(height: 2),
                      Text('No EMIs or subscriptions are due in the next $days days.', style: context.lt.caption),
                    ],
                  ),
                ),
              ],
            ),
          )
        else
          LuxeCard(
            padding: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _KeepReady(overview: o),
                const LuxeHairline(),
                _UpcomingList(items: o.items),
              ],
            ),
          ),
      ],
    );
  }
}

class _KeepReady extends StatelessWidget {
  const _KeepReady({required this.overview});

  final UpcomingOverview overview;

  @override
  Widget build(BuildContext context) {
    final p = context.luxe;
    final t = context.lt;
    final o = overview;
    final n = o.outflowCount;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('KEEP READY', style: t.eyebrow),
                const SizedBox(height: 6),
                LuxeAmount(o.toArrange, style: t.figure.copyWith(fontSize: 30), symbolScale: 0.55),
                const SizedBox(height: 2),
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
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('EXPECTED IN', style: t.eyebrow),
                const SizedBox(height: 6),
                AmountText(
                  o.expectedIn,
                  sign: SignDisplay.always,
                  decimals: DecimalDisplay.none,
                  color: p.positive,
                  style: t.number,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _UpcomingList extends StatelessWidget {
  const _UpcomingList({required this.items});

  final List<UpcomingItem> items;

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
    final rowHeight = 68 + (scale - 1).clamp(0.0, 1.5) * 24;
    final scrolls = items.length > UpcomingSection.visibleRows;
    final maxHeight = rowHeight * (UpcomingSection.visibleRows + 0.5);
    final list = ListView.builder(
      restorationId: UpcomingSection.listRestorationId,
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: 6),
      physics: scrolls ? const ClampingScrollPhysics() : const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      itemBuilder: (context, n) {
        final i = items[n];
        return _UpcomingRow(key: ValueKey('${i.kind.name}_${i.recordId}_${i.date}'), item: i);
      },
    );
    if (!scrolls) return list;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: list,
    );
  }
}

class _UpcomingRow extends StatelessWidget {
  const _UpcomingRow({super.key, required this.item});

  final UpcomingItem item;

  static const _days = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];

  @override
  Widget build(BuildContext context) {
    final p = context.luxe;
    final t = context.lt;
    final i = item;
    final due = relativeDue(i.daysUntil);
    final icon = i.kind == UpcomingKind.subscription ? LucideIcons.repeat : LucideIcons.landmark;
    return Squish(
      onTap: () => context.push(UpcomingSection.routeFor(i)),
      scale: 0.985,
      semanticLabel: '${i.title}, ${i.kind.label}, $due, ${MoneyFormatter.spoken(i.amount)}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 50,
              decoration: BoxDecoration(
                color: i.isOverdue ? p.tint(p.negative, 0.1) : p.canvas,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: i.isOverdue ? p.negative.withValues(alpha: 0.3) : p.line),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _days[i.date.weekday - 1],
                    style: t.micro.copyWith(fontSize: 9, letterSpacing: 1.2, color: i.isOverdue ? p.negative : null),
                  ),
                  Text('${i.date.day}', style: t.figure.copyWith(fontSize: 22, height: 1.05)),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(i.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.heading.copyWith(fontSize: 15)),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(icon, size: 11, color: p.inkMute),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          '${i.kind.label} · $due',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.caption.c(i.isOverdue ? p.negative : p.inkSoft),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: math.max(80, MediaQuery.sizeOf(context).width * 0.3)),
              child: AmountText(
                i.isInflow ? i.amount : -i.amount,
                sign: SignDisplay.always,
                decimals: DecimalDisplay.none,
                fit: true,
                textAlign: TextAlign.end,
                color: i.isInflow ? p.positive : p.ink,
                style: t.number,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
