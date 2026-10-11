import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/di/core_providers.dart';
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
import '../application/budget_actions.dart';
import '../application/budget_history.dart';
import '../domain/budget.dart';
import 'budget_widgets.dart';

/// One budget: progress, numbers, trend and contributing transactions.
class BudgetDetailScreen extends ConsumerWidget {
  const BudgetDetailScreen({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usage = ref.watch(budgetUsageProvider(id));
    final categoryName = usage.value == null ? null : ref.watch(categoryProvider(usage.value!.budget.categoryId))?.name;
    return Scaffold(
      appBar: AppBar(
        title: Text(categoryName == null ? 'Budget' : '$categoryName budget'),
        actions: [
          if (usage.value != null)
            FinnIconButton(
              icon: LucideIcons.pencil,
              tooltip: 'Edit budget',
              onPressed: () => context.push(AppRoutes.editBudget(id)),
            ),
          const SizedBox(width: Space.x2),
        ],
      ),
      body: AsyncView<BudgetUsage?>(
        value: usage,
        loading: const SkeletonPulse(
          child: Padding(
            padding: EdgeInsets.all(Space.gutter),
            child: Column(children: [CardSkeleton(height: 180), SizedBox(height: Space.x4), CardSkeleton(height: 240)]),
          ),
        ),
        builder: (context, u) => u == null
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
            : _DetailBody(usage: u),
      ),
    );
  }
}

class _DetailBody extends ConsumerWidget {
  const _DetailBody({required this.usage});

  final BudgetUsage usage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final u = usage;
    final c = context.colors;
    final ids = u.transactionIds;
    Widget box(Widget child, {double top = Space.x4}) => SliverToBoxAdapter(
          child: ResponsiveCenter(
            padding: EdgeInsets.fromLTRB(Space.gutter, top, Space.gutter, 0),
            child: child,
          ),
        );
    return CustomScrollView(
      key: PageStorageKey('budget-${u.budget.id}'),
      slivers: [
        box(StaggeredEntrance(child: _HeaderCard(usage: u)), top: Space.x2),
        box(StaggeredEntrance(index: 1, child: _NumbersCard(usage: u))),
        box(StaggeredEntrance(index: 2, child: _TrendCard(budgetId: u.budget.id))),
        box(StaggeredEntrance(index: 3, child: _ActionsRow(usage: u))),
        box(
          SectionHeader(
            icon: LucideIcons.receipt,
            title: 'Spending this period',
            subtitle: ids.isEmpty ? null : '${ids.length} transaction${ids.length == 1 ? '' : 's'}',
            tileColor: c.accentTransactions,
          ),
          top: Space.section,
        ),
        if (ids.isEmpty)
          box(
            Text(
              'No spending in this category yet this period.',
              style: context.text.body.copyWith(color: c.textSecondary),
            ),
            top: Space.x3,
          )
        else
          SliverList.builder(
            itemCount: ids.length,
            itemBuilder: (context, i) => ResponsiveCenter(
              key: ValueKey(ids[i]),
              padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
              child: _TransactionById(id: ids[i]),
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: Space.x12)),
      ],
    );
  }
}

class _TransactionById extends ConsumerWidget {
  const _TransactionById({required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tx = ref.watch(transactionByIdProvider(id)).value;
    if (tx == null) return const SizedBox.shrink();
    return TransactionRow(transaction: tx, showDate: true);
  }
}

class _HeaderCard extends ConsumerWidget {
  const _HeaderCard({required this.usage});

  final BudgetUsage usage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final u = usage;
    final c = context.colors;
    final t = context.text;
    final category = ref.watch(categoryProvider(u.budget.categoryId));
    final color = u.health.color(c);
    return FinnCard(
      padding: const EdgeInsets.all(Space.x5),
      child: Row(
        children: [
          ProgressRing(
            value: u.utilization,
            size: 116,
            strokeWidth: 10,
            color: color,
            semanticsLabel: 'Budget used',
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(formatBps(u.utilizationBps, decimals: 0), style: t.amountLarge),
                Text('used', style: t.caption),
              ],
            ),
          ),
          const SizedBox(width: Space.x5),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CategoryAvatar(category: category, size: 28),
                    const SizedBox(width: Space.x2),
                    Flexible(child: BudgetHealthPill(health: u.health)),
                  ],
                ),
                const SizedBox(height: Space.x3),
                Text('SPENT', style: t.eyebrow),
                AnimatedAmount(
                  u.spent,
                  style: t.amountLarge.copyWith(color: u.isOver ? c.negative : c.textPrimary),
                  fit: true,
                ),
                Text('of ${budgetMoney(context, u.budget.limit)} limit', style: t.caption),
                const SizedBox(height: Space.x2),
                BudgetRemainingLabel(usage: u),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NumbersCard extends ConsumerWidget {
  const _NumbersCard({required this.usage});

  final BudgetUsage usage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final u = usage;
    final c = context.colors;
    final t = context.text;
    final today = ref.watch(todayProvider);
    final days = daysLeftIn(u.period, today);
    final afterCommitted = u.remainingAfterCommitted;
    Widget money(Money m, {Color? color, SignDisplay sign = SignDisplay.auto}) => AmountText(
          m,
          sign: sign,
          style: t.bodyStrong.copyWith(fontWeight: FontWeight.w800, color: color),
        );
    return FinnCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(LucideIcons.calendarRange, size: 16, color: c.textSecondary),
              const SizedBox(width: Space.x2),
              Expanded(
                child: Text(
                  '${u.budget.periodType.label} · ${periodLabel(u.period)}',
                  style: t.bodyStrong,
                ),
              ),
              Text(daysLeftLabel(days), style: t.caption),
            ],
          ),
          const SizedBox(height: Space.x2),
          Text(
            u.budget.isPaused ? 'Paused — warnings and alerts are off.' : pacingHint(u),
            style: t.caption,
          ),
          const SizedBox(height: Space.x2),
          const FinnDivider(),
          KeyValueRow(label: 'Limit', valueWidget: money(u.budget.limit)),
          KeyValueRow(label: 'Spent so far', valueWidget: money(u.spent, color: u.isOver ? c.negative : null)),
          if (u.committed.isPositive)
            KeyValueRow(
              label: 'Expected (subscriptions)',
              valueWidget: money(u.committed, sign: SignDisplay.always, color: c.attention),
            ),
          KeyValueRow(
            label: u.isOver ? 'Over by' : 'Remaining',
            valueWidget: money(u.isOver ? -u.remaining : u.remaining, color: u.isOver ? c.negative : c.positive),
          ),
          if (u.committed.isPositive)
            KeyValueRow(
              label: 'Left after expected',
              valueWidget: money(afterCommitted, color: afterCommitted.isNegative ? c.negative : null),
            ),
          KeyValueRow(label: 'Warn me at', value: formatBps(u.budget.warningThresholdBps, decimals: 0)),
          if (u.committed.isPositive) ...[
            const SizedBox(height: Space.x1),
            Text(
              'Expected charges are upcoming subscription renewals in this category. '
              'They are not counted as spent until they are paid.',
              style: t.caption,
            ),
          ],
          if (u.budget.note != null) ...[
            const SizedBox(height: Space.x3),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(LucideIcons.info, size: 14, color: c.textSecondary),
                const SizedBox(width: Space.x2),
                Expanded(child: Text(u.budget.note!, style: t.body.copyWith(color: c.textSecondary))),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Spending trend vs previous periods (bar chart).
class _TrendCard extends ConsumerWidget {
  const _TrendCard({required this.budgetId});

  final String budgetId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final t = context.text;
    final points = ref.watch(budgetHistoryProvider(budgetId)).value ?? const <BudgetPeriodPoint>[];
    if (points.isEmpty) return const SizedBox.shrink();
    final hidden = AmountVisibility.hiddenOf(context);
    final limit = points.last.limit.toDouble();
    final maxSpent = points.map((p) => p.spent.toDouble()).fold<double>(0, (a, b) => a > b ? a : b);
    final maxY = (maxSpent > limit ? maxSpent : limit) * 1.15;
    final previousCount = points.where((p) => !p.isCurrent).length;
    final avg = averageSpentBefore(points);
    String label(BudgetPeriodPoint p) =>
        points.length > 2 ? DateFormats.shortMonth.format(p.period.start) : (p.isCurrent ? 'This period' : 'Before');
    final summary = points
        .map((p) => '${label(p)}: ${hidden ? 'hidden' : p.spent.format()}${p.isOver ? ' (over limit)' : ''}')
        .join(', ');
    return FinnCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Spending trend', style: t.sectionTitle),
          const SizedBox(height: Space.x1),
          Text(
            avg == null
                ? 'Compared with your limit'
                : 'Previous ${previousCount == 1 ? 'period' : '$previousCount periods'} averaged '
                    '${budgetMoney(context, avg)}',
            style: t.caption,
          ),
          const SizedBox(height: Space.x4),
          Semantics(
            label: 'Spending by period. $summary',
            excludeSemantics: true,
            child: SizedBox(
              height: 160,
              child: BarChart(
                BarChartData(
                  maxY: maxY <= 0 ? 1 : maxY,
                  alignment: BarChartAlignment.spaceAround,
                  gridData: const FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                  barTouchData: BarTouchData(
                    enabled: !hidden,
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipColor: (_) => c.textPrimary,
                      getTooltipItem: (group, _, rod, _) => BarTooltipItem(
                        points[group.x].spent.format(),
                        t.label.copyWith(color: c.surface, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                  extraLinesData: ExtraLinesData(horizontalLines: [
                    HorizontalLine(
                      y: limit,
                      color: c.textTertiary,
                      strokeWidth: 1.5,
                      dashArray: const [6, 4],
                      label: HorizontalLineLabel(
                        show: true,
                        alignment: Alignment.topRight,
                        style: t.micro.copyWith(color: c.textSecondary),
                        labelResolver: (_) => 'Limit',
                      ),
                    ),
                  ]),
                  titlesData: FlTitlesData(
                    leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 24,
                        getTitlesWidget: (value, meta) {
                          final p = points[value.toInt()];
                          return SideTitleWidget(
                            meta: meta,
                            child: Text(
                              label(p),
                              style: t.micro.copyWith(
                                color: p.isCurrent ? c.textPrimary : c.textSecondary,
                                fontWeight: p.isCurrent ? FontWeight.w900 : FontWeight.w600,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  barGroups: [
                    for (var i = 0; i < points.length; i++)
                      BarChartGroupData(x: i, barRods: [
                        BarChartRodData(
                          toY: points[i].spent.toDouble(),
                          width: points.length > 2 ? 18 : 36,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(Radii.sm)),
                          color: points[i].isOver
                              ? c.negative
                              : (points[i].isCurrent ? c.primary : c.primary.withValues(alpha: 0.35)),
                        ),
                      ]),
                  ],
                ),
                duration: context.motion.normal,
              ),
            ),
          ),
          const SizedBox(height: Space.x2),
          Row(
            children: [
              _Legend(color: c.primary, label: 'Within limit'),
              const SizedBox(width: Space.x4),
              _Legend(color: c.negative, label: 'Over limit'),
            ],
          ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: Radii.rSm)),
          const SizedBox(width: Space.x1_5),
          Text(label, style: context.text.caption),
        ],
      );
}

class _ActionsRow extends ConsumerStatefulWidget {
  const _ActionsRow({required this.usage});

  final BudgetUsage usage;

  @override
  ConsumerState<_ActionsRow> createState() => _ActionsRowState();
}

class _ActionsRowState extends ConsumerState<_ActionsRow> {
  bool _busy = false;

  Future<void> _togglePause() async {
    final b = widget.usage.budget;
    setState(() => _busy = true);
    await runAction(
      context,
      ref,
      action: const SetBudgetPausedAction(),
      input: SetBudgetPausedInput(id: b.id, paused: !b.isPaused),
      idempotencyKey: newIdempotencyKey(),
    );
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _delete() async {
    final b = widget.usage.budget;
    setState(() => _busy = true);
    final deleted = await runAction(
      context,
      ref,
      action: const DeleteBudgetAction(),
      input: BudgetIdInput(id: b.id),
      idempotencyKey: newIdempotencyKey(),
      successTitle: 'Budget deleted',
      successSubtitle: 'Your transactions are unchanged.',
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (deleted != null) context.go(AppRoutes.budgets);
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.usage.budget;
    return Wrap(
      spacing: Space.x2,
      runSpacing: Space.x2,
      children: [
        FinnButton(
          label: 'Edit',
          icon: LucideIcons.pencil,
          variant: FinnButtonVariant.outline,
          size: FinnButtonSize.sm,
          onPressed: _busy ? null : () => context.push(AppRoutes.editBudget(b.id)),
        ),
        FinnButton(
          label: b.isPaused ? 'Resume' : 'Pause',
          icon: b.isPaused ? LucideIcons.play : LucideIcons.pause,
          variant: FinnButtonVariant.outline,
          size: FinnButtonSize.sm,
          onPressed: _busy ? null : _togglePause,
        ),
        FinnButton(
          label: 'Delete',
          icon: LucideIcons.trash2,
          variant: FinnButtonVariant.ghost,
          size: FinnButtonSize.sm,
          onPressed: _busy ? null : _delete,
        ),
      ],
    );
  }
}
