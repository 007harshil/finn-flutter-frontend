import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/core_providers.dart';
import '../../../core/time/dates.dart';
import '../../../kit/kit.dart';
import '../../../shared/presentation/async_view.dart';
import '../application/analytics_providers.dart';
import 'sections/breakdown_sections.dart';
import 'sections/commitment_sections.dart';
import 'sections/flow_sections.dart';
import 'sections/overview_section.dart';

/// Insights: the period on top, then one topic at a time. A pinned row of
/// chips switches between topics, so the numbers you want are one tap away
/// instead of a long scroll.
class AnalyticsScreen extends ConsumerWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(insightsDataProvider);
    const appBar = LedgerAppBar(title: 'Insights');
    return AsyncView<InsightsData>(
      value: data,
      loading: Scaffold(backgroundColor: context.ink.paper, appBar: appBar, body: const LedgerPageSkeleton()),
      errorTitle: 'Could not load your insights',
      builder: (context, d) => _InsightsBody(data: d, appBar: appBar),
    );
  }
}

class _InsightsBody extends ConsumerStatefulWidget {
  const _InsightsBody({required this.data, required this.appBar});
  final InsightsData data;
  final PreferredSizeWidget appBar;

  @override
  ConsumerState<_InsightsBody> createState() => _InsightsBodyState();
}

class _InsightsBodyState extends ConsumerState<_InsightsBody> {
  final _scroll = ScrollController();
  final _filterKey = GlobalKey();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// After switching topic, bring the chip row back to the top of the
  /// viewport so the new topic starts at its first block.
  void _revealTop() {
    if (!_scroll.hasClients) return;
    // The chips sit directly below the period filter, so its height is the
    // scroll offset at which they pin.
    final box = _filterKey.currentContext?.findRenderObject() as RenderBox?;
    final target = box?.size.height ?? 0.0;
    if (_scroll.offset <= target) return;
    final motion = context.motion;
    if (motion.reduced) {
      _scroll.jumpTo(target);
    } else {
      _scroll.animateTo(target, duration: motion.slow, curve: motion.standard);
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
    final data = widget.data;
    final section = ref.watch(insightsSectionProvider);
    ref.listen(insightsSectionProvider, (prev, next) {
      if (prev != next) WidgetsBinding.instance.addPostFrameCallback((_) => _revealTop());
    });
    final children = _sectionChildren(context, section, data);

    return LedgerPage(
      appBar: widget.appBar,
      storageKey: 'insights',
      controller: _scroll,
      slivers: [
        SliverToBoxAdapter(
          child: PageColumn(
            key: _filterKey,
            top: Sp.sm,
            bottom: Sp.md,
            child: _FilterBar(filter: data.filter),
          ),
        ),
        SliverPersistentHeader(pinned: true, delegate: _ChipsHeader(selected: section)),
        PageBlock(
          top: Sp.lg,
          child: Column(
            // A new topic or period remounts the content, replaying the
            // chart entrances for the new numbers.
            key: ValueKey((section, data.filter)),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const SizedBox(height: Sp.section),
                children[i],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Period filter
// ---------------------------------------------------------------------------

class _FilterBar extends ConsumerWidget {
  const _FilterBar({required this.filter});
  final InsightsFilter filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctrl = ref.read(insightsFilterProvider.notifier);
    final current = ref.watch(todayProvider.select((d) => d.monthKey));
    final isMonth = filter.period == InsightsPeriod.month;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LedgerSegmented<InsightsPeriod>(
          segments: [
            for (final p in InsightsPeriod.values)
              LedgerSegment(p, p == InsightsPeriod.month && filter.month != current ? 'Month' : p.label),
          ],
          selected: filter.period,
          onChanged: ctrl.setPeriod,
        ),
        if (isMonth) ...[
          const SizedBox(height: Sp.sm),
          MonthStepper(
            month: filter.month,
            min: current.shift(-(insightsHistoryMonths - 1)),
            max: current,
            onChanged: ctrl.setMonth,
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Topic chips (pinned)
// ---------------------------------------------------------------------------

class _ChipsHeader extends SliverPersistentHeaderDelegate {
  _ChipsHeader({required this.selected});
  final InsightsSection selected;

  static const double _height = 56;

  @override
  double get minExtent => _height;

  @override
  double get maxExtent => _height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final c = context.ink;
    final pinned = shrinkOffset > 0 || overlapsContent;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.paper,
        border: Border(bottom: BorderSide(color: pinned ? c.line : Colors.transparent)),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Sp.maxWidth),
          child: _SectionChips(selected: selected),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(_ChipsHeader old) => old.selected != selected;
}

class _SectionChips extends ConsumerStatefulWidget {
  const _SectionChips({required this.selected});
  final InsightsSection selected;

  @override
  ConsumerState<_SectionChips> createState() => _SectionChipsState();
}

class _SectionChipsState extends ConsumerState<_SectionChips> {
  final _keys = {for (final s in InsightsSection.values) s: GlobalKey()};

  @override
  void didUpdateWidget(_SectionChips old) {
    super.didUpdateWidget(old);
    if (old.selected != widget.selected) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _center(widget.selected));
    }
  }

  void _center(InsightsSection s) {
    final ctx = _keys[s]?.currentContext;
    if (ctx == null || !mounted) return;
    Scrollable.ensureVisible(ctx, alignment: 0.5, duration: context.motion.normal, curve: context.motion.standard);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: Sp.gutter),
      child: Row(
        children: [
          for (final s in InsightsSection.values) ...[
            if (s.index > 0) const SizedBox(width: Sp.sm),
            KeyedSubtree(
              key: _keys[s],
              child: Semantics(
                inMutuallyExclusiveGroup: true,
                child: LedgerChip(
                  key: Key('insights-chip:${s.name}'),
                  label: s.label,
                  selected: s == widget.selected,
                  semanticLabel: '${s.label} insights',
                  onTap: () {
                    if (s == widget.selected) return;
                    ref.read(insightsSectionProvider.notifier).select(s);
                  },
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
