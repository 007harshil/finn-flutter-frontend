import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/di/data_providers.dart';
import '../../../app/router/routes.dart';
import '../../../core/time/dates.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/presentation/async_view.dart';
import '../../../shared/presentation/category_icons.dart';
import '../../alerts/presentation/alert_visuals.dart' show MaybeAnimate;
import '../../emergency_fund/domain/emergency_fund.dart';
import '../application/goal_view.dart';
import '../domain/goal.dart';
import 'savings_visuals.dart';
import 'savings_widgets.dart';

/// "Your vision": every goal in one board, the emergency fund as a single
/// line, then compact goal rows with one-tap "add money".
///
/// Top to bottom: board (saved vs. targets, a mosaic bar where each goal's
/// width is its target and its fill is what is saved, monthly effort needed
/// vs. planned, status shortcuts), emergency fund line, a pinned bar with
/// Active / Completed / Archived tabs plus sort & filter, then rows.
class GoalsScreen extends ConsumerStatefulWidget {
  const GoalsScreen({super.key});

  @override
  ConsumerState<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends ConsumerState<GoalsScreen> {
  GoalListFilter _filter = const GoalListFilter();
  final Set<String> _entered = {};

  void _set(GoalListFilter f) => setState(() => _filter = f);

  void _togglePace(GoalPace p) {
    final only = _filter.paces.length == 1 && _filter.paces.contains(p);
    _set(_filter.copyWith(tab: GoalTab.active, paces: only ? const {} : {p}));
  }

  Future<void> _openOptions() async {
    final next = await showFinnSheet<GoalListFilter>(context, builder: (_) => _OptionsSheet(initial: _filter));
    if (next != null && mounted) _set(next);
  }

  Future<void> _quickActions(GoalProgress g) async {
    final active = g.goal.status == GoalStatus.active;
    final choice = await showFinnActionMenu<int>(
      context,
      title: g.goal.name,
      items: [
        if (active) const FinnMenuItem(value: 0, label: 'Add money', icon: LucideIcons.plus),
        if (active && g.saved.isPositive) const FinnMenuItem(value: 1, label: 'Withdraw', icon: LucideIcons.minus),
        const FinnMenuItem(value: 2, label: 'Open details', icon: LucideIcons.arrowUpRight),
        const FinnMenuItem(value: 3, label: 'Edit goal', icon: LucideIcons.pencil),
      ],
    );
    if (!mounted || choice == null) return;
    context.push(switch (choice) {
      0 => AppRoutes.goalContribute(g.goal.id),
      1 => AppRoutes.goalWithdraw(g.goal.id),
      3 => AppRoutes.editGoal(g.goal.id),
      _ => AppRoutes.goal(g.goal.id),
    });
  }

  @override
  Widget build(BuildContext context) {
    final board = ref.watch(goalsBoardProvider);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: AsyncView<GoalsBoard>(
          value: board,
          loading: const _GoalsSkeleton(),
          builder: (context, b) {
            final shown = filterGoals(b.all, _filter);
            return CustomScrollView(
              key: const PageStorageKey('goals'),
              slivers: [
                _boxed(const _Header(), top: Space.x4),
                if (b.active.isNotEmpty)
                  _boxed(
                    StaggeredEntrance(child: _BoardCard(board: b, filter: _filter, onPace: _togglePace)),
                    top: Space.x3,
                  ),
                _boxed(const StaggeredEntrance(index: 1, child: _EmergencyLine()), top: Space.x3),
                if (b.all.isEmpty)
                  _boxed(
                    EmptyState(
                      icon: LucideIcons.target,
                      title: 'Start your first goal',
                      message: 'A trip, a new laptop, a home down payment — give it a name and a target, '
                          'and set money aside at your own pace.',
                      actionLabel: 'Create a goal',
                      actionIcon: LucideIcons.plus,
                      onAction: () => context.push(AppRoutes.newGoal),
                    ),
                    top: Space.x5,
                  )
                else ...[
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: _BarDelegate(
                      child: _Controls(
                        counts: b.tabCounts,
                        filter: _filter,
                        onTab: (t) => _set(_filter.copyWith(tab: t)),
                        onOptions: _openOptions,
                      ),
                    ),
                  ),
                  _boxed(_ResultLine(count: shown.length, filter: _filter, onChanged: _set, onSort: _openOptions)),
                  if (shown.isEmpty)
                    _boxed(_emptyFor(context), top: Space.x2)
                  else
                    SliverList.builder(
                      itemCount: shown.length,
                      itemBuilder: (context, i) {
                        final g = shown[i];
                        final row = GoalRow(
                          key: ValueKey(g.goal.id),
                          progress: g,
                          today: b.today,
                          onLongPress: () => _quickActions(g),
                        );
                        final first = _entered.add(g.goal.id);
                        return ResponsiveCenter(
                          padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.x2),
                          child: !first || i > 10
                              ? row
                              : row.maybeAnimate(
                                  context,
                                  (a) => a
                                      .fadeIn(delay: 40.ms * i, duration: 260.ms)
                                      .slideY(begin: 0.2, end: 0, delay: 40.ms * i, duration: 380.ms, curve: Curves.easeOutCubic),
                                ),
                        );
                      },
                    ),
                ],
                SliverToBoxAdapter(child: SizedBox(height: context.bottomClearance)),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _emptyFor(BuildContext context) {
    if (_filter.paces.isNotEmpty || _filter.categories.isNotEmpty) {
      return EmptyState(
        icon: LucideIcons.searchX,
        title: 'No matches',
        message: 'No goal fits these filters.',
        actionLabel: 'Clear filters',
        onAction: () => _set(_filter.cleared()),
      );
    }
    return switch (_filter.tab) {
      GoalTab.active => EmptyState(
          icon: LucideIcons.target,
          title: 'No active goals',
          message: 'Every goal is done or archived. Start a new one when you are ready.',
          actionLabel: 'Create a goal',
          actionIcon: LucideIcons.plus,
          onAction: () => context.push(AppRoutes.newGoal),
        ),
      GoalTab.completed => const EmptyState(
          icon: LucideIcons.partyPopper,
          title: 'Nothing completed yet',
          message: 'Goals you fully fund will appear here.',
        ),
      GoalTab.archived => const EmptyState(
          icon: LucideIcons.archive,
          title: 'No archived goals',
          message: 'Archive a goal to hide it without losing its history.',
        ),
    };
  }
}

Widget _boxed(Widget child, {double top = 0}) => SliverToBoxAdapter(
      child: ResponsiveCenter(padding: EdgeInsets.fromLTRB(Space.gutter, top, Space.gutter, 0), child: child),
    );

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final t = context.text;
    return Row(
      children: [
        Expanded(
          child: Semantics(
            header: true,
            label: 'Your vision',
            excludeSemantics: true,
            child: Text.rich(
              TextSpan(children: [
                const TextSpan(text: 'Your '),
                TextSpan(text: 'vision', style: TextStyle(color: context.colors.accentGoals)),
              ]),
              style: t.pageTitle,
            ),
          ),
        ),
        FinnButton(
          label: 'New goal',
          icon: LucideIcons.plus,
          size: FinnButtonSize.sm,
          onPressed: () => context.push(AppRoutes.newGoal),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Board
// ---------------------------------------------------------------------------

class _BoardCard extends StatelessWidget {
  const _BoardCard({required this.board, required this.filter, required this.onPace});

  final GoalsBoard board;
  final GoalListFilter filter;
  final ValueChanged<GoalPace> onPace;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final b = board;
    final need = b.neededMonthly;
    final plan = b.plannedMonthly;
    final short = need.isPositive && plan < need;
    final shortcuts = [
      for (final p in [GoalPace.behind, GoalPace.onTrack, GoalPace.noPlan])
        if (b.count(p) > 0) p,
    ];
    return FinnCard(
      radius: Radii.xxl,
      padding: const EdgeInsets.fromLTRB(Space.x4, Space.x4, Space.x4, Space.x3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text('SAVED FOR YOUR GOALS', style: t.eyebrow)),
              Text('${b.active.length} active', style: t.micro),
            ],
          ),
          const SizedBox(height: Space.x1),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: AnimatedAmount(b.saved, animateOnMount: true, fit: true, style: t.amountLarge),
              ),
              const SizedBox(width: Space.x2),
              Flexible(child: Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('of ${savingsMoney(context, b.target)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: t.caption),
              )),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  formatPct(b.progress),
                  style: t.bodyStrong.copyWith(color: c.accentGoals, fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.x3),
          GoalMosaic(goals: b.active, onOpen: (g) => context.push(AppRoutes.goal(g.goal.id))),
          const SizedBox(height: Space.x1),
          Text('Each block is a goal — wider = bigger target. Tap one to open it.', style: t.micro),
          if (need.isPositive || plan.isPositive) ...[
            const SizedBox(height: Space.x3),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: Space.x3, vertical: Space.x2_5),
              decoration: BoxDecoration(
                color: (short ? c.warning : c.positive).withValues(alpha: c.isDark ? 0.16 : 0.09),
                borderRadius: Radii.rLg,
              ),
              child: Row(
                children: [
                  Icon(short ? LucideIcons.trendingDown : LucideIcons.trendingUp,
                      size: 16, color: short ? c.warning : c.positive),
                  const SizedBox(width: Space.x2),
                  Expanded(
                    child: Text.rich(
                      TextSpan(children: [
                        if (need.isPositive) ...[
                          TextSpan(
                            text: '${savingsMoney(context, need)}/month',
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                          const TextSpan(text: ' keeps every dated goal on time'),
                        ] else
                          const TextSpan(text: 'No target dates set'),
                        TextSpan(
                          text: plan.isPositive ? ' · you put in ~${savingsMoney(context, plan)}' : ' · no monthly plan yet',
                          style: TextStyle(color: c.textSecondary),
                        ),
                      ]),
                      style: t.label.copyWith(color: c.textPrimary),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (shortcuts.isNotEmpty) ...[
            const SizedBox(height: Space.x3),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var i = 0; i < shortcuts.length; i++) ...[
                    if (i > 0) const SizedBox(width: Space.x2),
                    FinnTapChip(
                      key: ValueKey('goal-attn:${shortcuts[i].name}'),
                      label: shortcuts[i].countLabel(b.count(shortcuts[i])),
                      icon: shortcuts[i].icon,
                      color: shortcuts[i] == GoalPace.noPlan ? c.textSecondary : shortcuts[i].color(c),
                      selected: filter.tab == GoalTab.active &&
                          filter.paces.length == 1 &&
                          filter.paces.contains(shortcuts[i]),
                      height: 32,
                      onTap: () => onPace(shortcuts[i]),
                    ).maybeAnimate(
                      context,
                      (a) => a
                          .fadeIn(delay: 300.ms + 70.ms * i, duration: 280.ms)
                          .slideX(begin: 0.3, end: 0, delay: 300.ms + 70.ms * i, duration: 420.ms, curve: Curves.easeOutCubic),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Emergency fund in one tappable line: a shield filling with its level,
/// months covered, and the level word.
class _EmergencyLine extends ConsumerWidget {
  const _EmergencyLine();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(emergencyStatusProvider).value;
    if (s == null) return const CardSkeleton(height: 68);
    final c = context.colors;
    final t = context.text;
    final configured = s.level != EmergencyFundLevel.notConfigured;
    final color = switch (s.level) {
      EmergencyFundLevel.critical => c.negative,
      EmergencyFundLevel.building => c.attention,
      EmergencyFundLevel.funded => c.positive,
      EmergencyFundLevel.notConfigured => c.accentEmergency,
    };
    final coverage = s.coverageMonths;
    final sub = !configured
        ? 'Not set up · plan a safety net'
        : [
            if (coverage != null) '${coverageLabel(coverage)} of ${s.plan!.targetMonths} covered',
            '${formatPct(s.progress)} of ${savingsMoney(context, s.target)}',
          ].join(' · ');
    return FinnCard(
      key: const ValueKey('goals-emergency-line'),
      padding: const EdgeInsets.fromLTRB(Space.x3, Space.x2_5, Space.x3, Space.x2_5),
      onTap: () => context.push(AppRoutes.emergencyFund),
      semanticLabel: configured
          ? 'Emergency fund, ${s.level.label}. ${savingsMoney(context, s.saved)} saved. $sub.'
          : 'Emergency fund not set up. Tap to set it up.',
      child: Row(
        children: [
          ShieldFill(progress: configured ? s.progress : 0, color: color, size: 40),
          const SizedBox(width: Space.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(child: Text('Emergency fund', maxLines: 1, overflow: TextOverflow.ellipsis, style: t.bodyStrong)),
                    const SizedBox(width: Space.x2),
                    if (configured) Flexible(child: AmountText(s.saved, fit: true, style: t.label.copyWith(fontWeight: FontWeight.w800))),
                  ],
                ),
                const SizedBox(height: 2),
                Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.caption),
              ],
            ),
          ),
          const SizedBox(width: Space.x2),
          StatusPill(label: s.level.label, color: color, icon: emergencyLevelIcon(s.level)),
          const SizedBox(width: Space.x1),
          Icon(LucideIcons.chevronRight, size: 16, color: c.textTertiary),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Goal row
// ---------------------------------------------------------------------------

/// Compact goal: icon in a progress ring, name, %, a bar with a "should be
/// here by now" tick for dated goals, one hint line, and "+" to add money.
class GoalRow extends StatelessWidget {
  const GoalRow({super.key, required this.progress, required this.today, this.onLongPress});

  final GoalProgress progress;
  final DateTime today;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final g = progress;
    final pace = goalPaceOf(g);
    final accent = AccentSwatches.solid(g.goal.colorIndex);
    final active = g.goal.status == GoalStatus.active && !g.isAchieved;
    final expected = active ? expectedShare(g, today) : null;
    final date = g.goal.targetDate;
    final hint = [
      if (g.isAchieved) 'Target reached' else '${savingsMoney(context, g.remaining)} to go',
      if (date != null && !g.isAchieved) 'by ${DateFormats.shortMonthYear.format(date)}',
      if (pace == GoalPace.behind && g.requiredMonthly != null) 'needs ${savingsMoney(context, g.requiredMonthly!)}/mo',
    ].join(' · ');
    final archived = g.goal.status == GoalStatus.archived;
    return Semantics(
      container: true,
      label: '${g.goal.name}. ${savingsMoney(context, g.saved)} saved of ${savingsMoney(context, g.goal.target)}, '
          '${formatPct(g.progress)}. ${pace.label}. $hint.',
      child: PressableScale(
        child: Material(
          color: archived ? c.surfaceMuted : c.surface,
          shape: RoundedRectangleBorder(borderRadius: Radii.rXl, side: BorderSide(color: c.border)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () {
              HapticFeedback.selectionClick();
              context.push(AppRoutes.goal(g.goal.id));
            },
            onLongPress: onLongPress == null
                ? null
                : () {
                    HapticFeedback.mediumImpact();
                    onLongPress!();
                  },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Space.x3, Space.x3, Space.x1, Space.x2_5),
              child: Row(
                children: [
                  Opacity(
                    opacity: archived ? 0.55 : 1,
                    child: GoalRing(
                      progress: g.progress,
                      colors: AccentSwatches.of(g.goal.colorIndex),
                      size: 46,
                      stroke: 4.5,
                      milestones: false,
                      child: Icon(CategoryIcons.of(g.goal.category.iconKey), size: 22, color: accent),
                    ),
                  ),
                  const SizedBox(width: Space.x3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(g.goal.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.bodyStrong),
                            ),
                            const SizedBox(width: Space.x2),
                            Text(
                              formatPct(g.progress),
                              style: t.label.copyWith(fontWeight: FontWeight.w900, color: c.textPrimary),
                            ),
                          ],
                        ),
                        const SizedBox(height: Space.x1_5),
                        _GoalBar(progress: g.progress, expected: expected, color: accent, pace: pace),
                        const SizedBox(height: Space.x1_5),
                        Row(
                          children: [
                            Icon(pace.icon, size: 12, color: pace.color(c)),
                            const SizedBox(width: Space.x1),
                            Expanded(
                              child: Text(
                                hint,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: t.caption.copyWith(
                                  color: pace == GoalPace.behind ? c.warning : c.textSecondary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (active)
                    FinnIconButton(
                      key: ValueKey('goal-add:${g.goal.id}'),
                      icon: LucideIcons.plus,
                      tooltip: 'Add money to ${g.goal.name}',
                      size: FinnButtonSize.sm,
                      color: accent,
                      onPressed: () => context.push(AppRoutes.goalContribute(g.goal.id)),
                    )
                  else
                    const SizedBox(width: Space.x3),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Saved bar with a tick where a dated goal should be by now.
class _GoalBar extends StatelessWidget {
  const _GoalBar({required this.progress, required this.expected, required this.color, required this.pace});

  final double progress;
  final double? expected;
  final Color color;
  final GoalPace pace;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SizedBox(
      height: 12,
      child: LayoutBuilder(
        builder: (context, box) {
          final w = box.maxWidth;
          return Stack(
            alignment: Alignment.centerLeft,
            children: [
              Container(
                height: 6,
                decoration: BoxDecoration(color: c.surfaceMuted, borderRadius: Radii.rFull),
              ),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: progress.clamp(0.0, 1.0)),
                duration: context.reduceMotion ? Duration.zero : const Duration(milliseconds: 900),
                curve: Curves2.emphasized,
                builder: (context, v, _) => Container(
                  width: w * v,
                  height: 6,
                  decoration: BoxDecoration(
                    color: pace == GoalPace.done ? c.positive : color,
                    borderRadius: Radii.rFull,
                  ),
                ),
              ),
              if (expected != null && expected! > 0 && expected! < 1)
                Positioned(
                  left: (w * expected!).clamp(1.0, w - 2),
                  top: 0,
                  bottom: 0,
                  child: Tooltip(
                    message: 'Where you should be by now',
                    child: Container(
                      width: 2,
                      decoration: BoxDecoration(color: c.textPrimary, borderRadius: Radii.rFull),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Pinned controls
// ---------------------------------------------------------------------------

class _BarDelegate extends SliverPersistentHeaderDelegate {
  const _BarDelegate({required this.child});

  final Widget child;

  static const _height = 56.0;

  @override
  double get minExtent => _height;

  @override
  double get maxExtent => _height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final c = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.background,
        border: overlapsContent ? Border(bottom: BorderSide(color: c.border)) : null,
      ),
      child: ResponsiveCenter(
        padding: const EdgeInsets.symmetric(horizontal: Space.gutter, vertical: Space.x2),
        child: child,
      ),
    );
  }

  @override
  bool shouldRebuild(_BarDelegate old) => old.child != child;
}

class _Controls extends StatelessWidget {
  const _Controls({required this.counts, required this.filter, required this.onTab, required this.onOptions});

  final Map<GoalTab, int> counts;
  final GoalListFilter filter;
  final ValueChanged<GoalTab> onTab;
  final VoidCallback onOptions;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    const tabs = GoalTab.values;
    final index = tabs.indexOf(filter.tab);
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 40,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(color: c.surfaceMuted, borderRadius: Radii.rFull),
            child: Stack(
              children: [
                AnimatedAlign(
                  alignment: Alignment(-1 + 2 * index / (tabs.length - 1), 0),
                  duration: context.motion.normal,
                  curve: Curves2.emphasized,
                  child: FractionallySizedBox(
                    widthFactor: 1 / tabs.length,
                    heightFactor: 1,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: c.isDark ? c.border : c.surface,
                        borderRadius: Radii.rFull,
                        boxShadow: c.isDark ? Elevation.none : Elevation.sm,
                      ),
                    ),
                  ),
                ),
                Row(
                  children: [
                    for (final tab in tabs)
                      Expanded(
                        child: Semantics(
                          button: true,
                          selected: tab == filter.tab,
                          inMutuallyExclusiveGroup: true,
                          label: '${tab.label}, ${counts[tab] ?? 0}',
                          excludeSemantics: true,
                          child: GestureDetector(
                            key: ValueKey('goal-tab:${tab.name}'),
                            behavior: HitTestBehavior.opaque,
                            onTap: () {
                              if (tab == filter.tab) return;
                              HapticFeedback.selectionClick();
                              onTab(tab);
                            },
                            child: Center(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: Space.x1_5),
                                  child: Text.rich(
                                    TextSpan(children: [
                                      TextSpan(text: tab.label),
                                      TextSpan(
                                        text: ' ${counts[tab] ?? 0}',
                                        style: TextStyle(
                                          color: tab == filter.tab ? c.accentGoals : c.textTertiary,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ]),
                                    maxLines: 1,
                                    style: t.label.copyWith(
                                      color: tab == filter.tab ? c.textPrimary : c.textSecondary,
                                      fontWeight: tab == filter.tab ? FontWeight.w800 : FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: Space.x1),
        CountBadge(
          count: filter.activeCount,
          color: c.primary,
          semanticsLabel: '${filter.activeCount} filters on',
          child: FinnIconButton(
            key: const ValueKey('goal-options'),
            icon: LucideIcons.slidersHorizontal,
            tooltip: 'Sort & filter',
            variant: filter.activeCount > 0 ? FinnIconButtonVariant.filled : FinnIconButtonVariant.ghost,
            onPressed: onOptions,
          ),
        ),
      ],
    );
  }
}

class _ResultLine extends StatelessWidget {
  const _ResultLine({required this.count, required this.filter, required this.onChanged, required this.onSort});

  final int count;
  final GoalListFilter filter;
  final ValueChanged<GoalListFilter> onChanged;
  final VoidCallback onSort;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final f = filter;
    final removable = <(String, VoidCallback)>[
      for (final p in f.paces) (p.label, () => onChanged(f.copyWith(paces: {...f.paces}..remove(p)))),
      for (final k in f.categories) (k.label, () => onChanged(f.copyWith(categories: {...f.categories}..remove(k)))),
    ];
    return SizedBox(
      height: 36,
      child: Row(
        children: [
          Text('$count ${count == 1 ? 'GOAL' : 'GOALS'}', style: t.eyebrow),
          const SizedBox(width: Space.x2),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true,
              child: Row(
                children: [
                  for (final (label, remove) in removable) ...[
                    FinnTapChip(
                      label: label,
                      trailing: LucideIcons.x,
                      color: c.primary,
                      height: 28,
                      semantics: 'Remove filter $label',
                      onTap: remove,
                    ),
                    const SizedBox(width: Space.x1_5),
                  ],
                  FinnTapChip(
                    label: f.sort.label,
                    icon: LucideIcons.arrowDownUp,
                    trailing: LucideIcons.chevronDown,
                    height: 28,
                    semantics: 'Sorted by ${f.sort.label}. Change',
                    onTap: onSort,
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

// ---------------------------------------------------------------------------
// Sort & filter sheet
// ---------------------------------------------------------------------------

class _OptionsSheet extends StatefulWidget {
  const _OptionsSheet({required this.initial});

  final GoalListFilter initial;

  @override
  State<_OptionsSheet> createState() => _OptionsSheetState();
}

class _OptionsSheetState extends State<_OptionsSheet> {
  late GoalListFilter _f = widget.initial;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    Widget section(String title, List<Widget> chips) => Padding(
          padding: const EdgeInsets.only(bottom: Space.x5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: t.eyebrow),
              const SizedBox(height: Space.x2),
              Wrap(spacing: Space.x2, runSpacing: Space.x2, children: chips),
            ],
          ),
        );
    return FinnSheetScaffold(
      title: 'Sort & filter',
      footer: Row(
        children: [
          Expanded(
            child: FinnButton(
              label: 'Reset',
              variant: FinnButtonVariant.outline,
              expand: true,
              onPressed: () => setState(() => _f = _f.cleared()),
            ),
          ),
          const SizedBox(width: Space.x3),
          Expanded(
            child: FinnButton(
              key: const ValueKey('goal-apply'),
              label: 'Apply',
              expand: true,
              onPressed: () => Navigator.of(context).pop(_f),
            ),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          section('SORT BY', [
            for (final s in GoalSort.values)
              FinnTapChip(
                key: ValueKey('goal-sort:${s.name}'),
                label: s.label,
                selected: _f.sort == s,
                color: c.primary,
                height: 36,
                onTap: () => setState(() => _f = _f.copyWith(sort: s)),
              ),
          ]),
          if (_f.tab == GoalTab.active)
            section('STATUS', [
              for (final p in [GoalPace.behind, GoalPace.onTrack, GoalPace.noPlan])
                FinnTapChip(
                  key: ValueKey('goal-pace:${p.name}'),
                  label: p.label,
                  icon: p.icon,
                  selected: _f.paces.contains(p),
                  color: p.color(c),
                  height: 36,
                  onTap: () => setState(() {
                    final next = {..._f.paces};
                    if (!next.remove(p)) next.add(p);
                    _f = _f.copyWith(paces: next);
                  }),
                ),
            ]),
          section('CATEGORY', [
            for (final k in GoalCategory.values)
              FinnTapChip(
                label: k.label,
                icon: CategoryIcons.of(k.iconKey),
                selected: _f.categories.contains(k),
                color: c.accentGoals,
                height: 36,
                onTap: () => setState(() {
                  final next = {..._f.categories};
                  if (!next.remove(k)) next.add(k);
                  _f = _f.copyWith(categories: next);
                }),
              ),
          ]),
        ],
      ),
    );
  }
}

class _GoalsSkeleton extends StatelessWidget {
  const _GoalsSkeleton();

  @override
  Widget build(BuildContext context) => const SkeletonPulse(
        child: ResponsiveCenter(
          padding: EdgeInsets.symmetric(horizontal: Space.gutter),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: Space.x4),
              SkeletonBox(width: 160, height: 28),
              SizedBox(height: Space.x4),
              CardSkeleton(height: 200, radius: Radii.xxl),
              SizedBox(height: Space.x3),
              CardSkeleton(height: 64),
              SizedBox(height: Space.x3),
              SkeletonBox(height: 40, radius: Radii.full),
              SizedBox(height: Space.x4),
              CardSkeleton(height: 76),
              SizedBox(height: Space.x2),
              CardSkeleton(height: 76),
            ],
          ),
        ),
      );
}
