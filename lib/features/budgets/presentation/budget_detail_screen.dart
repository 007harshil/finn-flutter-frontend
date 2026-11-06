import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/di/data_providers.dart';
import '../../../app/router/routes.dart';
import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/time/dates.dart';
import '../../../kit/kit.dart';
import '../../../shared/presentation/action_runner.dart';
import '../../../shared/presentation/async_view.dart';
import '../../../shared/presentation/category_icons.dart';
import '../../../shared/presentation/transaction_row.dart';
import '../application/budget_actions.dart';
import '../application/budget_history.dart';
import '../application/budget_view.dart';
import '../domain/budget.dart';
import 'budget_charts.dart';
import 'budget_widgets.dart';

/// One budget: how much is left and whether the pace holds, a chart of
/// this period (or the last few), and the spending behind it with quick
/// filters by payee and day.
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
    final appBar = LedgerAppBar(
      title: categoryName == null ? 'Budget' : (past ? '$categoryName, $monthName' : '$categoryName budget'),
      actions: [
        if (b != null && !past) ...[
          LedgerIconButton(
            icon: LucideIcons.pencil,
            tooltip: 'Edit budget',
            onPressed: () => context.push(AppRoutes.editBudget(id)),
          ),
          LedgerIconButton(
            key: const ValueKey('budget-more'),
            icon: LucideIcons.ellipsisVertical,
            tooltip: 'More actions',
            onPressed: () => _menu(context, ref, b),
          ),
        ],
      ],
    );
    return AsyncView<BudgetPace?>(
      value: pace,
      loading: Scaffold(backgroundColor: context.ink.paper, appBar: appBar, body: const LedgerPageSkeleton(rows: 3)),
      builder: (context, p) => p == null
          ? LedgerPage(
              appBar: appBar,
              slivers: [
                PageBlock(
                  top: Sp.xxl,
                  child: LedgerEmpty(
                    title: 'Budget not found',
                    actionLabel: 'Back to budgets',
                    onAction: () => context.go(AppRoutes.budgets),
                  ),
                ),
              ],
            )
          : _DetailBody(pace: p, appBar: appBar),
    );
  }
}

enum _TxSort { newest, largest }

class _DetailBody extends ConsumerStatefulWidget {
  const _DetailBody({required this.pace, required this.appBar});

  final BudgetPace pace;
  final PreferredSizeWidget appBar;

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
    final month = p.usage.period.start.monthKey;
    final burn = ref.watch(budgetBurnProvider((p.usage.budget.id, month))).value;
    return LedgerPage(
      appBar: widget.appBar,
      storageKey: 'budget-${p.usage.budget.id}',
      slivers: [
        if (p.isPast)
          const PageBlock(
            top: Sp.sm,
            child: LedgerNote(
              icon: LucideIcons.lock,
              text: 'Past months are read-only',
            ),
          ),
        PageBlock(top: p.isPast ? Sp.lg : Sp.md, child: _Hero(pace: p)),
        if (burn != null) ...[
          PageBlock(
            top: Sp.section,
            child: _ChartSection(pace: p, burn: burn, day: _day, onDay: (d) => setState(() => _day = d)),
          ),
          PageBlock(top: Sp.section, child: _spending(context, burn)),
        ],
      ],
    );
  }

  Widget _spending(BuildContext context, BudgetBurn burn) {
    final all = burn.transactions;
    var shown = all.where((tx) {
      if (_payee != null && payeeOf(tx) != _payee) return false;
      if (_day != null && burn.indexOf(tx.date) != _day) return false;
      return true;
    }).toList();
    if (_sort == _TxSort.largest) shown = [...shown]..sort((a, b) => b.amount.compareTo(a.amount));
    final payees = topPayees(all);
    final newest = _sort == _TxSort.newest;
    final day = _day;
    return LedgerSection(
      title: 'Spending',
      count: shown.length,
      trailing: all.length < 2
          ? null
          : LedgerChip(
              key: const ValueKey('budget-tx-sort'),
              label: newest ? 'Newest' : 'Largest',
              icon: LucideIcons.arrowDownUp,
              semanticLabel: 'Sorted by ${newest ? 'newest' : 'largest'}. Change',
              onTap: () => setState(() => _sort = newest ? _TxSort.largest : _TxSort.newest),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (payees.length > 1 || day != null) ...[
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              child: Row(
                children: [
                  if (day != null) ...[
                    LedgerChip(
                      key: const ValueKey('budget-day-chip'),
                      label: DateFormats.shortWeekdayDayMonth.format(burn.dayAt(day)),
                      icon: LucideIcons.calendar,
                      selected: true,
                      removable: true,
                      semanticLabel: 'Showing one day. Remove',
                      onTap: () => setState(() => _day = null),
                    ),
                    const SizedBox(width: Sp.sm),
                  ],
                  if (payees.length > 1)
                    for (final (name, total, count) in payees) ...[
                      LedgerChip(
                        key: ValueKey('budget-payee:$name'),
                        label: '$name ${budgetMoney(context, total)}',
                        selected: _payee == name,
                        semanticLabel: '$name, $count ${count == 1 ? 'payment' : 'payments'}, '
                            '${budgetMoney(context, total)}. ${_payee == name ? 'Showing only these' : 'Show only these'}',
                        onTap: () => setState(() => _payee = _payee == name ? null : name),
                      ),
                      const SizedBox(width: Sp.sm),
                    ],
                ],
              ),
            ),
            const SizedBox(height: Sp.md),
          ],
          if (shown.isEmpty)
            LedgerEmpty(
              icon: all.isEmpty ? LucideIcons.notebookPen : LucideIcons.searchX,
              title: all.isEmpty ? 'No spending yet' : 'Nothing matches',
            )
          else
            LedgerPanel(
              khata: true,
              // Align hairlines with the row text (padding + 40pt mark + gap).
              dividerIndent: Khata.textX,
              children: [
                for (final tx in shown)
                  KeyedSubtree(key: ValueKey(tx.id), child: TransactionRow(transaction: tx, showDate: true)),
              ],
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Hero
// ---------------------------------------------------------------------------

class _Hero extends ConsumerWidget {
  const _Hero({required this.pace});

  final BudgetPace pace;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.ink;
    final p = pace;
    final u = p.usage;
    final hidden = AmountVisibility.hiddenOf(context);
    final category = ref.watch(categoryProvider(u.budget.categoryId));
    final paused = p.state == BudgetState.paused;
    final over = u.isOver;
    final projected = paused ? null : p.projected;
    final note = u.budget.note;
    final tone = switch (p.state) {
      BudgetState.over => SlabTone.bad,
      BudgetState.risk => SlabTone.warn,
      BudgetState.paused => SlabTone.neutral,
      BudgetState.onTrack => SlabTone.good,
    };
    final runsOut = !p.isPast && !paused && !over ? p.runsOutOn : null;
    final tags = <(IconData, String, Color, Color)>[
      if (runsOut != null) (LucideIcons.hourglass, 'Runs out ~${DateFormats.dayMonth.format(runsOut)}', c.amber, c.amberSoft),
      if (u.committed.isPositive)
        (LucideIcons.repeat, '${budgetMoney(context, u.committed)} subscriptions to come', c.lilac, c.sunken),
      if (paused) (LucideIcons.pause, 'No alerts while paused', c.inkSoft, c.sunken),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BahiSlab(
          leading: category == null ? LucideIcons.tag : CategoryIcons.of(category.iconKey),
          label: over ? 'Over by' : 'Left',
          figure: SlabFigure(u.remaining.abs(), color: over && !hidden ? Slab.bad : null),
          caption: 'of ${budgetMoney(context, u.budget.limit)} · ${paused ? 'Paused, ' : ''}${periodLabel(u.period)}',
          stamp: SlabStamp(label: p.state.label, tone: tone),
          visual: SlabRing(
            value: p.used,
            marker: p.isPast || paused ? null : p.elapsed,
            size: 100,
            color: slabToneColor(tone),
            top: hidden ? '••' : formatBps(u.utilizationBps, decimals: 0),
            bottom: 'used',
            semanticLabel: '${formatBps(u.utilizationBps, decimals: 0)} of the limit used, '
                '${formatBps(u.elapsedBps, decimals: 0)} of the period gone',
          ),
          stats: p.isPast
              ? [
                  SlabStat.money(label: 'Spent', amount: u.spent, color: u.isOver ? Slab.bad : null),
                  SlabStat.money(label: 'Daily average', amount: u.spent.scale(1, u.period.dayCount)),
                  SlabStat.money(label: 'Limit then', amount: u.budget.limit),
                ]
              : [
                  SlabStat.money(label: 'Spent', amount: u.spent, color: u.isOver ? Slab.bad : null),
                  p.safePerDay == null
                      ? SlabStat.text(label: 'Safe per day', text: '—')
                      : SlabStat.money(label: 'Safe per day', amount: p.safePerDay!),
                  projected == null
                      ? SlabStat.text(label: 'At this pace', text: '—')
                      : SlabStat.money(
                          label: 'At this pace',
                          amount: projected,
                          color: projected > u.budget.limit ? Slab.bad : null,
                        ),
                ],
        ),
        if (tags.isNotEmpty) ...[
          const SizedBox(height: Sp.md),
          Wrap(
            spacing: Sp.sm,
            runSpacing: Sp.sm,
            children: [
              for (final (icon, text, fg, bg) in tags)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: Sp.sm + 2, vertical: 6),
                  decoration: BoxDecoration(color: bg, borderRadius: Rad.rChip),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 14, color: fg),
                      const SizedBox(width: 6),
                      Text(text, style: context.type.small.copyWith(color: fg, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
            ],
          ),
        ],
        if (note != null && note.trim().isNotEmpty) ...[
          const SizedBox(height: Sp.md),
          LedgerNote(icon: LucideIcons.stickyNote, text: note),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Chart
// ---------------------------------------------------------------------------

enum _ChartView { period, history }

class _ChartSection extends ConsumerStatefulWidget {
  const _ChartSection({required this.pace, required this.burn, required this.day, required this.onDay});

  final BudgetPace pace;
  final BudgetBurn burn;
  final int? day;
  final ValueChanged<int?> onDay;

  @override
  ConsumerState<_ChartSection> createState() => _ChartSectionState();
}

class _ChartSectionState extends ConsumerState<_ChartSection> {
  _ChartView _view = _ChartView.period;
  int? _bar;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final u = widget.pace.usage;
    final history =
        ref.watch(budgetHistoryProvider((u.budget.id, u.period.start.monthKey))).value ?? const <BudgetPeriodPoint>[];
    final showHistory = _view == _ChartView.history && history.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LedgerSegmented<_ChartView>(
          segments: [
            const LedgerSegment(_ChartView.period, 'This period'),
            LedgerSegment(_ChartView.history, history.length > 2 ? 'Last ${history.length}' : 'Compare'),
          ],
          selected: _view,
          onChanged: (v) => setState(() => _view = v),
        ),
        const SizedBox(height: Sp.md),
        MonsoonCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              showHistory ? _historyReadout(context, history) : _periodReadout(context),
              const SizedBox(height: Sp.lg),
              if (showHistory)
                HistoryBars(points: history, selected: _bar, onSelect: (i) => setState(() => _bar = i))
              else ...[
                BurnChart(
                  burn: widget.burn,
                  limit: u.budget.limit,
                  selected: widget.day,
                  onSelect: widget.onDay,
                ),
                const SizedBox(height: Sp.sm),
                Wrap(
                  spacing: Sp.lg,
                  children: [
                    ChartDot(color: c.rain, label: 'Spent'),
                    ChartDot(color: c.saffron, label: 'Even pace'),
                    ChartDot(color: c.red, label: 'Limit'),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _periodReadout(BuildContext context) {
    final c = context.ink;
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
        note: '${budgetMoney(context, total)} by then, ${formatBps(total.ratioBps(u.budget.limit) ?? 0, decimals: 0)} of the limit',
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
        noteColor: now > u.budget.limit ? c.red : null,
      );
    }
    return _Readout(
      title: 'So far',
      value: budgetMoney(context, now),
      note: ahead.isPositive
          ? '${budgetMoney(context, ahead)} ahead of pace'
          : '${budgetMoney(context, -ahead)} under pace',
      noteColor: ahead.isPositive ? c.amber : null,
    );
  }

  Widget _historyReadout(BuildContext context, List<BudgetPeriodPoint> points) {
    final c = context.ink;
    final i = _bar;
    if (i != null && i < points.length) {
      final pt = points[i];
      final pct = formatBps(pt.spent.ratioBps(pt.limit) ?? 0, decimals: 0);
      return _Readout(
        title: periodLabel(pt.period),
        value: budgetMoney(context, pt.spent),
        note: pt.isOver ? 'Over the limit, $pct' : '$pct of the limit',
        noteColor: pt.isOver ? c.red : null,
      );
    }
    final avg = averageSpentBefore(points);
    final over = points.where((p) => p.isOver && !p.isCurrent).length;
    final before = points.where((p) => !p.isCurrent).length;
    return _Readout(
      title: 'Average before',
      value: avg == null ? '—' : budgetMoney(context, avg),
      note: before == 0 ? 'No earlier months yet' : 'Over the limit in $over of $before',
      noteColor: over > 0 ? c.amber : null,
    );
  }
}

class _Readout extends StatelessWidget {
  const _Readout({required this.title, required this.value, required this.note, this.noteColor});

  final String title;
  final String value;
  final String note;
  final Color? noteColor;

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    return Semantics(
      liveRegion: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: t.label),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(value, style: t.figure.copyWith(fontSize: 20), maxLines: 1),
                ),
              ],
            ),
          ),
          const SizedBox(width: Sp.md),
          Flexible(
            child: Align(
              alignment: Alignment.bottomRight,
              child: Text(note, textAlign: TextAlign.end, style: t.small.copyWith(color: noteColor)),
            ),
          ),
        ],
      ),
    );
  }
}
