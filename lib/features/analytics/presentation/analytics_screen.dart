import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/core_providers.dart';
import '../../../core/time/dates.dart';
import '../../../design_system/design_system.dart';
import '../../../design_system/luxe/luxe.dart';
import '../../../shared/presentation/luxe_async.dart';
import '../application/analytics_providers.dart';
import 'insight_widgets.dart';
import 'sections/breakdown_sections.dart';
import 'sections/commitment_sections.dart';
import 'sections/flow_sections.dart';
import 'sections/overview_section.dart';

/// Insights: one topic at a time. The period sits under the title; a
/// pinned rail of topics switches what is shown, so the numbers you want
/// are one tap away instead of a long scroll. Topic content cross-fades
/// and rises in, card by card.
class AnalyticsScreen extends ConsumerStatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  ConsumerState<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends ConsumerState<AnalyticsScreen> {
  final _scroll = ScrollController();
  final _headKey = GlobalKey();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// After switching topic, bring the topic rail back to the top of the
  /// viewport so the new topic starts at its first card.
  void _revealTop() {
    if (!_scroll.hasClients) return;
    final box = _headKey.currentContext?.findRenderObject() as RenderBox?;
    final target = (box?.size.height ?? 0.0) + 4;
    if (_scroll.offset <= target) return;
    if (context.reduceMotion) {
      _scroll.jumpTo(target);
    } else {
      _scroll.animateTo(target, duration: LuxeDurations.base, curve: LuxeCurves.arrive);
    }
  }

  List<Widget> _sectionChildren(BuildContext context, InsightsSection s, InsightsData d) => switch (s) {
    InsightsSection.overview => overviewSection(d),
    InsightsSection.spending => spendingSection(context, d),
    InsightsSection.cashFlow => cashFlowSection(context, d),
    InsightsSection.categories => categoriesSection(d),
    InsightsSection.payments => paymentsSection(context, d),
    InsightsSection.budgets => budgetsSection(context, d),
    InsightsSection.savings => savingsSection(context, d),
    InsightsSection.loans => loansSection(context, d),
    InsightsSection.subscriptions => subscriptionsSection(context, d),
  };

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(insightsDataProvider);
    final section = ref.watch(insightsSectionProvider);
    ref.listen(insightsSectionProvider, (prev, next) {
      if (prev != next) WidgetsBinding.instance.addPostFrameCallback((_) => _revealTop());
    });
    final data = value.value;
    return LuxeDetailPage(
      title: 'Insights',
      storageKey: 'insights',
      controller: _scroll,
      slivers: [
        SliverToBoxAdapter(
          child: ResponsiveCenter(
            key: _headKey,
            padding: const EdgeInsets.fromLTRB(LuxeSpace.gutter, 4, LuxeSpace.gutter, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Reveal(
                  child: LuxePageTitle(
                    eyebrow: data == null ? 'Your money, read' : data.periodLabel,
                    title: 'Insights',
                  ),
                ),
                const SizedBox(height: 18),
                if (data != null) Reveal(index: 1, child: _PeriodBar(filter: data.filter)),
              ],
            ),
          ),
        ),
        if (data == null)
          SliverToBoxAdapter(
            child: LuxeAsync<InsightsData>(
              value: value,
              loading: const LuxePageSkeleton(title: false, hero: 220, rows: 2),
              errorTitle: 'Could not load your insights',
              builder: (_, _) => const SizedBox.shrink(),
            ),
          )
        else ...[
          SliverPersistentHeader(
            pinned: true,
            delegate: LuxePinnedBar(height: 64, fullBleed: true, child: _TopicRail(selected: section)),
          ),
          SliverToBoxAdapter(
            child: ResponsiveCenter(
              padding: const EdgeInsets.fromLTRB(LuxeSpace.gutter, 10, LuxeSpace.gutter, 24),
              child: LuxeScope(
                child: AnimatedSwitcher(
                  duration: context.reduceMotion ? Duration.zero : LuxeDurations.base,
                  switchInCurve: LuxeCurves.arrive,
                  switchOutCurve: LuxeCurves.leave,
                  layoutBuilder: (current, previous) =>
                      Stack(alignment: Alignment.topCenter, children: [...previous, ?current]),
                  child: Builder(
                    // A new topic or period remounts the content, replaying
                    // the chart entrances for the new numbers.
                    key: ValueKey((section, data.filter)),
                    builder: (context) {
                      final children = _sectionChildren(context, section, data);
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var i = 0; i < children.length; i++) ...[
                            if (i > 0) const SizedBox(height: 16),
                            Reveal(index: i, child: children[i]),
                          ],
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Period
// ---------------------------------------------------------------------------

class _PeriodBar extends ConsumerWidget {
  const _PeriodBar({required this.filter});
  final InsightsFilter filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctrl = ref.read(insightsFilterProvider.notifier);
    final current = ref.watch(todayProvider.select((d) => d.monthKey));
    final isMonth = filter.period == InsightsPeriod.month;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LuxeSegmented<InsightsPeriod>(
          segments: [
            for (final p in InsightsPeriod.values)
              LuxeSegment(p, p == InsightsPeriod.month && filter.month != current ? 'Month' : p.label),
          ],
          selected: filter.period,
          onChanged: ctrl.setPeriod,
        ),
        MotionAnimatedSize(
          child: isMonth
              ? Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: LuxeMonthStepper(
                    month: filter.month,
                    compact: true,
                    min: current.shift(-(insightsHistoryMonths - 1)),
                    max: current,
                    subtitle: filter.month == current ? 'so far' : null,
                    onChanged: ctrl.setMonth,
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Topic rail (pinned)
// ---------------------------------------------------------------------------

class _TopicRail extends ConsumerStatefulWidget {
  const _TopicRail({required this.selected});
  final InsightsSection selected;

  @override
  ConsumerState<_TopicRail> createState() => _TopicRailState();
}

class _TopicRailState extends ConsumerState<_TopicRail> {
  final _keys = {for (final s in InsightsSection.values) s: GlobalKey()};

  @override
  void didUpdateWidget(_TopicRail old) {
    super.didUpdateWidget(old);
    if (old.selected != widget.selected) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _center(widget.selected));
    }
  }

  void _center(InsightsSection s) {
    final ctx = _keys[s]?.currentContext;
    if (ctx == null || !mounted) return;
    Scrollable.ensureVisible(
      ctx,
      alignment: 0.5,
      duration: context.reduceMotion ? Duration.zero : LuxeDurations.base,
      curve: LuxeCurves.arrive,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      key: const PageStorageKey('insights-topics'),
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: LuxeSpace.gutter),
      child: Row(
        children: [
          for (final s in InsightsSection.values) ...[
            if (s.index > 0) const SizedBox(width: 8),
            KeyedSubtree(
              key: _keys[s],
              child: LuxeChip(
                key: Key('insights-chip:${s.name}'),
                label: s.label,
                icon: s.icon,
                selected: s == widget.selected,
                semanticLabel: '${s.label} insights',
                onTap: () {
                  if (s == widget.selected) return;
                  ref.read(insightsSectionProvider.notifier).select(s);
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}
