import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/money/money.dart';
import '../../../../core/money/money_format.dart';
import '../../../../design_system/design_system.dart';
import '../../application/analytics_providers.dart';
import '../../domain/analytics.dart';
import '../insight_widgets.dart';

/// Overview: the headline numbers, a three-ring health check, what stands
/// out, and one tile per topic that jumps straight to its chip.
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
    final t = context.text;
    final cur = data.current;
    final change = data.expenseChangeBps;
    final rate = data.savingsRateBps;
    final white70 = Colors.white.withValues(alpha: 0.7);
    return GradientHeroCard(
      watermark: LucideIcons.chartColumn,
      semanticLabel: null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${data.isPartial ? 'SPENT SO FAR' : 'SPENT'} · ${data.periodLabel.toUpperCase()}',
            style: t.eyebrow.copyWith(color: white70),
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
                  label: cur.net.isNegative ? 'Overspent' : 'Saved',
                  align: CrossAxisAlignment.center,
                  child: _heroAmount(context, cur.net, sign: SignDisplay.always),
                ),
              ),
              Expanded(
                child: _HeroStat(
                  label: 'Daily avg',
                  align: CrossAxisAlignment.end,
                  child: rate == null && cur.expense.isZero
                      ? Text('—', style: t.amountSmall.copyWith(color: Colors.white))
                      : _heroAmount(context, data.dailyBurn),
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

/// Three rings a non-expert can read at a glance: how much of income was
/// kept, how much of the budget is used (vs time passed), goal progress.
class _HealthCard extends StatelessWidget {
  const _HealthCard({required this.data});
  final InsightsData data;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;

    final rate = data.savingsRateBps;
    final keptColor = rate == null ? c.textTertiary : (rate >= 2000 ? c.positive : (rate >= 0 ? c.warning : c.negative));
    final keptCaption = rate == null
        ? 'No income yet'
        : (rate >= 2000 ? 'Above the 20% mark' : (rate >= 0 ? 'Aim for 20%' : 'Spent more than earned'));

    final limit = data.budgetLimitTotal;
    final usedBps = data.budgetSpentTotal.ratioBps(limit);
    final elapsed = data.budgetElapsedBps;
    final budgetColor = usedBps == null
        ? c.textTertiary
        : (usedBps >= 10000 ? c.negative : (usedBps > elapsed + 500 ? c.warning : c.positive));
    final budgetCaption = usedBps == null
        ? 'No budgets'
        : (usedBps >= 10000 ? 'Over the limit' : (usedBps > elapsed + 500 ? 'Ahead of pace' : 'On pace'));

    final goals = data.goals.where((g) => g.goal.target.isPositive).toList();
    final target = Money.sum(goals.map((g) => g.goal.target));
    final saved = Money.sum(goals.map((g) => Money.min(g.saved, g.goal.target)));
    final goalBps = saved.ratioBps(target);

    return FinnCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(header: true, child: Text('Money health check', style: t.sectionTitle)),
          const SizedBox(height: Space.x0_5),
          Text('Three quick signs of how ${data.periodLabel} is going',
              style: t.caption.copyWith(color: c.textSecondary)),
          const SizedBox(height: Space.x4),
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
                  color: goalBps == null ? c.textTertiary : c.accentGoals,
                  center: goalBps == null ? '—' : formatBps(goalBps, decimals: 0),
                  label: 'Goals reached',
                  caption: goals.isEmpty ? 'No goals yet' : '${goals.length} goal${goals.length == 1 ? '' : 's'}',
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.x3),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(width: 2, height: 10, color: c.textPrimary),
              const SizedBox(width: Space.x1_5),
              Flexible(
                child: Text('Tick = target (20% kept) or time passed this month',
                    style: t.micro.copyWith(color: c.textTertiary, fontWeight: FontWeight.w700)),
              ),
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
  });

  final double value;
  final double? marker;
  final Color color;
  final String center;
  final String label;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    return Semantics(
      label: '$label $center. $caption',
      excludeSemantics: true,
      child: Column(
        children: [
          RingGauge(
            value: value,
            marker: marker,
            color: color,
            size: 84,
            stroke: 9,
            center: Text(center, style: t.amountSmall.copyWith(color: c.textPrimary)),
          ),
          const SizedBox(height: Space.x2),
          Text(label, style: t.label.copyWith(fontWeight: FontWeight.w800), textAlign: TextAlign.center),
          Text(caption,
              style: t.micro.copyWith(color: color == c.textTertiary ? c.textSecondary : color, fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
              maxLines: 2),
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
    final c = context.colors;
    final t = context.text;
    final hidden = AmountVisibility.hiddenOf(context);
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
                        Text(maskAmounts(i.title, hidden), style: t.bodyStrong),
                        const SizedBox(height: Space.x0_5),
                        Text(maskAmounts(i.body, hidden), style: t.caption.copyWith(color: c.textSecondary)),
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

/// One tile per topic: its key number, tap to open that chip.
class _ExploreGrid extends ConsumerWidget {
  const _ExploreGrid({required this.data});
  final InsightsData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
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
            ? [for (final d in data.dailySpend.where((d) => !d.isFuture).toList().reversed.take(10).toList().reversed) d.amount.toDouble()]
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
        SectionHeader(icon: LucideIcons.compass, title: 'Explore by topic', tileColor: c.accentAnalytics),
        const SizedBox(height: Space.x3),
        LayoutBuilder(
          builder: (context, box) {
            final w = (box.maxWidth - Space.x3) / 2;
            return Wrap(
              spacing: Space.x3,
              runSpacing: Space.x3,
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
    final c = context.colors;
    final t = context.text;
    final a = section.accent(c);
    return FinnCard(
      padding: const EdgeInsets.all(Space.x3),
      onTap: onTap,
      haptic: true,
      semanticLabel: '${section.label}: $value, $hint. Open ${section.label}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconTile(
                icon: section.icon,
                background: a.withValues(alpha: c.isDark ? 0.2 : 0.12),
                foreground: a,
                size: 28,
                radius: Radii.md,
                iconSize: 15,
              ),
              const SizedBox(width: Space.x2),
              Expanded(
                child: Text(section.label, style: t.label.copyWith(fontWeight: FontWeight.w800), maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              Icon(LucideIcons.chevronRight, size: 14, color: c.textTertiary),
            ],
          ),
          const SizedBox(height: Space.x2_5),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: t.amountSmall, maxLines: 1),
          ),
          const SizedBox(height: Space.x0_5),
          Text(hint, style: t.micro.copyWith(color: c.textSecondary, fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
          // Every tile keeps the spark row so tiles in a row line up.
          const SizedBox(height: Space.x2),
          spark == null ? const SizedBox(height: 22) : SparkBars(values: spark!, color: a, height: 22),
        ],
      ),
    );
  }
}
