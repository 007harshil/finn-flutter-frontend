import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../app/di/data_providers.dart';
import '../../../../app/router/routes.dart';
import '../../../../core/money/money.dart';
import '../../../../core/money/money_format.dart';
import '../../../../core/time/dates.dart';
import '../../../../kit/kit.dart';
import '../../../budgets/domain/budget.dart';
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
      LedgerEmpty(
        icon: LucideIcons.target,
        title: 'No budgets set yet',
        message: 'A budget is a monthly limit for a category, like ₹8,000 for food. '
            'Set one to see whether you are spending on pace.',
        actionLabel: 'Create a budget',
        onAction: () => context.push(AppRoutes.newBudget),
      ),
    ];
  }
  return [
    _Pace(data: data),
    _BudgetList(data: data),
  ];
}

class _Pace extends StatelessWidget {
  const _Pace({required this.data});
  final InsightsData data;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final t = context.type;
    final limit = data.budgetLimitTotal;
    final used = data.budgetSpentTotal.ratioBps(limit);
    final elapsed = data.budgetElapsedBps;
    final safe = data.budgetSafeDaily;
    String m(Money x) => moneyText(context, x);
    if (used == null) {
      return const LedgerEmpty(
        icon: LucideIcons.pause,
        title: 'All budgets are paused',
        message: 'Resume a budget to track it here.',
      );
    }
    final over = used >= 10000;
    final ahead = !over && used > elapsed + 500;
    final verdict = over ? 'You have gone over your budgets.' : (ahead ? 'Spending faster than planned.' : 'You are on pace.');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InsightLead(
          label: 'Budget used',
          value: Text(formatBps(used, decimals: 0), style: t.figureXL.copyWith(color: over ? c.red : null)),
          below: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LedgerBar(
                value: used / 10000,
                marker: elapsed / 10000,
                color: over ? c.red : (ahead ? c.amber : c.green),
                semanticLabel: '${formatBps(used, decimals: 0)} of budget used, '
                    '${formatBps(elapsed, decimals: 0)} of the period passed',
              ),
              const SizedBox(height: Sp.xs),
              Text('Tick = today', style: t.small),
            ],
          ),
        ),
        const SizedBox(height: Sp.md),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '$verdict ',
                style: t.bodyStrong.copyWith(color: over ? c.red : (ahead ? c.amber : c.ink)),
              ),
              TextSpan(
                text: 'You have used ${formatBps(used, decimals: 0)} of ${m(limit)}, and '
                    '${formatBps(elapsed, decimals: 0)} of the month has passed.',
              ),
            ],
          ),
          style: t.label,
        ),
        if (safe != null) ...[
          const SizedBox(height: Sp.lg),
          LedgerNote(
            icon: over ? LucideIcons.circleAlert : LucideIcons.wallet,
            tone: over ? NoteTone.alert : NoteTone.neutral,
            text: over
                ? 'Nothing left in your budgets for the next ${data.budgetDaysLeft} days.'
                : 'Safe to spend: ${m(safe)} a day for the next ${data.budgetDaysLeft} days.',
          ),
        ],
      ],
    );
  }
}

class _BudgetList extends StatelessWidget {
  const _BudgetList({required this.data});
  final InsightsData data;

  @override
  Widget build(BuildContext context) {
    final list = List.of(data.budgets)..sort((a, b) => b.utilizationBps.compareTo(a.utilizationBps));
    final p = data.budgetPeriod;
    return InsightListSection(
      title: 'Each budget',
      note: '${data.budgetHeadline}, ${DateFormats.dayMonth.format(p.start)} – ${DateFormats.dayMonth.format(p.end)}.',
      rows: [for (final u in list.take(8)) _BudgetRow(usage: u, marker: data.budgetElapsedBps / 10000)],
      actionLabel: list.length > 8 ? 'See all ${list.length} budgets' : null,
      onAction: list.length > 8 ? () => context.go(AppRoutes.budgets) : null,
      footer: const HowCalculated(
        text: 'Each budget compares actual spending in its category with its limit for the current period. '
            'A bar past the tick means that budget is running ahead of the month. '
            'Upcoming subscription charges are shown on the budget itself but are not counted as spent. '
            '"Near limit" starts at the warning level you set on each budget.',
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
    final c = context.ink;
    final t = context.type;
    final cat = ref.watch(categoryProvider(usage.budget.categoryId));
    final name = cat?.name ?? 'Budget';
    final paused = usage.health == BudgetHealth.paused;
    final color = switch (usage.health) {
      BudgetHealth.healthy => c.green,
      BudgetHealth.warning => c.amber,
      BudgetHealth.breached => c.red,
      BudgetHealth.paused => c.inkFaint,
    };
    final left = usage.remaining;
    final sub = left.isNegative
        ? '${moneyText(context, left.abs())} over the limit'
        : '${moneyText(context, left)} left of ${moneyText(context, usage.budget.limit)}';
    final row = LedgerRow(
      leading: CategoryMark(category: cat),
      title: name,
      subtitle: sub,
      subtitleColor: left.isNegative ? c.red : null,
      trailing: Text(
        usage.health.label,
        style: t.small.copyWith(
          color: switch (usage.health) {
            BudgetHealth.warning => c.amber,
            BudgetHealth.breached => c.red,
            _ => c.inkSoft,
          },
        ),
      ),
      below: LedgerBar(value: usage.utilizationBps / 10000, color: color, marker: paused ? null : marker),
      semanticLabel: '$name budget, ${usage.health.label}. $sub.',
      onTap: () => context.push(AppRoutes.budget(usage.budget.id)),
    );
    return paused ? Opacity(opacity: 0.6, child: row) : row;
  }
}

// ---------------------------------------------------------------------------
// Savings
// ---------------------------------------------------------------------------

String _span(int points) => points <= 1 ? 'this month' : 'in ${points - 1} months';

/// Savings: money set aside, its growth and average pace, and each goal.
List<Widget> savingsSection(BuildContext context, InsightsData data) {
  final t = context.type;
  if (data.savings.every((p) => p.value.isZero)) {
    return [
      LedgerEmpty(
        icon: LucideIcons.piggyBank,
        title: 'No savings set aside yet',
        message: 'Money moved into goals or your emergency fund shows up here. Start a goal, even a small one.',
        actionLabel: 'Start a goal',
        onAction: () => context.push(AppRoutes.newGoal),
      ),
    ];
  }
  final change = data.savingsChange;
  final avg = data.avgMonthlySavingsChange;
  return [
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InsightLead(
          label: 'Set aside now',
          value: AnimatedAmount(data.savings.last.value, style: t.figureXL, decimals: DecimalDisplay.none, fit: true),
        ),
        const SizedBox(height: Sp.xl),
        InsightStats(stats: [
          InsightStat(
            label: 'Change',
            value: insightAmount(context, change, sign: SignDisplay.always, color: signColor(context, change)),
            caption: _span(data.savings.length),
          ),
          InsightStat(
            label: 'Avg per month',
            value: insightAmount(context, avg, sign: SignDisplay.always),
            caption: 'added on average',
          ),
        ]),
      ],
    ),
    InsightChartCard(
      heading: 'Over time',
      title: data.savingsHeadline((x) => moneyText(context, x)),
      subtitle: 'Set aside for goals and your emergency fund at each month end. Touch a point for the amount.',
      howCalculated: 'Set aside = all contributions minus withdrawals to goals and the emergency fund up to '
          'each month end. This money is still part of your cash balance: it is set aside, not spent.',
      child: TrendLineChart(points: data.savings, color: context.ink.green, seriesLabel: 'Savings'),
    ),
    if (data.goals.isNotEmpty) _Goals(data: data),
  ];
}

class _Goals extends StatelessWidget {
  const _Goals({required this.data});
  final InsightsData data;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final t = context.type;
    final goals = data.goals;
    final list = List.of(goals)
      ..sort((a, b) => a.isAchieved == b.isAchieved ? b.progressBps.compareTo(a.progressBps) : (a.isAchieved ? 1 : -1));
    final reached = goals.where((g) => g.isAchieved).length;
    return InsightListSection(
      title: reached == 0 ? 'Your goals' : '$reached of ${goals.length} goals reached',
      dividerIndent: Sp.lg,
      rows: [
        for (final g in list.take(6))
          LedgerRow(
            title: g.goal.name,
            subtitle: g.isAchieved
                ? 'Reached'
                : '${moneyText(context, g.saved)} of ${moneyText(context, g.goal.target)}, '
                    '${moneyText(context, g.remaining)} to go',
            subtitleColor: g.isAchieved ? c.green : null,
            trailing: Text(formatBps(g.progressBps, decimals: 0), style: t.figure),
            below: LedgerBar(value: (g.progressBps / 10000).clamp(0.0, 1.0)),
            chevron: true,
            semanticLabel: '${g.goal.name}, ${formatBps(g.progressBps, decimals: 0)} saved',
            onTap: () => context.push(AppRoutes.goal(g.goal.id)),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Loans
// ---------------------------------------------------------------------------

/// Loans: what is still owed, how fast it is going down, and when it could
/// be cleared at that pace.
List<Widget> loansSection(BuildContext context, InsightsData data) {
  final c = context.ink;
  final t = context.type;
  if (data.debt.every((p) => p.value.isZero)) {
    return const [
      LedgerEmpty(
        icon: LucideIcons.landmark,
        title: 'You have no borrowed loans',
        message: 'Nothing to pay back. If you take a loan, its payoff progress shows up here.',
      ),
    ];
  }
  String m(Money x) => moneyText(context, x);
  final months = data.monthsToDebtFree;
  final repaid = data.debtRepaid;
  final avg = data.avgMonthlyDebtRepaid;
  return [
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InsightLead(
          label: 'Still owed',
          value: AnimatedAmount(data.debt.last.value, style: t.figureXL, decimals: DecimalDisplay.none, fit: true),
          sentence: months != null
              ? 'At this pace you could be debt-free in about $months month${months == 1 ? '' : 's'}, around '
                  '${monthLong(data.today.monthKey.shift(months))}, paying down about ${m(avg)} a month.'
              : repaid.isNegative
                  ? 'Your debt went up by ${m(repaid.abs())}.'
                  : 'Regular EMIs bring this down month by month.',
          sentenceColor: months == null && repaid.isNegative ? c.amber : null,
        ),
        const SizedBox(height: Sp.xl),
        InsightStats(stats: [
          InsightStat(
            label: 'Paid off',
            value: insightAmount(context, repaid.isNegative ? Money.zero : repaid, color: repaid.isPositive ? c.green : null),
            caption: _span(data.debt.length),
          ),
          InsightStat(
            label: 'Avg per month',
            value: insightAmount(context, avg.isNegative ? Money.zero : avg),
            caption: 'principal repaid',
          ),
        ]),
      ],
    ),
    InsightChartCard(
      heading: 'Over time',
      title: data.debtHeadline((x) => moneyText(context, x)),
      subtitle: 'What you still owe at each month end. A line going down is good news.',
      howCalculated: 'Outstanding debt = original principal minus principal repaid on loans you borrowed, measured '
          'at each month end (today for the current month). Interest paid does not reduce debt. Loans you gave '
          'to others are not included.',
      child: TrendLineChart(points: data.debt, seriesLabel: 'Debt'),
    ),
    if (data.loans.isNotEmpty) _Loans(data: data),
  ];
}

class _Loans extends StatelessWidget {
  const _Loans({required this.data});
  final InsightsData data;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final t = context.type;
    final loans = data.loans;
    return InsightListSection(
      title: loans.length == 1 ? 'Your loan' : 'Your ${loans.length} loans',
      note: 'The bar shows how much of each loan you have paid back.',
      dividerIndent: Sp.lg,
      rows: [
        for (final l in loans)
          Builder(builder: (context) {
            final paid = l.principalRepaid.ratioBps(l.loan.principal) ?? 0;
            final sub = '${formatBps(paid, decimals: 0)} paid back, ${moneyText(context, l.outstanding)} left';
            return LedgerRow(
              title: l.loan.name,
              subtitle: sub,
              trailing: l.isOverdue ? Text('Overdue', style: t.small.copyWith(color: c.red)) : null,
              below: LedgerBar(value: (paid / 10000).clamp(0.0, 1.0)),
              chevron: true,
              semanticLabel: '${l.loan.name}${l.isOverdue ? ', overdue' : ''}. $sub',
              onTap: () => context.push(AppRoutes.loan(l.loan.id)),
            );
          }),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Subscriptions
// ---------------------------------------------------------------------------

/// Subscriptions: what recurring payments cost per month, year and day,
/// their share of income, and the biggest ones.
List<Widget> subscriptionsSection(BuildContext context, InsightsData data) {
  final c = context.ink;
  final t = context.type;
  if (data.activeSubscriptionCount == 0) {
    return [
      LedgerEmpty(
        icon: LucideIcons.repeat,
        title: 'No active subscriptions',
        message: 'Netflix, gym, phone plans: anything you pay again and again. '
            'Add them to see what they cost you each month and year.',
        actionLabel: 'Add a subscription',
        onAction: () => context.push(AppRoutes.newSubscription),
      ),
    ];
  }
  final count = data.activeSubscriptionCount;
  final share = data.subscriptionsMonthly.ratioBps(data.avgMonthlyIncome);
  final heavy = share != null && share > 1000;
  final perDay = data.subscriptionsMonthly.scale(12, 365);
  return [
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InsightLead(
          label: 'Subscriptions a month',
          value: AnimatedAmount(data.subscriptionsMonthly, style: t.figureXL, decimals: DecimalDisplay.none, fit: true),
          sentence: heavy
              ? 'More than 10% of income. Worth a review.'
              : '$count active subscription${count == 1 ? '' : 's'}.',
          sentenceColor: heavy ? c.amber : null,
        ),
        const SizedBox(height: Sp.xl),
        InsightStats(stats: [
          InsightStat(label: 'Per year', value: insightAmount(context, data.subscriptionsAnnual)),
          InsightStat(label: 'Per day', value: insightAmount(context, perDay)),
          InsightStat(
            label: 'Of income',
            value: Text(share == null ? '—' : formatBps(share, decimals: 0), style: t.figure.copyWith(color: heavy ? c.amber : null)),
            caption: 'a typical month',
          ),
        ]),
      ],
    ),
    InsightListSection(
      title: 'Biggest recurring costs',
      note: 'Converted to a monthly amount so you can compare them fairly.',
      dividerIndent: Sp.lg,
      rows: [
        for (final s in data.topSubscriptions)
          LedgerRow(
            title: s.name,
            subtitle: '${moneyText(context, s.amount)} ${s.frequency.label.toLowerCase()}',
            trailing: insightAmount(context, s.monthlyEquivalent),
            trailingSub: Text('a month', style: t.small),
            semanticLabel: '${s.name}, ${moneyText(context, s.monthlyEquivalent)} a month',
            onTap: () => context.push(AppRoutes.subscription(s.id)),
          ),
      ],
      actionLabel: count > data.topSubscriptions.length ? 'See all $count' : null,
      onAction: count > data.topSubscriptions.length ? () => context.push(AppRoutes.subscriptions) : null,
      footer: const HowCalculated(
        text: 'Each active subscription is converted to a monthly amount (yearly ÷ 12, quarterly ÷ 3, weekly × 52 ÷ 12). '
            'These are commitments, not spending: a charge becomes spending only when you mark it paid. '
            'The share of income uses your average monthly income.',
      ),
    ),
  ];
}
