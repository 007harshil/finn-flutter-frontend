import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/di/data_providers.dart';
import '../../../app/router/routes.dart';
import '../../../core/money/money_format.dart';
import '../../../core/time/dates.dart';
import '../../../kit/kit.dart';
import '../../../shared/presentation/action_runner.dart';
import '../../../shared/presentation/async_view.dart';
import '../application/budget_actions.dart';
import '../application/budget_view.dart';
import 'budget_widgets.dart';

/// Budgets tab. Answers "how much can I still spend this month?" with one
/// number set on the page, then lists every budget in one panel, most
/// urgent first. Earlier months can be stepped back to and read, not changed.
class BudgetsScreen extends ConsumerStatefulWidget {
  const BudgetsScreen({super.key});

  @override
  ConsumerState<BudgetsScreen> createState() => _BudgetsScreenState();
}

class _BudgetsScreenState extends ConsumerState<BudgetsScreen> {
  BudgetListFilter _filter = const BudgetListFilter();

  /// Budget month shown; null = this month. Past months are read-only.
  MonthKey? _month;

  void _set(BudgetListFilter f) => setState(() => _filter = f);

  void _setMonth(MonthKey m, MonthKey current) => setState(() {
        _month = m >= current ? null : m;
        _filter = _filter.copyWith(state: () => null);
      });

  Future<void> _chooseSort() async {
    final next = await showFinnActionMenu<BudgetSort>(
      context,
      title: 'Sort budgets',
      items: [
        for (final s in BudgetSort.values)
          FinnMenuItem(
            value: s,
            label: s.label,
            icon: _filter.sort == s ? LucideIcons.circleDot : LucideIcons.circle,
          ),
      ],
    );
    if (next != null && mounted) _set(_filter.copyWith(sort: next));
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
    return AsyncView<BudgetsPulse>(
      value: ref.watch(budgetsPulseProvider(_month)),
      loading: Scaffold(backgroundColor: context.ink.paper, body: const SafeArea(child: LedgerPageSkeleton())),
      builder: (context, o) {
        String name(BudgetPace p) => ref.read(categoryProvider(p.usage.budget.categoryId))?.name ?? '';
        final shown = filterBudgets(o.paces, _filter, name);
        void onMonth(MonthKey m) => _setMonth(m, o.currentMonth);
        return LedgerPage(
          storageKey: 'budgets',
          slivers: [
            PageBlock(
              child: PageHeader(
                title: 'Budgets',
                actions: [
                  if (o.isPast)
                    LedgerButton(
                      key: const ValueKey('budget-this-month'),
                      label: 'This month',
                      variant: LedgerButtonVariant.secondary,
                      small: true,
                      onPressed: () => onMonth(o.currentMonth),
                    )
                  else if (o.paces.isNotEmpty)
                    LedgerButton(
                      label: 'New budget',
                      icon: LucideIcons.plus,
                      small: true,
                      onPressed: () => context.push(AppRoutes.newBudget),
                    ),
                ],
              ),
            ),
            PageBlock(
              top: Sp.lg,
              child: MonthStepper(
                month: o.month,
                min: o.firstMonth,
                max: o.currentMonth,
                trailing: o.isPast ? 'Read-only' : daysLeftLabel(o.daysLeft),
                onChanged: onMonth,
              ),
            ),
            if (o.paces.isEmpty)
              PageBlock(
                top: Sp.xl,
                child: o.isPast
                    ? const LedgerEmpty(
                        title: 'No budgets this month',
                        message: 'None of your budgets existed yet in this month.',
                      )
                    : LedgerEmpty(
                        icon: LucideIcons.chartPie,
                        title: 'No budgets yet',
                        message: 'Set a monthly limit for a category like Food or Shopping. '
                            'Every expense in that category counts towards it automatically.',
                        actionLabel: 'Create a budget',
                        onAction: () => context.push(AppRoutes.newBudget),
                      ),
              )
            else ...[
              if (o.hasTotals) PageBlock(top: Sp.xl, child: _MonthHero(pulse: o)),
              PageBlock(
                top: Sp.section,
                child: _FilterBar(
                  pulse: o,
                  filter: _filter,
                  onState: (s) => _set(_filter.copyWith(state: () => s)),
                  onSort: _chooseSort,
                ),
              ),
              PageBlock(
                top: Sp.md,
                child: shown.isEmpty
                    ? LedgerEmpty(
                        title: 'Nothing here',
                        message: 'No budget matches this view.',
                        actionLabel: 'Show all budgets',
                        onAction: () => _set(const BudgetListFilter()),
                      )
                    : LedgerPanel(
                        children: [
                          for (final p in shown)
                            BudgetRow(
                              key: ValueKey(p.usage.budget.id),
                              pace: p,
                              past: o.isPast,
                              onTap: () => context.push(
                                AppRoutes.budget(p.usage.budget.id, month: o.isPast ? o.month : null),
                              ),
                              onLongPress: o.isPast ? null : () => _quickActions(p),
                            ),
                        ],
                      ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// What is left across all active budgets, how fast it may go, and a bar
/// with a tick for how far through the month today is.
class _MonthHero extends StatelessWidget {
  const _MonthHero({required this.pulse});

  final BudgetsPulse pulse;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final t = context.type;
    final o = pulse;
    final hidden = AmountVisibility.hiddenOf(context);
    final over = o.isOver;
    final safe = o.safePerDay;
    final days = o.daysLeft;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          over ? 'Over by' : (o.isPast ? 'Left unspent' : 'Left to spend'),
          style: t.label.copyWith(color: over ? c.red : null),
        ),
        const SizedBox(height: Sp.xs),
        AnimatedAmount(
          o.remaining.abs(),
          style: t.figureXL.copyWith(color: over && !hidden ? c.red : c.ink),
          decimals: DecimalDisplay.none,
          fit: true,
          animateOnMount: true,
        ),
        const SizedBox(height: Sp.xs),
        Text('of ${budgetMoney(context, o.limit)}', style: t.label),
        const SizedBox(height: Sp.lg),
        LedgerBar(
          key: ValueKey(o.month),
          value: o.used,
          marker: o.isPast ? null : o.elapsed,
          semanticLabel: hidden ? null : '${(o.used * 100).round()} percent of the total limit spent',
        ),
        if (!o.isPast && safe != null) ...[
          const SizedBox(height: Sp.md),
          Text(
            '${budgetMoney(context, safe)} a day for $days ${days == 1 ? 'day' : 'days'}',
            style: t.label.copyWith(color: c.ink),
          ),
        ],
        if (o.committed.isPositive) ...[
          SizedBox(height: !o.isPast && safe != null ? Sp.xs : Sp.md),
          Text('${budgetMoney(context, o.committed)} in subscriptions still to come', style: t.label),
        ],
      ],
    );
  }
}

/// Status chips with counts (only the ones that have budgets) and a sort
/// button that fills in when the order is not the default.
class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.pulse, required this.filter, required this.onState, required this.onSort});

  final BudgetsPulse pulse;
  final BudgetListFilter filter;
  final ValueChanged<BudgetState?> onState;
  final VoidCallback onSort;

  @override
  Widget build(BuildContext context) {
    final counts = pulse.counts;
    final tabs = <(BudgetState?, String, int)>[
      (null, 'All', pulse.paces.length),
      for (final s in BudgetState.values)
        if ((counts[s] ?? 0) > 0 || filter.state == s) (s, s.chipLabel(past: pulse.isPast), counts[s] ?? 0),
    ];
    final sorted = filter.sort != BudgetSort.urgency;
    return Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < tabs.length; i++) ...[
                  if (i > 0) const SizedBox(width: Sp.sm),
                  LedgerChip(
                    key: ValueKey('budget-tab:${tabs[i].$1?.name ?? 'all'}'),
                    label: tabs[i].$2,
                    count: tabs[i].$3,
                    selected: filter.state == tabs[i].$1,
                    semanticLabel: '${tabs[i].$2}, ${tabs[i].$3}',
                    onTap: () => onState(filter.state == tabs[i].$1 ? null : tabs[i].$1),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(width: Sp.sm),
        LedgerIconButton(
          key: const ValueKey('budget-options'),
          icon: LucideIcons.arrowDownUp,
          tooltip: sorted ? 'Sorted by ${filter.sort.label.toLowerCase()}' : 'Sort budgets',
          selected: sorted,
          onPressed: onSort,
        ),
      ],
    );
  }
}
