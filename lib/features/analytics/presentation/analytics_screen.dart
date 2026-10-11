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
import '../../../shared/presentation/async_view.dart';
import '../../../shared/presentation/category_icons.dart';
import '../../budgets/domain/budget.dart';
import '../../transactions/domain/transaction.dart';
import '../application/analytics_providers.dart';
import '../domain/analytics.dart';
import 'insight_charts.dart';

/// Insights: where money came from and went, with plain-language takeaways.
class AnalyticsScreen extends ConsumerWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(insightsDataProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Insights')),
      body: AsyncView<InsightsData>(
        value: data,
        loading: const _InsightsSkeleton(),
        errorTitle: 'Could not load your insights',
        builder: (context, d) => _InsightsBody(data: d),
      ),
    );
  }
}

class _InsightsSkeleton extends StatelessWidget {
  const _InsightsSkeleton();

  @override
  Widget build(BuildContext context) => const SkeletonPulse(
        child: ResponsiveCenter(
          padding: EdgeInsets.all(Space.gutter),
          child: Column(
            children: [
              SkeletonBox(height: 40, radius: Radii.full),
              SizedBox(height: Space.x4),
              CardSkeleton(height: 190, radius: Radii.xxxl),
              SizedBox(height: Space.x4),
              CardSkeleton(height: 280),
              SizedBox(height: Space.x4),
              CardSkeleton(height: 240),
            ],
          ),
        ),
      );
}

/// Masks rupee amounts inside generated copy when balances are hidden.
String _maskAmounts(String s, bool hidden) =>
    hidden ? s.replaceAll(RegExp(r'[−-]?₹[\d,]+(\.\d+)?[KLCr]*'), MoneyFormatter.masked) : s;

class _InsightsBody extends StatelessWidget {
  const _InsightsBody({required this.data});
  final InsightsData data;

  @override
  Widget build(BuildContext context) {
    final hidden = AmountVisibility.hiddenOf(context);
    String money(Money m) => hidden ? MoneyFormatter.masked : m.format(decimals: DecimalDisplay.none);

    final sections = <Widget>[
      _HeroCard(data: data),
      _QuickStats(data: data),
      if (data.insights.isNotEmpty) _InsightList(insights: data.insights, hidden: hidden),
      _IncomeExpenseCard(data: data),
      _NetCard(data: data, money: money),
      _CategoryCard(data: data),
      _MethodsCard(data: data),
      _BudgetsCard(data: data),
      _SavingsCard(data: data, money: money),
      _DebtCard(data: data, money: money),
      _SubscriptionsCard(data: data, money: money),
    ];

    return CustomScrollView(
      key: const PageStorageKey('insights'),
      slivers: [
        SliverToBoxAdapter(
          child: ResponsiveCenter(
            padding: const EdgeInsets.fromLTRB(Space.gutter, Space.x2, Space.gutter, Space.x2),
            child: _FilterBar(filter: data.filter),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(0, Space.x2, 0, Space.x10),
          sliver: SliverList.separated(
            itemCount: sections.length,
            separatorBuilder: (_, _) => const SizedBox(height: Space.x4),
            itemBuilder: (context, i) => ResponsiveCenter(
              padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
              child: StaggeredEntrance(index: i, child: sections[i]),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Filters
// ---------------------------------------------------------------------------

class _FilterBar extends ConsumerWidget {
  const _FilterBar({required this.filter});
  final InsightsFilter filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctrl = ref.read(insightsFilterProvider.notifier);
    final current = ref.watch(todayProvider.select((d) => d.monthKey));
    final isMonth = filter.period == InsightsPeriod.month;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedTabs<InsightsPeriod>(
          items: [
            for (final p in InsightsPeriod.values)
              SegmentItem(p, p == InsightsPeriod.month && filter.month != current ? 'Month' : p.label),
          ],
          selected: filter.period,
          onChanged: ctrl.setPeriod,
        ),
        if (isMonth) ...[
          const SizedBox(height: Space.x3),
          MonthSwitcher(
            month: filter.month,
            min: current.shift(-(insightsHistoryMonths - 1)),
            max: current,
            onChanged: ctrl.setMonth,
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Hero & stats
// ---------------------------------------------------------------------------

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.data});
  final InsightsData data;

  @override
  Widget build(BuildContext context) {
    final t = context.text;
    final cur = data.current;
    final change = data.expenseChangeBps;
    final rate = data.savingsRateBps;
    final white70 = Colors.white.withValues(alpha: 0.7);
    final eyebrow = t.eyebrow.copyWith(color: white70);
    return GradientHeroCard(
      watermark: LucideIcons.chartColumn,
      semanticLabel: null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${data.isPartial ? 'SPENT SO FAR' : 'SPENT'} · ${data.periodLabel.toUpperCase()}',
            style: eyebrow,
          ),
          const SizedBox(height: Space.x1),
          AnimatedAmount(
            cur.expense,
            style: t.amountHero.copyWith(color: Colors.white),
            decimals: DecimalDisplay.none,
            fit: true,
          ),
          const SizedBox(height: Space.x2),
          if (change != null) _ChangePill(changeBps: change, against: data.previousLabel),
          if (change == null)
            Text('Nothing to compare with in ${data.previousLabel}', style: t.caption.copyWith(color: white70)),
          const SizedBox(height: Space.x4),
          Container(height: 1, color: Colors.white.withValues(alpha: 0.16)),
          const SizedBox(height: Space.x4),
          Row(
            children: [
              Expanded(child: _HeroStat(label: 'Income', child: _heroAmount(context, cur.income))),
              Expanded(
                child: _HeroStat(
                  label: cur.net.isNegative ? 'Net (deficit)' : 'Net saved',
                  align: CrossAxisAlignment.center,
                  child: _heroAmount(context, cur.net, sign: SignDisplay.always),
                ),
              ),
              Expanded(
                child: _HeroStat(
                  label: 'Savings rate',
                  align: CrossAxisAlignment.end,
                  child: Text(
                    rate == null ? '—' : formatBps(rate),
                    style: t.amountSmall.copyWith(color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _heroAmount(BuildContext context, Money m, {SignDisplay sign = SignDisplay.auto}) => AmountText(
        m,
        sign: sign,
        decimals: DecimalDisplay.none,
        compact: m.abs() >= const Money.rupees(1000000),
        style: context.text.amountSmall.copyWith(color: Colors.white),
        fit: true,
      );
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({required this.label, required this.child, this.align = CrossAxisAlignment.start});
  final String label;
  final Widget child;
  final CrossAxisAlignment align;

  @override
  Widget build(BuildContext context) => MergeSemantics(
        child: Column(
          crossAxisAlignment: align,
          children: [
            Text(label.toUpperCase(),
                style: context.text.micro.copyWith(color: Colors.white.withValues(alpha: 0.65), letterSpacing: 0.8)),
            const SizedBox(height: Space.x1),
            child,
          ],
        ),
      );
}

class _ChangePill extends StatelessWidget {
  const _ChangePill({required this.changeBps, required this.against});
  final int changeBps;
  final String against;

  @override
  Widget build(BuildContext context) {
    final down = changeBps < 0;
    final level = changeBps.abs() < 100;
    final pct = formatBps(changeBps.abs());
    final text = level ? 'About the same as $against' : '$pct ${down ? 'less' : 'more'} than $against';
    return Semantics(
      label: 'Spending ${level ? 'about the same as' : '$pct ${down ? 'lower' : 'higher'} than'} $against',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: Space.x2_5, vertical: Space.x1),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.14), borderRadius: Radii.rFull),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              level ? LucideIcons.minus : (down ? LucideIcons.trendingDown : LucideIcons.trendingUp),
              size: 13,
              color: Colors.white,
            ),
            const SizedBox(width: Space.x1),
            Flexible(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.text.micro.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickStats extends StatelessWidget {
  const _QuickStats({required this.data});
  final InsightsData data;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: StatTile(
            label: 'Daily average',
            icon: LucideIcons.calendarRange,
            accent: c.accentAnalytics,
            value: AmountText(data.dailyBurn, decimals: DecimalDisplay.none),
            caption: data.isPartial ? 'Spend per day so far' : 'Spend per day',
          ),
        ),
        const SizedBox(width: Space.x3),
        Expanded(
          child: StatTile(
            label: 'Transactions',
            icon: LucideIcons.receipt,
            accent: c.accentTransactions,
            value: Text('${data.current.transactionCount}'),
            caption: 'Income and spending',
            onTap: data.filter.period == InsightsPeriod.month
                ? () => context.push(AppRoutes.transactionsFiltered(month: data.filter.month))
                : null,
          ),
        ),
      ],
    );
  }
}

class _InsightList extends StatelessWidget {
  const _InsightList({required this.insights, required this.hidden});
  final List<Insight> insights;
  final bool hidden;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(icon: LucideIcons.lightbulb, title: 'What stands out', tileColor: c.attention),
        const SizedBox(height: Space.x3),
        for (final i in insights) ...[
          FinnCard(
            padding: const EdgeInsets.all(Space.x3 + 2),
            child: MergeSemantics(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IconTile(
                    icon: switch (i.tone) {
                      InsightTone.positive => LucideIcons.circleCheck,
                      InsightTone.caution => LucideIcons.triangleAlert,
                      InsightTone.neutral => LucideIcons.info,
                    },
                    background: _tone(i.tone).soft(c),
                    foreground: _tone(i.tone).color(c),
                    size: 32,
                    radius: Radii.md,
                    iconSize: 16,
                  ),
                  const SizedBox(width: Space.x3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_maskAmounts(i.title, hidden), style: t.bodyStrong),
                        const SizedBox(height: Space.x0_5),
                        Text(_maskAmounts(i.body, hidden), style: t.caption.copyWith(color: c.textSecondary)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: Space.x2),
        ],
      ],
    );
  }

  static FinnTone _tone(InsightTone t) => switch (t) {
        InsightTone.positive => FinnTone.positive,
        InsightTone.caution => FinnTone.warning,
        InsightTone.neutral => FinnTone.info,
      };
}

// ---------------------------------------------------------------------------
// Chart cards
// ---------------------------------------------------------------------------

String _window(InsightsData d) => d.windowMonths == 1 ? 'this month' : 'the last ${d.windowMonths} months';

class _NoData extends StatelessWidget {
  const _NoData({required this.message, this.icon = LucideIcons.chartNoAxesColumn});
  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: Space.x6, horizontal: Space.x4),
      decoration: BoxDecoration(color: c.surfaceMuted, borderRadius: Radii.rLg),
      child: Column(
        children: [
          Icon(icon, size: 22, color: c.textTertiary),
          const SizedBox(height: Space.x2),
          Text(message, textAlign: TextAlign.center, style: context.text.caption.copyWith(color: c.textSecondary)),
        ],
      ),
    );
  }
}

class _IncomeExpenseCard extends StatelessWidget {
  const _IncomeExpenseCard({required this.data});
  final InsightsData data;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InsightChartCard(
      icon: LucideIcons.chartColumn,
      title: data.incomeVsExpenseHeadline,
      subtitle: 'Income and spending each month, ${_window(data)}',
      legend: [LegendEntry('Income', c.positive), LegendEntry('Spending', c.negative)],
      howCalculated: 'Income is money received in each calendar month. Spending is every completed expense, '
          'including EMIs and settlements you paid. Loan disbursements and money you lent are not counted as '
          'income or spending, and moving money into goals is not spending. Touch a bar for the exact amount.',
      child: data.monthsHaveActivity
          ? IncomeExpenseBarChart(months: data.months)
          : const _NoData(message: 'Record income or expenses to see how each month compares.'),
    );
  }
}

class _NetCard extends StatelessWidget {
  const _NetCard({required this.data, required this.money});
  final InsightsData data;
  final MoneyText money;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InsightChartCard(
      icon: LucideIcons.scale,
      accent: c.accentNetWorth,
      title: data.netHeadline(money),
      subtitle: 'Income minus spending per month. Bars below the line are deficits.',
      legend: [LegendEntry('Surplus', c.positive), LegendEntry('Deficit', c.negative)],
      howCalculated: 'Net cash flow = income − spending for each calendar month. A surplus adds to your cash; '
          'a deficit is paid from savings or your balance. The current month only includes transactions up to today.',
      child: data.monthsHaveActivity
          ? NetCashFlowChart(months: data.months)
          : const _NoData(message: 'No cash flow recorded yet.'),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({required this.data});
  final InsightsData data;

  static const _maxSlices = 6;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final cats = data.categories;
    final top = cats.take(_maxSlices).toList();
    final rest = cats.skip(_maxSlices).toList();
    final restTotal = Money.sum(rest.map((x) => x.amount));
    Color colorOf(int i) => c.chartSeries[i % c.chartSeries.length];
    final slices = [
      for (var i = 0; i < top.length; i++) DonutSlice(label: top[i].name, amount: top[i].amount, color: colorOf(i)),
      if (restTotal.isPositive) DonutSlice(label: 'Everything else', amount: restTotal, color: c.textTertiary),
    ];
    return InsightChartCard(
      icon: LucideIcons.chartPie,
      accent: c.accentBudgets,
      title: data.categoryHeadline,
      subtitle: 'Where your money went in ${data.periodLabel}, compared with ${data.previousLabel}',
      howCalculated: 'Each category\'s share = its spending ÷ total spending in the period. The change compares '
          'the same category with ${data.previousLabel}. Categories beyond the top $_maxSlices are grouped as '
          '"Everything else".',
      child: cats.isEmpty
          ? const _NoData(message: 'No spending in this period.', icon: LucideIcons.chartPie)
          : Column(
              children: [
                Center(child: CategoryDonut(slices: slices, total: data.current.expense)),
                const SizedBox(height: Space.x4),
                for (var i = 0; i < top.length; i++)
                  _CategoryRow(slice: top[i], color: colorOf(i), rank: i + 1),
                if (restTotal.isPositive)
                  _RankRow(
                    color: c.textTertiary,
                    leading: CategoryIconTile(icon: LucideIcons.ellipsis, color: c.textTertiary, size: 32),
                    title: 'Everything else',
                    subtitle: '${rest.length} more categories',
                    amount: restTotal,
                    shareBps: restTotal.ratioBps(data.current.expense) ?? 0,
                  ),
                if (cats.length > 1) ...[
                  const SizedBox(height: Space.x1),
                  Text(
                    'Top ${top.length} of ${cats.length} categories by amount',
                    style: t.micro.copyWith(color: c.textTertiary),
                  ),
                ],
              ],
            ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({required this.slice, required this.color, required this.rank});
  final CategorySlice slice;
  final Color color;
  final int rank;

  @override
  Widget build(BuildContext context) {
    final change = slice.changeBps;
    final prev = slice.previous;
    final String sub;
    if (prev == null) {
      sub = '#$rank';
    } else if (prev.isZero) {
      sub = 'New this period';
    } else if (change == null || change.abs() < 100) {
      sub = 'About the same as before';
    } else {
      sub = '${change < 0 ? '↓' : '↑'} ${formatBps(change.abs(), decimals: 0)} ${change < 0 ? 'less' : 'more'} than before';
    }
    return _RankRow(
      color: color,
      leading: CategoryAvatar(category: slice.category, size: 32),
      title: slice.name,
      subtitle: sub,
      subtitleColor: change == null || change.abs() < 100
          ? null
          : (change < 0 ? context.colors.positive : context.colors.negative),
      amount: slice.amount,
      shareBps: slice.shareBps,
    );
  }
}

class _RankRow extends StatelessWidget {
  const _RankRow({
    required this.color,
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.shareBps,
    this.subtitleColor,
  });

  final Color color;
  final Widget leading;
  final String title;
  final String subtitle;
  final Color? subtitleColor;
  final Money amount;
  final int shareBps;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.x2),
        child: Row(
          children: [
            Container(width: 4, height: 32, decoration: BoxDecoration(color: color, borderRadius: Radii.rFull)),
            const SizedBox(width: Space.x2),
            leading,
            const SizedBox(width: Space.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: t.bodyStrong, maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(subtitle,
                      style: t.micro.copyWith(color: subtitleColor ?? c.textSecondary, fontWeight: FontWeight.w700),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            const SizedBox(width: Space.x2),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                AmountText(amount, style: t.amountSmall, decimals: DecimalDisplay.none),
                Text(formatBps(shareBps), style: t.micro.copyWith(color: c.textTertiary)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MethodsCard extends StatelessWidget {
  const _MethodsCard({required this.data});
  final InsightsData data;

  static IconData _icon(PaymentMethod m) => switch (m) {
        PaymentMethod.upi => LucideIcons.smartphone,
        PaymentMethod.card => LucideIcons.creditCard,
        PaymentMethod.cash => LucideIcons.banknote,
        PaymentMethod.bankTransfer => LucideIcons.building2,
        PaymentMethod.wallet => LucideIcons.wallet,
        PaymentMethod.other => LucideIcons.circleDot,
      };

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final total = data.current.expense;
    return InsightChartCard(
      icon: LucideIcons.creditCard,
      accent: c.accentTransactions,
      title: data.methodHeadline,
      subtitle: 'How you paid in ${data.periodLabel}',
      howCalculated: 'Share = spending through each payment method ÷ total spending. Expenses recorded without '
          'a method are counted as "Other".',
      child: data.methods.isEmpty
          ? const _NoData(message: 'No payments in this period.', icon: LucideIcons.creditCard)
          : Column(
              children: [
                for (var i = 0; i < data.methods.length; i++) ...[
                  MergeSemantics(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: Space.x1_5),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Icon(_icon(data.methods[i].key), size: 16, color: c.textSecondary),
                              const SizedBox(width: Space.x2),
                              Expanded(child: Text(data.methods[i].key.label, style: t.bodyStrong)),
                              AmountText(data.methods[i].value, style: t.amountSmall, decimals: DecimalDisplay.none),
                              const SizedBox(width: Space.x2),
                              SizedBox(
                                width: 44,
                                child: Text(
                                  formatBps(data.methods[i].value.ratioBps(total) ?? 0, decimals: 0),
                                  textAlign: TextAlign.end,
                                  style: t.label.copyWith(color: c.textSecondary),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: Space.x1_5),
                          FinnProgressBar(
                            value: (data.methods[i].value.ratioBps(total) ?? 0) / 10000,
                            color: c.chartSeries[i % c.chartSeries.length],
                            height: 6,
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

class _BudgetsCard extends StatelessWidget {
  const _BudgetsCard({required this.data});
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
      subtitle: 'Current budget period · ${DateFormats.dayMonth.format(p.start)} – ${DateFormats.dayMonth.format(p.end)}',
      howCalculated: 'Each budget compares actual spending in its category with its limit for the current period. '
          'Upcoming subscription charges are shown on the budget itself but are not counted as spent. '
          '"Near limit" starts at the warning level you set on each budget.',
      child: list.isEmpty
          ? Column(
              children: [
                const _NoData(message: 'Set a budget to see how your spending tracks against it.', icon: LucideIcons.target),
                const SizedBox(height: Space.x3),
                FinnButton(
                  label: 'Create a budget',
                  icon: LucideIcons.plus,
                  variant: FinnButtonVariant.outline,
                  onPressed: () => context.push(AppRoutes.newBudget),
                ),
              ],
            )
          : Column(
              children: [
                for (final u in list.take(6)) _BudgetRow(usage: u),
                if (list.length > 6)
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
  const _BudgetRow({required this.usage});
  final BudgetUsage usage;

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
                        Row(
                          children: [
                            AmountText(usage.spent, style: t.micro.copyWith(color: c.textSecondary), decimals: DecimalDisplay.none),
                            Text(' of ', style: t.micro.copyWith(color: c.textSecondary)),
                            AmountText(usage.budget.limit, style: t.micro.copyWith(color: c.textSecondary), decimals: DecimalDisplay.none),
                          ],
                        ),
                      ],
                    ),
                  ),
                  StatusPill(label: usage.health.label, color: color, icon: icon),
                ],
              ),
              const SizedBox(height: Space.x2),
              FinnProgressBar(value: (usage.utilizationBps / 10000).clamp(0, 1), color: color, height: 6),
            ],
          ),
        ),
      ),
    );
  }
}

class _SavingsCard extends StatelessWidget {
  const _SavingsCard({required this.data, required this.money});
  final InsightsData data;
  final MoneyText money;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final empty = data.savings.every((p) => p.value.isZero);
    return InsightChartCard(
      icon: LucideIcons.piggyBank,
      accent: c.accentGoals,
      title: data.savingsHeadline(money),
      subtitle: 'Money earmarked for goals and your emergency fund at each month end',
      legend: [LegendEntry('Earmarked savings', c.accentGoals)],
      howCalculated: 'Earmarked savings = all contributions minus withdrawals to goals and the emergency fund up to '
          'each month end. This money is still part of your cash balance — it is set aside, not spent.',
      child: empty
          ? Column(
              children: [
                const _NoData(message: 'Set money aside for a goal to watch it grow here.', icon: LucideIcons.piggyBank),
                const SizedBox(height: Space.x3),
                FinnButton(
                  label: 'Start a goal',
                  icon: LucideIcons.plus,
                  variant: FinnButtonVariant.outline,
                  onPressed: () => context.push(AppRoutes.newGoal),
                ),
              ],
            )
          : TrendLineChart(points: data.savings, color: c.accentGoals, seriesLabel: 'Savings'),
    );
  }
}

class _DebtCard extends StatelessWidget {
  const _DebtCard({required this.data, required this.money});
  final InsightsData data;
  final MoneyText money;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final empty = data.debt.every((p) => p.value.isZero);
    return InsightChartCard(
      icon: LucideIcons.landmark,
      accent: c.accentLoans,
      title: data.debtHeadline(money),
      subtitle: 'Outstanding principal on money you borrowed, at each month end',
      legend: [LegendEntry('Outstanding debt', c.accentLoans)],
      howCalculated: 'Outstanding debt = original principal minus principal repaid on loans you borrowed, measured '
          'at each month end (today for the current month). Interest paid does not reduce debt. Loans you gave '
          'to others are not included.',
      child: empty
          ? const _NoData(message: 'You have no borrowed loans. Nothing to track here.', icon: LucideIcons.landmark)
          : TrendLineChart(points: data.debt, color: c.accentLoans, seriesLabel: 'Debt'),
    );
  }
}

class _SubscriptionsCard extends StatelessWidget {
  const _SubscriptionsCard({required this.data, required this.money});
  final InsightsData data;
  final MoneyText money;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final income = data.current.income;
    final share = data.subscriptionsMonthly.ratioBps(income);
    return InsightChartCard(
      icon: LucideIcons.repeat,
      accent: c.accentSubscriptions,
      title: data.subscriptionHeadline(money),
      subtitle: data.activeSubscriptionCount == 0
          ? 'Recurring commitments you track'
          : '${data.activeSubscriptionCount} active · about ${money(data.subscriptionsAnnual)} a year',
      howCalculated: 'Each active subscription is converted to a monthly amount (yearly ÷ 12, quarterly ÷ 3, weekly × 52 ÷ 12). '
          'These are commitments, not spending — a charge becomes spending only when you mark it paid.',
      child: data.topSubscriptions.isEmpty
          ? const _NoData(message: 'Add subscriptions to see your recurring commitments.', icon: LucideIcons.repeat)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (share != null && income.isPositive)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Space.x2),
                    child: Text(
                      'That is ${formatBps(share)} of the income you received in ${data.periodLabel}.',
                      style: t.caption.copyWith(color: c.textSecondary),
                    ),
                  ),
                for (final s in data.topSubscriptions)
                  InkWell(
                    borderRadius: Radii.rMd,
                    onTap: () => context.push(AppRoutes.subscription(s.id)),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: Dimens.minTouch),
                      child: MergeSemantics(
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(s.name, style: t.bodyStrong, maxLines: 1, overflow: TextOverflow.ellipsis),
                                  Row(
                                    children: [
                                      AmountText(s.amount, style: t.micro.copyWith(color: c.textSecondary)),
                                      Text(' ${s.frequency.label.toLowerCase()}', style: t.micro.copyWith(color: c.textSecondary)),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            AmountText(s.monthlyEquivalent, style: t.amountSmall, decimals: DecimalDisplay.none),
                            Text(' /mo', style: t.micro.copyWith(color: c.textTertiary)),
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
                      child: Text('See all ${data.activeSubscriptionCount}',
                          style: t.label.copyWith(fontWeight: FontWeight.w800)),
                    ),
                  ),
              ],
            ),
    );
  }
}
