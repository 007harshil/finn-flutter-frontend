import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/di/data_providers.dart';
import '../../../core/money/money_format.dart';
import '../../../core/time/dates.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/presentation/async_view.dart';
import '../domain/timeline.dart';

/// Story colour for a theme (light and dark aware).
Color storyThemeColor(StoryTheme theme, FinnColors c) {
  final d = c.isDark;
  return switch (theme) {
    StoryTheme.celebration => d ? Palette.amber400 : Palette.amber600,
    StoryTheme.success => c.positive,
    StoryTheme.warning => c.negative,
    StoryTheme.fun => d ? Palette.pink400 : Palette.pink600,
    StoryTheme.adventurous => d ? Palette.orange400 : Palette.orange600,
    StoryTheme.growth => d ? Palette.indigo400 : Palette.indigo600,
    StoryTheme.neutral => c.textSecondary,
    StoryTheme.vision => d ? Palette.violet400 : Palette.violet600,
    StoryTheme.victory => d ? Palette.amber400 : Palette.amber700,
    StoryTheme.asset => c.accentEmergency,
    StoryTheme.freedom => Palette.sky500,
  };
}

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

/// The monthly financial story: a chapter per month with key moments on a
/// vertical spine.
class TimelineScreen extends ConsumerStatefulWidget {
  const TimelineScreen({super.key});

  @override
  ConsumerState<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends ConsumerState<TimelineScreen> {
  MonthKey? _month;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(title: const Text('Timeline')),
      body: AsyncView<List<MonthKey>>(
        value: ref.watch(timelineMonthsProvider),
        loading: const _TimelineSkeleton(),
        builder: (context, months) {
          // months: newest first, always includes the current month.
          final selected = _month != null && months.contains(_month) ? _month! : months.first;
          final idx = months.indexOf(selected);
          return CustomScrollView(
            key: const PageStorageKey<String>('timeline'),
            slivers: [
              SliverToBoxAdapter(
                child: ResponsiveCenter(
                  padding: const EdgeInsets.fromLTRB(Space.gutter, Space.x1, Space.gutter, Space.x4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('YOUR FINANCIAL STORY', style: context.text.eyebrow),
                      const SizedBox(height: Space.x3),
                      MonthSwitcher(
                        month: selected,
                        min: months.last,
                        max: months.first,
                        onChanged: (m) {
                          // Step through months that have a story (skip gaps).
                          final next = m < selected
                              ? (idx + 1 < months.length ? months[idx + 1] : selected)
                              : (idx > 0 ? months[idx - 1] : selected);
                          setState(() => _month = next);
                        },
                      ),
                    ],
                  ),
                ),
              ),
              _ChapterSliver(key: ValueKey(selected), month: selected),
            ],
          );
        },
      ),
    );
  }
}

class _ChapterSliver extends ConsumerWidget {
  const _ChapterSliver({super.key, required this.month});

  final MonthKey month;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(storyChapterProvider(month));
    final chapter = value.value;
    if (chapter == null) {
      return SliverToBoxAdapter(
        child: AsyncView<StoryChapter>(value: value, loading: const _TimelineSkeleton(), builder: (_, _) => const SizedBox()),
      );
    }
    if (chapter.events.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.gutter, Space.x6, Space.gutter, Space.x10),
          child: Align(
            alignment: Alignment.topCenter,
            child: EmptyState(
              icon: LucideIcons.bookOpen,
              title: 'A quiet chapter',
              message:
                  'No key moments in ${DateFormats.monthYear.format(month.start)} yet. Income, larger spends, loan payments and savings will appear here.',
            ),
          ),
        ),
      );
    }
    final events = chapter.events;
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.x12),
      sliver: SliverList.builder(
        itemCount: events.length + 2,
        itemBuilder: (context, i) {
          if (i == 0) return ResponsiveCenter(child: _ChapterHeader(chapter: chapter));
          if (i == events.length + 1) return const ResponsiveCenter(child: _SpineEnd());
          final e = events[i - 1];
          return ResponsiveCenter(
            key: ValueKey(e.id),
            child: StaggeredEntrance(
              index: i - 1,
              child: _EventTile(event: e, isFirst: i == 1),
            ),
          );
        },
      ),
    );
  }
}

class _ChapterHeader extends StatelessWidget {
  const _ChapterHeader({required this.chapter});

  final StoryChapter chapter;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final color = storyThemeColor(chapter.theme, c);
    final n = chapter.events.length;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.x5),
      child: FinnCard(
        padding: const EdgeInsets.all(Space.x5),
        child: Column(
          children: [
            IconTile(
              icon: storyThemeIcon(chapter.theme),
              background: color.withValues(alpha: c.isDark ? 0.18 : 0.12),
              foreground: color,
              size: 48,
              radius: Radii.xl,
              iconSize: 24,
            ),
            const SizedBox(height: Space.x3),
            Text(DateFormats.monthYear.format(chapter.month.start).toUpperCase(), style: t.eyebrow),
            const SizedBox(height: Space.x1),
            Semantics(
              header: true,
              child: Text(chapter.name, style: t.title.copyWith(color: color, fontSize: 22), textAlign: TextAlign.center),
            ),
            const SizedBox(height: Space.x1_5),
            Text(chapter.summary, style: t.body.copyWith(color: c.textSecondary), textAlign: TextAlign.center),
            const SizedBox(height: Space.x4),
            Row(
              children: [
                Expanded(child: Container(height: 1, color: c.border)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.x3),
                  child: Text(n == 1 ? '1 KEY MOMENT' : '$n KEY MOMENTS', style: t.micro),
                ),
                Expanded(child: Container(height: 1, color: c.border)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

const double _spineX = 17;
const double _dotSize = 14;

/// One moment hung on the spine.
class _EventTile extends StatelessWidget {
  const _EventTile({required this.event, required this.isFirst});

  final TimelineEvent event;
  final bool isFirst;

  void _open(BuildContext context) {
    final route = event.route;
    if (route != null) {
      context.push(route);
    } else {
      showFinnSheet<void>(context, builder: (_) => _EventDetailSheet(event: event));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final e = event;
    final color = storyThemeColor(e.theme, c);
    return Stack(
      children: [
        Positioned(
          left: _spineX - 1,
          top: isFirst ? 26 : 0,
          bottom: 0,
          child: Container(width: 2, color: c.border),
        ),
        Positioned(
          left: _spineX - _dotSize / 2,
          top: 26 - _dotSize / 2,
          child: Container(
            width: _dotSize,
            height: _dotSize,
            decoration: BoxDecoration(
              color: c.background,
              shape: BoxShape.circle,
              border: Border.all(color: color, width: 3),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: _spineX * 2 + Space.x2, bottom: Space.x3),
          child: FinnCard(
            onTap: () => _open(context),
            semanticLabel: '${e.title}, ${DateFormats.dayMonth.format(e.date)}',
            border: BorderSide(color: color.withValues(alpha: 0.35)),
            padding: const EdgeInsets.all(Space.x4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: c.isDark ? 0.16 : 0.1),
                    borderRadius: Radii.rLg,
                  ),
                  child: ExcludeSemantics(child: Text(e.emoji, style: const TextStyle(fontSize: 22))),
                ),
                const SizedBox(width: Space.x3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${DateFormats.dayMonth.format(e.date).toUpperCase()} · ${e.kind.label.toUpperCase()}',
                        style: t.eyebrow,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: Space.x1),
                      Text(e.title, style: t.bodyStrong.copyWith(color: color)),
                      const SizedBox(height: Space.x0_5),
                      Text(e.description, style: t.caption, maxLines: 3, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: Space.x2),
                      _AmountPill(event: e),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _AmountPill extends StatelessWidget {
  const _AmountPill({required this.event});

  final TimelineEvent event;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final e = event;
    final fg = e.isInflow ? c.positive : c.textPrimary;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: e.isInflow ? c.positiveSoft : c.surfaceMuted,
        borderRadius: Radii.rFull,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.x2_5, vertical: Space.x1),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(e.isInflow ? LucideIcons.arrowDownLeft : LucideIcons.arrowUpRight, size: 12, color: fg),
            const SizedBox(width: Space.x1),
            AmountText(
              e.isInflow ? e.amount : -e.amount,
              sign: SignDisplay.always,
              decimals: DecimalDisplay.none,
              color: fg,
              style: context.text.amountSmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _SpineEnd extends StatelessWidget {
  const _SpineEnd();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(left: _spineX - 14),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: c.surfaceMuted,
              shape: BoxShape.circle,
              border: Border.all(color: c.border, width: 2),
            ),
            child: Icon(LucideIcons.anchor, size: 14, color: c.textTertiary),
          ),
          const SizedBox(width: Space.x3),
          Text('Start of the chapter', style: context.text.micro),
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
    final c = context.colors;
    final t = context.text;
    final e = event;
    return FinnSheetScaffold(
      title: e.title,
      footer: FinnButton(label: 'Close', expand: true, variant: FinnButtonVariant.secondary, onPressed: () => Navigator.of(context).maybePop()),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: ExcludeSemantics(child: Text(e.emoji, style: const TextStyle(fontSize: 44)))),
          const SizedBox(height: Space.x3),
          Center(
            child: AmountText(
              e.isInflow ? e.amount : -e.amount,
              sign: SignDisplay.always,
              color: e.isInflow ? c.positive : c.textPrimary,
              style: t.amountLarge,
            ),
          ),
          const SizedBox(height: Space.x4),
          Text(e.description, style: t.body, textAlign: TextAlign.center),
          const SizedBox(height: Space.x4),
          KeyValueRow(label: 'Date', value: DateFormats.dayMonthYear.format(e.date)),
          KeyValueRow(label: 'Type', value: e.kind.label),
          KeyValueRow(label: 'Direction', value: e.isInflow ? 'Money in' : 'Money out'),
        ],
      ),
    );
  }
}

class _TimelineSkeleton extends StatelessWidget {
  const _TimelineSkeleton();

  @override
  Widget build(BuildContext context) {
    return const SkeletonPulse(
      child: Padding(
        padding: EdgeInsets.all(Space.gutter),
        child: Column(
          children: [
            CardSkeleton(height: 200),
            SizedBox(height: Space.x5),
            CardSkeleton(height: 120),
            SizedBox(height: Space.x3),
            CardSkeleton(height: 120),
          ],
        ),
      ),
    );
  }
}
