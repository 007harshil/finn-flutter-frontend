import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/di/data_providers.dart';
import '../../../app/router/routes.dart';
import '../../../app/shell/app_drawer.dart';
import '../../../core/money/money_format.dart';
import '../../../design_system/design_system.dart'
    show AmountText, AnimatedAmount, BottomClearanceX, FinnMenuItem, showFinnActionMenu;
import '../../../shared/presentation/async_view.dart';
import '../../../ui/ui.dart';
import '../../emergency_fund/domain/emergency_fund.dart';
import '../application/goal_view.dart';
import '../domain/goal.dart';
import 'goal_ui.dart';
import 'savings_widgets.dart';

/// Goals: what is saved across active goals and what it takes each month,
/// the emergency fund, then every goal closest-to-done first. One tap adds
/// money; a long press offers the rest.
class GoalsScreen extends ConsumerStatefulWidget {
  const GoalsScreen({super.key});

  @override
  ConsumerState<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends ConsumerState<GoalsScreen> {
  GoalListFilter _filter = const GoalListFilter();

  void _set(GoalListFilter f) => setState(() => _filter = f);

  void _togglePace(GoalPace p) {
    final only = _filter.tab == GoalTab.active && _filter.paces.length == 1 && _filter.paces.contains(p);
    _set(_filter.copyWith(tab: GoalTab.active, paces: only ? const {} : {p}));
  }

  Future<void> _pickSort() async {
    final picked = await showFinnActionMenu<GoalSort>(
      context,
      title: 'Sort by',
      items: [
        for (final s in GoalSort.values)
          FinnMenuItem(value: s, label: s.label, icon: s == _filter.sort ? LucideIcons.check : LucideIcons.arrowDownUp),
      ],
    );
    if (picked != null && mounted) _set(_filter.copyWith(sort: picked));
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
    return UiPage(
      leading: const AppMenuButton(),
      title: 'Goals',
      actions: [
        UiIconButton(icon: LucideIcons.plus, tooltip: 'New goal', onPressed: () => context.push(AppRoutes.newGoal)),
      ],
      body: AsyncView<GoalsBoard>(
        value: ref.watch(goalsBoardProvider),
        loading: const _Placeholder(),
        builder: (context, b) {
          final shown = filterGoals(b.all, _filter);
          return CustomScrollView(
            key: const PageStorageKey('goals'),
            slivers: [
              if (b.active.isNotEmpty)
                _box(
                  UiReveal(index: 0, child: _Summary(board: b)),
                  top: UiSpace.sm,
                ),
              _box(
                const UiReveal(index: 1, child: _EmergencyLine()),
                top: b.active.isNotEmpty ? UiSpace.section : UiSpace.sm,
              ),
              if (b.all.isEmpty)
                _box(
                  UiEmpty(
                    icon: LucideIcons.target,
                    title: 'Start your first goal',
                    message: 'A trip, a new laptop, a home down payment.',
                    action: 'Create a goal',
                    onAction: () => context.push(AppRoutes.newGoal),
                  ),
                )
              else ...[
                _box(
                  _Controls(
                    board: b,
                    filter: _filter,
                    count: shown.length,
                    onChanged: _set,
                    onPace: _togglePace,
                    onSort: _pickSort,
                  ),
                  top: UiSpace.section,
                ),
                if (shown.isEmpty)
                  _box(_emptyFor(context))
                else
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: UiSpace.gutter),
                    sliver: SliverList.builder(
                      itemCount: shown.length,
                      itemBuilder: (context, i) {
                        final g = shown[i];
                        return UiColumnWidth(
                          child: UiPanelSlice(
                            first: i == 0,
                            last: i == shown.length - 1,
                            child: GoalRow(
                              key: ValueKey(g.goal.id),
                              progress: g,
                              today: b.today,
                              onLongPress: () => _quickActions(g),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
              SliverToBoxAdapter(child: SizedBox(height: context.bottomClearance)),
            ],
          );
        },
      ),
    );
  }

  Widget _emptyFor(BuildContext context) {
    if (_filter.paces.isNotEmpty || _filter.categories.isNotEmpty) {
      return UiEmpty(
        icon: LucideIcons.searchX,
        title: 'No matches',
        action: 'Clear filters',
        onAction: () => _set(_filter.cleared()),
      );
    }
    return switch (_filter.tab) {
      GoalTab.active => UiEmpty(
        icon: LucideIcons.target,
        title: 'No active goals',
        action: 'Create a goal',
        onAction: () => context.push(AppRoutes.newGoal),
      ),
      GoalTab.completed => const UiEmpty(icon: LucideIcons.trophy, title: 'Nothing completed yet'),
      GoalTab.archived => const UiEmpty(icon: LucideIcons.archive, title: 'No archived goals'),
    };
  }
}

Widget _box(Widget child, {double top = 0}) => SliverPadding(
  padding: EdgeInsets.fromLTRB(UiSpace.gutter, top, UiSpace.gutter, 0),
  sliver: SliverToBoxAdapter(child: UiColumnWidth(child: child)),
);

/// Saved across active goals, how far that is, and the monthly effort the
/// dated goals need against what is planned.
class _Summary extends StatelessWidget {
  const _Summary({required this.board});

  final GoalsBoard board;

  @override
  Widget build(BuildContext context) {
    final c = UiColors.of(context);
    final t = UiType.of(context);
    final b = board;
    final need = b.neededMonthly;
    final plan = b.plannedMonthly;
    final short = need.isPositive && plan < need;
    return UiHero(
      label: 'Saved for goals',
      value: AnimatedAmount(b.saved, style: t.amount, decimals: DecimalDisplay.none, fit: true, animateOnMount: true),
      footer: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          UiProgressFooter(
            value: b.progress,
            color: c.goals,
            start: '${formatPct(b.progress)} saved',
            end: 'of ${savingsMoney(context, b.target)}',
            semanticsLabel: 'Saved across goals',
          ),
          if (need.isPositive || plan.isPositive) ...[
            const SizedBox(height: UiSpace.lg),
            Row(
              children: [
                Expanded(
                  child: UiStat(
                    label: 'Needed a month',
                    value: AmountText(need, style: t.figureSmall, decimals: DecimalDisplay.none),
                  ),
                ),
                const SizedBox(width: UiSpace.md),
                Expanded(
                  child: UiStat(
                    label: 'You plan',
                    value: AmountText(
                      plan,
                      style: t.figureSmall.copyWith(color: short ? c.warning : null),
                      decimals: DecimalDisplay.none,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// The emergency fund as one row: cover, saved, and the way in.
class _EmergencyLine extends ConsumerWidget {
  const _EmergencyLine();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(emergencyStatusProvider).value;
    if (s == null) return const UiPlaceholder(height: 60, radius: UiRadius.panel);
    final c = UiColors.of(context);
    final t = UiType.of(context);
    final configured = s.level != EmergencyFundLevel.notConfigured;
    final coverage = s.coverageMonths;
    final sub = !configured
        ? 'Not set up yet'
        : (coverage != null
              ? '${coverageLabel(coverage)} of ${s.plan!.targetMonths} covered'
              : '${formatPct(s.progress)} of ${savingsMoney(context, s.target)}');
    final urgent = s.level == EmergencyFundLevel.critical;
    return UiPanel(
      key: const ValueKey('goals-emergency-line'),
      child: UiListRow(
        leading: UiMark(icon: LucideIcons.shieldCheck, color: c.emergency),
        title: 'Emergency fund',
        subtitle: sub,
        subtitleColor: urgent ? c.negative : null,
        semanticLabel: configured
            ? 'Emergency fund, ${s.level.label}. ${savingsMoney(context, s.saved)} saved. $sub.'
            : 'Emergency fund not set up. Tap to set it up.',
        trailing: configured
            ? AmountText(s.saved, style: t.figureSmall, decimals: DecimalDisplay.none)
            : Text(
                'Set up',
                style: t.label.copyWith(color: c.ink, fontWeight: FontWeight.w600),
              ),
        onTap: () => context.push(AppRoutes.emergencyFund),
      ),
    );
  }
}

/// Active / Completed / Archived (only when there is history), one chip per
/// pace that needs a look, then "4 goals · Closest to done".
class _Controls extends StatelessWidget {
  const _Controls({
    required this.board,
    required this.filter,
    required this.count,
    required this.onChanged,
    required this.onPace,
    required this.onSort,
  });

  final GoalsBoard board;
  final GoalListFilter filter;
  final int count;
  final ValueChanged<GoalListFilter> onChanged;
  final ValueChanged<GoalPace> onPace;
  final VoidCallback onSort;

  @override
  Widget build(BuildContext context) {
    final c = UiColors.of(context);
    final b = board;
    final counts = b.tabCounts;
    final history = (counts[GoalTab.completed] ?? 0) + (counts[GoalTab.archived] ?? 0) > 0;
    final paces = filter.tab == GoalTab.active
        ? [
            for (final p in const [GoalPace.behind, GoalPace.onTrack, GoalPace.noPlan])
              if (b.count(p) > 0) p,
          ]
        : const <GoalPace>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (history) ...[
          UiSegmented<GoalTab>(
            segments: [
              for (final tab in GoalTab.values)
                if ((counts[tab] ?? 0) > 0 || tab == filter.tab || tab == GoalTab.active)
                  UiSegment(tab, tab.label, count: counts[tab] ?? 0, key: ValueKey('goal-tab:${tab.name}')),
            ],
            selected: filter.tab,
            onChanged: (t) => onChanged(GoalListFilter(tab: t, sort: filter.sort)),
          ),
          const SizedBox(height: UiSpace.sm),
        ],
        if (paces.length > 1)
          Wrap(
            spacing: UiSpace.sm,
            children: [
              for (final p in paces)
                UiChipButton(
                  key: ValueKey('goal-attn:${p.name}'),
                  label: p.countLabel(b.count(p)),
                  color: p == GoalPace.behind ? c.warning : null,
                  selected: filter.paces.length == 1 && filter.paces.contains(p),
                  semanticLabel:
                      '${p.countLabel(b.count(p))}. ${filter.paces.contains(p) ? 'Showing only these' : 'Show only these'}',
                  onTap: () => onPace(p),
                ),
            ],
          ),
        UiSectionTitle(title: count == 1 ? '1 goal' : '$count goals', action: filter.sort.label, onAction: onSort),
      ],
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
            UiPlaceholder(width: 110, height: 12),
            SizedBox(height: UiSpace.md),
            UiPlaceholder(width: 200, height: 40),
            SizedBox(height: UiSpace.xl),
            UiPlaceholder(height: 6),
            SizedBox(height: UiSpace.section),
            UiPlaceholder(height: 60, radius: UiRadius.panel),
            SizedBox(height: UiSpace.section),
            UiPlaceholder(height: 240, radius: UiRadius.panel),
          ],
        ),
      ),
    );
  }
}
