import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/di/data_providers.dart';
import '../../../app/router/routes.dart';
import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/time/dates.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/presentation/action_runner.dart';
import '../../../shared/presentation/async_view.dart';
import '../../../shared/presentation/category_icons.dart';
import '../../../shared/presentation/transaction_row.dart';
import '../../alerts/presentation/alert_visuals.dart' show MaybeAnimate;
import '../../transactions/domain/transaction.dart';
import '../application/budget_actions.dart';
import '../application/budget_history.dart';
import '../application/budget_view.dart';
import '../domain/budget.dart';
import 'budget_charts.dart';
import 'budget_widgets.dart';

/// One budget: a gauge that answers "how much is left and am I on pace",
/// a chart (this period's running total, or the last six periods), and the
/// spending behind it with quick filters by payee and day.
class BudgetDetailScreen extends ConsumerWidget {
  const BudgetDetailScreen({super.key, required this.id});

  final String id;

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
    final pace = ref.watch(budgetPaceProvider(id));
    final b = pace.value?.usage.budget;
    final categoryName = b == null ? null : ref.watch(categoryProvider(b.categoryId))?.name;
    return Scaffold(
      appBar: AppBar(
        title: Text(categoryName == null ? 'Budget' : '$categoryName budget'),
        actions: [
          if (b != null) ...[
            FinnIconButton(
              icon: LucideIcons.pencil,
              tooltip: 'Edit budget',
              onPressed: () => context.push(AppRoutes.editBudget(id)),
            ),
            FinnIconButton(
              key: const ValueKey('budget-more'),
              icon: LucideIcons.ellipsisVertical,
              tooltip: 'More actions',
              onPressed: () => _menu(context, ref, b),
            ),
          ],
          const SizedBox(width: Space.x2),
        ],
      ),
      body: AsyncView<BudgetPace?>(
        value: pace,
        loading: const SkeletonPulse(
          child: Padding(
            padding: EdgeInsets.all(Space.gutter),
            child: Column(children: [CardSkeleton(height: 300), SizedBox(height: Space.x4), CardSkeleton(height: 220)]),
          ),
        ),
        builder: (context, p) => p == null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(Space.x6),
                  child: EmptyState(
                    icon: LucideIcons.chartPie,
                    title: 'Budget not found',
                    message: 'It may have been deleted.',
                    actionLabel: 'Back to budgets',
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
    final c = context.colors;
    final t = context.text;
    final burn = ref.watch(budgetBurnProvider(p.usage.budget.id)).value;
    final all = burn?.transactions ?? const <Transaction>[];
    var shown = all.where((tx) {
      if (_payee != null && payeeOf(tx) != _payee) return false;
      if (_day != null && burn!.indexOf(tx.date) != _day) return false;
      return true;
    }).toList();
    if (_sort == _TxSort.largest) shown = [...shown]..sort((a, b) => b.amount.compareTo(a.amount));
    final payees = topPayees(all);
    final shownTotal = Money.sum(shown.map((tx) => tx.amount));

    Widget box(Widget child, {double top = Space.x3}) => SliverToBoxAdapter(
          child: ResponsiveCenter(padding: EdgeInsets.fromLTRB(Space.gutter, top, Space.gutter, 0), child: child),
        );
    return CustomScrollView(
      key: PageStorageKey('budget-${p.usage.budget.id}'),
      slivers: [
        box(StaggeredEntrance(child: _HeroCard(pace: p)), top: Space.x2),
        if (burn != null)
          box(
            StaggeredEntrance(
              index: 1,
              child: _ChartCard(
                pace: p,
                burn: burn,
                day: _day,
                onDay: (d) => setState(() => _day = d),
              ),
            ),
          ),
        box(
          Row(
            children: [
              Text('Spending', style: t.sectionTitle),
              const SizedBox(width: Space.x2),
              Text('${shown.length}', style: t.label.copyWith(color: c.textTertiary, fontWeight: FontWeight.w900)),
              const Spacer(),
              if (shown.isNotEmpty) Flexible(child: AmountText(shownTotal, style: t.amountSmall, fit: true)),
              const SizedBox(width: Space.x2),
              FinnTapChip(
                key: const ValueKey('budget-tx-sort'),
                label: _sort == _TxSort.newest ? 'Newest' : 'Largest',
                icon: LucideIcons.arrowDownUp,
                height: 28,
                semantics: 'Sorted by ${_sort == _TxSort.newest ? 'newest' : 'largest'}. Change',
                onTap: () => setState(() => _sort = _sort == _TxSort.newest ? _TxSort.largest : _TxSort.newest),
              ),
            ],
          ),
          top: Space.section,
        ),
        if (payees.length > 1 || _day != null)
          box(
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  if (_day != null && burn != null) ...[
                    FinnTapChip(
                      key: const ValueKey('budget-day-chip'),
                      label: DateFormats.shortWeekdayDayMonth.format(burn.dayAt(_day!)),
                      icon: LucideIcons.calendar,
                      trailing: LucideIcons.x,
                      color: c.primary,
                      selected: true,
                      semantics: 'Showing one day. Remove',
                      onTap: () => setState(() => _day = null),
                    ),
                    const SizedBox(width: Space.x1_5),
                  ],
                  for (final (name, total, count) in payees) ...[
                    FinnTapChip(
                      key: ValueKey('budget-payee:$name'),
                      label: '$name · ${budgetMoney(context, total)}',
                      selected: _payee == name,
                      color: _payee == name ? c.primary : null,
                      semantics: '$name, $count ${count == 1 ? 'payment' : 'payments'}, '
                          '${budgetMoney(context, total)}. ${_payee == name ? 'Showing only these' : 'Show only these'}',
                      onTap: () => setState(() => _payee = _payee == name ? null : name),
                    ),
                    const SizedBox(width: Space.x1_5),
                  ],
                ],
              ),
            ),
            top: Space.x2,
          ),
        if (shown.isEmpty)
          box(
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.x4),
              child: Row(
                children: [
                  Icon(all.isEmpty ? LucideIcons.sparkles : LucideIcons.searchX, size: 16, color: c.textTertiary),
                  const SizedBox(width: Space.x2),
                  Expanded(
                    child: Text(
                      all.isEmpty ? 'No spending in this category yet this period.' : 'Nothing matches these filters.',
                      style: t.body.copyWith(color: c.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          SliverList.builder(
            itemCount: shown.length,
            itemBuilder: (context, i) => ResponsiveCenter(
              key: ValueKey(shown[i].id),
              padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
              child: TransactionRow(
                transaction: shown[i],
                showDate: true,
              ),
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: Space.x12)),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Hero
// ---------------------------------------------------------------------------

class _HeroCard extends ConsumerWidget {
  const _HeroCard({required this.pace});

  final BudgetPace pace;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = pace;
    final u = p.usage;
    final c = context.colors;
    final t = context.text;
    final category = ref.watch(categoryProvider(u.budget.categoryId));
    final color = p.state.color(c);
    final paused = p.state == BudgetState.paused;
    final (IconData vIcon, String verdict) = _verdict(context, p);
    final safe = p.safePerDay;
    final projected = p.projected;
    return FinnCard(
      radius: Radii.xxl,
      padding: const EdgeInsets.fromLTRB(Space.x4, Space.x3, Space.x4, Space.x4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CategoryAvatar(category: category, size: 28),
              const SizedBox(width: Space.x2),
              Expanded(
                child: Text(
                  '${u.budget.periodType.label} · ${periodLabel(u.period)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.caption,
                ),
              ),
              StatusPill(label: p.state.label, color: color, icon: p.state.icon),
            ],
          ),
          const SizedBox(height: Space.x3),
          Center(
            child: BudgetGauge(
              used: p.used,
              elapsed: paused ? 0 : p.elapsed,
              warnAt: u.budget.warningThresholdBps / 10000,
              color: color,
              semanticsLabel: '${formatBps(u.utilizationBps, decimals: 0)} of the limit used, '
                  '${formatBps(u.elapsedBps, decimals: 0)} of the period gone',
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(u.isOver ? 'OVER BY' : 'LEFT', style: t.eyebrow),
                  AnimatedAmount(
                    u.remaining.abs(),
                    animateOnMount: true,
                    fit: true,
                    style: t.amountLarge.copyWith(color: u.isOver ? c.negative : c.textPrimary),
                  ),
                  Text('of ${budgetMoney(context, u.budget.limit)}', style: t.caption),
                ],
              ),
            ),
          ),
          const SizedBox(height: Space.x3),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: Space.x3, vertical: Space.x2_5),
            decoration: BoxDecoration(
              color: color.withValues(alpha: c.isDark ? 0.16 : 0.09),
              borderRadius: Radii.rLg,
            ),
            child: Row(
              children: [
                Icon(vIcon, size: 16, color: color),
                const SizedBox(width: Space.x2),
                Expanded(child: Text(verdict, style: t.label.copyWith(color: c.textPrimary, fontWeight: FontWeight.w700))),
              ],
            ),
          ).maybeAnimate(context, (a) => a.fadeIn(delay: 500.ms, duration: 300.ms).slideY(begin: 0.3, end: 0, delay: 500.ms)),
          const SizedBox(height: Space.x3),
          IntrinsicHeight(
            child: Row(
              children: [
                _Stat(
                  label: 'SPENT',
                  value: budgetMoney(context, u.spent),
                  sub: formatBps(u.utilizationBps, decimals: 0),
                  color: u.isOver ? c.negative : null,
                ),
                VerticalDivider(width: Space.x4, color: c.border),
                _Stat(
                  label: 'SAFE PER DAY',
                  value: safe == null ? '—' : budgetMoney(context, safe),
                  sub: p.daysLeft == 0 ? 'period ended' : daysLeftLabel(p.daysLeft).toLowerCase(),
                ),
                VerticalDivider(width: Space.x4, color: c.border),
                _Stat(
                  label: 'AT THIS PACE',
                  value: projected == null || paused ? '—' : budgetMoney(context, projected),
                  sub: projected == null || paused ? 'too early' : 'by ${DateFormats.dayMonth.format(u.period.end)}',
                  color: projected != null && !paused && projected > u.budget.limit ? c.negative : null,
                ),
              ],
            ),
          ),
          if (u.committed.isPositive || u.budget.note != null) ...[
            const SizedBox(height: Space.x3),
            Wrap(
              spacing: Space.x3,
              runSpacing: Space.x1,
              children: [
                if (u.committed.isPositive)
                  _Fact(
                    icon: LucideIcons.repeat,
                    text: '${budgetMoney(context, u.committed)} subscriptions due · '
                        '${budgetMoney(context, u.remainingAfterCommitted)} left after',
                  ),
                if (u.budget.note != null) _Fact(icon: LucideIcons.stickyNote, text: u.budget.note!),
              ],
            ),
          ],
        ],
      ),
    );
  }

  (IconData, String) _verdict(BuildContext context, BudgetPace p) {
    final u = p.usage;
    String m(Money x) => budgetMoney(context, x);
    return switch (p.state) {
      BudgetState.paused => (LucideIcons.circlePause, 'Paused — no warnings or alerts until you resume.'),
      BudgetState.over => (
          LucideIcons.triangleAlert,
          'You are ${m(-u.remaining)} over. Anything more here adds to the overspend.'
        ),
      _ when p.runsOutOn != null => (
          LucideIcons.gauge,
          'At this pace the limit runs out around ${DateFormats.dayMonth.format(p.runsOutOn!)}. '
              'Keep to ${p.safePerDay == null ? 'less' : '${m(p.safePerDay!)}/day'} to stay within it.'
        ),
      BudgetState.risk => (
          LucideIcons.gauge,
          'Used ${formatBps(u.utilizationBps, decimals: 0)} already. '
              '${p.safePerDay == null ? '' : 'Up to ${m(p.safePerDay!)}/day keeps you within the limit.'}'
        ),
      _ when p.projected != null => (
          LucideIcons.circleCheck,
          'On pace to finish with about ${m(u.budget.limit - p.projected!)} to spare.'
        ),
      _ => (LucideIcons.circleCheck, 'Plenty of room this period.'),
    };
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.sub, this.color});

  final String label;
  final String value;
  final String sub;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = context.text;
    return Expanded(
      child: MergeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.eyebrow.copyWith(fontSize: 10)),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value, maxLines: 1, style: t.amountSmall.copyWith(color: color)),
            ),
            Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.micro),
          ],
        ),
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: c.textTertiary),
        const SizedBox(width: Space.x1),
        Flexible(child: Text(text, style: context.text.micro)),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Chart card
// ---------------------------------------------------------------------------

enum _ChartView { period, history }

class _ChartCard extends ConsumerStatefulWidget {
  const _ChartCard({required this.pace, required this.burn, required this.day, required this.onDay});

  final BudgetPace pace;
  final BudgetBurn burn;
  final int? day;
  final ValueChanged<int?> onDay;

  @override
  ConsumerState<_ChartCard> createState() => _ChartCardState();
}

class _ChartCardState extends ConsumerState<_ChartCard> {
  _ChartView _view = _ChartView.period;
  int? _bar;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final p = widget.pace;
    final u = p.usage;
    final color = p.state == BudgetState.over ? c.negative : c.primary;
    final history = ref.watch(budgetHistoryProvider(u.budget.id)).value ?? const <BudgetPeriodPoint>[];
    final showHistory = _view == _ChartView.history && history.isNotEmpty;
    return FinnCard(
      radius: Radii.xxl,
      padding: const EdgeInsets.fromLTRB(Space.x4, Space.x3, Space.x4, Space.x3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedTabs<_ChartView>(
            items: [
              const SegmentItem(_ChartView.period, 'This period'),
              SegmentItem(_ChartView.history, history.length > 2 ? 'Last ${history.length}' : 'Compare'),
            ],
            selected: _view,
            onChanged: (v) => setState(() => _view = v),
          ),
          const SizedBox(height: Space.x3),
          AnimatedSwitcher(
            duration: context.motion.normal,
            child: KeyedSubtree(
              key: ValueKey(showHistory ? 'h$_bar' : 'p${widget.day}'),
              child: showHistory ? _historyReadout(context, history) : _periodReadout(context),
            ),
          ),
          const SizedBox(height: Space.x2),
          AnimatedSwitcher(
            duration: context.motion.normal,
            switchInCurve: Curves2.emphasized,
            child: showHistory
                ? HistoryBars(
                    key: const ValueKey('history'),
                    points: history,
                    color: c.primary,
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
          const SizedBox(height: Space.x1),
          Text(
            showHistory
                ? 'Line = limit · grey = your average before · tap a bar'
                : 'Dashed diagonal = even pace · tap or drag to read a day',
            style: t.micro,
          ),
        ],
      ),
    );
  }

  Widget _periodReadout(BuildContext context) {
    final c = context.colors;
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
        note: '${budgetMoney(context, total)} by then · ${formatBps(total.ratioBps(u.budget.limit) ?? 0, decimals: 0)} of limit',
      );
    }
    final last = b.todayIndex.clamp(0, cum.length - 1);
    final plan = u.budget.limit.scale(last + 1, cum.length);
    final now = Money.fromPaise(cum.isEmpty ? 0 : cum[last]);
    final ahead = now - plan;
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
    final c = context.colors;
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
      noteColor: over > 0 ? c.warning : c.positive,
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
    final t = context.text;
    final c = context.colors;
    return Semantics(
      liveRegion: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title.toUpperCase(), style: t.eyebrow),
                Text(value, style: t.amountMedium),
              ],
            ),
          ),
          Flexible(
            child: Text(
              note,
              textAlign: TextAlign.end,
              style: t.caption.copyWith(color: noteColor ?? c.textSecondary, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
