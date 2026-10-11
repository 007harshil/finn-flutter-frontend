import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/time/dates.dart';
import '../../../design_system/design_system.dart';
import '../domain/analytics.dart';

/// Card wrapper used by every Insights chart: a takeaway title, a
/// subtitle, optional legend, the chart, and a "How this is calculated"
/// disclosure.
class InsightChartCard extends StatelessWidget {
  const InsightChartCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
    required this.howCalculated,
    this.legend = const [],
    this.icon,
    this.accent,
  });

  /// States the takeaway, e.g. "You spent 12% less than September".
  final String title;
  final String subtitle;
  final Widget child;
  final String howCalculated;
  final List<LegendEntry> legend;
  final IconData? icon;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final a = accent ?? c.accentAnalytics;
    return FinnCard(
      padding: const EdgeInsets.fromLTRB(Space.x4, Space.x4, Space.x4, Space.x1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (icon != null) ...[
                IconTile(
                  icon: icon!,
                  background: a.withValues(alpha: c.isDark ? 0.2 : 0.12),
                  foreground: a,
                  size: 32,
                  radius: Radii.md,
                  iconSize: 16,
                ),
                const SizedBox(width: Space.x3),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(header: true, child: Text(title, style: t.sectionTitle)),
                    const SizedBox(height: Space.x0_5),
                    Text(subtitle, style: t.caption.copyWith(color: c.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
          if (legend.isNotEmpty) ...[
            const SizedBox(height: Space.x3),
            Wrap(
              spacing: Space.x4,
              runSpacing: Space.x1,
              children: [for (final l in legend) _LegendChip(entry: l)],
            ),
          ],
          const SizedBox(height: Space.x4),
          child,
          const SizedBox(height: Space.x1),
          HowCalculated(text: howCalculated),
        ],
      ),
    );
  }
}

@immutable
class LegendEntry {
  const LegendEntry(this.label, this.color, {this.dashed = false});
  final String label;
  final Color color;
  final bool dashed;
}

class _LegendChip extends StatelessWidget {
  const _LegendChip({required this.entry});
  final LegendEntry entry;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: entry.color, borderRadius: BorderRadius.circular(3)),
        ),
        const SizedBox(width: Space.x1_5),
        Text(entry.label, style: context.text.caption.copyWith(color: context.colors.textSecondary)),
      ],
    );
  }
}

/// Expandable plain-language explanation of a calculation.
class HowCalculated extends StatefulWidget {
  const HowCalculated({super.key, required this.text, this.label = 'How this is calculated'});
  final String text;
  final String label;

  @override
  State<HowCalculated> createState() => _HowCalculatedState();
}

class _HowCalculatedState extends State<HowCalculated> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          expanded: _open,
          label: widget.label,
          excludeSemantics: true,
          child: InkWell(
            borderRadius: Radii.rMd,
            onTap: () => setState(() => _open = !_open),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: Dimens.minTouch),
              child: Row(
                children: [
                  Icon(LucideIcons.info, size: 14, color: c.textSecondary),
                  const SizedBox(width: Space.x1_5),
                  Expanded(
                    child: Text(widget.label, style: t.label.copyWith(color: c.textSecondary, fontWeight: FontWeight.w700)),
                  ),
                  AnimatedRotation(
                    turns: _open ? 0.5 : 0,
                    duration: context.motion.fast,
                    child: Icon(LucideIcons.chevronDown, size: 16, color: c.textTertiary),
                  ),
                ],
              ),
            ),
          ),
        ),
        MotionAnimatedSize(
          child: _open
              ? Padding(
                  padding: const EdgeInsets.only(bottom: Space.x3),
                  child: Text(widget.text, style: t.caption.copyWith(color: c.textSecondary, height: 1.45)),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Axis helpers
// ---------------------------------------------------------------------------

/// A "nice" grid step (1, 2, 2.5, 5 × 10ⁿ) giving about [ticks] intervals.
double niceStep(double span, {int ticks = 4}) {
  if (span <= 0 || !span.isFinite) return 1;
  final raw = span / ticks;
  final mag = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
  final r = raw / mag;
  final nice = r <= 1 ? 1.0 : (r <= 2 ? 2.0 : (r <= 2.5 ? 2.5 : (r <= 5 ? 5.0 : 10.0)));
  return nice * mag;
}

String _axisMoney(double rupees) => MoneyFormatter.compact(Money.fromPaise((rupees * 100).round()));

const _monthAbbr = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String monthAbbr(MonthKey m) => _monthAbbr[m.month - 1];

String monthLong(MonthKey m) => DateFormats.monthYear.format(m.start);

FlTitlesData _titles(
  BuildContext context, {
  required List<MonthKey> months,
  required double interval,
  required bool hidden,
}) {
  final c = context.colors;
  final style = context.text.micro.copyWith(color: c.textTertiary, fontWeight: FontWeight.w700);
  final n = months.length;
  return FlTitlesData(
    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    leftTitles: AxisTitles(
      sideTitles: SideTitles(
        showTitles: !hidden,
        reservedSize: 46,
        interval: interval,
        getTitlesWidget: (v, meta) {
          if (v == meta.max && v != meta.min && (meta.max / interval) % 1 != 0) return const SizedBox.shrink();
          return SideTitleWidget(meta: meta, space: 6, child: Text(_axisMoney(v), style: style));
        },
      ),
    ),
    bottomTitles: AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: 24,
        interval: 1,
        getTitlesWidget: (v, meta) {
          final i = v.round();
          if (i < 0 || i >= n || (v - i).abs() > 0.01) return const SizedBox.shrink();
          if (n > 6 && i.isOdd && i != n - 1) return const SizedBox.shrink();
          return SideTitleWidget(meta: meta, space: 6, child: Text(monthAbbr(months[i]), style: style));
        },
      ),
    ),
  );
}

FlGridData _grid(BuildContext context, double interval) => FlGridData(
      show: true,
      drawVerticalLine: false,
      horizontalInterval: interval,
      getDrawingHorizontalLine: (_) => FlLine(color: context.colors.border, strokeWidth: 1, dashArray: const [3, 4]),
    );

String _tooltipMoney(Money m, bool hidden, {SignDisplay sign = SignDisplay.auto}) =>
    hidden ? MoneyFormatter.masked : MoneyFormatter.format(m, sign: sign, decimals: DecimalDisplay.none);

// ---------------------------------------------------------------------------
// Charts. Swap animations are disabled (duration zero): changing the time
// filter should feel like an instant re-read, not a performance.
// ---------------------------------------------------------------------------

/// Grouped bars: income and spending per month.
class IncomeExpenseBarChart extends StatelessWidget {
  const IncomeExpenseBarChart({super.key, required this.months, this.height = 200});
  final List<MonthlyCashFlow> months;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final hidden = AmountVisibility.hiddenOf(context);
    final maxV = months.fold<double>(0, (m, x) => math.max(m, math.max(x.income.toDouble(), x.expense.toDouble())));
    final interval = niceStep(maxV == 0 ? 1000 : maxV);
    final maxY = (maxV / interval).ceil() * interval;
    final rodWidth = months.length > 6 ? 6.0 : 10.0;
    final label = months
        .map((m) => '${monthLong(m.month)}: income ${hidden ? 'hidden' : m.income.whole}, '
            'spending ${hidden ? 'hidden' : m.expense.whole}')
        .join('. ');
    return Semantics(
      label: 'Bar chart of income and spending by month. $label',
      excludeSemantics: true,
      child: SizedBox(
        height: height,
        child: BarChart(
          BarChartData(
            maxY: maxY == 0 ? interval : maxY,
            minY: 0,
            alignment: BarChartAlignment.spaceAround,
            gridData: _grid(context, interval),
            borderData: FlBorderData(show: false),
            titlesData: _titles(context, months: [for (final m in months) m.month], interval: interval, hidden: hidden),
            barTouchData: BarTouchData(
              touchTooltipData: BarTouchTooltipData(
                getTooltipColor: (_) => c.primary,
                tooltipBorderRadius: Radii.rMd,
                fitInsideHorizontally: true,
                fitInsideVertically: true,
                getTooltipItem: (group, gi, rod, ri) {
                  final m = months[group.x];
                  final isIncome = ri == 0;
                  return BarTooltipItem(
                    '${monthAbbr(m.month)} · ${isIncome ? 'Income' : 'Spending'}\n',
                    context.text.micro.copyWith(color: c.onPrimary.withValues(alpha: 0.75)),
                    children: [
                      TextSpan(
                        text: _tooltipMoney(isIncome ? m.income : m.expense, hidden),
                        style: context.text.label.copyWith(color: c.onPrimary, fontWeight: FontWeight.w800),
                      ),
                    ],
                  );
                },
              ),
            ),
            barGroups: [
              for (var i = 0; i < months.length; i++)
                BarChartGroupData(
                  x: i,
                  barsSpace: 3,
                  barRods: [
                    BarChartRodData(
                      toY: months[i].income.toDouble(),
                      color: c.positive,
                      width: rodWidth,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                    ),
                    BarChartRodData(
                      toY: months[i].expense.toDouble(),
                      color: c.negative,
                      width: rodWidth,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                    ),
                  ],
                ),
            ],
          ),
          duration: Duration.zero,
        ),
      ),
    );
  }
}

/// Monthly net (income − spending) with a zero line.
class NetCashFlowChart extends StatelessWidget {
  const NetCashFlowChart({super.key, required this.months, this.height = 180});
  final List<MonthlyCashFlow> months;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final hidden = AmountVisibility.hiddenOf(context);
    final values = [for (final m in months) m.net.toDouble()];
    final maxV = values.fold<double>(0, math.max);
    final minV = values.fold<double>(0, math.min);
    final interval = niceStep(math.max(maxV - minV, 1000));
    final maxY = maxV <= 0 ? interval : (maxV / interval).ceil() * interval;
    final minY = minV >= 0 ? 0.0 : (minV / interval).floor() * interval;
    final label = months
        .map((m) => '${monthLong(m.month)}: ${hidden ? 'hidden' : (m.net.isNegative ? 'deficit ${m.net.abs().whole}' : 'surplus ${m.net.whole}')}')
        .join('. ');
    return Semantics(
      label: 'Bar chart of net cash flow by month. $label',
      excludeSemantics: true,
      child: SizedBox(
        height: height,
        child: BarChart(
          BarChartData(
            maxY: maxY,
            minY: minY,
            alignment: BarChartAlignment.spaceAround,
            gridData: _grid(context, interval),
            borderData: FlBorderData(show: false),
            titlesData: _titles(context, months: [for (final m in months) m.month], interval: interval, hidden: hidden),
            extraLinesData: ExtraLinesData(
              horizontalLines: [HorizontalLine(y: 0, color: c.borderStrong, strokeWidth: 1.5)],
            ),
            barTouchData: BarTouchData(
              touchTooltipData: BarTouchTooltipData(
                getTooltipColor: (_) => c.primary,
                tooltipBorderRadius: Radii.rMd,
                fitInsideHorizontally: true,
                fitInsideVertically: true,
                getTooltipItem: (group, gi, rod, ri) {
                  final m = months[group.x];
                  return BarTooltipItem(
                    '${monthAbbr(m.month)} · ${m.net.isNegative ? 'Deficit' : 'Surplus'}\n',
                    context.text.micro.copyWith(color: c.onPrimary.withValues(alpha: 0.75)),
                    children: [
                      TextSpan(
                        text: _tooltipMoney(m.net, hidden, sign: SignDisplay.always),
                        style: context.text.label.copyWith(color: c.onPrimary, fontWeight: FontWeight.w800),
                      ),
                    ],
                  );
                },
              ),
            ),
            barGroups: [
              for (var i = 0; i < months.length; i++)
                BarChartGroupData(
                  x: i,
                  barRods: [
                    BarChartRodData(
                      toY: values[i],
                      color: values[i] < 0 ? c.negative : c.positive,
                      width: months.length > 6 ? 10 : 16,
                      borderRadius: values[i] < 0
                          ? const BorderRadius.vertical(bottom: Radius.circular(3))
                          : const BorderRadius.vertical(top: Radius.circular(3)),
                    ),
                  ],
                ),
            ],
          ),
          duration: Duration.zero,
        ),
      ),
    );
  }
}

/// Month-end balance trend (savings, debt).
class TrendLineChart extends StatelessWidget {
  const TrendLineChart({
    super.key,
    required this.points,
    required this.color,
    required this.seriesLabel,
    this.height = 170,
  });

  final List<TrendPoint> points;
  final Color color;
  final String seriesLabel;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final hidden = AmountVisibility.hiddenOf(context);
    final values = [for (final p in points) p.value.toDouble()];
    final maxV = values.fold<double>(0, math.max);
    final interval = niceStep(maxV == 0 ? 1000 : maxV);
    final maxY = math.max(interval, (maxV / interval).ceil() * interval);
    final label = points.map((p) => '${monthLong(p.month)}: ${hidden ? 'hidden' : p.value.whole}').join('. ');
    return Semantics(
      label: 'Line chart of $seriesLabel at each month end. $label',
      excludeSemantics: true,
      child: SizedBox(
        height: height,
        child: LineChart(
          LineChartData(
            minX: 0,
            maxX: math.max(1, points.length - 1).toDouble(),
            minY: 0,
            maxY: maxY,
            gridData: _grid(context, interval),
            borderData: FlBorderData(show: false),
            titlesData: _titles(context, months: [for (final p in points) p.month], interval: interval, hidden: hidden),
            lineTouchData: LineTouchData(
              touchTooltipData: LineTouchTooltipData(
                getTooltipColor: (_) => c.primary,
                tooltipBorderRadius: Radii.rMd,
                fitInsideHorizontally: true,
                fitInsideVertically: true,
                getTooltipItems: (spots) => [
                  for (final s in spots)
                    LineTooltipItem(
                      '${monthAbbr(points[s.x.round()].month)} · $seriesLabel\n',
                      context.text.micro.copyWith(color: c.onPrimary.withValues(alpha: 0.75)),
                      children: [
                        TextSpan(
                          text: _tooltipMoney(points[s.x.round()].value, hidden),
                          style: context.text.label.copyWith(color: c.onPrimary, fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            lineBarsData: [
              LineChartBarData(
                spots: [for (var i = 0; i < values.length; i++) FlSpot(i.toDouble(), values[i])],
                color: color,
                barWidth: 2.5,
                isCurved: false,
                dotData: FlDotData(
                  show: true,
                  getDotPainter: (spot, _, _, _) => FlDotCirclePainter(
                    radius: 3,
                    color: c.surface,
                    strokeColor: color,
                    strokeWidth: 2,
                  ),
                ),
                belowBarData: BarAreaData(show: true, color: color.withValues(alpha: c.isDark ? 0.18 : 0.1)),
              ),
            ],
          ),
          duration: Duration.zero,
        ),
      ),
    );
  }
}

/// One slice of the category donut (already grouped and coloured).
@immutable
class DonutSlice {
  const DonutSlice({required this.label, required this.amount, required this.color});
  final String label;
  final Money amount;
  final Color color;
}

/// Category donut with the total in the centre.
class CategoryDonut extends StatelessWidget {
  const CategoryDonut({super.key, required this.slices, required this.total, this.size = 188});
  final List<DonutSlice> slices;
  final Money total;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = context.text;
    final hidden = AmountVisibility.hiddenOf(context);
    final ring = size * 0.14;
    return Semantics(
      label: 'Donut chart of spending by category, total ${hidden ? 'hidden' : total.whole}. '
          '${slices.map((s) => '${s.label} ${formatBps(s.amount.ratioBps(total) ?? 0, decimals: 0)}').join(', ')}',
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            PieChart(
              PieChartData(
                startDegreeOffset: -90,
                sectionsSpace: slices.length > 1 ? 2 : 0,
                centerSpaceRadius: size / 2 - ring,
                pieTouchData: PieTouchData(enabled: false),
                borderData: FlBorderData(show: false),
                sections: [
                  for (final s in slices)
                    PieChartSectionData(value: s.amount.toDouble(), color: s.color, radius: ring, showTitle: false),
                ],
              ),
              duration: Duration.zero,
            ),
            Padding(
              padding: EdgeInsets.all(ring + Space.x2),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('SPENT', style: t.eyebrow),
                  const SizedBox(height: Space.x0_5),
                  AmountText(total, style: t.amountMedium, compact: true, fit: true, textAlign: TextAlign.center),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
