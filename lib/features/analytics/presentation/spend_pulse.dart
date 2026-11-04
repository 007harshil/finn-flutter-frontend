import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/core_providers.dart';
import '../../../app/di/data_providers.dart';
import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/time/dates.dart';
import '../../../kit/kit.dart';
import '../../transactions/domain/transaction.dart';
import 'insight_charts.dart';

/// Running spend through a month and the month before it, day by day.
@immutable
class SpendPulse {
  const SpendPulse({required this.month, required this.thisMonth, required this.lastMonth});

  final MonthKey month;

  /// Cumulative paise spent by the end of each day (index 0 = day 1), up
  /// to today for the current month or the whole month for a past one.
  final List<int> thisMonth;

  /// Same for the previous month, whole month.
  final List<int> lastMonth;

  int get days => month.dayCount;
  int get spent => thisMonth.isEmpty ? 0 : thisMonth.last;

  /// Last month's running total on [day] (1-based), clamped to its length.
  int lastBy(int day) => lastMonth.isEmpty ? 0 : lastMonth[math.min(day, lastMonth.length) - 1];

  static SpendPulse build(List<Transaction> txs, MonthKey month, DateTime today) {
    final prev = month.previous;
    final daily = List<int>.filled(month.dayCount, 0);
    final prevDaily = List<int>.filled(prev.dayCount, 0);
    for (final t in txs) {
      if (t.type != TransactionType.expense) continue;
      final m = MonthKey.fromDate(t.date);
      if (m == month) {
        daily[t.date.day - 1] += t.amount.paise;
      } else if (m == prev) {
        prevDaily[t.date.day - 1] += t.amount.paise;
      }
    }
    final current = MonthKey.fromDate(today) == month;
    final upTo = current ? today.day : month.dayCount;
    return SpendPulse(
      month: month,
      thisMonth: _running(daily.take(upTo)),
      lastMonth: _running(prevDaily),
    );
  }

  static List<int> _running(Iterable<int> xs) {
    var sum = 0;
    return [for (final x in xs) sum += x];
  }
}

final spendPulseProvider = Provider.family<AsyncValue<SpendPulse>, MonthKey>((ref, month) {
  final today = ref.watch(todayProvider);
  return ref.watch(transactionsStreamProvider).whenData((txs) => SpendPulse.build(txs, month, today));
});

/// Monsoon "Pulse": this month's running spend (rain, with a wash)
/// against last month's (soft line). Drag or long-press across it to read any day; the reading
/// pins above the chart, never under the finger.
class SpendPulseCard extends ConsumerWidget {
  const SpendPulseCard({super.key, required this.month});

  final MonthKey month;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.ink;
    final pulse = ref.watch(spendPulseProvider(month)).value;
    if (pulse == null || (pulse.spent == 0 && pulse.lastMonth.lastOrNull == 0)) return const SizedBox.shrink();
    final day = pulse.thisMonth.length;
    final diff = pulse.spent - pulse.lastBy(day);
    final prevName = DateFormats.monthName.format(month.previous.start);
    final hidden = AmountVisibility.hiddenOf(context);
    final gap = MoneyFormatter.format(Money.fromPaise(diff.abs()), decimals: DecimalDisplay.none);
    final title = hidden || diff == 0
        ? 'Running total against $prevName'
        : diff < 0
            ? '$gap less than $prevName by day $day'
            : '$gap more than $prevName by day $day';
    return InsightChartCard(
      heading: 'Month so far',
      title: title,
      legend: [
        LegendEntry(DateFormats.monthName.format(month.start), c.rain),
        LegendEntry(prevName, c.inkSoft),
      ],
      howCalculated: 'Each line adds up completed expenses day by day, including EMIs and settlements. '
          'Transfers between your own accounts are not spending.',
      child: SpendPulseChart(pulse: pulse),
    );
  }
}

class SpendPulseChart extends StatefulWidget {
  const SpendPulseChart({super.key, required this.pulse, this.height = 168, this.readout = true});

  final SpendPulse pulse;
  final double height;

  /// The pinned reading above the chart; off where the card already shows
  /// the totals (it still appears while scrubbing).
  final bool readout;

  @override
  State<SpendPulseChart> createState() => _SpendPulseChartState();
}

class _SpendPulseChartState extends State<SpendPulseChart> {
  /// Selected day (1-based) while scrubbing.
  int? _day;
  DateTime _lastTick = DateTime.fromMillisecondsSinceEpoch(0);

  void _scrub(Offset local, double width) {
    final days = widget.pulse.days;
    final d = ((local.dx / width) * (days - 1)).round().clamp(0, days - 1) + 1;
    if (d == _day) return;
    // One selection tick per day boundary, never faster than every 60 ms.
    final now = DateTime.now();
    if (now.difference(_lastTick).inMilliseconds >= 60) {
      HapticFeedback.selectionClick();
      _lastTick = now;
    }
    setState(() => _day = d);
  }

  void _end() => setState(() => _day = null);

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final t = context.type;
    final p = widget.pulse;
    final day = _day ?? p.thisMonth.length;
    final date = DateTime(p.month.year, p.month.month, math.max(day, 1));
    final has = day >= 1 && day <= p.thisMonth.length;
    final hidden = AmountVisibility.hiddenOf(context);
    final spoken = hidden
        ? 'Running spend chart'
        : 'Spent ${MoneyFormatter.format(Money.fromPaise(p.spent), decimals: DecimalDisplay.none)} so far, '
            '${MoneyFormatter.format(Money.fromPaise(p.lastBy(p.thisMonth.length)), decimals: DecimalDisplay.none)} '
            'by the same day last month';

    final readout = Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(DateFormats.dayMonth.format(date), style: t.small),
              AmountText(
                Money.fromPaise(has ? p.thisMonth[day - 1] : 0),
                style: t.figure.copyWith(fontSize: 18, color: has ? c.rain : c.inkFaint),
                decimals: DecimalDisplay.none,
              ),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('Last month', style: t.small),
            AmountText(Money.fromPaise(p.lastBy(day)), style: t.figureSmall, decimals: DecimalDisplay.none),
          ],
        ),
      ],
    );

    return Semantics(
      label: spoken,
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.readout || _day != null) ...[readout, const SizedBox(height: Sp.md)],
          LayoutBuilder(
            builder: (context, box) => GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: (d) => _scrub(d.localPosition, box.maxWidth),
              onHorizontalDragUpdate: (d) => _scrub(d.localPosition, box.maxWidth),
              onHorizontalDragEnd: (_) => _end(),
              onHorizontalDragCancel: _end,
              onLongPressStart: (d) => _scrub(d.localPosition, box.maxWidth),
              onLongPressMoveUpdate: (d) => _scrub(d.localPosition, box.maxWidth),
              onLongPressEnd: (_) => _end(),
              child: TweenAnimationBuilder<double>(
                // Draw in once, left to right; instant under reduced motion.
                tween: Tween(begin: context.reduceMotion ? 1 : 0, end: 1),
                duration: context.motion.reduced ? Duration.zero : const Duration(milliseconds: 700),
                curve: Curves.easeOutCubic,
                builder: (context, reveal, _) => CustomPaint(
                  size: Size(box.maxWidth, widget.height),
                  painter: _PulsePainter(
                    pulse: p,
                    reveal: reveal,
                    cursor: _day,
                    line: c.rain,
                    fill: c.rain.withValues(alpha: c.isDark ? 0.30 : 0.26),
                    previous: c.inkSoft.withValues(alpha: 0.5),
                    grid: c.line,
                    cursorColor: c.ink,
                    dot: c.surface,
                    label: t.small,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PulsePainter extends CustomPainter {
  _PulsePainter({
    required this.pulse,
    required this.reveal,
    required this.cursor,
    required this.line,
    required this.fill,
    required this.previous,
    required this.grid,
    required this.cursorColor,
    required this.dot,
    required this.label,
  });

  final SpendPulse pulse;
  final double reveal;
  final int? cursor;
  final Color line;
  final Color fill;
  final Color previous;
  final Color grid;
  final Color cursorColor;
  final Color dot;
  final TextStyle label;

  static const _bottom = 20.0;

  @override
  void paint(Canvas canvas, Size size) {
    final days = pulse.days;
    final chartH = size.height - _bottom;
    final top = math.max(pulse.spent, pulse.lastMonth.isEmpty ? 0 : pulse.lastMonth.last);
    final maxY = top <= 0 ? 1.0 : top * 1.1;
    double x(int day) => days <= 1 ? 0 : (day - 1) / (days - 1) * size.width;
    double y(int paise) => chartH - paise / maxY * chartH;

    // Quiet guides at a third and two thirds.
    final g = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (final f in [1 / 3, 2 / 3]) {
      canvas.drawLine(Offset(0, chartH * f), Offset(size.width, chartH * f), g);
    }
    canvas.drawLine(Offset(0, chartH), Offset(size.width, chartH), g);

    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width * reveal, size.height));

    // Last month, a soft solid line.
    final prev = Path();
    final n = math.min(pulse.lastMonth.length, days);
    for (var d = 1; d <= n; d++) {
      final o = Offset(x(d), y(pulse.lastMonth[d - 1]));
      d == 1 ? prev.moveTo(o.dx, o.dy) : prev.lineTo(o.dx, o.dy);
    }
    final dash = Paint()
      ..color = previous
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    canvas.drawPath(prev, dash..strokeJoin = StrokeJoin.round);

    // This month, solid with a soft wash underneath.
    final cur = pulse.thisMonth;
    if (cur.isNotEmpty) {
      final path = Path()..moveTo(x(1), y(cur[0]));
      for (var d = 2; d <= cur.length; d++) {
        path.lineTo(x(d), y(cur[d - 1]));
      }
      final area = Path.from(path)
        ..lineTo(x(cur.length), chartH)
        ..lineTo(x(1), chartH)
        ..close();
      canvas.drawPath(
        area,
        Paint()
          ..shader = ui.Gradient.linear(Offset(0, 0), Offset(0, chartH), [fill, fill.withValues(alpha: 0)]),
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = line
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.6
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round,
      );
      final end = Offset(x(cur.length), y(cur.last));
      canvas.drawCircle(end, 5, Paint()..color = dot);
      canvas.drawCircle(end, 3.5, Paint()..color = line);
    }
    canvas.restore();

    // Scrub cursor.
    final cd = cursor;
    if (cd != null) {
      final cx = x(cd);
      canvas.drawLine(
        Offset(cx, 0),
        Offset(cx, chartH),
        Paint()
          ..color = cursorColor.withValues(alpha: 0.5)
          ..strokeWidth = 1,
      );
      if (cd <= cur.length) {
        final o = Offset(cx, y(cur[cd - 1]));
        canvas.drawCircle(o, 6, Paint()..color = dot);
        canvas.drawCircle(o, 4, Paint()..color = line);
      }
    }

    // Day ticks: 1, the middle and the last day.
    for (final d in [1, (days / 2).round(), days]) {
      final tp = TextPainter(text: TextSpan(text: '$d', style: label), textDirection: TextDirection.ltr)..layout();
      final dx = (x(d) - tp.width / 2).clamp(0.0, size.width - tp.width);
      tp.paint(canvas, Offset(dx, chartH + 4));
    }
  }

  @override
  bool shouldRepaint(_PulsePainter old) =>
      old.pulse != pulse || old.reveal != reveal || old.cursor != cursor || old.line != line || old.grid != grid;
}
