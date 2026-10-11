import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/di/data_providers.dart';
import '../../../app/router/routes.dart';
import '../../../core/money/money_format.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/presentation/action_runner.dart';
import '../../../shared/presentation/async_view.dart';
import '../../alerts/presentation/alert_visuals.dart' show MaybeAnimate;
import '../application/budget_actions.dart';
import '../application/budget_view.dart';
import 'budget_widgets.dart';

/// Budgets tab. Answers "can I keep spending like this?" in one card, then
/// lists every budget as a compact row, most urgent first.
///
/// Top to bottom: month pulse (left to spend, safe per day, one pace bar
/// with a "today" tick and where spending is heading, status shortcuts),
/// a pinned bar of status tabs with counts plus sort & filter, then rows.
class BudgetsScreen extends ConsumerStatefulWidget {
  const BudgetsScreen({super.key});

  @override
  ConsumerState<BudgetsScreen> createState() => _BudgetsScreenState();
}

class _BudgetsScreenState extends ConsumerState<BudgetsScreen> {
  BudgetListFilter _filter = const BudgetListFilter();

  /// Rows that already played their entrance (scrolling back never replays).
  final Set<String> _entered = {};

  void _set(BudgetListFilter f) => setState(() => _filter = f);

  void _toggleState(BudgetState s) => _set(_filter.copyWith(state: () => _filter.state == s ? null : s));

  Future<void> _openOptions() async {
    final next = await showFinnSheet<BudgetListFilter>(context, builder: (_) => _OptionsSheet(initial: _filter));
    if (next != null && mounted) _set(next);
  }

  Future<void> _quickActions(BudgetPace p) async {
    final b = p.usage.budget;
    final name = ref.read(categoryProvider(b.categoryId))?.name ?? 'Budget';
    final choice = await showFinnActionMenu<int>(
      context,
      title: '$name budget',
      items: [
        const FinnMenuItem(value: 0, label: 'Open details', icon: LucideIcons.arrowUpRight),
        const FinnMenuItem(value: 1, label: 'Change limit', icon: LucideIcons.pencil),
        FinnMenuItem(
          value: 2,
          label: b.isPaused ? 'Resume tracking' : 'Pause tracking',
          icon: b.isPaused ? LucideIcons.play : LucideIcons.pause,
        ),
      ],
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 0:
        context.push(AppRoutes.budget(b.id));
      case 1:
        context.push(AppRoutes.editBudget(b.id));
      case 2:
        await runAction(
          context,
          ref,
          action: const SetBudgetPausedAction(),
          input: SetBudgetPausedInput(id: b.id, paused: !b.isPaused),
          idempotencyKey: newIdempotencyKey(),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final pulse = ref.watch(budgetsPulseProvider);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: AsyncView<BudgetsPulse>(
          value: pulse,
          loading: const _BudgetsSkeleton(),
          builder: (context, o) {
            String name(BudgetPace p) => ref.read(categoryProvider(p.usage.budget.categoryId))?.name ?? '';
            final shown = filterBudgets(o.paces, _filter, name);
            return CustomScrollView(
              key: const PageStorageKey('budgets'),
              slivers: [
                _boxed(_Header(pulse: o), top: Space.x4),
                if (o.paces.isEmpty)
                  _boxed(
                    EmptyState(
                      icon: LucideIcons.chartPie,
                      title: 'No budgets yet',
                      message: 'Set a monthly limit for a category like Food or Shopping. '
                          'FiNN tracks spending against it automatically.',
                      actionLabel: 'Create a budget',
                      actionIcon: LucideIcons.plus,
                      onAction: () => context.push(AppRoutes.newBudget),
                    ),
                    top: Space.x6,
                  )
                else ...[
                  if (o.hasTotals)
                    _boxed(
                      StaggeredEntrance(child: _PulseCard(pulse: o, filter: _filter, onState: _toggleState)),
                      top: Space.x3,
                    ),
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: _BarDelegate(
                      child: _Controls(pulse: o, filter: _filter, onState: (s) => _set(_filter.copyWith(state: () => s)), onOptions: _openOptions),
                    ),
                  ),
                  _boxed(_ResultLine(count: shown.length, filter: _filter, onChanged: _set, onSort: _openOptions)),
                  if (shown.isEmpty)
                    _boxed(
                      EmptyState(
                        icon: LucideIcons.searchX,
                        title: 'Nothing here',
                        message: 'No budget matches this view.',
                        actionLabel: 'Show all budgets',
                        onAction: () => _set(const BudgetListFilter()),
                      ),
                      top: Space.x4,
                    )
                  else
                    SliverList.builder(
                      itemCount: shown.length,
                      itemBuilder: (context, i) {
                        final p = shown[i];
                        final id = p.usage.budget.id;
                        final row = BudgetRow(
                          key: ValueKey(id),
                          pace: p,
                          onTap: () => context.push(AppRoutes.budget(id)),
                          onLongPress: () => _quickActions(p),
                        );
                        final first = _entered.add(id);
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
}

Widget _boxed(Widget child, {double top = 0}) => SliverToBoxAdapter(
      child: ResponsiveCenter(padding: EdgeInsets.fromLTRB(Space.gutter, top, Space.gutter, 0), child: child),
    );

class _Header extends StatelessWidget {
  const _Header({required this.pulse});

  final BudgetsPulse pulse;

  @override
  Widget build(BuildContext context) {
    final t = context.text;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(header: true, child: Text('Budgets', style: t.pageTitle)),
              Text('${periodLabel(pulse.period)} · ${daysLeftLabel(pulse.daysLeft)}', style: t.caption),
            ],
          ),
        ),
        FinnButton(
          label: 'New budget',
          icon: LucideIcons.plus,
          size: FinnButtonSize.sm,
          onPressed: () => context.push(AppRoutes.newBudget),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Pulse card
// ---------------------------------------------------------------------------

class _PulseCard extends StatelessWidget {
  const _PulseCard({required this.pulse, required this.filter, required this.onState});

  final BudgetsPulse pulse;
  final BudgetListFilter filter;
  final ValueChanged<BudgetState> onState;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final o = pulse;
    final heading = o.projectedShare;
    final (String verdict, Color tone, IconData icon) = o.isOver
        ? ('Over budget', c.negative, LucideIcons.triangleAlert)
        : heading != null && heading > 1
            ? ('Spending fast', c.warning, LucideIcons.gauge)
            : ('On pace', c.positive, LucideIcons.circleCheck);
    final safe = o.safePerDay;
    final sub = [
      'of ${budgetMoney(context, o.limit)}',
      if (safe != null) '${budgetMoney(context, safe)}/day for ${o.daysLeft} ${o.daysLeft == 1 ? 'day' : 'days'}',
    ].join(' · ');
    final shortcuts = [
      for (final s in [BudgetState.over, BudgetState.risk, BudgetState.onTrack])
        if (o.count(s) > 0) s,
    ];
    return FinnCard(
      radius: Radii.xxl,
      padding: const EdgeInsets.fromLTRB(Space.x4, Space.x4, Space.x4, Space.x3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text('LEFT TO SPEND THIS MONTH', style: t.eyebrow)),
              StatusPill(label: verdict, color: tone, icon: icon),
            ],
          ),
          const SizedBox(height: Space.x1),
          Semantics(
            label: o.isOver
                ? 'Over budget by ${budgetMoney(context, -o.remaining)}'
                : '${budgetMoney(context, o.remaining)} left to spend. $sub',
            excludeSemantics: true,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (o.isOver) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Text('Over by ', style: t.bodyStrong.copyWith(color: c.negative)),
                  ),
                ],
                Flexible(
                  child: AnimatedAmount(
                    o.remaining.abs(),
                    animateOnMount: true,
                    fit: true,
                    style: t.amountLarge.copyWith(color: o.isOver ? c.negative : c.textPrimary),
                  ),
                ),
              ],
            ),
          ),
          Text(sub, style: t.caption),
          const SizedBox(height: Space.x3),
          PaceTrack(
            used: o.used,
            projected: o.projectedShare,
            elapsed: o.elapsed,
            color: o.isOver ? c.negative : c.primary,
            height: 12,
          ),
          const SizedBox(height: Space.x1_5),
          _PulseLegend(pulse: o),
          if (o.committed.isPositive) ...[
            const SizedBox(height: Space.x1),
            Row(
              children: [
                Icon(LucideIcons.repeat, size: 12, color: c.textTertiary),
                const SizedBox(width: Space.x1),
                Expanded(
                  child: Text(
                    '${budgetMoney(context, o.committed)} in subscriptions still to come',
                    style: t.micro,
                  ),
                ),
              ],
            ),
          ],
          if (shortcuts.isNotEmpty) ...[
            const SizedBox(height: Space.x3),
            const FinnDivider(),
            const SizedBox(height: Space.x2_5),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var i = 0; i < shortcuts.length; i++) ...[
                    if (i > 0) const SizedBox(width: Space.x2),
                    FinnTapChip(
                      key: ValueKey('budget-attn:${shortcuts[i].name}'),
                      label: shortcuts[i].countLabel(o.count(shortcuts[i])),
                      icon: shortcuts[i].icon,
                      color: shortcuts[i].color(c),
                      selected: filter.state == shortcuts[i],
                      height: 32,
                      semantics: '${shortcuts[i].countLabel(o.count(shortcuts[i]))}. '
                          '${filter.state == shortcuts[i] ? 'Showing only these' : 'Show only these'}',
                      onTap: () => onState(shortcuts[i]),
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

/// Key for the pace bar: spent, where it is heading, and the today tick.
class _PulseLegend extends StatelessWidget {
  const _PulseLegend({required this.pulse});

  final BudgetsPulse pulse;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final o = pulse;
    final projected = o.projected;
    Widget swatch(Color color, {bool hatched = false}) => Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: hatched ? color.withValues(alpha: 0.25) : color,
            borderRadius: Radii.rSm,
            border: hatched ? Border.all(color: color, width: 1.2) : null,
          ),
        );
    final over = projected != null && projected > o.limit;
    return Wrap(
      spacing: Space.x3,
      runSpacing: Space.x1,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          swatch(o.isOver ? c.negative : c.primary),
          const SizedBox(width: Space.x1),
          Text('Spent ${budgetMoney(context, o.spent)}', style: t.micro.copyWith(color: c.textPrimary)),
        ]),
        if (projected != null && !o.isOver)
          Row(mainAxisSize: MainAxisSize.min, children: [
            swatch(over ? c.negative : c.primary, hatched: true),
            const SizedBox(width: Space.x1),
            Text(
              'Heading for ${budgetMoney(context, projected)}',
              style: t.micro.copyWith(color: over ? c.negative : c.textSecondary, fontWeight: FontWeight.w700),
            ),
          ]),
        Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 2, height: 10, color: c.textPrimary),
          const SizedBox(width: Space.x1),
          Text('Today · ${formatBps((o.elapsed * 10000).round(), decimals: 0)} of month', style: t.micro),
        ]),
      ],
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
  const _Controls({required this.pulse, required this.filter, required this.onState, required this.onOptions});

  final BudgetsPulse pulse;
  final BudgetListFilter filter;
  final ValueChanged<BudgetState?> onState;
  final VoidCallback onOptions;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final counts = pulse.counts;
    final tabs = <(BudgetState?, String, int)>[
      (null, 'All', pulse.paces.length),
      for (final s in BudgetState.values)
        if ((counts[s] ?? 0) > 0 || filter.state == s) (s, s.label, counts[s] ?? 0),
    ];
    return Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < tabs.length; i++) ...[
                  if (i > 0) const SizedBox(width: Space.x1_5),
                  _TabChip(
                    key: ValueKey('budget-tab:${tabs[i].$1?.name ?? 'all'}'),
                    label: tabs[i].$2,
                    count: tabs[i].$3,
                    color: tabs[i].$1?.color(c),
                    selected: filter.state == tabs[i].$1,
                    onTap: () => onState(tabs[i].$1),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(width: Space.x1),
        CountBadge(
          count: filter.optionCount,
          color: c.primary,
          semanticsLabel: '${filter.optionCount} options changed',
          child: FinnIconButton(
            key: const ValueKey('budget-options'),
            icon: LucideIcons.slidersHorizontal,
            tooltip: 'Sort & filter',
            variant: filter.optionCount > 0 ? FinnIconButtonVariant.filled : FinnIconButtonVariant.ghost,
            onPressed: onOptions,
          ),
        ),
      ],
    );
  }
}

/// Tab-like chip: label + count, tinted dot for the status colour.
class _TabChip extends StatelessWidget {
  const _TabChip({
    super.key,
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
    this.color,
  });

  final String label;
  final int count;
  final Color? color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    return Semantics(
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      label: '$label, $count',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: selected ? null : onTap,
        child: AnimatedContainer(
          duration: context.motion.normal,
          curve: Curves2.emphasized,
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: Space.x3),
          decoration: BoxDecoration(
            color: selected ? c.textPrimary : c.surfaceMuted,
            borderRadius: Radii.rFull,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (color != null) ...[
                Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                const SizedBox(width: Space.x1_5),
              ],
              Text(
                label,
                style: t.label.copyWith(
                  color: selected ? c.onSolid : c.textSecondary,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
              const SizedBox(width: Space.x1),
              Text(
                '$count',
                style: t.label.copyWith(
                  color: selected ? c.onSolid.withValues(alpha: 0.7) : c.textTertiary,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResultLine extends StatelessWidget {
  const _ResultLine({required this.count, required this.filter, required this.onChanged, required this.onSort});

  final int count;
  final BudgetListFilter filter;
  final ValueChanged<BudgetListFilter> onChanged;
  final VoidCallback onSort;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final f = filter;
    return SizedBox(
      height: 36,
      child: Row(
        children: [
          Text('$count ${count == 1 ? 'BUDGET' : 'BUDGETS'}', style: t.eyebrow),
          const SizedBox(width: Space.x2),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true,
              child: Row(
                children: [
                  if (f.period != BudgetPeriodFilter.all) ...[
                    FinnTapChip(
                      label: f.period.label,
                      trailing: LucideIcons.x,
                      color: c.primary,
                      height: 28,
                      semantics: 'Remove filter ${f.period.label}',
                      onTap: () => onChanged(f.copyWith(period: BudgetPeriodFilter.all)),
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

  final BudgetListFilter initial;

  @override
  State<_OptionsSheet> createState() => _OptionsSheetState();
}

class _OptionsSheetState extends State<_OptionsSheet> {
  late BudgetListFilter _f = widget.initial;

  @override
  Widget build(BuildContext context) {
    final t = context.text;
    return FinnSheetScaffold(
      title: 'Sort & filter',
      footer: Row(
        children: [
          Expanded(
            child: FinnButton(
              label: 'Reset',
              variant: FinnButtonVariant.outline,
              expand: true,
              onPressed: () => setState(() => _f = BudgetListFilter(state: _f.state)),
            ),
          ),
          const SizedBox(width: Space.x3),
          Expanded(
            child: FinnButton(
              key: const ValueKey('budget-apply'),
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
          Text('SORT BY', style: t.eyebrow),
          const SizedBox(height: Space.x2),
          Wrap(
            spacing: Space.x2,
            runSpacing: Space.x2,
            children: [
              for (final s in BudgetSort.values)
                FinnTapChip(
                  key: ValueKey('budget-sort:${s.name}'),
                  label: s.label,
                  selected: _f.sort == s,
                  height: 36,
                  color: context.colors.primary,
                  onTap: () => setState(() => _f = _f.copyWith(sort: s)),
                ),
            ],
          ),
          const SizedBox(height: Space.x5),
          Text('PERIOD', style: t.eyebrow),
          const SizedBox(height: Space.x2),
          SegmentedTabs<BudgetPeriodFilter>(
            items: [for (final p in BudgetPeriodFilter.values) SegmentItem(p, p.label)],
            selected: _f.period,
            onChanged: (p) => setState(() => _f = _f.copyWith(period: p)),
          ),
        ],
      ),
    );
  }
}

class _BudgetsSkeleton extends StatelessWidget {
  const _BudgetsSkeleton();

  @override
  Widget build(BuildContext context) => const SkeletonPulse(
        child: ResponsiveCenter(
          padding: EdgeInsets.symmetric(horizontal: Space.gutter),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: Space.x4),
              SkeletonBox(width: 140, height: 28),
              SizedBox(height: Space.x4),
              CardSkeleton(height: 190, radius: Radii.xxl),
              SizedBox(height: Space.x3),
              SkeletonBox(height: 36, radius: Radii.full),
              SizedBox(height: Space.x4),
              CardSkeleton(height: 72),
              SizedBox(height: Space.x2),
              CardSkeleton(height: 72),
              SizedBox(height: Space.x2),
              CardSkeleton(height: 72),
            ],
          ),
        ),
      );
}
