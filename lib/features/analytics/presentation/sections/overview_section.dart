import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/money/money.dart';
import '../../../../core/money/money_format.dart';
import '../../../../kit/kit.dart';
import '../../application/analytics_providers.dart';
import '../../domain/analytics.dart';
import '../insight_widgets.dart';

/// Overview: what was spent in the period with money in and kept beside
/// it, a three-line health check, what stands out, and one row per topic
/// that jumps straight to its chip.
List<Widget> overviewSection(InsightsData data) => [
      _Hero(data: data),
      _HealthCheck(data: data),
      if (data.insights.isNotEmpty) _StandsOut(insights: data.insights),
      _Explore(data: data),
    ];

/// Indent that lines row dividers up with the text after a 40pt well.
const double _rowIndent = Sp.lg + 40 + Sp.md + 2;

class _Hero extends StatelessWidget {
  const _Hero({required this.data});
  final InsightsData data;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final t = context.type;
    final cur = data.current;
    final rate = data.savingsRateBps;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InsightLead(
          label: data.isPartial ? 'Spent so far' : 'Spent',
          value: AnimatedAmount(cur.expense, style: t.figureXL, decimals: DecimalDisplay.none, fit: true),
          below: _Change(data: data),
        ),
        const SizedBox(height: Sp.xl),
        InsightStats(stats: [
          InsightStat(
            label: 'Income',
            value: insightAmount(context, cur.income, color: cur.income.isPositive ? c.green : null),
          ),
          InsightStat(
            label: cur.net.isNegative ? 'Overspent' : 'Saved',
            value: insightAmount(context, cur.net, sign: SignDisplay.always, color: signColor(context, cur.net)),
          ),
          InsightStat(
            label: 'Daily avg',
            value: rate == null && cur.expense.isZero ? Text('—', style: t.figure) : insightAmount(context, data.dailyBurn),
          ),
        ]),
      ],
    );
  }
}

/// "12% less than September", or why there is nothing to compare.
class _Change extends StatelessWidget {
  const _Change({required this.data});
  final InsightsData data;

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    final against = data.previousLabel;
    final change = data.expenseChangeBps;
    if (change == null) return Text('Nothing to compare with in $against', style: t.label);
    final down = change < 0;
    final level = change.abs() < 100;
    final pct = formatBps(change.abs());
    return Semantics(
      label: 'Spending ${level ? 'about the same as' : '$pct ${down ? 'lower' : 'higher'} than'} $against',
      excludeSemantics: true,
      child: Text(
        level ? 'About the same as $against' : '$pct ${down ? 'less' : 'more'} than $against',
        style: t.label,
      ),
    );
  }
}

/// Three signs a non-expert can read at a glance: how much of income was
/// kept (against 20%), how much of the budget is used (against time
/// passed), and goal progress.
class _HealthCheck extends StatelessWidget {
  const _HealthCheck({required this.data});
  final InsightsData data;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final t = context.type;

    final rate = data.savingsRateBps;
    final keptColor = rate == null ? c.inkFaint : (rate >= 2000 ? c.green : (rate >= 0 ? c.amber : c.red));
    final keptCaption = rate == null
        ? 'No income yet'
        : (rate >= 2000 ? 'Above the 20% mark' : (rate >= 0 ? 'Aim for 20%' : 'Spent more than earned'));

    final limit = data.budgetLimitTotal;
    final usedBps = data.budgetSpentTotal.ratioBps(limit);
    final elapsed = data.budgetElapsedBps;
    final over = usedBps != null && usedBps >= 10000;
    final ahead = usedBps != null && !over && usedBps > elapsed + 500;
    final budgetColor = usedBps == null ? c.inkFaint : (over ? c.red : (ahead ? c.amber : c.green));
    final budgetCaption = usedBps == null ? 'No budgets' : (over ? 'Over the limit' : (ahead ? 'Ahead of pace' : 'On pace'));

    final goals = data.goals.where((g) => g.goal.target.isPositive).toList();
    final target = Money.sum(goals.map((g) => g.goal.target));
    final saved = Money.sum(goals.map((g) => Money.min(g.saved, g.goal.target)));
    final goalBps = saved.ratioBps(target);

    return LedgerSection(
      title: 'Money health check',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LedgerPanel(
            children: [
              _HealthRow(
                label: 'Income kept',
                value: rate == null ? '—' : formatBps(rate, decimals: 0),
                share: rate == null ? 0 : rate / 10000,
                marker: 0.2,
                color: keptColor,
                caption: keptCaption,
                captionColor: rate != null && rate < 2000 ? keptColor : null,
              ),
              _HealthRow(
                label: 'Budget used',
                value: usedBps == null ? '—' : formatBps(usedBps, decimals: 0),
                share: (usedBps ?? 0) / 10000,
                marker: usedBps == null ? null : elapsed / 10000,
                color: budgetColor,
                caption: budgetCaption,
                captionColor: over || ahead ? budgetColor : null,
              ),
              _HealthRow(
                label: 'Goals reached',
                value: goalBps == null ? '—' : formatBps(goalBps, decimals: 0),
                share: (goalBps ?? 0) / 10000,
                color: goalBps == null ? c.inkFaint : c.green,
                caption: goals.isEmpty ? 'No goals yet' : '${goals.length} goal${goals.length == 1 ? '' : 's'}',
              ),
            ],
          ),
          const SizedBox(height: Sp.sm),
          Text('Tick = target (20% kept) or time passed this month', style: t.small),
        ],
      ),
    );
  }
}

class _HealthRow extends StatelessWidget {
  const _HealthRow({
    required this.label,
    required this.value,
    required this.share,
    required this.color,
    required this.caption,
    this.captionColor,
    this.marker,
  });

  final String label;
  final String value;
  final double share;
  final double? marker;
  final Color color;
  final String caption;
  final Color? captionColor;

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    return LedgerRow(
      title: label,
      subtitle: caption,
      subtitleColor: captionColor,
      trailing: Text(value, style: t.figure),
      // Over 100% kept or used is still one full bar here; the caption
      // carries the warning.
      below: LedgerBar(value: share.clamp(0.0, 1.0), marker: marker, color: color),
      semanticLabel: '$label $value. $caption',
    );
  }
}

class _StandsOut extends StatelessWidget {
  const _StandsOut({required this.insights});
  final List<Insight> insights;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final hidden = AmountVisibility.hiddenOf(context);
    return LedgerSection(
      title: 'What stands out',
      child: LedgerPanel(
        dividerIndent: _rowIndent,
        children: [
          for (final i in insights)
            LedgerRow(
              leading: IconWell(
                icon: switch (i.tone) {
                  InsightTone.positive => LucideIcons.circleCheck,
                  InsightTone.caution => LucideIcons.triangleAlert,
                  InsightTone.neutral => LucideIcons.info,
                },
                color: switch (i.tone) {
                  InsightTone.positive => c.green,
                  InsightTone.caution => c.amber,
                  InsightTone.neutral => null,
                },
              ),
              title: maskAmounts(i.title, hidden),
              titleLines: 3,
              subtitle: maskAmounts(i.body, hidden),
              subtitleLines: 4,
            ),
        ],
      ),
    );
  }
}

/// One row per topic: its key number, tap to open that chip.
class _Explore extends ConsumerWidget {
  const _Explore({required this.data});
  final InsightsData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.type;
    String m(Money x, {bool compact = true}) => moneyText(context, x, compact: compact);

    final topCat = data.categories.isEmpty ? null : data.categories.first;
    final topMethod = data.methods.isEmpty ? null : data.methods.first;
    final net = data.current.net;
    final active = data.budgetsActive;
    final rows = <(InsightsSection, String, String)>[
      (
        InsightsSection.spending,
        data.hasActivity ? '${m(data.dailyBurn)}/day' : 'No spending',
        'Average daily spend',
      ),
      (
        InsightsSection.cashFlow,
        data.current.income.isZero && data.current.expense.isZero
            ? 'No activity'
            : '${net.isNegative ? '−' : '+'}${m(net.abs())}',
        net.isNegative ? 'Spent more than earned' : 'Kept after spending',
      ),
      (
        InsightsSection.categories,
        topCat == null ? 'No spending' : topCat.name,
        topCat == null ? 'Biggest spend' : 'Biggest spend, ${formatBps(topCat.shareBps, decimals: 0)}',
      ),
      (
        InsightsSection.payments,
        topMethod == null ? 'No payments' : topMethod.key.label,
        topMethod == null
            ? 'How you pay'
            : 'Used for ${formatBps(topMethod.value.ratioBps(data.current.expense) ?? 0, decimals: 0)}',
      ),
      (
        InsightsSection.budgets,
        active == 0 ? 'Not set' : '${active - data.budgetsOver} of $active',
        active == 0 ? 'Create a budget' : 'Budgets on track',
      ),
      (
        InsightsSection.savings,
        data.savings.isEmpty || data.savings.last.value.isZero ? 'Nothing yet' : m(data.savings.last.value),
        'Set aside for goals',
      ),
      (
        InsightsSection.loans,
        data.debt.isEmpty || data.debt.last.value.isZero ? 'No loans' : m(data.debt.last.value),
        'Still owed',
      ),
      (
        InsightsSection.subscriptions,
        data.activeSubscriptionCount == 0 ? 'None' : '${m(data.subscriptionsMonthly)}/mo',
        data.activeSubscriptionCount == 0 ? 'Recurring payments' : '${data.activeSubscriptionCount} active',
      ),
    ];

    return LedgerSection(
      title: 'Explore by topic',
      child: LedgerPanel(
        dividerIndent: _rowIndent,
        children: [
          for (final (section, value, hint) in rows)
            LedgerRow(
              key: Key('insights-explore:${section.name}'),
              leading: IconWell(icon: section.icon),
              title: section.label,
              subtitle: hint,
              subtitleLines: 2,
              trailing: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 120),
                child: Text(value, style: t.figure, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.end),
              ),
              chevron: true,
              semanticLabel: '${section.label}: $value, $hint. Open ${section.label}',
              onTap: () => ref.read(insightsSectionProvider.notifier).select(section),
            ),
        ],
      ),
    );
  }
}
