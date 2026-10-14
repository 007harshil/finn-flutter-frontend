import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/time/dates.dart';
import '../../../kit/kit.dart';
import '../application/analytics_providers.dart';
import '../domain/analytics.dart';
import 'insight_widgets.dart';

/// A chart in its own section: the section title, then one panel with the
/// takeaway sentence, the chart, its colour key and an optional "How this
/// is calculated" disclosure.
class InsightChartCard extends StatelessWidget {
  const InsightChartCard({
    super.key,
    required this.heading,
    required this.title,
    required this.child,
    this.subtitle,
    this.howCalculated,
    this.legend = const [],
  });

  /// Short section title ("Day by day").
  final String heading;

  /// States the takeaway, e.g. "You spent 12% less than September".
  final String title;
  final String? subtitle;
  final Widget child;
  final String? howCalculated;
  final List<LegendEntry> legend;

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    final how = howCalculated;
    final sub = subtitle;
    return LedgerSection(
      title: heading,
      child: LedgerPanel(
        padding: EdgeInsets.fromLTRB(Sp.lg, Sp.lg, Sp.lg, how == null ? Sp.lg : 0),
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: t.bodyStrong),
              if (sub != null) ...[
                const SizedBox(height: 2),
                Text(sub, style: t.label),
              ],
              const SizedBox(height: Sp.lg),
              child,
              if (legend.isNotEmpty) ...[
                const SizedBox(height: Sp.md),
                Wrap(
                  spacing: Sp.lg,
                  runSpacing: Sp.xs,
                  children: [for (final l in legend) _LegendKey(entry: l)],
                ),
              ],
              if (how != null) ...[
                const SizedBox(height: Sp.xs),
                HowCalculated(text: how),
              ],
            ],
          ),
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

class _LegendKey extends StatelessWidget {
  const _LegendKey({required this.entry});
  final LegendEntry entry;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        InsightSwatch(color: entry.color, dashed: entry.dashed),
        const SizedBox(width: Sp.sm - 2),
        Text(entry.label, style: context.type.small),
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
    final c = context.ink;
    final t = context.type;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          expanded: _open,
          label: widget.label,
          excludeSemantics: true,
          child: InkWell(
            borderRadius: Rad.rSm,
            onTap: () => setState(() => _open = !_open),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Row(
                children: [
                  Expanded(child: Text(widget.label, style: t.label)),
                  AnimatedRotation(
                    turns: _open ? 0.5 : 0,
                    duration: context.motion.fast,
                    child: Icon(LucideIcons.chevronDown, size: 18, color: c.inkSoft),
                  ),
                ],
              ),
            ),
          ),
        ),
        MotionAnimatedSize(
          child: _open
              ? Padding(
                  padding: const EdgeInsets.only(bottom: Sp.md),
                  child: Text(widget.text, style: t.label.copyWith(color: c.ink)),
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

const weekdayNames = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
const _weekdayShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

TextStyle _axisStyle(BuildContext context) =>
    context.type.small.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);

AxisTitles _leftMoneyTitles(BuildContext context, double interval, bool hidden) => AxisTitles(
      sideTitles: SideTitles(
        showTitles: !hidden,
        reservedSize: 50,
        interval: interval,
        getTitlesWidget: (v, meta) {
          if (v == meta.max && v != meta.min && (meta.max / interval) % 1 != 0) return const SizedBox.shrink();
          return SideTitleWidget(meta: meta, space: 6, child: Text(_axisMoney(v), style: _axisStyle(context)));
        },
      ),
    );

FlTitlesData _titles(
  BuildContext context, {
  required int count,
  required String Function(int i) label,
  required bool Function(int i, int n) show,
  required double interval,
  required bool hidden,
}) {
  return FlTitlesData(
    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    leftTitles: _leftMoneyTitles(context, interval, hidden),
    bottomTitles: AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: 26,
        interval: 1,
        getTitlesWidget: (v, meta) {
          final i = v.round();
          if (i < 0 || i >= count || (v - i).abs() > 0.01 || !show(i, count)) return const SizedBox.shrink();
          return SideTitleWidget(meta: meta, space: 6, child: Text(label(i), style: _axisStyle(context)));
        },
      ),
    ),
  );
}

FlTitlesData _monthTitles(BuildContext context, List<MonthKey> months, double interval, bool hidden) => _titles(
      context,
      count: months.length,
      label: (i) => monthAbbr(months[i]),
      show: (i, n) => n <= 6 || i.isEven || i == n - 1,
      interval: interval,
      hidden: hidden,
    );

FlGridData _grid(BuildContext context, double interval) => FlGridData(
      show: true,
      drawVerticalLine: false,
      horizontalInterval: interval,
      getDrawingHorizontalLine: (_) => FlLine(color: context.ink.line, strokeWidth: 1),
    );

String _tooltipMoney(Money m, bool hidden, {SignDisplay sign = SignDisplay.auto}) =>
    hidden ? MoneyFormatter.masked : MoneyFormatter.format(m, sign: sign, decimals: DecimalDisplay.none);

/// Dashed "your average" baseline with a compact label at the right edge.
HorizontalLine _averageLine(BuildContext context, double y, String label, bool hidden) {
  final c = context.ink;
  return HorizontalLine(
    y: y,
    color: c.inkSoft,
    strokeWidth: 1,
    dashArray: const [4, 4],
    label: HorizontalLineLabel(
      show: true,
      alignment: Alignment.topRight,
      padding: const EdgeInsets.only(right: 2, bottom: 2),
      style: _axisStyle(context),
      labelResolver: (_) => hidden ? label : '$label ${_axisMoney(y)}',
    ),
  );
}

BarTouchTooltipData _barTooltip(BuildContext context, BarTooltipItem? Function(int group, int rod) item) {
  final c = context.ink;
  return BarTouchTooltipData(
    getTooltipColor: (_) => c.ink,
    tooltipBorderRadius: Rad.rSm,
    fitInsideHorizontally: true,
    fitInsideVertically: true,
    getTooltipItem: (group, gi, rod, ri) => item(group.x, ri),
  );
}

BarTooltipItem _tip(BuildContext context, String heading, String value, {String? note}) {
  final c = context.ink;
  final t = context.type;
  return BarTooltipItem(
    '$heading\n',
    t.small.copyWith(color: c.onInk.withValues(alpha: 0.8)),
    children: [
      TextSpan(text: value, style: t.figure.copyWith(color: c.onInk)),
      if (note != null) TextSpan(text: '\n$note', style: t.small.copyWith(color: c.onInk.withValues(alpha: 0.8))),
    ],
  );
}

/// "1.8× your average" / "Below your average" for tooltips.
String _vsAverage(Money v, Money avg) {
  if (!avg.isPositive || v.isZero) return v.isZero ? 'Nothing spent' : '';
  final ratio = v.paise / avg.paise;
  if (ratio >= 1.15) return '${ratio.toStringAsFixed(1)}× your average';
  if (ratio <= 0.85) return 'Below your average';
  return 'About your average';
}

void _haptic(FlTouchEvent e) {
  if (e is FlTapDownEvent) HapticFeedback.selectionClick();
}

const _top = BorderRadius.vertical(top: Radius.circular(3));

// ---------------------------------------------------------------------------
// Charts. Ink and greys for bars and axes; green only for money in, red
// only for overspending. Each grows into place once (GrowIn); fl_chart's
// own swap animation stays off so the entrance is the only motion.
// ---------------------------------------------------------------------------

/// Grouped bars: income (green) and spending (ink) per month, with the
/// average spend.
class IncomeExpenseBarChart extends StatelessWidget {
  const IncomeExpenseBarChart({super.key, required this.months, this.averageExpense, this.height = 210});
  final List<MonthlyCashFlow> months;
  final Money? averageExpense;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final hidden = AmountVisibility.hiddenOf(context);
    final maxV = months.fold<double>(0, (m, x) => math.max(m, math.max(x.income.toDouble(), x.expense.toDouble())));
    final interval = niceStep(maxV == 0 ? 1000 : maxV);
    final maxY = (maxV / interval).ceil() * interval;
    final rodWidth = months.length > 6 ? 6.0 : 10.0;
    final avg = averageExpense;
    final label = months
        .map((m) => '${monthLong(m.month)}: income ${hidden ? 'hidden' : m.income.whole}, '
            'spending ${hidden ? 'hidden' : m.expense.whole}')
        .join('. ');
    return Semantics(
      label: 'Bar chart of income and spending by month. $label',
      excludeSemantics: true,
      child: GrowIn(
        builder: (context, t) => SizedBox(
          height: height,
          child: BarChart(
            BarChartData(
              maxY: maxY == 0 ? interval : maxY,
              minY: 0,
              alignment: BarChartAlignment.spaceAround,
              gridData: _grid(context, interval),
              borderData: FlBorderData(show: false),
              titlesData: _monthTitles(context, [for (final m in months) m.month], interval, hidden),
              extraLinesData: ExtraLinesData(horizontalLines: [
                if (avg != null && avg.isPositive) _averageLine(context, avg.toDouble() * t, 'Avg spend', hidden),
              ]),
              barTouchData: BarTouchData(
                touchCallback: (e, _) => _haptic(e),
                touchTooltipData: _barTooltip(context, (x, ri) {
                  final m = months[x];
                  final isIncome = ri == 0;
                  return _tip(
                    context,
                    '${monthAbbr(m.month)}, ${isIncome ? 'income' : 'spending'}',
                    _tooltipMoney(isIncome ? m.income : m.expense, hidden),
                  );
                }),
              ),
              barGroups: [
                for (var i = 0; i < months.length; i++)
                  BarChartGroupData(
                    x: i,
                    barsSpace: 3,
                    barRods: [
                      BarChartRodData(toY: months[i].income.toDouble() * t, color: c.green, width: rodWidth, borderRadius: _top),
                      BarChartRodData(toY: months[i].expense.toDouble() * t, color: c.ink, width: rodWidth, borderRadius: _top),
                    ],
                  ),
              ],
            ),
            duration: Duration.zero,
          ),
        ),
      ),
    );
  }
}

/// Monthly net (income − spending) with a zero line and the average.
/// Kept money is green, overspending red.
class NetCashFlowChart extends StatelessWidget {
  const NetCashFlowChart({super.key, required this.months, this.average, this.height = 190});
  final List<MonthlyCashFlow> months;
  final Money? average;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final hidden = AmountVisibility.hiddenOf(context);
    final values = [for (final m in months) m.net.toDouble()];
    final maxV = values.fold<double>(0, math.max);
    final minV = values.fold<double>(0, math.min);
    final interval = niceStep(math.max(maxV - minV, 1000));
    final maxY = maxV <= 0 ? interval : (maxV / interval).ceil() * interval;
    final minY = minV >= 0 ? 0.0 : (minV / interval).floor() * interval;
    final avg = average;
    final label = months
        .map((m) => '${monthLong(m.month)}: ${hidden ? 'hidden' : (m.net.isNegative ? 'deficit ${m.net.abs().whole}' : 'surplus ${m.net.whole}')}')
        .join('. ');
    return Semantics(
      label: 'Bar chart of money saved each month. $label',
      excludeSemantics: true,
      child: GrowIn(
        builder: (context, t) => SizedBox(
          height: height,
          child: BarChart(
            BarChartData(
              maxY: maxY,
              minY: minY,
              alignment: BarChartAlignment.spaceAround,
              gridData: _grid(context, interval),
              borderData: FlBorderData(show: false),
              titlesData: _monthTitles(context, [for (final m in months) m.month], interval, hidden),
              extraLinesData: ExtraLinesData(
                horizontalLines: [
                  HorizontalLine(y: 0, color: c.lineStrong, strokeWidth: 1),
                  if (avg != null && !avg.isZero) _averageLine(context, avg.toDouble() * t, 'Avg', hidden),
                ],
              ),
              barTouchData: BarTouchData(
                touchCallback: (e, _) => _haptic(e),
                touchTooltipData: _barTooltip(context, (x, _) {
                  final m = months[x];
                  return _tip(
                    context,
                    '${monthAbbr(m.month)}, ${m.net.isNegative ? 'overspent' : 'saved'}',
                    _tooltipMoney(m.net, hidden, sign: SignDisplay.always),
                  );
                }),
              ),
              barGroups: [
                for (var i = 0; i < months.length; i++)
                  BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: values[i] * t,
                        color: values[i] < 0 ? c.red : c.green,
                        width: months.length > 6 ? 10 : 16,
                        borderRadius: values[i] < 0 ? const BorderRadius.vertical(bottom: Radius.circular(3)) : _top,
                      ),
                    ],
                  ),
              ],
            ),
            duration: Duration.zero,
          ),
        ),
      ),
    );
  }
}

/// Bar per day of the month. Days above the daily average are ink, the
/// rest a quiet grey; the dashed line is the average.
class DailySpendChart extends StatelessWidget {
  const DailySpendChart({super.key, required this.days, required this.average, this.height = 200});
  final List<DaySpend> days;
  final Money average;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final hidden = AmountVisibility.hiddenOf(context);
    final maxV = days.fold<double>(0, (m, d) => math.max(m, d.amount.toDouble()));
    final interval = niceStep(maxV == 0 ? 1000 : maxV);
    final maxY = math.max(interval, (maxV / interval).ceil() * interval);
    final avg = average.toDouble();
    final spent = days.where((d) => !d.isFuture && d.amount.isPositive);
    final label = hidden
        ? 'Amounts hidden.'
        : spent.map((d) => '${DateFormats.dayMonth.format(d.date)} ${d.amount.whole}').join(', ');
    return Semantics(
      label: 'Bar chart of spending on each day. Daily average ${hidden ? 'hidden' : average.whole}. $label',
      excludeSemantics: true,
      child: GrowIn(
        builder: (context, t) => SizedBox(
          height: height,
          child: BarChart(
            BarChartData(
              maxY: maxY,
              minY: 0,
              alignment: BarChartAlignment.spaceBetween,
              gridData: _grid(context, interval),
              borderData: FlBorderData(show: false),
              titlesData: _titles(
                context,
                count: days.length,
                label: (i) => '${days[i].date.day}',
                show: (i, n) => i == 0 || (i + 1) % 7 == 0 || i == n - 1 && (n - 1) % 7 > 2,
                interval: interval,
                hidden: hidden,
              ),
              extraLinesData: ExtraLinesData(horizontalLines: [
                if (avg > 0) _averageLine(context, avg * t, 'Avg', hidden),
              ]),
              barTouchData: BarTouchData(
                touchCallback: (e, _) => _haptic(e),
                touchTooltipData: _barTooltip(context, (x, _) {
                  final d = days[x];
                  if (d.isFuture) return _tip(context, DateFormats.shortWeekdayDayMonth.format(d.date), 'Still ahead');
                  final note = _vsAverage(d.amount, average);
                  return _tip(
                    context,
                    DateFormats.shortWeekdayDayMonth.format(d.date),
                    _tooltipMoney(d.amount, hidden),
                    note: note.isEmpty ? null : note,
                  );
                }),
              ),
              barGroups: [
                for (var i = 0; i < days.length; i++)
                  BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: days[i].amount.toDouble() * t,
                        color: avg > 0 && days[i].amount.toDouble() > avg ? c.ink : c.lineStrong,
                        width: 5,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
                        backDrawRodData: BackgroundBarChartRodData(
                          show: days[i].isFuture,
                          toY: maxY,
                          color: c.sunken,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            duration: Duration.zero,
          ),
        ),
      ),
    );
  }
}

/// Spending per month with the monthly average (multi-month views).
/// Months more than 10% above the average are ink.
class MonthlySpendChart extends StatelessWidget {
  const MonthlySpendChart({super.key, required this.months, required this.average, this.height = 200});
  final List<MonthlyCashFlow> months;
  final Money average;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final hidden = AmountVisibility.hiddenOf(context);
    final maxV = months.fold<double>(0, (m, x) => math.max(m, x.expense.toDouble()));
    final interval = niceStep(maxV == 0 ? 1000 : maxV);
    final maxY = math.max(interval, (maxV / interval).ceil() * interval);
    final avg = average.toDouble();
    final label = months.map((m) => '${monthLong(m.month)}: ${hidden ? 'hidden' : m.expense.whole}').join('. ');
    return Semantics(
      label: 'Bar chart of spending by month. $label',
      excludeSemantics: true,
      child: GrowIn(
        builder: (context, t) => SizedBox(
          height: height,
          child: BarChart(
            BarChartData(
              maxY: maxY,
              minY: 0,
              alignment: BarChartAlignment.spaceAround,
              gridData: _grid(context, interval),
              borderData: FlBorderData(show: false),
              titlesData: _monthTitles(context, [for (final m in months) m.month], interval, hidden),
              extraLinesData: ExtraLinesData(horizontalLines: [
                if (avg > 0) _averageLine(context, avg * t, 'Avg', hidden),
              ]),
              barTouchData: BarTouchData(
                touchCallback: (e, _) => _haptic(e),
                touchTooltipData: _barTooltip(context, (x, _) {
                  final m = months[x];
                  final note = _vsAverage(m.expense, average);
                  return _tip(context, monthLong(m.month), _tooltipMoney(m.expense, hidden), note: note.isEmpty ? null : note);
                }),
              ),
              barGroups: [
                for (var i = 0; i < months.length; i++)
                  BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: months[i].expense.toDouble() * t,
                        color: avg > 0 && months[i].expense.toDouble() > avg * 1.1 ? c.ink : c.lineStrong,
                        width: months.length > 6 ? 12 : 20,
                        borderRadius: _top,
                      ),
                    ],
                  ),
              ],
            ),
            duration: Duration.zero,
          ),
        ),
      ),
    );
  }
}

/// Average spend on each weekday; the priciest day is ink.
class WeekdayChart extends StatelessWidget {
  const WeekdayChart({super.key, required this.averages, this.height = 170});
  final List<Money> averages;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final hidden = AmountVisibility.hiddenOf(context);
    final values = [for (final m in averages) m.toDouble()];
    final maxV = values.fold<double>(0, math.max);
    final interval = niceStep(maxV == 0 ? 1000 : maxV, ticks: 3);
    final maxY = math.max(interval, (maxV / interval).ceil() * interval);
    final peak = maxV <= 0 ? -1 : values.indexOf(maxV);
    final label = [
      for (var i = 0; i < 7; i++) '${weekdayNames[i]} ${hidden ? 'hidden' : averages[i].whole}',
    ].join(', ');
    return Semantics(
      label: 'Bar chart of average spending by weekday. $label',
      excludeSemantics: true,
      child: GrowIn(
        builder: (context, t) => SizedBox(
          height: height,
          child: BarChart(
            BarChartData(
              maxY: maxY,
              minY: 0,
              alignment: BarChartAlignment.spaceAround,
              gridData: _grid(context, interval),
              borderData: FlBorderData(show: false),
              titlesData: _titles(
                context,
                count: 7,
                label: (i) => _weekdayShort[i],
                show: (_, _) => true,
                interval: interval,
                hidden: hidden,
              ),
              barTouchData: BarTouchData(
                touchCallback: (e, _) => _haptic(e),
                touchTooltipData: _barTooltip(
                  context,
                  (x, _) => _tip(context, '${weekdayNames[x]}s', _tooltipMoney(averages[x], hidden), note: 'on a typical day'),
                ),
              ),
              barGroups: [
                for (var i = 0; i < 7; i++)
                  BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: values[i] * t,
                        color: i == peak ? c.ink : c.lineStrong,
                        width: 18,
                        borderRadius: _top,
                      ),
                    ],
                  ),
              ],
            ),
            duration: Duration.zero,
          ),
        ),
      ),
    );
  }
}

/// Month-end balance trend (savings, debt): a plain line with the latest
/// point marked.
class TrendLineChart extends StatelessWidget {
  const TrendLineChart({
    super.key,
    required this.points,
    required this.seriesLabel,
    this.color,
    this.height = 180,
  });

  final List<TrendPoint> points;

  /// Line colour; ink by default.
  final Color? color;
  final String seriesLabel;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final type = context.type;
    final line = color ?? c.ink;
    final hidden = AmountVisibility.hiddenOf(context);
    final values = [for (final p in points) p.value.toDouble()];
    final maxV = values.fold<double>(0, math.max);
    final interval = niceStep(maxV == 0 ? 1000 : maxV);
    final maxY = math.max(interval, (maxV / interval).ceil() * interval);
    final label = points.map((p) => '${monthLong(p.month)}: ${hidden ? 'hidden' : p.value.whole}').join('. ');
    return Semantics(
      label: 'Line chart of $seriesLabel at each month end. $label',
      excludeSemantics: true,
      child: GrowIn(
        builder: (context, t) => SizedBox(
          height: height,
          child: LineChart(
            LineChartData(
              minX: 0,
              maxX: math.max(1, points.length - 1).toDouble(),
              minY: 0,
              maxY: maxY,
              gridData: _grid(context, interval),
              borderData: FlBorderData(show: false),
              titlesData: _monthTitles(context, [for (final p in points) p.month], interval, hidden),
              lineTouchData: LineTouchData(
                touchCallback: (e, _) => _haptic(e),
                getTouchedSpotIndicator: (bar, idx) => [
                  for (var i = 0; i < idx.length; i++)
                    TouchedSpotIndicatorData(
                      FlLine(color: c.inkSoft, strokeWidth: 1),
                      FlDotData(
                        getDotPainter: (_, _, _, _) =>
                            FlDotCirclePainter(radius: 4, color: line, strokeColor: c.surface, strokeWidth: 2),
                      ),
                    ),
                ],
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (_) => c.ink,
                  tooltipBorderRadius: Rad.rSm,
                  fitInsideHorizontally: true,
                  fitInsideVertically: true,
                  getTooltipItems: (spots) => [
                    for (final s in spots)
                      LineTooltipItem(
                        '${monthAbbr(points[s.x.round()].month)}, ${seriesLabel.toLowerCase()}\n',
                        type.small.copyWith(color: c.onInk.withValues(alpha: 0.8)),
                        children: [
                          TextSpan(
                            text: _tooltipMoney(points[s.x.round()].value, hidden),
                            style: type.figure.copyWith(color: c.onInk),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: [for (var i = 0; i < values.length; i++) FlSpot(i.toDouble(), values[i] * t)],
                  color: line,
                  barWidth: 2,
                  isCurved: false,
                  dotData: FlDotData(
                    show: true,
                    checkToShowDot: (spot, _) => spot.x.round() == values.length - 1,
                    getDotPainter: (_, _, _, _) =>
                        FlDotCirclePainter(radius: 4, color: line, strokeColor: c.surface, strokeWidth: 2),
                  ),
                  belowBarData: BarAreaData(show: false),
                ),
              ],
            ),
            duration: Duration.zero,
          ),
        ),
      ),
    );
  }
}
