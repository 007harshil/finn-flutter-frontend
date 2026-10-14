import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/di/data_providers.dart';
import '../../../core/money/money_format.dart';
import '../../../core/time/dates.dart';
import '../../../kit/kit.dart';
import '../../../shared/presentation/async_view.dart';
import '../domain/timeline.dart';

IconData _kindIcon(TimelineEventKind kind) => switch (kind) {
      TimelineEventKind.income => LucideIcons.arrowDownLeft,
      TimelineEventKind.majorExpense => LucideIcons.arrowUpRight,
      TimelineEventKind.loanPayment => LucideIcons.landmark,
      TimelineEventKind.goalContribution => LucideIcons.target,
      TimelineEventKind.goalWithdrawal => LucideIcons.target,
      TimelineEventKind.emergencyContribution => LucideIcons.shieldCheck,
      TimelineEventKind.settlement => LucideIcons.circleCheck,
      TimelineEventKind.subscriptionPaid => LucideIcons.repeat,
    };

/// The monthly financial story: a chapter per month, its key moments
/// grouped by day.
class TimelineScreen extends ConsumerStatefulWidget {
  const TimelineScreen({super.key});

  @override
  ConsumerState<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends ConsumerState<TimelineScreen> {
  MonthKey? _month;

  @override
  Widget build(BuildContext context) {
    return AsyncView<List<MonthKey>>(
      value: ref.watch(timelineMonthsProvider),
      loading: Scaffold(
        backgroundColor: context.ink.paper,
        appBar: const LedgerAppBar(title: 'Timeline'),
        body: const SafeArea(child: LedgerPageSkeleton()),
      ),
      builder: (context, months) {
        // months: newest first, always includes the current month.
        final selected = _month != null && months.contains(_month) ? _month! : months.first;
        final idx = months.indexOf(selected);
        return LedgerPage(
          storageKey: 'timeline',
          appBar: const LedgerAppBar(title: 'Timeline'),
          slivers: [
            PageBlock(
              top: Sp.md,
              child: Transform.translate(
                // Optically align the left arrow with the gutter.
                offset: const Offset(-12, 0),
                child: MonthStepper(
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
              ),
            ),
            _ChapterSlivers(key: ValueKey(selected), month: selected),
          ],
        );
      },
    );
  }
}

class _ChapterSlivers extends ConsumerWidget {
  const _ChapterSlivers({super.key, required this.month});

  final MonthKey month;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(storyChapterProvider(month));
    final chapter = value.value;
    if (chapter == null) {
      return SliverToBoxAdapter(
        child: AsyncView<StoryChapter>(value: value, loading: const LedgerPageSkeleton(), builder: (_, _) => const SizedBox()),
      );
    }
    if (chapter.events.isEmpty) {
      return PageBlock(
        top: Sp.xl,
        child: LedgerEmpty(
          icon: LucideIcons.bookOpen,
          title: 'A quiet month',
          message:
              'No key moments in ${DateFormats.monthYear.format(month.start)} yet. Income, larger spends, loan payments and savings will appear here.',
        ),
      );
    }
    // Events arrive newest first; keep that order, grouped by day.
    final days = <DateTime, List<TimelineEvent>>{};
    for (final e in chapter.events) {
      days.putIfAbsent(DateTime(e.date.year, e.date.month, e.date.day), () => []).add(e);
    }
    return SliverMainAxisGroup(
      slivers: [
        PageBlock(top: Sp.lg, child: _ChapterHeader(chapter: chapter)),
        for (final d in days.entries)
          PageBlock(
            top: Sp.section,
            child: LedgerSection(
              title: DateFormats.weekdayDayMonth.format(d.key),
              child: LedgerPanel(
                dividerIndent: Sp.lg + 40 + Sp.md + 2,
                children: [for (final e in d.value) _EventRow(key: ValueKey(e.id), event: e)],
              ),
            ),
          ),
      ],
    );
  }
}

class _ChapterHeader extends StatelessWidget {
  const _ChapterHeader({required this.chapter});

  final StoryChapter chapter;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final t = context.type;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(header: true, child: Text(chapter.name, style: t.figureL)),
        const SizedBox(height: Sp.sm),
        Text(chapter.summary, style: t.body.copyWith(color: c.inkSoft)),
      ],
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({super.key, required this.event});

  final TimelineEvent event;

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
    final c = context.ink;
    final t = context.type;
    final e = event;
    return LedgerRow(
      leading: IconWell(icon: _kindIcon(e.kind)),
      title: e.title,
      subtitle: e.kind.label,
      trailing: AmountText(
        e.isInflow ? e.amount : -e.amount,
        sign: SignDisplay.always,
        decimals: DecimalDisplay.none,
        style: t.figure.copyWith(color: e.isInflow ? c.green : c.ink),
      ),
      semanticLabel: '${e.title}, ${DateFormats.dayMonth.format(e.date)}',
      onTap: () => _open(context),
    );
  }
}

class _EventDetailSheet extends StatelessWidget {
  const _EventDetailSheet({required this.event});

  final TimelineEvent event;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final t = context.type;
    final e = event;
    return FinnSheetScaffold(
      title: e.title,
      footer: LedgerButton(
        label: 'Close',
        expand: true,
        variant: LedgerButtonVariant.secondary,
        onPressed: () => Navigator.of(context).maybePop(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: AmountText(
              e.isInflow ? e.amount : -e.amount,
              sign: SignDisplay.always,
              style: t.figureXL.copyWith(color: e.isInflow ? c.green : c.ink),
            ),
          ),
          const SizedBox(height: Sp.lg),
          Text(e.description, style: t.body.copyWith(color: c.inkSoft), textAlign: TextAlign.center),
          const SizedBox(height: Sp.lg),
          LedgerFact(inset: false, label: 'Date', text: DateFormats.dayMonthYear.format(e.date)),
          LedgerFact(inset: false, label: 'Type', text: e.kind.label),
          LedgerFact(inset: false, label: 'Direction', text: e.isInflow ? 'Money in' : 'Money out'),
        ],
      ),
    );
  }
}
