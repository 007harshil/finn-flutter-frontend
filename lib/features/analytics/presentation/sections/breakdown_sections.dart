import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/money/money.dart';
import '../../../../core/money/money_format.dart';
import '../../../../design_system/design_system.dart';
import '../../../../shared/presentation/category_icons.dart';
import '../../../transactions/domain/transaction.dart';
import '../../application/analytics_providers.dart';
import '../../domain/analytics.dart';
import '../insight_charts.dart';
import '../insight_widgets.dart';

// ---------------------------------------------------------------------------
// Categories
// ---------------------------------------------------------------------------

/// Categories: an interactive donut + ranked list (tap either to focus a
/// category), and what changed compared with the previous period.
List<Widget> categoriesSection(InsightsData data) => [
      _CategoryCard(data: data),
      _ChangesCard(data: data),
    ];

class _CategoryCard extends StatefulWidget {
  const _CategoryCard({required this.data});
  final InsightsData data;

  @override
  State<_CategoryCard> createState() => _CategoryCardState();
}

class _CategoryCardState extends State<_CategoryCard> {
  static const _maxSlices = 6;
  int? _selected;

  void _select(int? i) => setState(() => _selected = i);

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
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
    final topShare = cats.isEmpty ? 1 : math.max(1, cats.first.shareBps);
    return InsightChartCard(
      icon: LucideIcons.chartPie,
      accent: c.accentPending,
      title: data.categoryHeadline,
      subtitle: 'Where your money went in ${data.periodLabel}. Tap a slice or a row to focus on it.',
      howCalculated: 'Each category\'s share = its spending ÷ total spending in the period. The change compares '
          'the same category with ${data.previousLabel}. Categories beyond the top $_maxSlices are grouped as '
          '"Everything else".',
      child: cats.isEmpty
          ? const InsightNoData(message: 'No spending in this period.', icon: LucideIcons.chartPie)
          : Column(
              children: [
                Center(
                  child: CategoryDonut(slices: slices, total: data.current.expense, selected: _selected, onSelect: _select),
                ),
                const SizedBox(height: Space.x4),
                for (var i = 0; i < top.length; i++)
                  _CategoryRow(
                    slice: top[i],
                    color: colorOf(i),
                    rank: i + 1,
                    barValue: top[i].shareBps / topShare,
                    selected: _selected == i,
                    dimmed: _selected != null && _selected != i,
                    onTap: () => _select(_selected == i ? null : i),
                  ),
                if (restTotal.isPositive)
                  _RankRow(
                    color: c.textTertiary,
                    leading: CategoryIconTile(icon: LucideIcons.ellipsis, color: c.textTertiary, size: 32),
                    title: 'Everything else',
                    subtitle: '${rest.length} more categories',
                    amount: restTotal,
                    shareBps: restTotal.ratioBps(data.current.expense) ?? 0,
                    barValue: (restTotal.ratioBps(data.current.expense) ?? 0) / topShare,
                    selected: _selected == top.length,
                    dimmed: _selected != null && _selected != top.length,
                    onTap: () => _select(_selected == top.length ? null : top.length),
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
  const _CategoryRow({
    required this.slice,
    required this.color,
    required this.rank,
    required this.barValue,
    required this.selected,
    required this.dimmed,
    required this.onTap,
  });

  final CategorySlice slice;
  final Color color;
  final int rank;
  final double barValue;
  final bool selected;
  final bool dimmed;
  final VoidCallback onTap;

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
      barValue: barValue,
      selected: selected,
      dimmed: dimmed,
      onTap: onTap,
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
    required this.barValue,
    required this.selected,
    required this.dimmed,
    required this.onTap,
    this.subtitleColor,
  });

  final Color color;
  final Widget leading;
  final String title;
  final String subtitle;
  final Color? subtitleColor;
  final Money amount;
  final int shareBps;
  final double barValue;
  final bool selected;
  final bool dimmed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        borderRadius: Radii.rLg,
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: AnimatedOpacity(
          duration: context.motion.fast,
          opacity: dimmed ? 0.45 : 1,
          child: AnimatedContainer(
            duration: context.motion.fast,
            padding: const EdgeInsets.symmetric(vertical: Space.x2, horizontal: Space.x2),
            decoration: BoxDecoration(
              color: selected ? color.withValues(alpha: c.isDark ? 0.18 : 0.09) : Colors.transparent,
              borderRadius: Radii.rLg,
            ),
            child: MergeSemantics(
              child: Row(
                children: [
                  leading,
                  const SizedBox(width: Space.x3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(child: Text(title, style: t.bodyStrong, maxLines: 1, overflow: TextOverflow.ellipsis)),
                            AmountText(amount, style: t.amountSmall, decimals: DecimalDisplay.none),
                          ],
                        ),
                        const SizedBox(height: Space.x1),
                        RelativeBar(value: barValue, color: color, height: 5),
                        const SizedBox(height: Space.x1),
                        Row(
                          children: [
                            Expanded(
                              child: Text(subtitle,
                                  style: t.micro.copyWith(color: subtitleColor ?? c.textSecondary, fontWeight: FontWeight.w700),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                            ),
                            Text(formatBps(shareBps), style: t.micro.copyWith(color: c.textTertiary, fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Diverging bars: which categories went up (right, red) or down (left,
/// green) compared with the previous period.
class _ChangesCard extends StatelessWidget {
  const _ChangesCard({required this.data});
  final InsightsData data;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final changes = [
      for (final s in data.categories)
        if (s.previous != null && s.amount != s.previous) (s, s.amount - s.previous!),
    ]..sort((a, b) => b.$2.abs().compareTo(a.$2.abs()));
    final list = changes.take(5).toList();
    final maxAbs = list.isEmpty ? 1.0 : list.first.$2.abs().toDouble();
    final up = Money.sum(changes.where((x) => x.$2.isPositive).map((x) => x.$2));
    final down = Money.sum(changes.where((x) => x.$2.isNegative).map((x) => x.$2.abs()));
    String m(Money x) => moneyText(context, x, compact: true);
    return InsightChartCard(
      icon: LucideIcons.arrowUpDown,
      accent: c.warning,
      title: list.isEmpty ? 'What changed' : 'Biggest changes vs ${data.previousLabel}',
      subtitle: list.isEmpty
          ? 'Nothing to compare yet'
          : 'Right (red) = spent more · Left (green) = spent less. '
              'Up ${m(up)}, down ${m(down)} overall.',
      child: list.isEmpty
          ? const InsightNoData(message: 'Once you have two periods of spending, changes show up here.', icon: LucideIcons.arrowUpDown)
          : Column(
              children: [
                for (final (s, delta) in list)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: Space.x1_5),
                    child: MergeSemantics(
                      child: Row(
                        children: [
                          SizedBox(
                            width: 92,
                            child: Text(s.name, style: t.label.copyWith(fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
                          ),
                          const SizedBox(width: Space.x2),
                          Expanded(child: _Diverging(value: delta.toDouble() / maxAbs)),
                          const SizedBox(width: Space.x2),
                          SizedBox(
                            width: 64,
                            child: Text(
                              '${delta.isNegative ? '−' : '+'}${m(delta.abs())}',
                              textAlign: TextAlign.end,
                              style: t.label.copyWith(
                                color: delta.isNegative ? c.positive : c.negative,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _Diverging extends StatelessWidget {
  const _Diverging({required this.value});

  /// −1 … 1.
  final double value;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GrowIn(
      builder: (context, t) => SizedBox(
        height: 14,
        child: LayoutBuilder(
          builder: (context, box) {
            final half = box.maxWidth / 2;
            final w = half * value.abs().clamp(0, 1) * t;
            return Stack(
              children: [
                Positioned(left: half - 0.5, top: 0, bottom: 0, child: Container(width: 1, color: c.borderStrong)),
                Positioned(
                  left: value < 0 ? half - w : half,
                  top: 2,
                  bottom: 2,
                  child: Container(
                    width: w,
                    decoration: BoxDecoration(
                      color: value < 0 ? c.positive : c.negative,
                      borderRadius: value < 0
                          ? const BorderRadius.horizontal(left: Radius.circular(4))
                          : const BorderRadius.horizontal(right: Radius.circular(4)),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Payments
// ---------------------------------------------------------------------------

IconData _methodIcon(PaymentMethod m) => switch (m) {
      PaymentMethod.upi => LucideIcons.smartphone,
      PaymentMethod.card => LucideIcons.creditCard,
      PaymentMethod.cash => LucideIcons.banknote,
      PaymentMethod.bankTransfer => LucideIcons.building2,
      PaymentMethod.wallet => LucideIcons.wallet,
      PaymentMethod.other => LucideIcons.circleDot,
    };

/// Payments: digital vs cash, and the split across payment methods.
List<Widget> paymentsSection(BuildContext context, InsightsData data) {
  final c = context.colors;
  final t = context.text;
  final total = data.current.expense;
  final digital = data.digitalShareBps;
  Color colorOf(int i) => c.chartSeries[i % c.chartSeries.length];
  return [
    TakeawayCard(
      icon: LucideIcons.smartphone,
      tone: FinnTone.info,
      title: digital == null
          ? 'No payments in ${data.periodLabel}'
          : '${formatBps(digital, decimals: 0)} of your spending was digital',
      body: digital == null
          ? 'Record expenses with a payment method to see how you pay.'
          : 'Cash covered ${formatBps(10000 - digital, decimals: 0)}. UPI, cards, bank transfers and wallets make up the rest.',
    ),
    InsightChartCard(
      icon: LucideIcons.creditCard,
      accent: c.accentTransactions,
      title: data.methodHeadline,
      subtitle: 'How you paid in ${data.periodLabel}. Each colour is one way of paying.',
      howCalculated: 'Share = spending through each payment method ÷ total spending. Expenses recorded without '
          'a method are counted as "Other".',
      child: data.methods.isEmpty
          ? const InsightNoData(message: 'No payments in this period.', icon: LucideIcons.creditCard)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SplitBar(
                  height: 18,
                  semanticLabel: data.methods
                      .map((m) => '${m.key.label} ${formatBps(m.value.ratioBps(total) ?? 0, decimals: 0)}')
                      .join(', '),
                  segments: [
                    for (var i = 0; i < data.methods.length; i++)
                      SplitSegment(data.methods[i].value.toDouble(), colorOf(i)),
                  ],
                ),
                const SizedBox(height: Space.x3),
                for (var i = 0; i < data.methods.length; i++)
                  MergeSemantics(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: Space.x2),
                      child: Row(
                        children: [
                          IconTile(
                            icon: _methodIcon(data.methods[i].key),
                            background: colorOf(i).withValues(alpha: c.isDark ? 0.22 : 0.14),
                            foreground: colorOf(i),
                            size: 32,
                            radius: Radii.md,
                            iconSize: 16,
                          ),
                          const SizedBox(width: Space.x3),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(child: Text(data.methods[i].key.label, style: t.bodyStrong)),
                                    AmountText(data.methods[i].value, style: t.amountSmall, decimals: DecimalDisplay.none),
                                    const SizedBox(width: Space.x2),
                                    SizedBox(
                                      width: 40,
                                      child: Text(
                                        formatBps(data.methods[i].value.ratioBps(total) ?? 0, decimals: 0),
                                        textAlign: TextAlign.end,
                                        style: t.label.copyWith(color: c.textSecondary),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: Space.x1_5),
                                RelativeBar(
                                  value: (data.methods[i].value.ratioBps(total) ?? 0) / 10000,
                                  color: colorOf(i),
                                  height: 6,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    ),
  ];
}
