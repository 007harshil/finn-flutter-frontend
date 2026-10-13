import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/di/data_providers.dart';
import '../../../core/money/money_format.dart';
import '../../../core/time/dates.dart';
import '../../../design_system/design_system.dart' show AmountText, BottomClearanceX, FinnSheetScaffold, showFinnSheet;
import '../../../shared/presentation/async_view.dart';
import '../../../ui/ui.dart';
import '../domain/timeline.dart';

/// Colour for a chapter's theme; null keeps it ink. Colour carries meaning
/// only: good months green, hard months red, savings in their own hue.
Color? storyThemeColor(StoryTheme theme, UiColors c) => switch (theme) {
  StoryTheme.success || StoryTheme.growth || StoryTheme.celebration || StoryTheme.victory => c.positive,
  StoryTheme.warning => c.negative,
  StoryTheme.asset => c.emergency,
  StoryTheme.vision || StoryTheme.freedom => c.goals,
  StoryTheme.fun || StoryTheme.adventurous || StoryTheme.neutral => null,
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

IconData timelineKindIcon(TimelineEventKind kind) => switch (kind) {
  TimelineEventKind.income => LucideIcons.arrowDownLeft,
  TimelineEventKind.majorExpense => LucideIcons.shoppingBag,
  TimelineEventKind.loanPayment => LucideIcons.landmark,
  TimelineEventKind.goalContribution || TimelineEventKind.goalWithdrawal => LucideIcons.target,
  TimelineEventKind.emergencyContribution => LucideIcons.shieldCheck,
  TimelineEventKind.settlement => LucideIcons.handshake,
  TimelineEventKind.subscriptionPaid => LucideIcons.repeat,
};

/// The month as a short story: its name and one-line summary, then the
/// key moments newest first. Arrows step between months that have one.
class TimelineScreen extends ConsumerStatefulWidget {
  const TimelineScreen({super.key});

  @override
  ConsumerState<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends ConsumerState<TimelineScreen> {
  MonthKey? _month;

  void _go(MonthKey to) {
    HapticFeedback.selectionClick();
    setState(() => _month = to);
  }

  @override
  Widget build(BuildContext context) {
    final t = UiType.of(context);
    return UiPage(
      title: 'Timeline',
      body: AsyncView<List<MonthKey>>(
        value: ref.watch(timelineMonthsProvider),
        loading: const _Placeholder(),
        builder: (context, months) {
          // Newest first; always includes the current month.
          final selected = _month != null && months.contains(_month) ? _month! : months.first;
          final idx = months.indexOf(selected);
          final older = idx + 1 < months.length ? months[idx + 1] : null;
          final newer = idx > 0 ? months[idx - 1] : null;
          return CustomScrollView(
            key: const PageStorageKey<String>('timeline'),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(UiSpace.gutter, 0, UiSpace.gutter, 0),
                sliver: SliverToBoxAdapter(
                  child: UiColumnWidth(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onHorizontalDragEnd: (d) {
                        final v = d.primaryVelocity ?? 0;
                        if (v < -200 && newer != null) _go(newer);
                        if (v > 200 && older != null) _go(older);
                      },
                      child: Row(
                        children: [
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(left: UiSpace.xs),
                              child: Semantics(
                                liveRegion: true,
                                child: Text(DateFormats.monthYear.format(selected.start), style: t.title),
                              ),
                            ),
                          ),
                          UiStepButton(
                            icon: LucideIcons.chevronLeft,
                            tooltip: 'Previous month',
                            onPressed: older == null ? null : () => _go(older),
                          ),
                          UiStepButton(
                            icon: LucideIcons.chevronRight,
                            tooltip: 'Next month',
                            onPressed: newer == null ? null : () => _go(newer),
                          ),
                        ],
                      ),
                    ),
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
        child: AsyncView<StoryChapter>(value: value, loading: const _Placeholder(), builder: (_, _) => const SizedBox()),
      );
    }
    if (chapter.events.isEmpty) {
      return const SliverToBoxAdapter(
        child: UiEmpty(
          icon: LucideIcons.bookOpen,
          title: 'A quiet month',
          message: 'Income, bigger spends, loan payments and savings show up here.',
        ),
      );
    }
    final events = chapter.events;
    return SliverPadding(
      padding: EdgeInsets.fromLTRB(UiSpace.gutter, UiSpace.lg, UiSpace.gutter, context.bottomClearance),
      sliver: SliverList.builder(
        itemCount: events.length + 1,
        itemBuilder: (context, i) {
          if (i == 0) {
            return UiColumnWidth(
              child: UiReveal(index: 0, child: _ChapterHeader(chapter: chapter)),
            );
          }
          final e = events[i - 1];
          return UiColumnWidth(
            key: ValueKey(e.id),
            child: UiPanelSlice(
              first: i == 1,
              last: i == events.length,
              child: _EventRow(event: e),
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
    final c = UiColors.of(context);
    final t = UiType.of(context);
    final n = chapter.events.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(UiSpace.xs, 0, UiSpace.xs, UiSpace.xl),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          UiMark(icon: storyThemeIcon(chapter.theme), color: storyThemeColor(chapter.theme, c), size: 40),
          const SizedBox(width: UiSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(header: true, child: Text(chapter.name, style: t.section)),
                const SizedBox(height: 2),
                Text(chapter.summary, style: t.label),
                const SizedBox(height: UiSpace.xs),
                Text(n == 1 ? '1 key moment' : '$n key moments', style: t.small),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.event});

  final TimelineEvent event;

  void _open(BuildContext context) {
    final route = event.route;
    if (route != null) {
      context.push(route);
    } else {
      showFinnSheet<void>(context, builder: (_) => _EventSheet(event: event));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = UiColors.of(context);
    final t = UiType.of(context);
    final e = event;
    return UiListRow(
      leading: UiMark(icon: timelineKindIcon(e.kind), color: e.isInflow ? c.positive : null),
      title: e.title,
      subtitle: '${DateFormats.dayMonth.format(e.date)} · ${e.kind.label}',
      semanticLabel: '${e.title}, ${DateFormats.dayMonth.format(e.date)}',
      trailing: AmountText(
        e.isInflow ? e.amount : -e.amount,
        sign: SignDisplay.always,
        decimals: DecimalDisplay.none,
        style: t.figureSmall.copyWith(color: e.isInflow ? c.positive : c.ink),
      ),
      onTap: () => _open(context),
    );
  }
}

class _EventSheet extends StatelessWidget {
  const _EventSheet({required this.event});

  final TimelineEvent event;

  @override
  Widget build(BuildContext context) {
    final c = UiColors.of(context);
    final t = UiType.of(context);
    final e = event;
    return FinnSheetScaffold(
      title: e.title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AmountText(
            e.isInflow ? e.amount : -e.amount,
            sign: SignDisplay.always,
            style: t.amount.copyWith(color: e.isInflow ? c.positive : c.ink),
          ),
          const SizedBox(height: UiSpace.xs),
          Text('${DateFormats.dayMonthYear.format(e.date)} · ${e.kind.label}', style: t.label),
          const SizedBox(height: UiSpace.lg),
          Text(e.description, style: t.body.copyWith(fontWeight: FontWeight.w400, height: 1.5)),
        ],
      ),
    );
  }
}

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
            UiPlaceholder(width: 160, height: 22),
            SizedBox(height: UiSpace.xl),
            UiPlaceholder(width: 220, height: 16),
            SizedBox(height: UiSpace.sm),
            UiPlaceholder(width: 260, height: 12),
            SizedBox(height: UiSpace.xl),
            UiPlaceholder(height: 240, radius: UiRadius.panel),
          ],
        ),
      ),
    );
  }
}
