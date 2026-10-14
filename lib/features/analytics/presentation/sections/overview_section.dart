import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/money/money.dart';
import '../../../../core/money/money_format.dart';
import '../../../../design_system/design_system.dart';
import '../../../../design_system/luxe/luxe.dart';
import '../../application/analytics_providers.dart';
import '../../domain/analytics.dart';
import '../insight_widgets.dart';

/// Overview: what was spent and how it compares, a three-ring health
/// check, what stands out, and one tile per topic that jumps straight to
/// its chip.
List<Widget> overviewSection(InsightsData data) => [
  _HeroCard(data: data),
  _HealthCard(data: data),
  if (data.insights.isNotEmpty) _InsightList(insights: data.insights),
  _ExploreGrid(data: data),
];

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.data});
  final InsightsData data;

  @override
  Widget build(BuildContext context) {
    final p = context.luxe;
    final t = context.lt;
    final cur = data.current;
    final change = data.expenseChangeBps;
    final rate = data.savingsRateBps;
    // Figures scale down to fit their third of the row.
    Widget figure(Money m, {SignDisplay sign = SignDisplay.auto}) => LuxeAmount(
      m,
      sign: sign,
      style: t.number.copyWith(fontSize: 15, color: p.onObsidian),
    );
    return LuxeObsidian(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${data.isPartial ? 'SPENT SO FAR' : 'SPENT'} · ${data.periodLabel.toUpperCase()}',
            style: t.eyebrow.copyWith(fontSize: 10, color: p.onObsidianSoft),
          ),
          const SizedBox(height: 8),
          LuxeAmount(cur.expense, countFromZero: true, style: t.display.copyWith(fontSize: 42, color: p.onObsidian)),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: change == null
                ? Text('Nothing to compare with in ${data.previousLabel}', style: t.caption.c(p.onObsidianSoft))
                : _ChangePill(changeBps: change, against: data.previousLabel),
          ),
          const SizedBox(height: 18),
          SizedBox(height: 1, child: ColoredBox(color: p.onObsidian.withValues(alpha: 0.1))),
          const SizedBox(height: 16),
          LuxeFigureRow(
            onDark: true,
            children: [
              LuxeFigure(label: 'Income', onDark: true, child: figure(cur.income)),
              LuxeFigure(
                label: cur.net.isNegative ? 'Overspent' : 'Saved',
                onDark: true,
                child: figure(cur.net, sign: SignDisplay.always),
              ),
              LuxeFigure(
                label: 'Daily avg',
                onDark: true,
                child: rate == null && cur.expense.isZero
                    ? Text('—', style: t.number.copyWith(color: p.onObsidian))
                    : figure(data.dailyBurn),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ChangePill extends StatelessWidget {
  const _ChangePill({required this.changeBps, required this.against});
  final int changeBps;
  final String against;

  @override
  Widget build(BuildContext context) {
    final p = context.luxe;
    final down = changeBps < 0;
    final level = changeBps.abs() < 100;
    final pct = formatBps(changeBps.abs());
    final text = level ? 'About the same as $against' : '$pct ${down ? 'less' : 'more'} than $against';
    final tone = level ? p.onObsidianSoft : (down ? (p.isDark ? p.positive : const Color(0xFF9BD3B5)) : p.gold);
    return Semantics(
      label: 'Spending ${level ? 'about the same as' : '$pct ${down ? 'lower' : 'higher'} than'} $against',
      excludeSemantics: true,
      child: LuxeStatus(
        label: text,
        color: tone,
        icon: level ? LucideIcons.minus : (down ? LucideIcons.trendingDown : LucideIcons.trendingUp),
      ),
    );
  }
}

/// Three rings a non-expert can read at a glance: how much of income was
/// kept, how much of the budget is used (vs time passed), goal progress.
class _HealthCard extends StatelessWidget {
  const _HealthCard({required this.data});
  final InsightsData data;

  @override
  Widget build(BuildContext context) {
    final p = context.luxe;
    final t = context.lt;

    final rate = data.savingsRateBps;
    final keptColor = rate == null ? p.inkMute : (rate >= 2000 ? p.positive : (rate >= 0 ? p.goldInk : p.negative));
    final keptCaption = rate == null
        ? 'No income yet'
        : (rate >= 2000 ? 'Above the 20% mark' : (rate >= 0 ? 'Aim for 20%' : 'Spent more than earned'));

    final limit = data.budgetLimitTotal;
    final usedBps = data.budgetSpentTotal.ratioBps(limit);
    final elapsed = data.budgetElapsedBps;
    final budgetColor = usedBps == null
        ? p.inkMute
        : (usedBps >= 10000 ? p.negative : (usedBps > elapsed + 500 ? p.warning : p.positive));
    final budgetCaption = usedBps == null
        ? 'No budgets'
        : (usedBps >= 10000 ? 'Over the limit' : (usedBps > elapsed + 500 ? 'Ahead of pace' : 'On pace'));

    final goals = data.goals.where((g) => g.goal.target.isPositive).toList();
    final target = Money.sum(goals.map((g) => g.goal.target));
    final saved = Money.sum(goals.map((g) => Money.min(g.saved, g.goal.target)));
    final goalBps = saved.ratioBps(target);

    return LuxeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(header: true, child: Text('Money health check', style: t.title.copyWith(fontSize: 22))),
          const SizedBox(height: 4),
          Text('Three quick signs of how ${data.periodLabel} is going', style: t.caption),
          const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _Ring(
                  value: rate == null ? 0 : rate / 10000,
                  marker: 0.2,
                  color: keptColor,
                  center: rate == null ? '—' : formatBps(rate, decimals: 0),
                  label: 'Income kept',
                  caption: keptCaption,
                ),
              ),
              Expanded(
                child: _Ring(
                  value: (usedBps ?? 0) / 10000,
                  marker: usedBps == null ? null : elapsed / 10000,
                  color: budgetColor,
                  center: usedBps == null ? '—' : formatBps(usedBps, decimals: 0),
                  label: 'Budget used',
                  caption: budgetCaption,
                ),
              ),
              Expanded(
                child: _Ring(
                  value: (goalBps ?? 0) / 10000,
                  color: goalBps == null ? p.inkMute : p.gold,
                  gradient: goalBps == null ? null : p.goldGradient.colors,
                  center: goalBps == null ? '—' : formatBps(goalBps, decimals: 0),
                  label: 'Goals reached',
                  caption: goals.isEmpty ? 'No goals yet' : '${goals.length} goal${goals.length == 1 ? '' : 's'}',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(width: 1.6, height: 10, color: p.ink),
              const SizedBox(width: 8),
              Flexible(child: Text('Tick = target (20% kept) or time passed this month', style: t.micro)),
            ],
          ),
        ],
      ),
    );
  }
}

class _Ring extends StatelessWidget {
  const _Ring({
    required this.value,
    required this.color,
    required this.center,
    required this.label,
    required this.caption,
    this.marker,
    this.gradient,
  });

  final double value;
  final double? marker;
  final Color color;
  final List<Color>? gradient;
  final String center;
  final String label;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final p = context.luxe;
    final t = context.lt;
    return Semantics(
      label: '$label $center. $caption',
      excludeSemantics: true,
      child: Column(
        children: [
          LuxeRing(
            value: value.clamp(0.0, 1.0),
            marker: marker,
            color: color,
            gradient: gradient,
            size: 82,
            stroke: 4,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Text(center, style: t.figure.copyWith(fontSize: 22)),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(label, style: t.label.w(700).c(p.ink), textAlign: TextAlign.center),
          const SizedBox(height: 2),
          Text(
            caption,
            style: t.micro.w(700).c(color == p.inkMute ? p.inkSoft : color),
            textAlign: TextAlign.center,
            maxLines: 2,
          ),
        ],
      ),
    );
  }
}

class _InsightList extends StatelessWidget {
  const _InsightList({required this.insights});
  final List<Insight> insights;

  @override
  Widget build(BuildContext context) {
    final p = context.luxe;
    final t = context.lt;
    final hidden = AmountVisibility.hiddenOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 8, bottom: 12),
          child: LuxeEyebrowHeader(label: 'What stands out'),
        ),
        LuxeCard(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
          child: Column(
            children: [
              for (var i = 0; i < insights.length; i++) ...[
                if (i > 0) const LuxeHairline(indent: 48),
                MergeSemantics(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        LuxeIconDisc(
                          icon: switch (insights[i].tone) {
                            InsightTone.positive => LucideIcons.circleCheck,
                            InsightTone.caution => LucideIcons.triangleAlert,
                            InsightTone.neutral => LucideIcons.lightbulb,
                          },
                          color: switch (insights[i].tone) {
                            InsightTone.positive => p.positive,
                            InsightTone.caution => p.warning,
                            InsightTone.neutral => p.goldInk,
                          },
                          size: 34,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(maskAmounts(insights[i].title, hidden), style: t.label.w(700).c(p.ink)),
                              const SizedBox(height: 3),
                              Text(maskAmounts(insights[i].body, hidden), style: t.caption),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// One tile per topic: its key number, tap to open that topic.
class _ExploreGrid extends ConsumerWidget {
  const _ExploreGrid({required this.data});
  final InsightsData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    String m(Money x, {bool compact = true}) => moneyText(context, x, compact: compact);

    final topCat = data.categories.isEmpty ? null : data.categories.first;
    final topMethod = data.methods.isEmpty ? null : data.methods.first;
    final net = data.current.net;
    final active = data.budgetsActive;
    final tiles = <(InsightsSection, String, String, List<double>?)>[
      (
        InsightsSection.spending,
        data.hasActivity ? '${m(data.dailyBurn)}/day' : 'No spending',
        'Average daily spend',
        data.dailySpend.isNotEmpty
            ? [
                for (final d in data.dailySpend.where((d) => !d.isFuture).toList().reversed.take(10).toList().reversed)
                  d.amount.toDouble(),
              ]
            : [for (final x in data.months) x.expense.toDouble()],
      ),
      (
        InsightsSection.cashFlow,
        data.current.income.isZero && data.current.expense.isZero
            ? 'No activity'
            : '${net.isNegative ? '−' : '+'}${m(net.abs())}',
        net.isNegative ? 'Spent more than earned' : 'Kept after spending',
        null,
      ),
      (
        InsightsSection.categories,
        topCat == null ? 'No spending' : topCat.name,
        topCat == null ? 'Biggest spend' : 'Biggest spend · ${formatBps(topCat.shareBps, decimals: 0)}',
        null,
      ),
      (
        InsightsSection.payments,
        topMethod == null ? 'No payments' : topMethod.key.label,
        topMethod == null
            ? 'How you pay'
            : 'Used for ${formatBps(topMethod.value.ratioBps(data.current.expense) ?? 0, decimals: 0)}',
        null,
      ),
      (
        InsightsSection.budgets,
        active == 0 ? 'Not set' : '${active - data.budgetsOver} of $active',
        active == 0 ? 'Create a budget' : 'Budgets on track',
        null,
      ),
      (
        InsightsSection.savings,
        data.savings.isEmpty || data.savings.last.value.isZero ? 'Nothing yet' : m(data.savings.last.value),
        'Set aside for goals',
        [for (final p in data.savings) p.value.toDouble()],
      ),
      (
        InsightsSection.loans,
        data.debt.isEmpty || data.debt.last.value.isZero ? 'No loans' : m(data.debt.last.value),
        'Still owed',
        null,
      ),
      (
        InsightsSection.subscriptions,
        data.activeSubscriptionCount == 0 ? 'None' : '${m(data.subscriptionsMonthly)}/mo',
        data.activeSubscriptionCount == 0 ? 'Recurring payments' : '${data.activeSubscriptionCount} active',
        null,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 8, bottom: 12),
          child: LuxeEyebrowHeader(label: 'Explore by topic', caption: 'Tap a tile to open that topic'),
        ),
        LayoutBuilder(
          builder: (context, box) {
            final w = (box.maxWidth - 10) / 2;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final (section, value, hint, spark) in tiles)
                  SizedBox(
                    width: w,
                    child: _ExploreTile(
                      key: Key('insights-explore:${section.name}'),
                      section: section,
                      value: value,
                      hint: hint,
                      spark: spark != null && spark.any((v) => v > 0) ? spark : null,
                      onTap: () => ref.read(insightsSectionProvider.notifier).select(section),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _ExploreTile extends StatelessWidget {
  const _ExploreTile({
    super.key,
    required this.section,
    required this.value,
    required this.hint,
    required this.onTap,
    this.spark,
  });

  final InsightsSection section;
  final String value;
  final String hint;
  final List<double>? spark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.luxe;
    final t = context.lt;
    return LuxeCard(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      radius: LuxeSpace.rTile,
      onTap: onTap,
      semanticLabel: '${section.label}: $value, $hint. Open ${section.label}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(section.icon, size: 15, color: p.goldInk),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  section.label.toUpperCase(),
                  style: t.eyebrow.copyWith(fontSize: 9.5),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(LucideIcons.arrowUpRight, size: 13, color: p.inkMute),
            ],
          ),
          const SizedBox(height: 12),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: t.figure.copyWith(fontSize: 22), maxLines: 1),
          ),
          const SizedBox(height: 2),
          Text(hint, style: t.micro, maxLines: 1, overflow: TextOverflow.ellipsis),
          // Every tile keeps the spark row so tiles in a row line up.
          const SizedBox(height: 10),
          spark == null ? const SizedBox(height: 20) : SparkBars(values: spark!, color: p.gold, height: 20),
        ],
      ),
    );
  }
}
