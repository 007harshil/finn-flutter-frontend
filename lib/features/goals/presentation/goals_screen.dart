import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/di/data_providers.dart';
import '../../../app/router/routes.dart';
import '../../../core/money/money_format.dart';
import '../../../kit/kit.dart';
import '../../../shared/presentation/async_view.dart';
import '../../emergency_fund/domain/emergency_fund.dart';
import '../application/goal_view.dart';
import '../domain/goal.dart';
import 'goal_parts.dart';

/// Every goal in one place: what is saved across active goals, then the
/// goals by tab (with status filters and sort), then the emergency fund as
/// the one safety-net line.
class GoalsScreen extends ConsumerStatefulWidget {
  const GoalsScreen({super.key});

  @override
  ConsumerState<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends ConsumerState<GoalsScreen> {
  GoalListFilter _filter = const GoalListFilter();

  void _set(GoalListFilter f) => setState(() => _filter = f);

  void _togglePace(GoalPace p) {
    final only = _filter.paces.length == 1 && _filter.paces.contains(p);
    _set(_filter.copyWith(tab: GoalTab.active, paces: only ? const {} : {p}));
  }

  // Status filters only exist on the Active tab, so a tab change drops them.
  void _tab(GoalTab t) => _set(GoalListFilter(tab: t, sort: _filter.sort));

  Future<void> _sort() async {
    final current = _filter.sort;
    final next = await showFinnActionMenu<GoalSort>(
      context,
      title: 'Sort goals',
      items: [
        for (final s in GoalSort.values)
          FinnMenuItem(value: s, label: s.label, icon: s == current ? LucideIcons.circleCheck : LucideIcons.circle),
      ],
    );
    if (next != null && mounted) _set(_filter.copyWith(sort: next));
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
    final header = PageHeader(
      title: 'Goals',
      actions: [
        LedgerButton(
          label: 'New goal',
          icon: LucideIcons.plus,
          small: true,
          onPressed: () => context.push(AppRoutes.newGoal),
        ),
      ],
    );
    return AsyncView<GoalsBoard>(
      value: ref.watch(goalsBoardProvider),
      loading: Scaffold(backgroundColor: context.ink.paper, body: const SafeArea(child: LedgerPageSkeleton())),
      builder: (context, b) {
        final shown = filterGoals(b.all, _filter);
        return LedgerPage(
          storageKey: 'goals',
          slivers: [
            PageBlock(child: header),
            if (b.active.isNotEmpty) PageBlock(top: Sp.xxl, child: _Hero(board: b)),
            if (b.all.isEmpty)
              PageBlock(
                top: Sp.xl,
                child: LedgerEmpty(
                  title: 'Start your first goal',
                  message: 'A trip, a laptop, a home down payment. Give it a name and a target, '
                      'and set money aside at your own pace.',
                  actionLabel: 'Create a goal',
                  onAction: () => context.push(AppRoutes.newGoal),
                ),
              )
            else ...[
              PageBlock(
                top: b.active.isNotEmpty ? Sp.section : Sp.xl,
                child: _Controls(
                  board: b,
                  filter: _filter,
                  onTab: _tab,
                  onPace: _togglePace,
                  onSort: _sort,
                  showSort: shown.length > 1,
                ),
              ),
              PageBlock(
                top: Sp.md,
                child: shown.isEmpty
                    ? _emptyFor(context)
                    : LedgerPanel(
                        dividerIndent: Sp.lg + 40 + Sp.md + 2,
                        children: [
                          for (final g in shown)
                            GoalListRow(
                              key: ValueKey(g.goal.id),
                              progress: g,
                              today: b.today,
                              onLongPress: () => _quickActions(g),
                            ),
                        ],
                      ),
              ),
            ],
            const PageBlock(top: Sp.section, child: _SafetyNet()),
          ],
        );
      },
    );
  }

  Widget _emptyFor(BuildContext context) {
    if (_filter.paces.isNotEmpty) {
      return LedgerEmpty(
        title: 'No matches',
        message: 'No active goal has this status right now.',
        actionLabel: 'Show all',
        onAction: () => _set(_filter.cleared()),
      );
    }
    return switch (_filter.tab) {
      GoalTab.active => LedgerEmpty(
        title: 'No active goals',
        message: 'Every goal is done or archived. Start a new one when you are ready.',
        actionLabel: 'Create a goal',
        onAction: () => context.push(AppRoutes.newGoal),
      ),
      GoalTab.completed => const LedgerEmpty(
        title: 'Nothing completed yet',
        message: 'Goals you fully fund will appear here.',
      ),
      GoalTab.archived => const LedgerEmpty(
        title: 'No archived goals',
        message: 'Archive a goal to hide it without losing its history.',
      ),
    };
  }
}

/// Saved across active goals against their targets, and whether the
/// monthly amounts going in keep dated goals on time.
class _Hero extends StatelessWidget {
  const _Hero({required this.board});

  final GoalsBoard board;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final t = context.type;
    final b = board;
    final need = b.neededMonthly;
    final plan = b.plannedMonthly;
    final short = need.isPositive && plan < need;
    final sentence = !need.isPositive
        ? null
        : '${goalMoney(context, need)} a month keeps every dated goal on time. '
            '${plan.isPositive ? 'You put in about ${goalMoney(context, plan)}.' : 'No monthly amounts are planned yet.'}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Saved for goals', style: t.label),
        const SizedBox(height: Sp.xs),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Flexible(
              child: AnimatedAmount(
                b.saved,
                style: t.figureXL,
                decimals: DecimalDisplay.none,
                fit: true,
                animateOnMount: true,
              ),
            ),
            const SizedBox(width: Sp.sm),
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Text('of ${goalMoney(context, b.target)}', style: t.figureSmall),
            ),
          ],
        ),
        const SizedBox(height: Sp.lg),
        LedgerBar(
          value: b.progress,
          semanticLabel: AmountVisibility.hiddenOf(context) ? null : '${goalPercent(b.progress)} of all targets saved',
        ),
        if (sentence != null) ...[
          const SizedBox(height: Sp.md),
          Text(sentence, style: t.label.copyWith(color: short ? c.amber : null)),
        ],
      ],
    );
  }
}

/// Tabs, then (on Active) status filters and sort.
class _Controls extends StatelessWidget {
  const _Controls({
    required this.board,
    required this.filter,
    required this.onTab,
    required this.onPace,
    required this.onSort,
    required this.showSort,
  });

  final GoalsBoard board;
  final GoalListFilter filter;
  final ValueChanged<GoalTab> onTab;
  final ValueChanged<GoalPace> onPace;
  final VoidCallback onSort;
  final bool showSort;

  @override
  Widget build(BuildContext context) {
    final counts = board.tabCounts;
    final paces = filter.tab != GoalTab.active
        ? const <GoalPace>[]
        : [
            for (final p in const [GoalPace.behind, GoalPace.onTrack, GoalPace.noPlan])
              if (board.count(p) > 0 || filter.paces.contains(p)) p,
          ];
    final sorted = filter.sort != GoalSort.closest;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LedgerSegmented<GoalTab>(
          selected: filter.tab,
          onChanged: onTab,
          segments: [
            for (final tab in GoalTab.values)
              LedgerSegment(tab, tab.label, count: counts[tab] ?? 0, key: ValueKey('goal-tab:${tab.name}')),
          ],
        ),
        if (paces.isNotEmpty || showSort || sorted) ...[
          const SizedBox(height: Sp.md),
          Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (var i = 0; i < paces.length; i++) ...[
                        if (i > 0) const SizedBox(width: Sp.sm),
                        LedgerChip(
                          key: ValueKey('goal-attn:${paces[i].name}'),
                          label: paces[i].label,
                          count: board.count(paces[i]),
                          selected: filter.paces.contains(paces[i]),
                          semanticLabel: '${paces[i].label}, ${board.count(paces[i])} goals',
                          onTap: () => onPace(paces[i]),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (showSort || sorted)
                Transform.translate(
                  offset: const Offset(6, 0),
                  child: LedgerIconButton(
                    key: const ValueKey('goal-sort'),
                    icon: LucideIcons.arrowDownUp,
                    tooltip: 'Sort goals, ${filter.sort.label.toLowerCase()}',
                    selected: sorted,
                    onPressed: onSort,
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// One goal: category mark, name, how much is left and by when (amber when
/// behind), saved amount and share, a bar with a tick where a dated goal
/// should be by now, and "+" to add money to an active goal.
class GoalListRow extends StatelessWidget {
  const GoalListRow({super.key, required this.progress, required this.today, this.onLongPress});

  final GoalProgress progress;
  final DateTime today;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final t = context.type;
    final g = progress;
    final pace = goalPaceOf(g);
    final archived = g.goal.status == GoalStatus.archived;
    final active = !archived && !g.isAchieved;
    final expected = active ? expectedShare(g, today) : null;
    final date = g.goal.targetDate;
    final behind = active && pace == GoalPace.behind && g.requiredMonthly != null;
    final String sub;
    if (g.isAchieved) {
      sub = 'Target reached';
    } else if (behind) {
      sub = 'Behind, needs ${goalMoney(context, g.requiredMonthly!)} a month';
    } else {
      sub = '${goalMoney(context, g.remaining)} to go${date == null ? '' : ', by ${goalMonth.format(date)}'}';
    }
    final hidden = AmountVisibility.hiddenOf(context);
    final soft = archived ? c.inkSoft : null;
    // Two lines that each pair text with a figure, so the subtitle gets the
    // full width instead of sharing it with the amount column.
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(
              child: Text(
                g.goal.name,
                style: t.body.copyWith(
                  fontWeight: FontWeight.w500,
                  fontVariations: const [FontVariation.weight(540)],
                  color: soft,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: Sp.md),
            AmountText(g.saved, style: t.figure.copyWith(color: soft), decimals: DecimalDisplay.none),
          ],
        ),
        const SizedBox(height: 2),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(
              child: Text(
                sub,
                style: t.label.copyWith(color: behind ? c.amber : null),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: Sp.sm),
            Text(goalPercent(g.progress), style: t.small),
          ],
        ),
      ],
    );
    return Semantics(
      container: true,
      button: true,
      label: '${g.goal.name}. '
          '${hidden ? '' : '${AmountText.spokenLabel(g.saved)} saved of ${AmountText.spokenLabel(g.goal.target)}, '}'
          '${goalPercent(g.progress)}. $sub.',
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
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 60),
          child: Padding(
            padding: EdgeInsets.fromLTRB(Sp.lg, Sp.md + 2, active ? Sp.xs : Sp.lg, Sp.md + 2),
            child: Row(
              children: [
                Expanded(
                  child: ExcludeSemantics(
                    child: Row(
                      children: [
                        GoalMark(category: g.goal.category, dimmed: archived),
                        const SizedBox(width: Sp.md + 2),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              body,
                              const SizedBox(height: Sp.sm + 2),
                              LedgerBar(value: g.progress, marker: expected, color: archived ? c.inkSoft : null),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (active) ...[
                  const SizedBox(width: Sp.xs),
                  LedgerIconButton(
                    key: ValueKey('goal-add:${g.goal.id}'),
                    icon: LucideIcons.plus,
                    tooltip: 'Add money to ${g.goal.name}',
                    onPressed: () => context.push(AppRoutes.goalContribute(g.goal.id)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The emergency fund as one row: months covered and a bar coloured by
/// its level.
class _SafetyNet extends ConsumerWidget {
  const _SafetyNet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(emergencyStatusProvider).value;
    return LedgerSection(
      title: 'Safety net',
      child: s == null ? const LedgerSkeleton(height: 84, radius: Rad.lg) : _EmergencyRow(status: s),
    );
  }
}

class _EmergencyRow extends StatelessWidget {
  const _EmergencyRow({required this.status});

  final EmergencyFundStatus status;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final t = context.type;
    final s = status;
    final configured = s.level != EmergencyFundLevel.notConfigured && s.plan != null;
    final coverage = s.coverageMonths;
    final String sub;
    if (!configured) {
      sub = 'Not set up yet';
    } else if (coverage != null) {
      final months = s.plan!.targetMonths;
      sub = '${_tenths(coverage)} of $months ${months == 1 ? 'month' : 'months'} covered';
    } else {
      sub = '${goalPercent(s.progress)} of target saved';
    }
    final color = switch (s.level) {
      EmergencyFundLevel.critical => c.red,
      EmergencyFundLevel.building => c.amber,
      EmergencyFundLevel.funded => c.green,
      EmergencyFundLevel.notConfigured => null,
    };
    final hidden = AmountVisibility.hiddenOf(context);
    return LedgerPanel(
      children: [
        LedgerRow(
          key: const ValueKey('goals-emergency-line'),
          leading: const IconWell(icon: LucideIcons.shield),
          title: 'Emergency fund',
          subtitle: sub,
          trailing: configured || s.saved.isPositive
              ? AmountText(s.saved, style: t.figure, decimals: DecimalDisplay.none)
              : null,
          below: configured ? LedgerBar(value: s.progress, color: color) : null,
          semanticLabel: configured
              ? 'Emergency fund, ${s.level.label}. '
                  '${hidden ? '' : '${AmountText.spokenLabel(s.saved)} saved. '}$sub.'
              : 'Emergency fund, not set up yet. Opens setup.',
          onTap: () => context.push(AppRoutes.emergencyFund),
        ),
      ],
    );
  }

  static String _tenths(double v) => v.toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '');
}
