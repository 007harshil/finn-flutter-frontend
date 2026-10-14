import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/routes.dart';
import '../../../../core/money/money.dart';
import '../../../../core/money/money_format.dart';
import '../../../../core/time/dates.dart';
import '../../../../kit/kit.dart';
import '../../../../shared/presentation/transaction_row.dart';
import '../../application/analytics_providers.dart';
import '../insight_charts.dart';
import '../insight_widgets.dart';

String _window(InsightsData d) => d.windowMonths == 1 ? 'this month' : 'the last ${d.windowMonths} months';

// ---------------------------------------------------------------------------
// Daily spend
// ---------------------------------------------------------------------------

/// Daily spend: the everyday baseline (average per day), which days were
/// expensive, which weekdays cost most, and the biggest single expenses.
List<Widget> spendingSection(BuildContext context, InsightsData data) {
  final t = context.type;
  String m(Money x) => moneyText(context, x);
  final single = data.filter.period == InsightsPeriod.month;
  final peak = data.peakDay;
  final projected = data.projectedMonthSpend;
  final spent = data.current.expense.isPositive;

  return [
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InsightLead(
          label: 'Daily average',
          value: AnimatedAmount(data.dailyBurn, style: t.figureXL, decimals: DecimalDisplay.none, fit: true),
          sentence: !spent
              ? 'No spending recorded for ${data.periodLabel}. Add an expense and your daily pattern shows up here.'
              : single && peak != null
                  ? 'Your everyday baseline. The biggest day was '
                      '${DateFormats.weekdayDayMonth.format(peak.date)} at ${m(peak.amount)}.'
                  : 'Your everyday baseline. A typical month costs ${m(data.avgMonthlyExpense)}.',
        ),
        const SizedBox(height: Sp.xl),
        InsightStats(stats: [
          single
              ? InsightStat(
                  label: 'Biggest day',
                  value: insightAmount(context, peak?.amount ?? Money.zero),
                  caption: peak == null ? '—' : DateFormats.dayMonth.format(peak.date),
                )
              : InsightStat(
                  label: 'Typical month',
                  value: insightAmount(context, data.avgMonthlyExpense),
                  caption: 'average',
                ),
          projected != null
              ? InsightStat(
                  label: 'Month-end estimate',
                  value: insightAmount(context, projected),
                  caption: 'if this pace holds',
                )
              : InsightStat(
                  label: 'Total spent',
                  value: insightAmount(context, data.current.expense),
                  caption: data.periodLabel,
                ),
        ]),
      ],
    ),
    if (single) _DayByDay(data: data) else _MonthByMonth(data: data),
    _Weekdays(data: data),
    if (data.topExpenses.isNotEmpty) _BiggestExpenses(data: data),
  ];
}

class _DayByDay extends StatelessWidget {
  const _DayByDay({required this.data});
  final InsightsData data;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final noSpend = data.noSpendDays;
    final above = data.dailySpend.where((d) => !d.isFuture && d.amount > data.dailyBurn).length;
    return InsightChartCard(
      heading: 'Day by day',
      title: data.current.expense.isZero
          ? 'Spending on each day'
          : '$above of ${data.elapsedDays} days were above your average',
      subtitle: noSpend == 0
          ? 'Each bar is one day. Touch a bar for the amount.'
          : 'Each bar is one day. You had $noSpend no-spend day${noSpend == 1 ? '' : 's'}.',
      legend: [
        LegendEntry('Normal day', c.lineStrong),
        LegendEntry('Above average', c.ink),
        LegendEntry('Your average', c.inkSoft, dashed: true),
      ],
      howCalculated: 'Each bar adds up the completed expenses on that day, including EMIs and settlements. '
          'Your daily average = total spending ÷ days passed so far in the period.',
      child: data.current.expense.isZero
          ? const InsightNoData(message: 'No spending yet this month.')
          : DailySpendChart(days: data.dailySpend, average: data.dailyBurn),
    );
  }
}

class _MonthByMonth extends StatelessWidget {
  const _MonthByMonth({required this.data});
  final InsightsData data;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final avg = data.avgMonthlyExpense;
    final above = data.activeMonths.where((x) => x.expense.toDouble() > avg.toDouble() * 1.1).length;
    return InsightChartCard(
      heading: 'Month by month',
      title: data.monthsHaveActivity
          ? '$above of ${data.activeMonths.length} months cost more than usual'
          : 'Spending each month',
      subtitle: 'Spending each month, ${_window(data)}. Touch a bar for the amount.',
      legend: [
        LegendEntry('Usual month', c.lineStrong),
        LegendEntry('Pricier month', c.ink),
        LegendEntry('Your average', c.inkSoft, dashed: true),
      ],
      howCalculated: 'Each bar is the total of completed expenses in that month. The average uses months that '
          'have any activity. A month is "pricier" when it is more than 10% above the average.',
      child: data.monthsHaveActivity
          ? MonthlySpendChart(months: data.months, average: avg)
          : const InsightNoData(message: 'Record expenses to see how each month compares.'),
    );
  }
}

class _Weekdays extends StatelessWidget {
  const _Weekdays({required this.data});
  final InsightsData data;

  @override
  Widget build(BuildContext context) {
    final busy = data.busiestWeekday;
    final quiet = data.quietestWeekday;
    String m(Money x) => moneyText(context, x);
    return InsightChartCard(
      heading: 'By weekday',
      title: busy == null ? 'Which days cost the most' : '${weekdayNames[busy]}s cost you the most',
      subtitle: busy == null || quiet == null
          ? 'Typical spend on each day of the week'
          : 'About ${m(data.weekdayAverages[busy])} on a typical ${weekdayNames[busy]}, '
              'against ${m(data.weekdayAverages[quiet])} on a ${weekdayNames[quiet]}.',
      howCalculated: 'For each weekday: total spending on that weekday ÷ how many of that weekday have passed in '
          'the period. Plan bigger shopping on lighter days to spread your spending.',
      child: busy == null
          ? const InsightNoData(message: 'No spending pattern yet.')
          : WeekdayChart(averages: data.weekdayAverages),
    );
  }
}

class _BiggestExpenses extends StatelessWidget {
  const _BiggestExpenses({required this.data});
  final InsightsData data;

  @override
  Widget build(BuildContext context) {
    final top = data.topExpenses;
    final share = Money.sum(top.map((t) => t.amount)).ratioBps(data.current.expense);
    final month = data.filter.period == InsightsPeriod.month;
    return InsightListSection(
      title: 'Your ${top.length} biggest expenses',
      note: share == null
          ? null
          : 'Together they make up ${formatBps(share, decimals: 0)} of everything you spent in ${data.periodLabel}.',
      rows: [for (final tx in top) TransactionRow(transaction: tx, showDate: true)],
      actionLabel: month ? 'See all ${data.current.transactionCount} transactions' : null,
      onAction: month ? () => context.push(AppRoutes.transactionsFiltered(month: data.filter.month)) : null,
    );
  }
}

// ---------------------------------------------------------------------------
// In vs out
// ---------------------------------------------------------------------------

/// Money in vs money out: of every ₹100 earned how much was kept, monthly
/// averages as a baseline, and the month-by-month comparison.
List<Widget> cashFlowSection(BuildContext context, InsightsData data) {
  final c = context.ink;
  final months = data.activeMonths.length;
  return [
    _Per100(data: data),
    LedgerSection(
      title: 'Monthly averages',
      child: InsightStats(stats: [
        InsightStat(
          label: 'Avg income',
          value: insightAmount(context, data.avgMonthlyIncome, color: data.avgMonthlyIncome.isPositive ? c.green : null),
          caption: 'per month',
        ),
        InsightStat(
          label: 'Avg spending',
          value: insightAmount(context, data.avgMonthlyExpense),
          caption: 'per month',
        ),
        InsightStat(
          label: 'Avg saved',
          value: insightAmount(
            context,
            data.avgMonthlyNet,
            sign: SignDisplay.always,
            color: signColor(context, data.avgMonthlyNet),
          ),
          caption: months <= 1 ? 'this month' : 'over $months months',
        ),
      ]),
    ),
    InsightChartCard(
      heading: 'Month by month',
      title: data.incomeVsExpenseHeadline,
      subtitle: 'Money in and money out, ${_window(data)}. Touch a bar for the amount.',
      legend: [
        LegendEntry('Income', c.green),
        LegendEntry('Spending', c.ink),
        LegendEntry('Avg spending', c.inkSoft, dashed: true),
      ],
      howCalculated: 'Income is money received in each calendar month. Spending is every completed expense, '
          'including EMIs and settlements you paid. Loan disbursements and money you lent are not counted as '
          'income or spending, and moving money into goals is not spending.',
      child: data.monthsHaveActivity
          ? IncomeExpenseBarChart(months: data.months, averageExpense: data.avgMonthlyExpense)
          : const InsightNoData(message: 'Record income or expenses to see how each month compares.'),
    ),
    InsightChartCard(
      heading: 'Left over',
      title: data.netHeadline((x) => moneyText(context, x)),
      subtitle: 'What was left each month. Bars below the line mean you spent more than you earned.',
      legend: [
        LegendEntry('Saved', c.green),
        LegendEntry('Overspent', c.red),
        LegendEntry('Your average', c.inkSoft, dashed: true),
      ],
      howCalculated: 'Left over = income − spending for each calendar month. A surplus adds to your cash; '
          'a deficit is paid from savings or your balance. The current month only includes transactions up to today.',
      child: data.monthsHaveActivity
          ? NetCashFlowChart(months: data.months, average: data.avgMonthlyNet)
          : const InsightNoData(message: 'No cash flow recorded yet.'),
    ),
  ];
}

/// What was kept in the period, "of every ₹100 you earned, you kept ₹22",
/// and a bar split into spent and kept.
class _Per100 extends StatelessWidget {
  const _Per100({required this.data});
  final InsightsData data;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final t = context.type;
    final hidden = AmountVisibility.hiddenOf(context);
    final cur = data.current;
    String m(Money x) => moneyText(context, x);
    if (cur.income.isZero) {
      return InsightLead(
        label: 'Income',
        value: AnimatedAmount(cur.income, style: t.figureXL, decimals: DecimalDisplay.none, fit: true),
        sentence: cur.expense.isZero
            ? 'No income recorded for ${data.periodLabel}. Add your salary or other income to see how much you keep.'
            : 'No income recorded for ${data.periodLabel}, and you spent ${m(cur.expense)}. '
                'Add income to see what you keep.',
      );
    }
    final spent = (cur.expense.paise * 100 / cur.income.paise).round();
    final kept = 100 - spent;
    final over = kept < 0;
    return InsightLead(
      label: over ? 'Overspent' : 'Kept',
      value: AnimatedAmount(
        cur.net.abs(),
        style: t.figureXL.copyWith(color: hidden ? null : (over ? c.red : c.green)),
        decimals: DecimalDisplay.none,
        fit: true,
      ),
      below: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LedgerStackBar(
            gapColor: c.paper,
            semanticLabel: over ? 'Spent all income and more' : 'Spent $spent rupees, kept $kept rupees of every 100',
            parts: [
              BarPart(over ? 1 : spent / 100, over ? c.red : c.ink),
              if (!over) BarPart(kept / 100, c.green),
            ],
          ),
          const SizedBox(height: Sp.md),
          Wrap(
            spacing: Sp.lg,
            runSpacing: Sp.xs,
            children: [
              InsightKeyValue(color: over ? c.red : c.ink, label: 'Spent', value: m(cur.expense)),
              InsightKeyValue(color: c.green, label: 'Earned', value: m(cur.income)),
            ],
          ),
        ],
      ),
      sentence: over
          ? 'You spent ₹$spent for every ₹100 you earned. The extra came from your savings or balance.'
          : kept >= 20
              ? 'You kept ₹$kept of every ₹100 you earned. Keeping ₹20 or more is a healthy habit.'
              : 'You kept ₹$kept of every ₹100 you earned. A good target is ₹20.',
    );
  }
}
