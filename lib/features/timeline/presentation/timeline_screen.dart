import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/di/data_providers.dart';
import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/time/dates.dart';
import '../../../design_system/design_system.dart';
import '../../../design_system/luxe/luxe.dart';
import '../../../shared/presentation/luxe_async.dart';
import '../../../shared/presentation/luxe_page.dart';
import '../domain/timeline.dart';

/// Story colour for a theme: quiet tones that sit in the Luxe palette.
Color storyThemeColor(StoryTheme theme, LuxePalette p) => switch (theme) {
  StoryTheme.celebration || StoryTheme.victory => p.goldInk,
  StoryTheme.success || StoryTheme.asset => p.positive,
  StoryTheme.warning => p.negative,
  StoryTheme.fun => p.mute(const Color(0xFFB0567A)),
  StoryTheme.adventurous => p.warning,
  StoryTheme.growth || StoryTheme.freedom => p.info,
  StoryTheme.vision => p.mute(const Color(0xFF7A62B0)),
  StoryTheme.neutral => p.inkSoft,
};

IconData storyThemeIcon(StoryTheme theme) => switch (theme) {
  StoryTheme.adventurous => LucideIcons.scale,
  StoryTheme.vision => LucideIcons.target,
  StoryTheme.success => LucideIcons.trendingUp,
  StoryTheme.fun => LucideIcons.sparkles,
  StoryTheme.celebration || StoryTheme.victory => LucideIcons.partyPopper,
  StoryTheme.growth => LucideIcons.sprout,
  StoryTheme.asset => LucideIcons.shieldCheck,
  StoryTheme.freedom => LucideIcons.rocket,
  StoryTheme.warning => LucideIcons.triangleAlert,
  StoryTheme.neutral => LucideIcons.bookOpen,
};

/// One vector mark per kind of moment (no emoji).
IconData timelineKindIcon(TimelineEventKind kind) => switch (kind) {
  TimelineEventKind.income => LucideIcons.banknote,
  TimelineEventKind.majorExpense => LucideIcons.shoppingBag,
  TimelineEventKind.loanPayment => LucideIcons.landmark,
  TimelineEventKind.goalContribution => LucideIcons.target,
  TimelineEventKind.goalWithdrawal => LucideIcons.undo2,
  TimelineEventKind.emergencyContribution => LucideIcons.shieldCheck,
  TimelineEventKind.settlement => LucideIcons.handshake,
  TimelineEventKind.subscriptionPaid => LucideIcons.repeat,
};

/// The monthly financial story: a chapter per month — a cover with the
/// month's name and a strip of every moment across its days — then each
/// moment hung on a rail.
class TimelineScreen extends ConsumerStatefulWidget {
  const TimelineScreen({super.key});

  @override
  ConsumerState<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends ConsumerState<TimelineScreen> {
  MonthKey? _month;

  @override
  Widget build(BuildContext context) {
    final months = ref.watch(timelineMonthsProvider);
    return LuxeDetailPage(
      title: 'Timeline',
      storageKey: 'timeline',
      slivers: [
        luxeBox(
          const Reveal(
            child: LuxePageTitle(eyebrow: 'Your financial story', title: 'Timeline'),
          ),
          top: 4,
          bottom: 16,
        ),
        SliverToBoxAdapter(
          child: LuxeAsync<List<MonthKey>>(
            value: months,
            loading: const LuxePageSkeleton(title: false, hero: 240, rows: 3),
            errorTitle: 'Could not load your story',
            builder: (context, months) {
              // months: newest first, always includes the current month.
              final selected = _month != null && months.contains(_month) ? _month! : months.first;
              final idx = months.indexOf(selected);
              return ResponsiveCenter(
                padding: const EdgeInsets.symmetric(horizontal: LuxeSpace.gutter),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Reveal(
                      index: 1,
                      child: LuxeMonthStepper(
                        month: selected,
                        min: months.last,
                        max: months.first,
                        subtitle: '${months.length - idx} of ${months.length} chapters',
                        onChanged: (m) {
                          // Step through months that have a story (skip gaps).
                          final next = m < selected
                              ? (idx + 1 < months.length ? months[idx + 1] : selected)
                              : (idx > 0 ? months[idx - 1] : selected);
                          setState(() => _month = next);
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    AnimatedSwitcher(
                      duration: context.reduceMotion ? Duration.zero : LuxeDurations.base,
                      switchInCurve: LuxeCurves.arrive,
                      switchOutCurve: LuxeCurves.leave,
                      layoutBuilder: (current, previous) =>
                          Stack(alignment: Alignment.topCenter, children: [...previous, ?current]),
                      child: _Chapter(key: ValueKey(selected), month: selected),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _Chapter extends ConsumerWidget {
  const _Chapter({super.key, required this.month});

  final MonthKey month;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(storyChapterProvider(month));
    return LuxeAsync<StoryChapter>(
      value: value,
      loading: const LuxePageSkeleton(title: false, controls: false, hero: 240, rows: 3),
      errorTitle: 'Could not load this chapter',
      builder: (context, chapter) {
        final events = chapter.events;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Reveal(index: 2, scale: 0.97, child: _Cover(chapter: chapter)),
            const SizedBox(height: 26),
            if (events.isEmpty)
              LuxeEmpty(
                icon: LucideIcons.bookOpen,
                title: 'A quiet chapter',
                message:
                    'No key moments in ${DateFormats.monthYear.format(month.start)} yet. Income, larger spends, '
                    'loan payments and savings will appear here.',
              )
            else ...[
              LuxeEyebrowHeader(
                label: events.length == 1 ? '1 key moment' : '${events.length} key moments',
                caption: 'Newest first · tap a moment for the full story',
              ),
              const SizedBox(height: 16),
              for (var i = 0; i < events.length; i++)
                Reveal(
                  key: ValueKey(events[i].id),
                  index: 3 + i,
                  child: LuxeRailNode(
                    color: storyThemeColor(events[i].theme, context.luxe),
                    icon: timelineKindIcon(events[i].kind),
                    first: i == 0,
                    nodeTop: 26,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _EventCard(event: events[i]),
                    ),
                  ),
                ),
              Reveal(index: 3 + events.length, child: const _SpineEnd()),
            ],
          ],
        );
      },
    );
  }
}

/// The chapter cover: theme mark, month, serif chapter name, the summary,
/// money in / out, and every moment placed on the month's days.
class _Cover extends StatelessWidget {
  const _Cover({required this.chapter});

  final StoryChapter chapter;

  @override
  Widget build(BuildContext context) {
    final p = context.luxe;
    final t = context.lt;
    final c = chapter;
    final tone = storyThemeColor(c.theme, LuxePalette.dark);
    final inflow = Money.sum(c.events.where((e) => e.isInflow).map((e) => e.amount));
    final outflow = Money.sum(c.events.where((e) => !e.isInflow).map((e) => e.amount));
    return LuxeObsidian(
      glow: tone,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              LuxeIconDisc(icon: storyThemeIcon(c.theme), color: tone, onDark: true, size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  DateFormats.monthYear.format(c.month.start).toUpperCase(),
                  style: t.eyebrow.copyWith(fontSize: 10, color: p.onObsidianSoft),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Semantics(
            header: true,
            child: Text(c.name, style: t.headline.copyWith(fontSize: 32, color: p.onObsidian)),
          ),
          const SizedBox(height: 8),
          Text(c.summary, style: t.body.c(p.onObsidianSoft)),
          if (c.events.isNotEmpty) ...[
            const SizedBox(height: 22),
            _MonthStrip(chapter: c, inTone: tone),
            const SizedBox(height: 18),
            SizedBox(height: 1, child: ColoredBox(color: p.onObsidian.withValues(alpha: 0.1))),
            const SizedBox(height: 14),
            LuxeFigureRow(
              onDark: true,
              children: [
                LuxeFigure(
                  label: 'Moments',
                  onDark: true,
                  child: Text('${c.events.length}', style: t.number.copyWith(fontSize: 17, color: p.onObsidian)),
                ),
                LuxeFigure(label: 'In', onDark: true, child: LuxeFigureAmount(inflow, onDark: true, size: 15)),
                LuxeFigure(label: 'Out', onDark: true, child: LuxeFigureAmount(outflow, onDark: true, size: 15)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// The month as a hairline from day 1 to its last day: money in rises
/// above the line, money out hangs below, sized by amount. Draws in from
/// the left.
class _MonthStrip extends StatelessWidget {
  const _MonthStrip({required this.chapter, required this.inTone});

  final StoryChapter chapter;
  final Color inTone;

  @override
  Widget build(BuildContext context) {
    final p = context.luxe;
    final t = context.lt;
    final c = chapter;
    final days = DateUtils.getDaysInMonth(c.month.year, c.month.month);
    final maxPaise = c.events.fold<int>(1, (m, e) => math.max(m, e.amount.paise));
    final marks = [
      for (final e in c.events)
        (
          at: ((e.date.day - 1) / math.max(1, days - 1)).clamp(0.0, 1.0),
          size: 0.3 + 0.7 * math.sqrt(e.amount.paise / maxPaise),
          inflow: e.isInflow,
          color: storyThemeColor(e.theme, LuxePalette.dark),
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          label: '${c.events.length} moments across ${DateFormats.monthYear.format(c.month.start)}',
          excludeSemantics: true,
          child: SizedBox(
            height: 56,
            child: DrawIn(
              value: 1,
              delay: const Duration(milliseconds: 300),
              duration: const Duration(milliseconds: 1500),
              builder: (context, v) => CustomPaint(
                painter: _StripPainter(
                  marks: marks,
                  progress: v,
                  line: p.onObsidian.withValues(alpha: 0.2),
                  tick: p.onObsidian.withValues(alpha: 0.12),
                  inColor: inTone,
                  outColor: p.onObsidian.withValues(alpha: 0.75),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Text('1', style: t.micro.c(p.onObsidianSoft)),
            const Spacer(),
            Text('IN ABOVE · OUT BELOW', style: t.eyebrow.copyWith(fontSize: 8, color: p.onObsidianSoft)),
            const Spacer(),
            Text('$days', style: t.micro.c(p.onObsidianSoft)),
          ],
        ),
      ],
    );
  }
}

class _StripPainter extends CustomPainter {
  _StripPainter({
    required this.marks,
    required this.progress,
    required this.line,
    required this.tick,
    required this.inColor,
    required this.outColor,
  });

  final List<({double at, double size, bool inflow, Color color})> marks;
  final double progress;
  final Color line;
  final Color tick;
  final Color inColor;
  final Color outColor;

  @override
  void paint(Canvas canvas, Size size) {
    final mid = size.height / 2;
    final w = size.width;
    canvas.drawLine(
      Offset(0, mid),
      Offset(w * progress, mid),
      Paint()
        ..color = line
        ..strokeWidth = 1,
    );
    final tp = Paint()
      ..color = tick
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final x = w * i / 4;
      if (x > w * progress) break;
      canvas.drawLine(Offset(x, mid - 3), Offset(x, mid + 3), tp);
    }
    for (final m in marks) {
      if (m.at > progress) continue;
      final land = ((progress - m.at) * 6).clamp(0.0, 1.0);
      final x = w * m.at;
      final len = (mid - 6) * m.size * Curves.easeOutBack.transform(land);
      final color = m.inflow ? inColor : outColor;
      final end = Offset(x, m.inflow ? mid - len : mid + len);
      canvas.drawLine(
        Offset(x, mid),
        end,
        Paint()
          ..color = color.withValues(alpha: 0.6)
          ..strokeWidth = 1.2
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawCircle(end, 2.6 + 1.6 * m.size, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(_StripPainter o) => o.progress != progress || o.marks.length != marks.length;
}

/// One moment: when and what kind, its title in the story tone, what
/// happened, and the money that moved.
class _EventCard extends StatelessWidget {
  const _EventCard({required this.event});

  final TimelineEvent event;

  void _open(BuildContext context) {
    final route = event.route;
    if (route != null) {
      context.push(route);
    } else {
      showLuxeSheet<void>(context, builder: (_) => _EventDetailSheet(event: event));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.luxe;
    final t = context.lt;
    final e = event;
    final color = storyThemeColor(e.theme, p);
    return LuxeCard(
      onTap: () => _open(context),
      semanticLabel: '${e.title}, ${DateFormats.dayMonth.format(e.date)}',
      radius: LuxeSpace.rTile,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${DateFormats.dayMonth.format(e.date).toUpperCase()} · ${e.kind.label.toUpperCase()}',
                  style: t.eyebrow.copyWith(fontSize: 9.5),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(e.route == null ? LucideIcons.chevronRight : LucideIcons.arrowUpRight, size: 14, color: p.inkMute),
            ],
          ),
          const SizedBox(height: 8),
          Text(e.title, style: t.title.copyWith(fontSize: 20, color: color)),
          const SizedBox(height: 4),
          Text(e.description, style: t.caption, maxLines: 3, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 12),
          _AmountPill(event: e),
        ],
      ),
    );
  }
}

class _AmountPill extends StatelessWidget {
  const _AmountPill({required this.event});

  final TimelineEvent event;

  @override
  Widget build(BuildContext context) {
    final p = context.luxe;
    final e = event;
    final fg = e.isInflow ? p.positive : p.ink;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: e.isInflow ? p.tint(p.positive, 0.09) : p.sunk,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(e.isInflow ? LucideIcons.arrowDownLeft : LucideIcons.arrowUpRight, size: 12, color: fg),
          const SizedBox(width: 6),
          LuxeAmount(
            e.isInflow ? e.amount : -e.amount,
            sign: SignDisplay.always,
            fit: false,
            style: context.lt.numberSmall.c(fg),
          ),
        ],
      ),
    );
  }
}

class _SpineEnd extends StatelessWidget {
  const _SpineEnd();

  @override
  Widget build(BuildContext context) {
    final p = context.luxe;
    return Padding(
      padding: const EdgeInsets.only(left: 3, top: 4),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: p.paper,
              shape: BoxShape.circle,
              border: Border.all(color: p.lineStrong),
            ),
            child: Icon(LucideIcons.anchor, size: 13, color: p.inkMute),
          ),
          const SizedBox(width: 14),
          Text('Start of the chapter', style: context.lt.micro),
        ],
      ),
    );
  }
}

class _EventDetailSheet extends StatelessWidget {
  const _EventDetailSheet({required this.event});

  final TimelineEvent event;

  @override
  Widget build(BuildContext context) {
    final p = context.luxe;
    final t = context.lt;
    final e = event;
    final color = storyThemeColor(e.theme, p);
    return LuxeSheet(
      eyebrow: e.kind.label,
      title: e.title,
      footer: LuxeButton(
        label: 'Close',
        expand: true,
        variant: LuxeButtonVariant.outline,
        onPressed: () => Navigator.of(context).maybePop(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          Center(
            child: Reveal(
              scale: 0.8,
              blur: 0,
              child: LuxeIconDisc(icon: timelineKindIcon(e.kind), color: color, size: 64),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: LuxeAmount(
              e.isInflow ? e.amount : -e.amount,
              sign: SignDisplay.always,
              color: e.isInflow ? p.positive : p.ink,
              style: t.display.copyWith(fontSize: 40),
            ),
          ),
          const SizedBox(height: 16),
          Text(e.description, style: t.bodySoft, textAlign: TextAlign.center),
          const SizedBox(height: 20),
          LuxeFacts(
            facts: [
              LuxeFact('Date', value: DateFormats.dayMonthYear.format(e.date)),
              LuxeFact('Type', value: e.kind.label),
              LuxeFact('Direction', value: e.isInflow ? 'Money in' : 'Money out'),
            ],
          ),
        ],
      ),
    );
  }
}
