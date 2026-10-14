import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/time/dates.dart';
import '../../../kit/kit.dart';
import '../application/budget_history.dart';
import '../application/budget_view.dart';
import 'budget_widgets.dart';

/// Running total through the period against the limit and an even-pace
/// line, with daily spends as short bars along the floor and a dashed line
/// to where the period ends at today's pace. Tap or drag to read a day;
/// the parent shows the readout and can filter its list to that day.
///
/// Ink only; red where the total is above the limit.
class BurnChart extends StatelessWidget {
  const BurnChart({
    super.key,
    required this.burn,
    required this.limit,
    required this.selected,
    required this.onSelect,
    this.height = 160,
  });

  final BudgetBurn burn;
  final Money limit;
  final int? selected;
  final ValueChanged<int?> onSelect;
  final double height;

  int _indexAt(double dx, double width) {
    final n = burn.daily.length;
    final i = n <= 1 ? 0 : (dx / width * (n - 1)).round();
    final last = burn.todayIndex.clamp(0, n - 1);
    return i.clamp(0, last);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final t = context.type;
    final hidden = AmountVisibility.hiddenOf(context);
    final motion = context.motion;
    return Semantics(
      label: 'Spending through the period. Tap a day to read it.',
      child: LayoutBuilder(
        builder: (context, box) {
          void pick(double dx, {bool toggle = false}) {
            final i = _indexAt(dx, box.maxWidth);
            if (toggle && i == selected) {
              onSelect(null);
            } else if (i != selected) {
              HapticFeedback.selectionClick();
              onSelect(i);
            }
          }

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (d) => pick(d.localPosition.dx, toggle: true),
            onHorizontalDragStart: (d) => pick(d.localPosition.dx),
            onHorizontalDragUpdate: (d) => pick(d.localPosition.dx),
            child: RepaintBoundary(
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: motion.slow,
                curve: motion.standard,
                builder: (context, reveal, _) => CustomPaint(
                  size: Size(box.maxWidth, height),
                  painter: _BurnPainter(
                    daily: burn.daily,
                    todayIndex: burn.todayIndex,
                    limit: limit.paise,
                    limitLabel: hidden ? 'Limit' : 'Limit ${limit.compact}',
                    startLabel: DateFormats.dayMonth.format(burn.period.start),
                    endLabel: DateFormats.dayMonth.format(burn.period.end),
                    selected: selected,
                    reveal: reveal,
                    ink: c.ink,
                    soft: c.inkSoft,
                    red: c.red,
                    sunken: c.sunken,
                    line: c.line,
                    surface: c.surface,
                    labelStyle: t.small,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _BurnPainter extends CustomPainter {
  _BurnPainter({
    required this.daily,
    required this.todayIndex,
    required this.limit,
    required this.limitLabel,
    required this.startLabel,
    required this.endLabel,
    required this.selected,
    required this.reveal,
    required this.ink,
    required this.soft,
    required this.red,
    required this.sunken,
    required this.line,
    required this.surface,
    required this.labelStyle,
  });

  final List<int> daily;
  final int todayIndex;
  final int limit;
  final String limitLabel;
  final String startLabel;
  final String endLabel;
  final int? selected;
  final double reveal;
  final Color ink;
  final Color soft;
  final Color red;
  final Color sunken;
  final Color line;
  final Color surface;
  final TextStyle labelStyle;

  static const _top = 20.0;
  static const _bottom = 22.0;

  void _dashed(Canvas canvas, Offset a, Offset b, Paint p, {double dash = 5, double gap = 4}) {
    final total = (b - a).distance;
    if (total == 0) return;
    final dir = (b - a) / total;
    for (var d = 0.0; d < total; d += dash + gap) {
      canvas.drawLine(a + dir * d, a + dir * math.min(d + dash, total), p);
    }
  }

  void _text(Canvas canvas, String s, Offset at, {TextAlign align = TextAlign.left, Color? color}) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: labelStyle.copyWith(color: color ?? soft)),
      textDirection: TextDirection.ltr,
    )..layout();
    final dx = switch (align) {
      TextAlign.right => at.dx - tp.width,
      TextAlign.center => at.dx - tp.width / 2,
      _ => at.dx,
    };
    tp.paint(canvas, Offset(dx, at.dy));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final n = daily.length;
    if (n == 0) return;
    final cum = <int>[];
    var sum = 0;
    for (final d in daily) {
      cum.add(sum += d);
    }
    final last = todayIndex.clamp(-1, n - 1);
    final spentToday = last >= 0 ? cum[last] : 0;
    final projected = last >= 1 && last < n - 1 ? spentToday * n / (last + 1) : spentToday.toDouble();
    final maxY = [limit.toDouble(), spentToday.toDouble(), projected].reduce(math.max) * 1.08;
    final w = size.width;
    final chartH = size.height - _top - _bottom;
    double x(int i) => n == 1 ? w / 2 : i / (n - 1) * w;
    double y(num v) => _top + chartH - (maxY <= 0 ? 0 : v / maxY * chartH);

    // Floor, limit and even-pace guide.
    canvas.drawLine(Offset(0, y(0)), Offset(w, y(0)), Paint()
      ..color = line
      ..strokeWidth = 1);
    final limitY = y(limit);
    _dashed(canvas, Offset(0, limitY), Offset(w, limitY), Paint()
      ..color = soft
      ..strokeWidth = 1);
    // Right end, clear of the running total: above the line unless the
    // projection ends above it, then below.
    _text(canvas, limitLabel, Offset(w, projected > limit ? limitY + 4 : limitY - 18), align: TextAlign.right);
    _dashed(
      canvas,
      Offset(0, y(0)),
      Offset(w, limitY),
      Paint()
        ..color = soft.withValues(alpha: 0.7)
        ..strokeWidth = 1,
      dash: 2,
      gap: 4,
    );

    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, w * reveal, size.height));

    // Daily spends along the floor.
    final maxDay = daily.fold<int>(0, math.max);
    if (maxDay > 0) {
      final barW = math.max(2.0, w / n * 0.5);
      for (var i = 0; i <= last; i++) {
        if (daily[i] == 0) continue;
        final h = math.max(2.0, daily[i] / maxDay * 24);
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(x(i) - barW / 2, y(0) - h, barW, h), const Radius.circular(1)),
          Paint()..color = i == selected ? ink : sunken,
        );
      }
    }

    if (last >= 0) {
      // Running total: a flat low tint under an ink line, red above the limit.
      final path = Path()..moveTo(x(0), y(cum[0]));
      for (var i = 1; i <= last; i++) {
        path.lineTo(x(i), y(cum[i]));
      }
      final area = Path.from(path)
        ..lineTo(x(last), y(0))
        ..lineTo(x(0), y(0))
        ..close();
      canvas.drawPath(area, Paint()..color = ink.withValues(alpha: 0.05));
      final stroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round
        ..color = ink;
      canvas.drawPath(path, stroke);
      if (spentToday > limit) {
        canvas.save();
        canvas.clipRect(Rect.fromLTRB(0, 0, w, limitY));
        canvas.drawPath(path, stroke..color = red);
        canvas.restore();
      }

      // Where it is heading at today's pace.
      if (last < n - 1 && last >= 1) {
        _dashed(
          canvas,
          Offset(x(last), y(spentToday)),
          Offset(x(n - 1), y(projected)),
          Paint()
            ..color = projected > limit ? red : soft
            ..strokeWidth = 1.5
            ..strokeCap = StrokeCap.round,
          dash: 3,
          gap: 4,
        );
      }
      final p = Offset(x(last), y(spentToday));
      canvas.drawCircle(p, 4.5, Paint()..color = surface);
      canvas.drawCircle(p, 3, Paint()..color = spentToday > limit ? red : ink);
    }
    canvas.restore();

    // Selection guide.
    final s = selected;
    if (s != null && s >= 0 && s <= last) {
      final sx = x(s);
      canvas.drawLine(Offset(sx, _top - 4), Offset(sx, y(0)), Paint()
        ..color = ink
        ..strokeWidth = 1);
      final p = Offset(sx, y(cum[s]));
      canvas.drawCircle(p, 5.5, Paint()..color = ink);
      canvas.drawCircle(p, 2.5, Paint()..color = surface);
    }

    // Axis labels: start, today, end.
    final base = size.height - _bottom + 5;
    _text(canvas, startLabel, Offset(0, base));
    _text(canvas, endLabel, Offset(w, base), align: TextAlign.right);
    if (last > 0 && last < n - 1) {
      final tx = x(last).clamp(60.0, w - 60.0);
      _text(canvas, 'Today', Offset(tx, base), align: TextAlign.center, color: ink);
    }
  }

  @override
  bool shouldRepaint(_BurnPainter old) =>
      old.reveal != reveal ||
      old.selected != selected ||
      old.limit != limit ||
      old.todayIndex != todayIndex ||
      old.ink != ink ||
      old.limitLabel != limitLabel ||
      !identical(old.daily, daily);
}

/// Spending per period against the limit, newest on the right. Tap a bar
/// to read it. Earlier periods are quiet, this one is ink, over the limit
/// is red.
class HistoryBars extends StatelessWidget {
  const HistoryBars({super.key, required this.points, required this.selected, required this.onSelect});

  final List<BudgetPeriodPoint> points;
  final int? selected;
  final ValueChanged<int?> onSelect;

  static const _height = 140.0;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final t = context.type;
    final motion = context.motion;
    final limit = points.isEmpty ? 0 : points.last.limit.paise;
    final maxV = points.fold<int>(limit, (m, p) => math.max(m, p.spent.paise)) * 1.1;
    double h(int v) => maxV <= 0 ? 0 : v / maxV;
    final avg = averageSpentBefore(points);
    String label(BudgetPeriodPoint p) =>
        points.length > 2 ? DateFormats.shortMonth.format(p.period.start) : (p.isCurrent ? 'Now' : 'Before');
    return SizedBox(
      height: _height,
      child: LayoutBuilder(
        builder: (context, box) {
          const labelH = 22.0;
          final chartH = box.maxHeight - labelH;
          final limitTop = chartH * (1 - h(limit));
          final avgTop = avg == null ? null : chartH * (1 - h(avg.paise));
          return Stack(
            children: [
              Positioned(left: 0, right: 0, top: chartH, child: Container(height: 1, color: c.line)),
              if (avgTop != null)
                Positioned(left: 0, right: 0, top: avgTop, child: Container(height: 1, color: c.lineStrong)),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < points.length; i++)
                    Expanded(
                      child: Semantics(
                        button: true,
                        selected: selected == i,
                        label: '${label(points[i])}: ${budgetMoney(context, points[i].spent)}'
                            '${points[i].isOver ? ', over the limit' : ''}',
                        excludeSemantics: true,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            HapticFeedback.selectionClick();
                            onSelect(selected == i ? null : i);
                          },
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              SizedBox(
                                height: chartH,
                                child: Align(
                                  alignment: Alignment.bottomCenter,
                                  child: TweenAnimationBuilder<double>(
                                    tween: Tween(begin: 0, end: h(points[i].spent.paise)),
                                    duration: motion.slow,
                                    curve: motion.standard,
                                    builder: (context, v, _) => FractionallySizedBox(
                                      heightFactor: v.clamp(0.0, 1.0),
                                      widthFactor: 0.5,
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: points[i].isOver
                                              ? c.red
                                              : (points[i].isCurrent || selected == i ? c.ink : c.lineStrong),
                                          borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(
                                height: labelH,
                                child: Align(
                                  alignment: Alignment.bottomCenter,
                                  child: Text(
                                    label(points[i]),
                                    style: t.small.copyWith(
                                      color: points[i].isCurrent || selected == i ? c.ink : c.inkSoft,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              // Limit on top of the bars so it reads across them.
              Positioned(
                left: 0,
                right: 0,
                top: limitTop,
                child: IgnorePointer(child: Container(height: 1.5, color: c.ink)),
              ),
            ],
          );
        },
      ),
    );
  }
}
