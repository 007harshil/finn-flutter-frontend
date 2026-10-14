import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/core_providers.dart';
import '../../../core/time/dates.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/presentation/async_view.dart';
import '../application/analytics_providers.dart';
import 'insight_widgets.dart';
import 'sections/breakdown_sections.dart';
import 'sections/commitment_sections.dart';
import 'sections/flow_sections.dart';
import 'sections/overview_section.dart';

/// Insights: one topic at a time. A pinned row of chips switches between
/// topics, so the numbers you want are one tap away instead of a long scroll.
class AnalyticsScreen extends ConsumerWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(insightsDataProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Insights')),
      body: AsyncView<InsightsData>(
        value: data,
        loading: const _InsightsSkeleton(),
        errorTitle: 'Could not load your insights',
        builder: (context, d) => _InsightsBody(data: d),
      ),
    );
  }
}

class _InsightsSkeleton extends StatelessWidget {
  const _InsightsSkeleton();

  @override
  Widget build(BuildContext context) => const SkeletonPulse(
        child: ResponsiveCenter(
          padding: EdgeInsets.all(Space.gutter),
          child: Column(
            children: [
              SkeletonBox(height: 40, radius: Radii.full),
              SizedBox(height: Space.x3),
              SkeletonBox(height: 40, radius: Radii.full),
              SizedBox(height: Space.x4),
              CardSkeleton(height: 190, radius: Radii.xxxl),
              SizedBox(height: Space.x4),
              CardSkeleton(height: 240),
            ],
          ),
        ),
      );
}

class _InsightsBody extends ConsumerStatefulWidget {
  const _InsightsBody({required this.data});
  final InsightsData data;

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
  /// viewport so the new topic starts at its first card.
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
      _scroll.animateTo(target, duration: motion.slow, curve: motion.emphasized);
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
    final motion = context.motion;

    return CustomScrollView(
      key: const PageStorageKey('insights'),
      controller: _scroll,
      slivers: [
        SliverToBoxAdapter(
          child: ResponsiveCenter(
            key: _filterKey,
            padding: const EdgeInsets.fromLTRB(Space.gutter, Space.x2, Space.gutter, Space.x1),
            child: _FilterBar(filter: data.filter),
          ),
        ),
        SliverPersistentHeader(
          pinned: true,
          delegate: _ChipsHeader(selected: section),
        ),
        SliverToBoxAdapter(
          child: ResponsiveCenter(
            padding: EdgeInsets.fromLTRB(Space.gutter, Space.x3, Space.gutter, Space.x10 + context.bottomClearance),
            child: AnimatedSwitcher(
              duration: motion.normal,
              switchInCurve: motion.emphasized,
              switchOutCurve: Curves2.exit,
              layoutBuilder: (current, previous) => Stack(
                alignment: Alignment.topCenter,
                children: [...previous, ?current],
              ),
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: SlideTransition(
                  position: Tween(begin: const Offset(0, 0.02), end: Offset.zero).animate(anim),
                  child: child,
                ),
              ),
              child: Column(
                // A new topic or period remounts the content, replaying the
                // chart entrances for the new numbers.
                key: ValueKey((section, data.filter)),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < children.length; i++) ...[
                    if (i > 0) const SizedBox(height: Space.x4),
                    StaggeredEntrance(index: i, child: children[i]),
                  ],
                ],
              ),
            ),
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
        SegmentedTabs<InsightsPeriod>(
          items: [
            for (final p in InsightsPeriod.values)
              SegmentItem(p, p == InsightsPeriod.month && filter.month != current ? 'Month' : p.label),
          ],
          selected: filter.period,
          onChanged: ctrl.setPeriod,
        ),
        if (isMonth) ...[
          const SizedBox(height: Space.x3),
          MonthSwitcher(
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

  static const double _height = 60;

  @override
  double get minExtent => _height;

  @override
  double get maxExtent => _height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final c = context.colors;
    final pinned = shrinkOffset > 0 || overlapsContent;
    return AnimatedContainer(
      duration: context.motion.fast,
      decoration: BoxDecoration(
        color: c.background,
        border: Border(bottom: BorderSide(color: pinned ? c.border : Colors.transparent)),
      ),
      child: Center(child: ResponsiveCenter(child: _SectionChips(selected: selected))),
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
    Scrollable.ensureVisible(ctx, alignment: 0.5, duration: context.motion.normal, curve: context.motion.emphasized);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
      child: Row(
        children: [
          for (final s in InsightsSection.values) ...[
            if (s.index > 0) const SizedBox(width: Space.x2),
            _SectionChip(
              key: _keys[s],
              section: s,
              selected: s == widget.selected,
              onTap: () {
                if (s == widget.selected) return;
                HapticFeedback.selectionClick();
                ref.read(insightsSectionProvider.notifier).select(s);
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _SectionChip extends StatelessWidget {
  const _SectionChip({super.key, required this.section, required this.selected, required this.onTap});

  final InsightsSection section;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final a = section.accent(c);
    final fg = selected ? Colors.white : c.textPrimary;
    return Semantics(
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      label: '${section.label} insights',
      excludeSemantics: true,
      child: GestureDetector(
        key: Key('insights-chip:${section.name}'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedScale(
          scale: selected ? 1.0 : 0.96,
          duration: context.motion.fast,
          child: AnimatedContainer(
            duration: context.motion.normal,
            curve: Curves2.emphasized,
            constraints: const BoxConstraints(minHeight: 40),
            padding: const EdgeInsets.symmetric(horizontal: Space.x3, vertical: Space.x2),
            decoration: BoxDecoration(
              color: selected ? a : c.surface,
              borderRadius: Radii.rFull,
              border: Border.all(color: selected ? a : c.border, width: 1.5),
              boxShadow: selected && !c.isDark
                  ? [BoxShadow(color: a.withValues(alpha: 0.3), blurRadius: 10, offset: const Offset(0, 3))]
                  : const [],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(section.icon, size: 15, color: selected ? Colors.white : a),
                const SizedBox(width: Space.x1_5),
                Text(section.label, style: context.text.label.copyWith(color: fg, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
