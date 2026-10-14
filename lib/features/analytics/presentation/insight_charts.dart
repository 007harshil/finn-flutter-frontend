import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/time/dates.dart';
import '../../../design_system/design_system.dart';
import '../application/analytics_providers.dart';
import '../domain/analytics.dart';
import 'insight_widgets.dart';

/// Card wrapper used by every Insights chart: a takeaway title, a
/// subtitle, optional legend, the chart, and an optional "How this is
/// calculated" disclosure.
class InsightChartCard extends StatelessWidget {
  const InsightChartCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
    this.howCalculated,
    this.legend = const [],
    this.icon,
    this.accent,
  });

  /// States the takeaway, e.g. "You spent 12% less than September".
  final String title;
  final String subtitle;
  final Widget child;
  final String? howCalculated;
  final List<LegendEntry> legend;
  final IconData? icon;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final a = accent ?? c.accentAnalytics;
    final how = howCalculated;
    return FinnCard(
      padding: EdgeInsets.fromLTRB(Space.x4, Space.x4, Space.x4, how == null ? Space.x4 : Space.x1),
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
          if (how != null) ...[
            const SizedBox(height: Space.x1),
            HowCalculated(text: how),
          ],
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
        if (entry.dashed)
          SizedBox(
            width: 14,
            height: 10,
            child: CustomPaint(painter: _DashPainter(entry.color)),
          )
        else
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

class _DashPainter extends CustomPainter {
  _DashPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final y = size.height / 2;
    canvas.drawLine(Offset(0, y), Offset(size.width * 0.4, y), p);
    canvas.drawLine(Offset(size.width * 0.6, y), Offset(size.width, y), p);
  }

  @override
  bool shouldRepaint(_DashPainter old) => old.color != color;
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

const weekdayNames = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
const _weekdayShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

TextStyle _axisStyle(BuildContext context) =>
    context.text.micro.copyWith(color: context.colors.textTertiary, fontWeight: FontWeight.w700);

AxisTitles _leftMoneyTitles(BuildContext context, double interval, bool hidden) => AxisTitles(
      sideTitles: SideTitles(
        showTitles: !hidden,
        reservedSize: 46,
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
        reservedSize: 24,
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
      getDrawingHorizontalLine: (_) => FlLine(color: context.colors.border, strokeWidth: 1, dashArray: const [3, 4]),
    );

String _tooltipMoney(Money m, bool hidden, {SignDisplay sign = SignDisplay.auto}) =>
    hidden ? MoneyFormatter.masked : MoneyFormatter.format(m, sign: sign, decimals: DecimalDisplay.none);

/// Dashed "your average" baseline with a compact label at the right edge.
HorizontalLine _averageLine(BuildContext context, double y, Color color, String label, bool hidden) => HorizontalLine(
      y: y,
      color: color,
      strokeWidth: 1.5,
      dashArray: const [5, 4],
      label: HorizontalLineLabel(
        show: true,
        alignment: Alignment.topRight,
        padding: const EdgeInsets.only(right: 2, bottom: 2),
        style: context.text.micro.copyWith(color: color, fontWeight: FontWeight.w900),
        labelResolver: (_) => hidden ? label : '$label ${_axisMoney(y)}',
      ),
    );

BarTouchTooltipData _barTooltip(BuildContext context, BarTooltipItem? Function(int group, int rod) item) {
  final c = context.colors;
  return BarTouchTooltipData(
    getTooltipColor: (_) => c.primary,
    tooltipBorderRadius: Radii.rMd,
    fitInsideHorizontally: true,
    fitInsideVertically: true,
    getTooltipItem: (group, gi, rod, ri) => item(group.x, ri),
  );
}

BarTooltipItem _tip(BuildContext context, String heading, String value, {String? note}) {
  final c = context.colors;
  return BarTooltipItem(
    '$heading\n',
    context.text.micro.copyWith(color: c.onPrimary.withValues(alpha: 0.75)),
    children: [
      TextSpan(
        text: value,
        style: context.text.label.copyWith(color: c.onPrimary, fontWeight: FontWeight.w800),
      ),
      if (note != null)
        TextSpan(
          text: '\n$note',
          style: context.text.micro.copyWith(color: c.onPrimary.withValues(alpha: 0.85), fontWeight: FontWeight.w700),
        ),
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

// ---------------------------------------------------------------------------
// Charts. Each grows into place once (GrowIn); fl_chart's own swap
// animation stays off so the entrance is the only motion.
// ---------------------------------------------------------------------------

/// Grouped bars: income and spending per month, with the average spend.
class IncomeExpenseBarChart extends StatelessWidget {
  const IncomeExpenseBarChart({super.key, required this.months, this.averageExpense, this.height = 210});
  final List<MonthlyCashFlow> months;
  final Money? averageExpense;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
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
                if (avg != null && avg.isPositive)
                  _averageLine(context, avg.toDouble() * t, c.negative, 'Avg spend', hidden),
              ]),
              barTouchData: BarTouchData(
                touchCallback: (e, _) => _haptic(e),
                touchTooltipData: _barTooltip(context, (x, ri) {
                  final m = months[x];
                  final isIncome = ri == 0;
                  return _tip(
                    context,
                    '${monthAbbr(m.month)} · ${isIncome ? 'Income' : 'Spending'}',
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
                      BarChartRodData(
                        toY: months[i].income.toDouble() * t,
                        color: c.positive,
                        width: rodWidth,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                      ),
                      BarChartRodData(
                        toY: months[i].expense.toDouble() * t,
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
      ),
    );
  }
}

/// Monthly net (income − spending) with a zero line and the average.
class NetCashFlowChart extends StatelessWidget {
  const NetCashFlowChart({super.key, required this.months, this.average, this.height = 190});
  final List<MonthlyCashFlow> months;
  final Money? average;
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
                  HorizontalLine(y: 0, color: c.borderStrong, strokeWidth: 1.5),
                  if (avg != null && !avg.isZero)
                    _averageLine(context, avg.toDouble() * t, c.accentNetWorth, 'Avg', hidden),
                ],
              ),
              barTouchData: BarTouchData(
                touchCallback: (e, _) => _haptic(e),
                touchTooltipData: _barTooltip(context, (x, _) {
                  final m = months[x];
                  return _tip(
                    context,
                    '${monthAbbr(m.month)} · ${m.net.isNegative ? 'Overspent' : 'Saved'}',
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
      ),
    );
  }
}

/// Bar per day of the month. Days well above the daily average turn
/// amber/red so expensive days pop out; the dashed line is the average.
class DailySpendChart extends StatelessWidget {
  const DailySpendChart({super.key, required this.days, required this.average, this.height = 200});
  final List<DaySpend> days;
  final Money average;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final hidden = AmountVisibility.hiddenOf(context);
    final maxV = days.fold<double>(0, (m, d) => math.max(m, d.amount.toDouble()));
    final interval = niceStep(maxV == 0 ? 1000 : maxV);
    final maxY = math.max(interval, (maxV / interval).ceil() * interval);
    final avg = average.toDouble();
    Color colorOf(DaySpend d) {
      final v = d.amount.toDouble();
      if (avg > 0 && v >= avg * 2) return c.negative;
      if (avg > 0 && v > avg) return c.warning;
      return c.info;
    }

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
                if (avg > 0) _averageLine(context, avg * t, c.textPrimary, 'Avg', hidden),
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
                        color: colorOf(days[i]),
                        width: 5,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
                        backDrawRodData: BackgroundBarChartRodData(
                          show: days[i].isFuture,
                          toY: maxY,
                          color: c.surfaceMuted.withValues(alpha: 0.6),
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
class MonthlySpendChart extends StatelessWidget {
  const MonthlySpendChart({super.key, required this.months, required this.average, this.height = 200});
  final List<MonthlyCashFlow> months;
  final Money average;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
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
                if (avg > 0) _averageLine(context, avg * t, c.textPrimary, 'Avg', hidden),
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
                        color: avg > 0 && months[i].expense.toDouble() > avg * 1.1 ? c.warning : c.info,
                        width: months.length > 6 ? 12 : 20,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
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

/// Average spend on each weekday; the priciest day is highlighted.
class WeekdayChart extends StatelessWidget {
  const WeekdayChart({super.key, required this.averages, required this.color, this.height = 170});
  final List<Money> averages;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
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
                        color: i == peak ? color : color.withValues(alpha: c.isDark ? 0.4 : 0.3),
                        width: 22,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
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

/// Month-end balance trend (savings, debt) with a highlighted latest point.
class TrendLineChart extends StatelessWidget {
  const TrendLineChart({
    super.key,
    required this.points,
    required this.color,
    required this.seriesLabel,
    this.height = 180,
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
                  spots: [for (var i = 0; i < values.length; i++) FlSpot(i.toDouble(), values[i] * t)],
                  color: color,
                  barWidth: 3,
                  isCurved: true,
                  curveSmoothness: 0.25,
                  preventCurveOverShooting: true,
                  dotData: FlDotData(
                    show: true,
                    getDotPainter: (spot, _, _, i) => FlDotCirclePainter(
                      radius: i == values.length - 1 ? 5 : 3,
                      color: i == values.length - 1 ? color : c.surface,
                      strokeColor: i == values.length - 1 ? c.surface : color,
                      strokeWidth: 2,
                    ),
                  ),
                  belowBarData: BarAreaData(
                    show: true,
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [color.withValues(alpha: c.isDark ? 0.3 : 0.2), color.withValues(alpha: 0)],
                    ),
                  ),
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

/// One slice of the category donut (already grouped and coloured).
@immutable
class DonutSlice {
  const DonutSlice({required this.label, required this.amount, required this.color});
  final String label;
  final Money amount;
  final Color color;
}

/// Category donut that sweeps in. Tap a slice to select it: the centre
/// then shows that slice instead of the total. Tap again to clear.
class CategoryDonut extends StatelessWidget {
  const CategoryDonut({
    super.key,
    required this.slices,
    required this.total,
    this.selected,
    this.onSelect,
    this.size = 200,
  });

  final List<DonutSlice> slices;
  final Money total;
  final int? selected;
  final ValueChanged<int?>? onSelect;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = context.text;
    final c = context.colors;
    final hidden = AmountVisibility.hiddenOf(context);
    final ring = size * 0.14;
    final sel = selected != null && selected! < slices.length ? slices[selected!] : null;
    final sum = slices.fold<double>(0, (a, s) => a + s.amount.toDouble());
    return Semantics(
      label: 'Donut chart of spending by category, total ${hidden ? 'hidden' : total.whole}. '
          '${slices.map((s) => '${s.label} ${formatBps(s.amount.ratioBps(total) ?? 0, decimals: 0)}').join(', ')}',
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            GrowIn(
              builder: (context, p) => PieChart(
                PieChartData(
                  startDegreeOffset: -90,
                  sectionsSpace: slices.length > 1 ? 2 : 0,
                  centerSpaceRadius: size / 2 - ring - 6,
                  pieTouchData: PieTouchData(
                    enabled: onSelect != null,
                    touchCallback: (e, r) {
                      if (e is! FlTapUpEvent) return;
                      final i = r?.touchedSection?.touchedSectionIndex;
                      HapticFeedback.selectionClick();
                      if (i == null || i < 0 || i >= slices.length) {
                        onSelect?.call(null);
                      } else {
                        onSelect?.call(i == selected ? null : i);
                      }
                    },
                  ),
                  borderData: FlBorderData(show: false),
                  sections: [
                    for (var i = 0; i < slices.length; i++)
                      PieChartSectionData(
                        value: slices[i].amount.toDouble() * p,
                        color: selected == null || selected == i
                            ? slices[i].color
                            : slices[i].color.withValues(alpha: 0.3),
                        radius: selected == i ? ring + 6 : ring,
                        showTitle: false,
                      ),
                    // Transparent filler so the ring sweeps round as it grows.
                    if (p < 1) PieChartSectionData(value: sum * (1 - p), color: Colors.transparent, radius: ring, showTitle: false),
                  ],
                ),
                duration: Duration.zero,
              ),
            ),
            Padding(
              padding: EdgeInsets.all(ring + Space.x3),
              child: AnimatedSwitcher(
                duration: context.motion.fast,
                child: Column(
                  key: ValueKey(selected),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      sel == null ? 'SPENT' : sel.label.toUpperCase(),
                      style: t.eyebrow.copyWith(color: sel?.color),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: Space.x0_5),
                    AmountText(sel?.amount ?? total, style: t.amountMedium, compact: true, fit: true, textAlign: TextAlign.center),
                    if (sel != null)
                      Text(
                        '${formatBps(sel.amount.ratioBps(total) ?? 0, decimals: 0)} of spending',
                        style: t.micro.copyWith(color: c.textSecondary, fontWeight: FontWeight.w700),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
