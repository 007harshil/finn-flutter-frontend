import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/di/data_providers.dart';
import '../../../app/router/routes.dart';
import '../../../app/shell/app_drawer.dart';
import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/time/dates.dart';
import '../../../design_system/design_system.dart'
    show AnimatedAmount, BottomClearanceX, FinnMenuItem, showFinnActionMenu;
import '../../../shared/presentation/action_runner.dart';
import '../../../shared/presentation/async_view.dart';
import '../../../ui/ui.dart';
import '../application/budget_actions.dart';
import '../application/budget_view.dart';
import 'budget_widgets.dart';

/// Budgets: what is left to spend this month across every limit, then each
/// budget most urgent first. Arrows step back through past months, which
/// are read-only.
class BudgetsScreen extends ConsumerStatefulWidget {
  const BudgetsScreen({super.key});

  @override
  ConsumerState<BudgetsScreen> createState() => _BudgetsScreenState();
}

class _BudgetsScreenState extends ConsumerState<BudgetsScreen> {
  BudgetListFilter _filter = const BudgetListFilter();

  /// Month on screen; null = this month.
  MonthKey? _month;

  void _setMonth(MonthKey m, MonthKey current) => setState(() {
    _month = m >= current ? null : m;
    _filter = _filter.copyWith(state: () => null);
  });

  Future<void> _pickSort() async {
    final picked = await showFinnActionMenu<BudgetSort>(
      context,
      title: 'Sort by',
      items: [
        for (final s in BudgetSort.values)
          FinnMenuItem(value: s, label: s.label, icon: s == _filter.sort ? LucideIcons.check : LucideIcons.arrowDownUp),
      ],
    );
    if (picked != null && mounted) setState(() => _filter = _filter.copyWith(sort: picked));
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
    final value = ref.watch(budgetsPulseProvider(_month));
    final past = value.value?.isPast ?? false;
    return UiPage(
      leading: const AppMenuButton(),
      title: 'Budgets',
      actions: [
        if (!past)
          UiIconButton(
            icon: LucideIcons.plus,
            tooltip: 'New budget',
            onPressed: () => context.push(AppRoutes.newBudget),
          ),
      ],
      body: AsyncView<BudgetsPulse>(
        value: value,
        loading: const _Placeholder(),
        builder: (context, o) {
          final shown = filterBudgets(
            o.paces,
            _filter,
            (p) => ref.read(categoryProvider(p.usage.budget.categoryId))?.name ?? '',
          );
          return CustomScrollView(
            key: const PageStorageKey('budgets'),
            slivers: [
              _box(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _MonthBar(pulse: o, onMonth: (m) => _setMonth(m, o.currentMonth)),
                    if (o.paces.isNotEmpty && o.hasTotals) ...[
                      const SizedBox(height: UiSpace.lg),
                      UiReveal(index: 0, child: _Summary(pulse: o)),
                    ],
                  ],
                ),
              ),
              if (o.paces.isEmpty)
                _box(
                  o.isPast
                      ? const UiEmpty(
                          icon: LucideIcons.calendarX,
                          title: 'No budgets this month',
                          message: 'None of your budgets existed yet.',
                        )
                      : UiEmpty(
                          icon: LucideIcons.chartPie,
                          title: 'No budgets yet',
                          message: 'Set a monthly limit for a category like Food or Shopping.',
                          action: 'Create a budget',
                          onAction: () => context.push(AppRoutes.newBudget),
                        ),
                )
              else ...[
                _box(
                  _Controls(
                    pulse: o,
                    filter: _filter,
                    count: shown.length,
                    onState: (s) => setState(() => _filter = _filter.copyWith(state: () => s)),
                    onSort: _pickSort,
                  ),
                  top: UiSpace.xl,
                ),
                if (shown.isEmpty)
                  _box(
                    UiEmpty(
                      icon: LucideIcons.searchX,
                      title: 'Nothing here',
                      action: 'Show all budgets',
                      onAction: () => setState(() => _filter = const BudgetListFilter()),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: UiSpace.gutter),
                    sliver: SliverList.builder(
                      itemCount: shown.length,
                      itemBuilder: (context, i) {
                        final p = shown[i];
                        final id = p.usage.budget.id;
                        return UiColumnWidth(
                          child: UiPanelSlice(
                            first: i == 0,
                            last: i == shown.length - 1,
                            child: BudgetRow(
                              key: ValueKey(id),
                              pace: p,
                              past: o.isPast,
                              onTap: () => context.push(AppRoutes.budget(id, month: o.isPast ? o.month : null)),
                              onLongPress: o.isPast ? null : () => _quickActions(p),
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
}

Widget _box(Widget child, {double top = 0}) => SliverPadding(
  padding: EdgeInsets.fromLTRB(UiSpace.gutter, top, UiSpace.gutter, 0),
  sliver: SliverToBoxAdapter(child: UiColumnWidth(child: child)),
);

/// "‹ October 2026 ›" (swipe works too); a past month says it is read-only
/// and offers the way back.
class _MonthBar extends StatelessWidget {
  const _MonthBar({required this.pulse, required this.onMonth});

  final BudgetsPulse pulse;
  final ValueChanged<MonthKey> onMonth;

  @override
  Widget build(BuildContext context) {
    final o = pulse;
    final canPrev = o.month > o.firstMonth;
    final canNext = o.month < o.currentMonth;
    void go(MonthKey m) {
      HapticFeedback.selectionClick();
      onMonth(m);
    }

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragEnd: (d) {
        final v = d.primaryVelocity ?? 0;
        if (v > 200 && canPrev) go(o.month.previous);
        if (v < -200 && canNext) go(o.month.next);
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          UiPeriodStepper(
            label: DateFormats.monthYear.format(o.month.start),
            onPrevious: canPrev ? () => go(o.month.previous) : null,
            onNext: canNext ? () => go(o.month.next) : null,
            trailing: o.isPast
                ? UiChipButton(
                    key: const ValueKey('budget-this-month'),
                    label: 'This month',
                    onTap: () => onMonth(o.currentMonth),
                  )
                : null,
          ),
          if (o.isPast) UiNotice(icon: LucideIcons.lock, text: 'Read-only · ${periodLabel(o.period)}'),
        ],
      ),
    );
  }
}

/// What is left across every active budget, how fast it is going and how
/// much of the month is gone.
class _Summary extends StatelessWidget {
  const _Summary({required this.pulse});

  final BudgetsPulse pulse;

  @override
  Widget build(BuildContext context) {
    final c = UiColors.of(context);
    final t = UiType.of(context);
    final o = pulse;
    String m(Money x) => budgetMoney(context, x);
    final fast = !o.isPast && !o.isOver && (o.projectedShare ?? 0) > 1;
    final color = o.isOver ? c.negative : (fast ? c.warning : null);
    final safe = o.safePerDay;
    final caption = switch (o) {
      _ when o.isPast => 'Spent ${m(o.spent)}',
      _ when o.isOver => daysLeftLabel(o.daysLeft),
      _ when fast => 'Heading for ${m(o.projected!)} at this pace',
      _ when safe != null => '${m(safe)}/day for ${o.daysLeft == 1 ? '1 day' : '${o.daysLeft} days'}',
      _ => daysLeftLabel(o.daysLeft),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        UiHero(
          label: switch (o) {
            _ when o.isOver => o.isPast ? 'Went over by' : 'Over budget by',
            _ => o.isPast ? 'Left unspent' : 'Left to spend',
          },
          value: AnimatedAmount(
            o.remaining.abs(),
            style: t.amount.copyWith(color: o.isOver ? c.negative : null),
            decimals: DecimalDisplay.none,
            fit: true,
            animateOnMount: true,
          ),
          caption: caption,
          captionColor: color,
          footer: UiProgressFooter(
            value: o.used,
            color: color ?? c.ink,
            start: '${(o.used * 100).round()}% used',
            end: 'of ${m(o.limit)}',
            semanticsLabel: 'Limit used',
          ),
        ),
        if (o.committed.isPositive && !o.isPast)
          Padding(
            padding: const EdgeInsets.only(top: UiSpace.sm),
            child: UiNotice(icon: LucideIcons.repeat, text: '${m(o.committed)} in subscriptions still to come'),
          ),
      ],
    );
  }
}

/// One chip per status present (tap to show only those, again to show
/// all), then "6 budgets · Most urgent".
class _Controls extends StatelessWidget {
  const _Controls({
    required this.pulse,
    required this.filter,
    required this.count,
    required this.onState,
    required this.onSort,
  });

  final BudgetsPulse pulse;
  final BudgetListFilter filter;
  final int count;
  final ValueChanged<BudgetState?> onState;
  final VoidCallback onSort;

  @override
  Widget build(BuildContext context) {
    final c = UiColors.of(context);
    final o = pulse;
    final states = [
      for (final s in BudgetState.values)
        if (o.count(s) > 0) s,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (states.length > 1)
          Wrap(
            spacing: UiSpace.sm,
            children: [
              for (final s in states)
                UiChipButton(
                  key: ValueKey('budget-tab:${s.name}'),
                  label: s.countLabel(o.count(s), past: o.isPast),
                  color: s == BudgetState.onTrack || s == BudgetState.paused ? null : s.color(c),
                  selected: filter.state == s,
                  semanticLabel:
                      '${s.countLabel(o.count(s), past: o.isPast)}. ${filter.state == s ? 'Showing only these' : 'Show only these'}',
                  onTap: () => onState(filter.state == s ? null : s),
                ),
            ],
          ),
        UiSectionTitle(
          title: count == 1 ? '1 budget' : '$count budgets',
          action: filter.sort.label,
          onAction: onSort,
        ),
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
            UiPlaceholder(width: 150, height: 20),
            SizedBox(height: UiSpace.xl),
            UiPlaceholder(width: 110, height: 12),
            SizedBox(height: UiSpace.md),
            UiPlaceholder(width: 200, height: 40),
            SizedBox(height: UiSpace.xl),
            UiPlaceholder(height: 6),
            SizedBox(height: UiSpace.section),
            UiPlaceholder(height: 280, radius: UiRadius.panel),
          ],
        ),
      ),
    );
  }
}
