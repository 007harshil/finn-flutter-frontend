import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/di/data_providers.dart';
import '../../../app/router/routes.dart';
import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/time/dates.dart';
import '../../../design_system/design_system.dart'
    show AmountText, AnimatedAmount, BottomClearanceX, FinnMenuItem, showFinnActionMenu;
import '../../../shared/presentation/action_runner.dart';
import '../../../shared/presentation/async_view.dart';
import '../../../shared/presentation/transaction_row.dart';
import '../../../ui/ui.dart';
import '../../transactions/domain/transaction.dart';
import '../application/budget_actions.dart';
import '../application/budget_history.dart';
import '../application/budget_view.dart';
import '../domain/budget.dart';
import 'budget_charts.dart';
import 'budget_widgets.dart';

/// One budget: how much is left and whether the pace holds, a chart (this
/// period's running total, or the last six periods), and the spending
/// behind it with quick filters by payee and day.
class BudgetDetailScreen extends ConsumerWidget {
  const BudgetDetailScreen({super.key, required this.id, this.month});

  final String id;

  /// Budget month to show; null = this month. Past months are read-only.
  final MonthKey? month;

  Future<void> _menu(BuildContext context, WidgetRef ref, Budget b) async {
    final choice = await showFinnActionMenu<int>(
      context,
      items: [
        FinnMenuItem(
          value: 0,
          label: b.isPaused ? 'Resume tracking' : 'Pause tracking',
          icon: b.isPaused ? LucideIcons.play : LucideIcons.pause,
        ),
        const FinnMenuItem(value: 1, label: 'Delete budget', icon: LucideIcons.trash2, destructive: true),
      ],
    );
    if (!context.mounted || choice == null) return;
    if (choice == 0) {
      await runAction(
        context,
        ref,
        action: const SetBudgetPausedAction(),
        input: SetBudgetPausedInput(id: b.id, paused: !b.isPaused),
        idempotencyKey: newIdempotencyKey(),
      );
      return;
    }
    final deleted = await runAction(
      context,
      ref,
      action: const DeleteBudgetAction(),
      input: BudgetIdInput(id: b.id),
      idempotencyKey: newIdempotencyKey(),
      successTitle: 'Budget deleted',
      successSubtitle: 'Your transactions are unchanged.',
    );
    if (deleted != null && context.mounted) context.go(AppRoutes.budgets);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pace = ref.watch(budgetPaceProvider((id, month)));
    final past = pace.value?.isPast ?? false;
    final b = pace.value?.usage.budget;
    final categoryName = b == null ? null : ref.watch(categoryProvider(b.categoryId))?.name;
    final monthName = past ? DateFormats.monthYear.format(pace.value!.usage.period.start) : null;
    return UiPage(
      title: categoryName == null ? 'Budget' : (past ? '$categoryName · $monthName' : categoryName),
      actions: [
        if (b != null && !past) ...[
          UiIconButton(
            icon: LucideIcons.pencil,
            tooltip: 'Edit budget',
            size: 20,
            onPressed: () => context.push(AppRoutes.editBudget(id)),
          ),
          UiIconButton(
            key: const ValueKey('budget-more'),
            icon: LucideIcons.ellipsis,
            tooltip: 'More actions',
            onPressed: () => _menu(context, ref, b),
          ),
        ],
      ],
      body: AsyncView<BudgetPace?>(
        value: pace,
        loading: const _Placeholder(),
        builder: (context, p) => p == null
            ? Center(
                child: SingleChildScrollView(
                  child: UiEmpty(
                    icon: LucideIcons.chartPie,
                    title: 'Budget not found',
                    message: 'It may have been deleted.',
                    action: 'Back to budgets',
                    onAction: () => context.go(AppRoutes.budgets),
                  ),
                ),
              )
            : _DetailBody(pace: p),
      ),
    );
  }
}

enum _TxSort { newest, largest }

class _DetailBody extends ConsumerStatefulWidget {
  const _DetailBody({required this.pace});

  final BudgetPace pace;

  @override
  ConsumerState<_DetailBody> createState() => _DetailBodyState();
}

class _DetailBodyState extends ConsumerState<_DetailBody> {
  int? _day;
  String? _payee;
  _TxSort _sort = _TxSort.newest;

  @override
  Widget build(BuildContext context) {
    final p = widget.pace;
    final t = UiType.of(context);
    final month = p.usage.period.start.monthKey;
    final burn = ref.watch(budgetBurnProvider((p.usage.budget.id, month))).value;
    final all = burn?.transactions ?? const <Transaction>[];
    var shown = all.where((tx) {
      if (_payee != null && payeeOf(tx) != _payee) return false;
      if (_day != null && burn!.indexOf(tx.date) != _day) return false;
      return true;
    }).toList();
    if (_sort == _TxSort.largest) shown = [...shown]..sort((a, b) => b.amount.compareTo(a.amount));
    final payees = topPayees(all);
    final shownTotal = Money.sum(shown.map((tx) => tx.amount));
    final day = _day;

    Widget box(Widget child, {double top = 0}) => SliverPadding(
      padding: EdgeInsets.fromLTRB(UiSpace.gutter, top, UiSpace.gutter, 0),
      sliver: SliverToBoxAdapter(child: UiColumnWidth(child: child)),
    );
    return CustomScrollView(
      key: PageStorageKey('budget-${p.usage.budget.id}'),
      slivers: [
        if (p.isPast) box(const UiNotice(icon: LucideIcons.lock, text: 'Past month · read-only')),
        box(UiReveal(index: 0, child: _Hero(pace: p)), top: UiSpace.sm),
        if (burn != null)
          box(
            UiReveal(
              index: 1,
              child: _ChartPanel(pace: p, burn: burn, day: _day, onDay: (d) => setState(() => _day = d)),
            ),
            top: UiSpace.section,
          ),
        box(
          UiSectionTitle(
            title: 'Spending',
            trailing: shown.isEmpty ? null : AmountText(shownTotal, style: t.label),
            action: _sort == _TxSort.newest ? 'Newest' : 'Largest',
            onAction: () => setState(() => _sort = _sort == _TxSort.newest ? _TxSort.largest : _TxSort.newest),
          ),
          top: UiSpace.section - UiSpace.sm,
        ),
        if (payees.length > 1 || day != null)
          box(
            Padding(
              padding: const EdgeInsets.only(bottom: UiSpace.sm),
              child: Wrap(
                spacing: UiSpace.sm,
                children: [
                  if (day != null && burn != null)
                    UiChipButton(
                      key: const ValueKey('budget-day-chip'),
                      label: DateFormats.shortWeekdayDayMonth.format(burn.dayAt(day)),
                      trailingIcon: LucideIcons.x,
                      selected: true,
                      semanticLabel: 'Showing one day. Remove',
                      onTap: () => setState(() => _day = null),
                    ),
                  if (payees.length > 1)
                    for (final (name, total, count) in payees)
                      UiChipButton(
                        key: ValueKey('budget-payee:$name'),
                        label: '$name · ${budgetMoney(context, total)}',
                        selected: _payee == name,
                        semanticLabel:
                            '$name, $count payment${count == 1 ? '' : 's'}, ${budgetMoney(context, total)}. '
                            '${_payee == name ? 'Showing only these' : 'Show only these'}',
                        onTap: () => setState(() => _payee = _payee == name ? null : name),
                      ),
                ],
              ),
            ),
          ),
        if (shown.isEmpty)
          box(
            UiNotice(
              icon: LucideIcons.inbox,
              text: all.isEmpty ? 'No spending here yet this period' : 'Nothing matches these filters',
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: UiSpace.gutter),
            sliver: SliverList.builder(
              itemCount: shown.length,
              itemBuilder: (context, i) => UiColumnWidth(
                key: ValueKey(shown[i].id),
                child: UiPanelSlice(
                  first: i == 0,
                  last: i == shown.length - 1,
                  child: TransactionRow(transaction: shown[i], showDate: true),
                ),
              ),
            ),
          ),
        SliverToBoxAdapter(child: SizedBox(height: context.bottomClearance)),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Hero
// ---------------------------------------------------------------------------

/// What is left (or how far over), one line on the pace, the limit used
/// and three figures that answer "how much can I still spend".
class _Hero extends StatelessWidget {
  const _Hero({required this.pace});

  final BudgetPace pace;

  @override
  Widget build(BuildContext context) {
    final p = pace;
    final u = p.usage;
    final c = UiColors.of(context);
    final t = UiType.of(context);
    final color = p.state.color(c);
    final calm = p.state == BudgetState.onTrack || p.state == BudgetState.paused;
    String m(Money x) => budgetMoney(context, x);
    Widget fig(String text, {Color? color}) => Text(text, style: t.figureSmall.copyWith(color: color));

    final stats = p.isPast
        ? [
            UiStat(label: 'Spent', value: AmountText(u.spent, style: t.figureSmall)),
            UiStat(label: 'Daily average', value: fig(m(u.spent.scale(1, u.period.dayCount)))),
            UiStat(label: 'Limit then', value: fig(m(u.budget.limit))),
          ]
        : [
            UiStat(label: 'Spent', value: AmountText(u.spent, style: t.figureSmall)),
            UiStat(label: 'Safe per day', value: fig(p.safePerDay == null ? '—' : m(p.safePerDay!))),
            UiStat(
              label: 'At this pace',
              value: fig(
                p.projected == null ? '—' : m(p.projected!),
                color: p.projected != null && p.projected! > u.budget.limit ? c.negative : null,
              ),
            ),
          ];

    final notes = <Widget>[
      if (!p.isPast && u.committed.isPositive)
        UiNotice(icon: LucideIcons.repeat, text: '${m(u.committed)} in subscriptions still due'),
      if (u.budget.note != null) UiNotice(icon: LucideIcons.stickyNote, text: u.budget.note!),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        UiHero(
          label: u.isOver ? 'Over by' : (p.isPast ? 'Left unspent' : 'Left'),
          labelTrailing: Text(p.isPast ? periodLabel(u.period) : daysLeftLabel(p.daysLeft), style: t.label),
          value: AnimatedAmount(
            u.remaining.abs(),
            style: t.amount.copyWith(color: u.isOver ? c.negative : null),
            decimals: DecimalDisplay.none,
            fit: true,
            animateOnMount: true,
          ),
          caption: _verdict(context, p),
          captionColor: calm ? null : color,
          footer: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              UiProgressFooter(
                value: p.used,
                color: calm ? c.ink : color,
                start: '${formatBps(u.utilizationBps, decimals: 0)} of ${m(u.budget.limit)}',
                end: p.isPast || p.state == BudgetState.paused ? '' : '${(p.elapsed * 100).round()}% of month gone',
                semanticsLabel: 'Limit used',
              ),
              const SizedBox(height: UiSpace.lg),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < stats.length; i++) ...[
                    if (i > 0) const SizedBox(width: UiSpace.md),
                    Expanded(child: stats[i]),
                  ],
                ],
              ),
            ],
          ),
        ),
        if (notes.isNotEmpty) ...[const SizedBox(height: UiSpace.sm), ...notes],
      ],
    );
  }

  String _verdict(BuildContext context, BudgetPace p) {
    final u = p.usage;
    String m(Money x) => budgetMoney(context, x);
    return switch (p.state) {
      BudgetState.over when p.isPast => 'Went over the limit that month',
      _ when p.isPast => 'Stayed within the limit',
      BudgetState.paused => 'Paused · no alerts until you resume',
      BudgetState.over => 'Anything more here adds to the overspend',
      _ when p.runsOutOn != null => 'Runs out around ${DateFormats.dayMonth.format(p.runsOutOn!)} at this pace',
      BudgetState.risk => '${formatBps(u.utilizationBps, decimals: 0)} used already',
      _ when p.projected != null => 'On pace to finish ${m(u.budget.limit - p.projected!)} under',
      _ => 'Plenty of room this period',
    };
  }
}

// ---------------------------------------------------------------------------
// Chart
// ---------------------------------------------------------------------------

enum _ChartView { period, history }

/// This period's running total (tap a day to read it and filter the list),
/// or the last periods side by side.
class _ChartPanel extends ConsumerStatefulWidget {
  const _ChartPanel({required this.pace, required this.burn, required this.day, required this.onDay});

  final BudgetPace pace;
  final BudgetBurn burn;
  final int? day;
  final ValueChanged<int?> onDay;

  @override
  ConsumerState<_ChartPanel> createState() => _ChartPanelState();
}

class _ChartPanelState extends ConsumerState<_ChartPanel> {
  _ChartView _view = _ChartView.period;
  int? _bar;

  @override
  Widget build(BuildContext context) {
    final c = UiColors.of(context);
    final m = UiMotion.of(context);
    final p = widget.pace;
    final u = p.usage;
    final color = p.state == BudgetState.over ? c.negative : c.ink;
    final history =
        ref.watch(budgetHistoryProvider((u.budget.id, u.period.start.monthKey))).value ?? const <BudgetPeriodPoint>[];
    final showHistory = _view == _ChartView.history && history.isNotEmpty;
    return UiPanel(
      padding: const EdgeInsets.all(UiSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (history.length > 1) ...[
            UiSegmented<_ChartView>(
              segments: [
                const UiSegment(_ChartView.period, 'This period'),
                UiSegment(_ChartView.history, history.length > 2 ? 'Last ${history.length}' : 'Compare'),
              ],
              selected: _view,
              onChanged: (v) => setState(() => _view = v),
            ),
            const SizedBox(height: UiSpace.lg),
          ],
          AnimatedSwitcher(
            duration: m.normal,
            child: KeyedSubtree(
              key: ValueKey(showHistory ? 'h$_bar' : 'p${widget.day}'),
              child: showHistory ? _historyReadout(context, history) : _periodReadout(context),
            ),
          ),
          const SizedBox(height: UiSpace.md),
          AnimatedSwitcher(
            duration: m.normal,
            switchInCurve: UiMotion.ease,
            child: showHistory
                ? HistoryBars(
                    key: const ValueKey('history'),
                    points: history,
                    color: c.ink,
                    selected: _bar,
                    onSelect: (i) => setState(() => _bar = i),
                  )
                : BurnChart(
                    key: const ValueKey('burn'),
                    burn: widget.burn,
                    limit: u.budget.limit,
                    color: color,
                    selected: widget.day,
                    onSelect: widget.onDay,
                  ),
          ),
        ],
      ),
    );
  }

  Widget _periodReadout(BuildContext context) {
    final c = UiColors.of(context);
    final b = widget.burn;
    final u = widget.pace.usage;
    final cum = b.cumulative;
    final d = widget.day;
    if (d != null && d >= 0 && d < cum.length) {
      final spent = Money.fromPaise(b.daily[d]);
      final total = Money.fromPaise(cum[d]);
      return _Readout(
        title: DateFormats.shortWeekdayDayMonth.format(b.dayAt(d)),
        value: spent.isZero ? 'No spending' : '${budgetMoney(context, spent)} spent',
        note: '${budgetMoney(context, total)} by then',
      );
    }
    final last = b.todayIndex.clamp(0, cum.length - 1);
    final plan = u.budget.limit.scale(last + 1, cum.length);
    final now = Money.fromPaise(cum.isEmpty ? 0 : cum[last]);
    final ahead = now - plan;
    if (widget.pace.isPast) {
      return _Readout(
        title: 'Month total',
        value: budgetMoney(context, now),
        note: '${formatBps(now.ratioBps(u.budget.limit) ?? 0, decimals: 0)} of the limit',
        noteColor: now > u.budget.limit ? c.negative : null,
      );
    }
    return _Readout(
      title: 'So far',
      value: budgetMoney(context, now),
      note: ahead.isPositive
          ? '${budgetMoney(context, ahead)} ahead of an even pace'
          : '${budgetMoney(context, -ahead)} under an even pace',
      noteColor: ahead.isPositive ? c.warning : c.positive,
    );
  }

  Widget _historyReadout(BuildContext context, List<BudgetPeriodPoint> points) {
    final c = UiColors.of(context);
    final i = _bar;
    if (i != null && i < points.length) {
      final pt = points[i];
      return _Readout(
        title: periodLabel(pt.period),
        value: budgetMoney(context, pt.spent),
        note: '${formatBps(pt.spent.ratioBps(pt.limit) ?? 0, decimals: 0)} of limit${pt.isOver ? ' · over' : ''}',
        noteColor: pt.isOver ? c.negative : null,
      );
    }
    final avg = averageSpentBefore(points);
    final over = points.where((p) => p.isOver && !p.isCurrent).length;
    final before = points.where((p) => !p.isCurrent).length;
    return _Readout(
      title: 'Average before',
      value: avg == null ? '—' : budgetMoney(context, avg),
      note: before == 0 ? 'No earlier periods yet' : 'Over the limit in $over of $before',
      noteColor: over > 0 ? c.warning : null,
    );
  }
}

/// Small label over a figure, with one quiet note at the end.
class _Readout extends StatelessWidget {
  const _Readout({required this.title, required this.value, required this.note, this.noteColor});

  final String title;
  final String value;
  final String note;
  final Color? noteColor;

  @override
  Widget build(BuildContext context) {
    final t = UiType.of(context);
    return Semantics(
      liveRegion: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: t.small),
                const SizedBox(height: 2),
                Text(value, style: t.figure),
              ],
            ),
          ),
          const SizedBox(width: UiSpace.md),
          Flexible(
            child: Text(note, textAlign: TextAlign.end, style: t.small.copyWith(color: noteColor)),
          ),
        ],
      ),
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
            UiPlaceholder(width: 90, height: 12),
            SizedBox(height: UiSpace.md),
            UiPlaceholder(width: 200, height: 40),
            SizedBox(height: UiSpace.section),
            UiPlaceholder(height: 240, radius: UiRadius.panel),
          ],
        ),
      ),
    );
  }
}
