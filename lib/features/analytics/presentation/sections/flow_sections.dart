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
import '../../../transactions/domain/transaction.dart';
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
  final c = context.colors;
  String m(Money x) => moneyText(context, x);
  final single = data.filter.period == InsightsPeriod.month;
  final peak = data.peakDay;
  final projected = data.projectedMonthSpend;

  return [
    TakeawayCard(
      icon: LucideIcons.calendarDays,
      tone: FinnTone.info,
      title: data.hasActivity && data.current.expense.isPositive
          ? 'You spend about ${m(data.dailyBurn)} a day'
          : 'No spending recorded for ${data.periodLabel}',
      body: !data.current.expense.isPositive
          ? 'Add an expense and your daily pattern shows up here.'
          : single && peak != null
              ? 'That is your everyday baseline. Your biggest day was '
                  '${DateFormats.weekdayDayMonth.format(peak.date)} at ${m(peak.amount)}.'
              : 'That is your everyday baseline. A typical month costs ${m(data.avgMonthlyExpense)}.',
    ),
    KpiStrip(items: [
      Kpi(
        label: 'Daily average',
        value: AmountText(data.dailyBurn, decimals: DecimalDisplay.none),
        caption: 'per day',
      ),
      single
          ? Kpi(
              label: 'Biggest day',
              value: AmountText(peak?.amount ?? Money.zero, decimals: DecimalDisplay.none),
              caption: peak == null ? '—' : DateFormats.dayMonth.format(peak.date),
            )
          : Kpi(
              label: 'Typical month',
              value: AmountText(data.avgMonthlyExpense, decimals: DecimalDisplay.none),
              caption: 'average',
            ),
      projected != null
          ? Kpi(
              label: 'Month-end estimate',
              value: AmountText(projected, decimals: DecimalDisplay.none),
              caption: 'if this pace holds',
              captionColor: c.warning,
            )
          : Kpi(
              label: 'Total spent',
              value: AmountText(data.current.expense, decimals: DecimalDisplay.none),
              caption: data.periodLabel,
            ),
    ]),
    if (single) _DayByDayCard(data: data) else _MonthByMonthCard(data: data),
    _WeekdayCard(data: data),
    _BiggestExpensesCard(data: data),
  ];
}

class _DayByDayCard extends StatelessWidget {
  const _DayByDayCard({required this.data});
  final InsightsData data;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final noSpend = data.noSpendDays;
    final above = data.dailySpend.where((d) => !d.isFuture && d.amount > data.dailyBurn).length;
    return InsightChartCard(
      icon: LucideIcons.chartColumn,
      accent: c.info,
      title: data.current.expense.isZero
          ? 'Day by day'
          : '$above of ${data.elapsedDays} days were above your average',
      subtitle: noSpend == 0
          ? 'Every bar is one day. Touch a bar for the amount.'
          : 'Every bar is one day. You had $noSpend no-spend day${noSpend == 1 ? '' : 's'} — nice.',
      legend: [
        LegendEntry('Normal day', c.info),
        LegendEntry('Above average', c.warning),
        LegendEntry('2× average', c.negative),
        LegendEntry('Your average', c.textPrimary, dashed: true),
      ],
      howCalculated: 'Each bar adds up the completed expenses on that day, including EMIs and settlements. '
          'Your daily average = total spending ÷ days passed so far in the period.',
      child: data.current.expense.isZero
          ? const InsightNoData(message: 'No spending yet this month.')
          : DailySpendChart(days: data.dailySpend, average: data.dailyBurn),
    );
  }
}

class _MonthByMonthCard extends StatelessWidget {
  const _MonthByMonthCard({required this.data});
  final InsightsData data;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final avg = data.avgMonthlyExpense;
    final above = data.activeMonths.where((x) => x.expense.toDouble() > avg.toDouble() * 1.1).length;
    return InsightChartCard(
      icon: LucideIcons.chartColumn,
      accent: c.info,
      title: data.monthsHaveActivity ? '$above of ${data.activeMonths.length} months cost more than usual' : 'Month by month',
      subtitle: 'Spending each month, ${_window(data)}. Touch a bar for the amount.',
      legend: [
        LegendEntry('Usual month', c.info),
        LegendEntry('Pricier month', c.warning),
        LegendEntry('Your average', c.textPrimary, dashed: true),
      ],
      howCalculated: 'Each bar is the total of completed expenses in that month. The average uses months that '
          'have any activity. A month is "pricier" when it is more than 10% above the average.',
      child: data.monthsHaveActivity
          ? MonthlySpendChart(months: data.months, average: avg)
          : const InsightNoData(message: 'Record expenses to see how each month compares.'),
    );
  }
}

class _WeekdayCard extends StatelessWidget {
  const _WeekdayCard({required this.data});
  final InsightsData data;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final busy = data.busiestWeekday;
    final quiet = data.quietestWeekday;
    String m(Money x) => moneyText(context, x);
    return InsightChartCard(
      icon: LucideIcons.calendarRange,
      accent: c.accentPending,
      title: busy == null ? 'Which days cost the most' : '${weekdayNames[busy]}s cost you the most',
      subtitle: busy == null || quiet == null
          ? 'Typical spend on each day of the week'
          : 'About ${m(data.weekdayAverages[busy])} on a typical ${weekdayNames[busy]}, '
              'vs ${m(data.weekdayAverages[quiet])} on a ${weekdayNames[quiet]}.',
      howCalculated: 'For each weekday: total spending on that weekday ÷ how many of that weekday have passed in '
          'the period. Plan bigger shopping on lighter days to spread your spending.',
      child: busy == null
          ? const InsightNoData(message: 'No spending pattern yet.', icon: LucideIcons.calendarRange)
          : WeekdayChart(averages: data.weekdayAverages, color: c.accentPending),
    );
  }
}

class _BiggestExpensesCard extends StatelessWidget {
  const _BiggestExpensesCard({required this.data});
  final InsightsData data;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final top = data.topExpenses;
    final total = data.current.expense;
    final topSum = Money.sum(top.map((t) => t.amount));
    final share = topSum.ratioBps(total);
    return InsightChartCard(
      icon: LucideIcons.receipt,
      accent: c.negative,
      title: top.isEmpty ? 'Biggest expenses' : 'Your ${top.length} biggest expenses',
      subtitle: share == null || top.isEmpty
          ? 'Largest single payments in ${data.periodLabel}'
          : 'Together they make up ${formatBps(share, decimals: 0)} of everything you spent in ${data.periodLabel}.',
      child: top.isEmpty
          ? const InsightNoData(message: 'No expenses in this period.', icon: LucideIcons.receipt)
          : Column(
              children: [
                for (final t in top) _ExpenseRow(tx: t, max: top.first.amount),
                if (data.filter.period == InsightsPeriod.month)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () => context.push(AppRoutes.transactionsFiltered(month: data.filter.month)),
                      child: Text('See all ${data.current.transactionCount} transactions',
                          style: context.text.label.copyWith(fontWeight: FontWeight.w800)),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _ExpenseRow extends ConsumerWidget {
  const _ExpenseRow({required this.tx, required this.max});
  final Transaction tx;
  final Money max;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final t = context.text;
    final cat = ref.watch(categoryProvider(tx.categoryId));
    final title = tx.counterparty ?? tx.note ?? cat?.name ?? 'Expense';
    return InkWell(
      borderRadius: Radii.rLg,
      onTap: () => context.push(AppRoutes.transaction(tx.id)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.x2),
        child: MergeSemantics(
          child: Row(
            children: [
              CategoryAvatar(category: cat, size: 34),
              const SizedBox(width: Space.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(title, style: t.bodyStrong, maxLines: 1, overflow: TextOverflow.ellipsis)),
                        const SizedBox(width: Space.x2),
                        AmountText(tx.amount, style: t.amountSmall, decimals: DecimalDisplay.none),
                      ],
                    ),
                    Text(
                      '${DateFormats.shortWeekdayDayMonth.format(tx.date)} · ${cat?.name ?? 'Uncategorised'}',
                      style: t.micro.copyWith(color: c.textSecondary, fontWeight: FontWeight.w700),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: Space.x1_5),
                    RelativeBar(
                      value: max.isZero ? 0 : tx.amount.toDouble() / max.toDouble(),
                      color: c.negative.withValues(alpha: 0.75),
                      height: 5,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// In vs out
// ---------------------------------------------------------------------------

/// Money in vs money out: of every ₹100 earned how much was kept, monthly
/// averages as a baseline, and the month-by-month comparison.
List<Widget> cashFlowSection(BuildContext context, InsightsData data) {
  final c = context.colors;
  final months = data.activeMonths.length;
  return [
    _Per100Card(data: data),
    KpiStrip(items: [
      Kpi(
        label: 'Avg income',
        value: AmountText(data.avgMonthlyIncome, decimals: DecimalDisplay.none, color: c.positive),
        caption: 'per month',
      ),
      Kpi(
        label: 'Avg spending',
        value: AmountText(data.avgMonthlyExpense, decimals: DecimalDisplay.none, color: c.negative),
        caption: 'per month',
      ),
      Kpi(
        label: 'Avg saved',
        value: AmountText(data.avgMonthlyNet, decimals: DecimalDisplay.none, sign: SignDisplay.always, colorize: true),
        caption: months <= 1 ? 'this month' : 'over $months months',
      ),
    ]),
    InsightChartCard(
      icon: LucideIcons.chartColumn,
      title: data.incomeVsExpenseHeadline,
      subtitle: 'Green is money in, red is money out, ${_window(data)}. Touch a bar for the amount.',
      legend: [
        LegendEntry('Income', c.positive),
        LegendEntry('Spending', c.negative),
        LegendEntry('Avg spending', c.negative, dashed: true),
      ],
      howCalculated: 'Income is money received in each calendar month. Spending is every completed expense, '
          'including EMIs and settlements you paid. Loan disbursements and money you lent are not counted as '
          'income or spending, and moving money into goals is not spending.',
      child: data.monthsHaveActivity
          ? IncomeExpenseBarChart(months: data.months, averageExpense: data.avgMonthlyExpense)
          : const InsightNoData(message: 'Record income or expenses to see how each month compares.'),
    ),
    InsightChartCard(
      icon: LucideIcons.scale,
      accent: c.accentNetWorth,
      title: data.netHeadline((x) => moneyText(context, x)),
      subtitle: 'What was left each month. Bars below the line mean you spent more than you earned.',
      legend: [
        LegendEntry('Saved', c.positive),
        LegendEntry('Overspent', c.negative),
        LegendEntry('Your average', c.accentNetWorth, dashed: true),
      ],
      howCalculated: 'Left over = income − spending for each calendar month. A surplus adds to your cash; '
          'a deficit is paid from savings or your balance. The current month only includes transactions up to today.',
      child: data.monthsHaveActivity
          ? NetCashFlowChart(months: data.months, average: data.avgMonthlyNet)
          : const InsightNoData(message: 'No cash flow recorded yet.'),
    ),
  ];
}

/// "Of every ₹100 you earned, you kept ₹22" with a split bar.
class _Per100Card extends StatelessWidget {
  const _Per100Card({required this.data});
  final InsightsData data;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final cur = data.current;
    String m(Money x) => moneyText(context, x);
    if (cur.income.isZero) {
      return TakeawayCard(
        icon: LucideIcons.arrowLeftRight,
        tone: cur.expense.isZero ? FinnTone.info : FinnTone.warning,
        title: 'No income recorded for ${data.periodLabel}',
        body: cur.expense.isZero
            ? 'Add your salary or other income to see how much you keep.'
            : 'You spent ${m(cur.expense)} with no income recorded. Add income to see what you keep.',
      );
    }
    final spent = (cur.expense.paise * 100 / cur.income.paise).round();
    final kept = 100 - spent;
    final over = kept < 0;
    final tone = over ? FinnTone.negative : (kept >= 20 ? FinnTone.positive : FinnTone.warning);
    return FinnCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconTile(
                icon: over ? LucideIcons.triangleAlert : LucideIcons.piggyBank,
                background: tone.soft(c),
                foreground: tone.color(c),
                size: 36,
                radius: Radii.md,
                iconSize: 18,
              ),
              const SizedBox(width: Space.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        over
                            ? 'You spent ₹$spent for every ₹100 you earned'
                            : 'You kept ₹$kept of every ₹100 you earned',
                        style: t.sectionTitle,
                      ),
                    ),
                    const SizedBox(height: Space.x0_5),
                    Text(
                      over
                          ? 'The extra came from your savings or balance in ${data.periodLabel}.'
                          : kept >= 20
                              ? 'Great — keeping ₹20 or more of every ₹100 is a healthy habit.'
                              : 'A good target is to keep ₹20 of every ₹100.',
                      style: t.caption.copyWith(color: c.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.x4),
          SplitBar(
            height: 22,
            semanticLabel: over ? 'Spent all income and more' : 'Spent $spent rupees, kept $kept rupees of every 100',
            segments: [
              SplitSegment(over ? 100 : spent.toDouble(), c.negative),
              if (!over) SplitSegment(kept.toDouble(), c.positive),
            ],
          ),
          const SizedBox(height: Space.x3),
          Wrap(
            spacing: Space.x4,
            runSpacing: Space.x1,
            children: [
              LegendValue(color: c.negative, label: 'Spent', value: m(cur.expense)),
              LegendValue(color: c.positive, label: over ? 'Earned' : 'Kept', value: m(over ? cur.income : cur.net)),
            ],
          ),
        ],
      ),
    );
  }
}
