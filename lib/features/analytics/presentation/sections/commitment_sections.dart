import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../app/di/data_providers.dart';
import '../../../../app/router/routes.dart';
import '../../../../core/money/money.dart';
import '../../../../core/money/money_format.dart';
import '../../../../core/time/dates.dart';
import '../../../../design_system/design_system.dart';
import '../../../../shared/presentation/category_icons.dart';
import '../../../budgets/domain/budget.dart';
import '../../../goals/domain/goal.dart';
import '../../../loans/domain/loan_calculator.dart';
import '../../application/analytics_providers.dart';
import '../insight_charts.dart';
import '../insight_widgets.dart';

// ---------------------------------------------------------------------------
// Budgets
// ---------------------------------------------------------------------------

/// Budgets: how much of the budget is used against how much of the month
/// has passed, a safe daily amount, and each budget with a "today" tick.
List<Widget> budgetsSection(BuildContext context, InsightsData data) {
  if (data.budgets.isEmpty) {
    return [
      InsightChartCard(
        icon: LucideIcons.target,
        accent: context.colors.accentBudgets,
        title: 'No budgets set yet',
        subtitle: 'A budget is a monthly limit for a category, like ₹8,000 for food.',
        child: InsightNoData(
          message: 'Set a budget to see whether you are spending on pace.',
          icon: LucideIcons.target,
          action: FinnButton(
            label: 'Create a budget',
            icon: LucideIcons.plus,
            variant: FinnButtonVariant.outline,
            onPressed: () => context.push(AppRoutes.newBudget),
          ),
        ),
      ),
    ];
  }
  return [
    _PaceCard(data: data),
    _BudgetListCard(data: data),
  ];
}

class _PaceCard extends StatelessWidget {
  const _PaceCard({required this.data});
  final InsightsData data;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final limit = data.budgetLimitTotal;
    final used = data.budgetSpentTotal.ratioBps(limit);
    final elapsed = data.budgetElapsedBps;
    final safe = data.budgetSafeDaily;
    String m(Money x) => moneyText(context, x);
    if (used == null) {
      return TakeawayCard(icon: LucideIcons.pause, title: 'All budgets are paused', body: 'Resume a budget to track it here.');
    }
    final over = used >= 10000;
    final ahead = !over && used > elapsed + 500;
    final color = over ? c.negative : (ahead ? c.warning : c.positive);
    final title = over ? 'You have gone over your budgets' : (ahead ? 'Spending faster than planned' : 'You are on pace');
    return FinnCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              RingGauge(
                value: used / 10000,
                marker: elapsed / 10000,
                color: color,
                size: 116,
                stroke: 12,
                semanticLabel: '${formatBps(used, decimals: 0)} of budget used, ${formatBps(elapsed, decimals: 0)} of the period passed',
                center: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(formatBps(used, decimals: 0), style: t.amountMedium),
                    Text('USED', style: t.eyebrow),
                  ],
                ),
              ),
              const SizedBox(width: Space.x4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(header: true, child: Text(title, style: t.sectionTitle.copyWith(color: color))),
                    const SizedBox(height: Space.x1),
                    Text(
                      'You have used ${formatBps(used, decimals: 0)} of ${m(limit)}, and '
                      '${formatBps(elapsed, decimals: 0)} of the month has passed.',
                      style: t.caption.copyWith(color: c.textSecondary, height: 1.4),
                    ),
                    const SizedBox(height: Space.x2),
                    Row(
                      children: [
                        Container(width: 2, height: 10, color: c.textPrimary),
                        const SizedBox(width: Space.x1_5),
                        Flexible(
                          child: Text('Tick = today', style: t.micro.copyWith(color: c.textTertiary, fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (safe != null) ...[
            const SizedBox(height: Space.x4),
            Container(
              padding: const EdgeInsets.all(Space.x3),
              decoration: BoxDecoration(
                color: (over ? FinnTone.negative : FinnTone.positive).soft(c),
                borderRadius: Radii.rLg,
              ),
              child: MergeSemantics(
                child: Row(
                  children: [
                    Icon(over ? LucideIcons.circleAlert : LucideIcons.wallet, size: 18, color: over ? c.negative : c.positive),
                    const SizedBox(width: Space.x2),
                    Expanded(
                      child: Text(
                        over
                            ? 'Nothing left in your budgets for the next ${data.budgetDaysLeft} days.'
                            : 'Safe to spend: ${m(safe)} a day for the next ${data.budgetDaysLeft} days.',
                        style: t.label.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _BudgetListCard extends StatelessWidget {
  const _BudgetListCard({required this.data});
  final InsightsData data;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final list = List.of(data.budgets)..sort((a, b) => b.utilizationBps.compareTo(a.utilizationBps));
    final p = data.budgetPeriod;
    return InsightChartCard(
      icon: LucideIcons.target,
      accent: c.accentBudgets,
      title: data.budgetHeadline,
      subtitle: '${DateFormats.dayMonth.format(p.start)} – ${DateFormats.dayMonth.format(p.end)}. '
          'A bar past the tick means that budget is running ahead of the month.',
      howCalculated: 'Each budget compares actual spending in its category with its limit for the current period. '
          'Upcoming subscription charges are shown on the budget itself but are not counted as spent. '
          '"Near limit" starts at the warning level you set on each budget.',
      child: Column(
        children: [
          for (final u in list.take(8)) _BudgetRow(usage: u, marker: data.budgetElapsedBps / 10000),
          if (list.length > 8)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => context.go(AppRoutes.budgets),
                child: Text('See all ${list.length} budgets', style: t.label.copyWith(fontWeight: FontWeight.w800)),
              ),
            ),
        ],
      ),
    );
  }
}

class _BudgetRow extends ConsumerWidget {
  const _BudgetRow({required this.usage, required this.marker});
  final BudgetUsage usage;
  final double marker;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final t = context.text;
    final cat = ref.watch(categoryProvider(usage.budget.categoryId));
    final (Color color, IconData icon) = switch (usage.health) {
      BudgetHealth.healthy => (c.positive, LucideIcons.circleCheck),
      BudgetHealth.warning => (c.warning, LucideIcons.triangleAlert),
      BudgetHealth.breached => (c.negative, LucideIcons.circleAlert),
      BudgetHealth.paused => (c.textTertiary, LucideIcons.pause),
    };
    final left = usage.remaining;
    return InkWell(
      borderRadius: Radii.rLg,
      onTap: () => context.push(AppRoutes.budget(usage.budget.id)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.x2),
        child: MergeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  CategoryAvatar(category: cat, size: 32),
                  const SizedBox(width: Space.x3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(cat?.name ?? 'Budget', style: t.bodyStrong, maxLines: 1, overflow: TextOverflow.ellipsis),
                        Text(
                          left.isNegative
                              ? '${moneyText(context, left.abs())} over the limit'
                              : '${moneyText(context, left)} left of ${moneyText(context, usage.budget.limit)}',
                          style: t.micro.copyWith(color: left.isNegative ? c.negative : c.textSecondary, fontWeight: FontWeight.w700),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  StatusPill(label: usage.health.label, color: color, icon: icon),
                ],
              ),
              const SizedBox(height: Space.x2),
              RelativeBar(
                value: usage.utilizationBps / 10000,
                color: color,
                height: 8,
                marker: usage.health == BudgetHealth.paused ? null : marker,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Savings
// ---------------------------------------------------------------------------

String _span(int points) => points <= 1 ? 'this month' : 'in ${points - 1} months';

/// Savings: money set aside, its growth and average pace, and each goal.
List<Widget> savingsSection(BuildContext context, InsightsData data) {
  final c = context.colors;
  final empty = data.savings.every((p) => p.value.isZero);
  if (empty) {
    return [
      InsightChartCard(
        icon: LucideIcons.piggyBank,
        accent: c.accentGoals,
        title: 'No savings set aside yet',
        subtitle: 'Money moved into goals or your emergency fund shows up here.',
        child: InsightNoData(
          message: 'Start a goal — even a small one — and watch it grow here.',
          icon: LucideIcons.piggyBank,
          action: FinnButton(
            label: 'Start a goal',
            icon: LucideIcons.plus,
            variant: FinnButtonVariant.outline,
            onPressed: () => context.push(AppRoutes.newGoal),
          ),
        ),
      ),
    ];
  }
  final change = data.savingsChange;
  return [
    KpiStrip(items: [
      Kpi(label: 'Set aside now', value: AmountText(data.savings.last.value, decimals: DecimalDisplay.none, color: c.accentGoals)),
      Kpi(
        label: 'Change',
        value: AmountText(change, decimals: DecimalDisplay.none, sign: SignDisplay.always, colorize: true),
        caption: _span(data.savings.length),
      ),
      Kpi(
        label: 'Avg per month',
        value: AmountText(data.avgMonthlySavingsChange, decimals: DecimalDisplay.none, sign: SignDisplay.always),
        caption: 'added on average',
      ),
    ]),
    InsightChartCard(
      icon: LucideIcons.trendingUp,
      accent: c.accentGoals,
      title: data.savingsHeadline((x) => moneyText(context, x)),
      subtitle: 'Money set aside for goals and your emergency fund at each month end. Touch a point for the amount.',
      howCalculated: 'Set aside = all contributions minus withdrawals to goals and the emergency fund up to '
          'each month end. This money is still part of your cash balance — it is set aside, not spent.',
      child: TrendLineChart(points: data.savings, color: c.accentGoals, seriesLabel: 'Savings'),
    ),
    if (data.goals.isNotEmpty) _GoalsCard(goals: data.goals),
  ];
}

class _GoalsCard extends StatelessWidget {
  const _GoalsCard({required this.goals});
  final List<GoalProgress> goals;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final list = List.of(goals)..sort((a, b) => a.isAchieved == b.isAchieved ? b.progressBps.compareTo(a.progressBps) : (a.isAchieved ? 1 : -1));
    final reached = goals.where((g) => g.isAchieved).length;
    return InsightChartCard(
      icon: LucideIcons.flag,
      accent: c.accentGoals,
      title: reached == 0 ? 'Your goals' : '$reached of ${goals.length} goals reached',
      subtitle: 'Each ring fills as you save towards the goal. Tap one to add money.',
      child: Column(
        children: [
          for (final g in list.take(6))
            InkWell(
              borderRadius: Radii.rLg,
              onTap: () => context.push(AppRoutes.goal(g.goal.id)),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: Space.x2),
                child: Semantics(
                  label: '${g.goal.name}, ${formatBps(g.progressBps, decimals: 0)} saved',
                  child: Row(
                    children: [
                      RingGauge(
                        value: g.progressBps / 10000,
                        color: c.chartSeries[g.goal.colorIndex % c.chartSeries.length],
                        size: 46,
                        stroke: 5,
                        center: Text(formatBps(g.progressBps, decimals: 0), style: t.micro.copyWith(fontWeight: FontWeight.w900)),
                      ),
                      const SizedBox(width: Space.x3),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(g.goal.name, style: t.bodyStrong, maxLines: 1, overflow: TextOverflow.ellipsis),
                            Text(
                              g.isAchieved
                                  ? 'Reached — well done!'
                                  : '${moneyText(context, g.saved)} of ${moneyText(context, g.goal.target)} · '
                                      '${moneyText(context, g.remaining)} to go',
                              style: t.micro.copyWith(color: g.isAchieved ? c.positive : c.textSecondary, fontWeight: FontWeight.w700),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      Icon(LucideIcons.chevronRight, size: 16, color: c.textTertiary),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Loans
// ---------------------------------------------------------------------------

/// Loans: what is still owed, how fast it is going down, and when it could
/// be cleared at that pace.
List<Widget> loansSection(BuildContext context, InsightsData data) {
  final c = context.colors;
  final empty = data.debt.every((p) => p.value.isZero);
  if (empty) {
    return [
      TakeawayCard(
        icon: LucideIcons.partyPopper,
        tone: FinnTone.positive,
        title: 'You have no borrowed loans',
        body: 'Nothing to pay back. If you take a loan, its payoff progress shows up here.',
      ),
    ];
  }
  String m(Money x) => moneyText(context, x);
  final months = data.monthsToDebtFree;
  final repaid = data.debtRepaid;
  return [
    TakeawayCard(
      icon: months != null ? LucideIcons.flagTriangleRight : LucideIcons.landmark,
      tone: months != null ? FinnTone.positive : (repaid.isNegative ? FinnTone.warning : FinnTone.info),
      title: months != null
          ? 'At this pace you could be debt-free in about $months month${months == 1 ? '' : 's'}'
          : repaid.isNegative
              ? 'Your debt went up by ${m(repaid.abs())}'
              : 'You still owe ${m(data.debt.last.value)}',
      body: months != null
          ? 'Around ${monthLong(data.today.monthKey.shift(months))}, paying down about ${m(data.avgMonthlyDebtRepaid)} a month.'
          : 'Regular EMIs bring this down month by month.',
    ),
    KpiStrip(items: [
      Kpi(label: 'Still owed', value: AmountText(data.debt.last.value, decimals: DecimalDisplay.none, color: c.accentLoans)),
      Kpi(
        label: 'Paid off',
        value: AmountText(repaid.isNegative ? Money.zero : repaid, decimals: DecimalDisplay.none, color: c.positive),
        caption: _span(data.debt.length),
      ),
      Kpi(
        label: 'Avg per month',
        value: AmountText(data.avgMonthlyDebtRepaid.isNegative ? Money.zero : data.avgMonthlyDebtRepaid, decimals: DecimalDisplay.none),
        caption: 'principal repaid',
      ),
    ]),
    InsightChartCard(
      icon: LucideIcons.trendingDown,
      accent: c.accentLoans,
      title: data.debtHeadline((x) => moneyText(context, x)),
      subtitle: 'What you still owe at each month end. A line going down is good news.',
      howCalculated: 'Outstanding debt = original principal minus principal repaid on loans you borrowed, measured '
          'at each month end (today for the current month). Interest paid does not reduce debt. Loans you gave '
          'to others are not included.',
      child: TrendLineChart(points: data.debt, color: c.accentLoans, seriesLabel: 'Debt'),
    ),
    if (data.loans.isNotEmpty) _LoansCard(loans: data.loans),
  ];
}

class _LoansCard extends StatelessWidget {
  const _LoansCard({required this.loans});
  final List<LoanState> loans;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    return InsightChartCard(
      icon: LucideIcons.landmark,
      accent: c.accentLoans,
      title: loans.length == 1 ? 'Your loan' : 'Your ${loans.length} loans',
      subtitle: 'The bar shows how much of each loan you have paid back.',
      child: Column(
        children: [
          for (final l in loans)
            InkWell(
              borderRadius: Radii.rLg,
              onTap: () => context.push(AppRoutes.loan(l.loan.id)),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: Space.x2),
                child: MergeSemantics(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(l.loan.name, style: t.bodyStrong, maxLines: 1, overflow: TextOverflow.ellipsis),
                                Text(
                                  '${formatBps(l.principalRepaid.ratioBps(l.loan.principal) ?? 0, decimals: 0)} paid back · '
                                  '${moneyText(context, l.outstanding)} left',
                                  style: t.micro.copyWith(color: c.textSecondary, fontWeight: FontWeight.w700),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          if (l.isOverdue)
                            StatusPill(label: 'Overdue', color: c.negative, icon: LucideIcons.circleAlert)
                          else
                            Icon(LucideIcons.chevronRight, size: 16, color: c.textTertiary),
                        ],
                      ),
                      const SizedBox(height: Space.x2),
                      RelativeBar(
                        value: (l.principalRepaid.ratioBps(l.loan.principal) ?? 0) / 10000,
                        color: c.positive,
                        height: 8,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Subscriptions
// ---------------------------------------------------------------------------

/// Subscriptions: what recurring payments cost per month, year and day,
/// their share of income, and the biggest ones.
List<Widget> subscriptionsSection(BuildContext context, InsightsData data) {
  final c = context.colors;
  final t = context.text;
  if (data.activeSubscriptionCount == 0) {
    return [
      InsightChartCard(
        icon: LucideIcons.repeat,
        accent: c.accentSubscriptions,
        title: 'No active subscriptions',
        subtitle: 'Netflix, gym, phone plans — anything you pay again and again.',
        child: InsightNoData(
          message: 'Add subscriptions to see what they cost you each month and year.',
          icon: LucideIcons.repeat,
          action: FinnButton(
            label: 'Add a subscription',
            icon: LucideIcons.plus,
            variant: FinnButtonVariant.outline,
            onPressed: () => context.push(AppRoutes.newSubscription),
          ),
        ),
      ),
    ];
  }
  String m(Money x) => moneyText(context, x);
  final income = data.avgMonthlyIncome;
  final share = data.subscriptionsMonthly.ratioBps(income);
  final perDay = data.subscriptionsMonthly.scale(12, 365);
  final maxMonthly = data.topSubscriptions.isEmpty ? Money.zero : data.topSubscriptions.first.monthlyEquivalent;
  return [
    FinnCard(
      child: Row(
        children: [
          RingGauge(
            value: (share ?? 0) / 10000,
            color: share != null && share > 1000 ? c.warning : c.accentSubscriptions,
            size: 108,
            stroke: 11,
            semanticLabel: share == null ? null : 'Subscriptions take ${formatBps(share)} of a typical month\'s income',
            center: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(share == null ? '—' : formatBps(share, decimals: 0), style: t.amountMedium),
                Text('OF INCOME', style: t.eyebrow),
              ],
            ),
          ),
          const SizedBox(width: Space.x4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(data.subscriptionHeadline(m), style: t.sectionTitle),
                ),
                const SizedBox(height: Space.x2),
                LegendValue(color: c.accentSubscriptions, label: 'Per year', value: m(data.subscriptionsAnnual)),
                const SizedBox(height: Space.x1),
                LegendValue(color: c.accentSubscriptions.withValues(alpha: 0.5), label: 'Per day', value: m(perDay)),
                const SizedBox(height: Space.x1),
                Text(
                  share != null && share > 1000
                      ? 'More than 10% of income — worth a review.'
                      : '${data.activeSubscriptionCount} active subscription${data.activeSubscriptionCount == 1 ? '' : 's'}',
                  style: t.micro.copyWith(color: share != null && share > 1000 ? c.warning : c.textSecondary, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
    InsightChartCard(
      icon: LucideIcons.repeat,
      accent: c.accentSubscriptions,
      title: 'Biggest recurring costs',
      subtitle: 'Converted to a monthly amount so you can compare them fairly.',
      howCalculated: 'Each active subscription is converted to a monthly amount (yearly ÷ 12, quarterly ÷ 3, weekly × 52 ÷ 12). '
          'These are commitments, not spending — a charge becomes spending only when you mark it paid. '
          'The share of income uses your average monthly income.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final s in data.topSubscriptions)
            InkWell(
              borderRadius: Radii.rMd,
              onTap: () => context.push(AppRoutes.subscription(s.id)),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: Space.x2),
                child: MergeSemantics(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(s.name, style: t.bodyStrong, maxLines: 1, overflow: TextOverflow.ellipsis),
                                Text(
                                  '${moneyText(context, s.amount)} ${s.frequency.label.toLowerCase()}',
                                  style: t.micro.copyWith(color: c.textSecondary),
                                ),
                              ],
                            ),
                          ),
                          AmountText(s.monthlyEquivalent, style: t.amountSmall, decimals: DecimalDisplay.none),
                          Text(' /mo', style: t.micro.copyWith(color: c.textTertiary)),
                        ],
                      ),
                      const SizedBox(height: Space.x1_5),
                      RelativeBar(
                        value: maxMonthly.isZero ? 0 : s.monthlyEquivalent.toDouble() / maxMonthly.toDouble(),
                        color: c.accentSubscriptions,
                        height: 6,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (data.activeSubscriptionCount > data.topSubscriptions.length)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => context.push(AppRoutes.subscriptions),
                child: Text('See all ${data.activeSubscriptionCount}', style: t.label.copyWith(fontWeight: FontWeight.w800)),
              ),
            ),
        ],
      ),
    ),
  ];
}
