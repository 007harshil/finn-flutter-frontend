import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/time/dates.dart';
import '../../../design_system/design_system.dart';
import '../application/budget_history.dart';
import '../application/budget_view.dart';
import 'budget_widgets.dart';

/// Half-circle usage gauge. The arc fills with spending; a notch on the rim
/// marks how far through the period today is, so "fill past the notch"
/// reads as "spending faster than time". The faint zone is the warning
/// threshold.
class BudgetGauge extends StatelessWidget {
  const BudgetGauge({
    super.key,
    required this.used,
    required this.elapsed,
    required this.warnAt,
    required this.color,
    required this.child,
    this.semanticsLabel,
  });

  /// Spent share of the limit (may exceed 1).
  final double used;
  final double elapsed;
  final double warnAt;
  final Color color;
  final Widget child;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      label: semanticsLabel,
      child: LayoutBuilder(
        builder: (context, box) {
          final w = math.min(box.maxWidth, 280.0);
          final h = w * 0.56;
          return SizedBox(
            width: w,
            height: h,
            child: Stack(
              alignment: Alignment.bottomCenter,
              children: [
                Positioned.fill(
                  child: RepaintBoundary(
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: 1),
                      duration: context.reduceMotion ? Duration.zero : const Duration(milliseconds: 1200),
                      curve: Curves.easeOutCubic,
                      builder: (context, t, _) => CustomPaint(
                        painter: _GaugePainter(
                          used: used * t,
                          elapsed: elapsed,
                          warnAt: warnAt,
                          reveal: t,
                          color: used > 1 ? c.negative : color,
                          track: c.surfaceMuted,
                          warn: c.warning,
                          ink: c.textPrimary,
                          knob: c.surface,
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.only(bottom: h * 0.02, left: w * 0.2, right: w * 0.2),
                  child: child,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  const _GaugePainter({
    required this.used,
    required this.elapsed,
    required this.warnAt,
    required this.reveal,
    required this.color,
    required this.track,
    required this.warn,
    required this.ink,
    required this.knob,
  });

  final double used;
  final double elapsed;
  final double warnAt;
  final double reveal;
  final Color color;
  final Color track;
  final Color warn;
  final Color ink;
  final Color knob;

  static const _stroke = 14.0;

  @override
  void paint(Canvas canvas, Size size) {
    final r = math.min(size.width / 2, size.height) - _stroke / 2 - 6;
    final center = Offset(size.width / 2, size.height - 4);
    final rect = Rect.fromCircle(center: center, radius: r);
    Paint arc(Color c, [double w = _stroke]) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round
      ..color = c;

    canvas.drawArc(rect, math.pi, math.pi, false, arc(track));
    if (warnAt > 0 && warnAt < 1) {
      canvas.drawArc(rect, math.pi + math.pi * warnAt, math.pi * (1 - warnAt), false,
          arc(warn.withValues(alpha: 0.22), _stroke)..strokeCap = StrokeCap.butt);
    }
    final fill = used.clamp(0.0, 1.0);
    if (fill > 0) canvas.drawArc(rect, math.pi, math.pi * fill, false, arc(color));

    // Today notch on the outer rim.
    if (elapsed > 0 && elapsed < 1) {
      final a = math.pi + math.pi * elapsed;
      final dir = Offset(math.cos(a), math.sin(a));
      final outer = center + dir * (r + _stroke / 2 + 5);
      final inner = center + dir * (r - _stroke / 2 - 2);
      canvas.drawLine(
        inner,
        outer,
        Paint()
          ..color = ink.withValues(alpha: reveal)
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round,
      );
    }

    // Knob at the end of the fill.
    if (fill > 0) {
      final a = math.pi + math.pi * fill;
      final p = center + Offset(math.cos(a), math.sin(a)) * r;
      canvas.drawCircle(p.translate(0, 1.5), _stroke / 2 + 2, Paint()..color = Colors.black.withValues(alpha: 0.15));
      canvas.drawCircle(p, _stroke / 2 + 2, Paint()..color = knob);
      canvas.drawCircle(p, _stroke / 2 - 2, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(_GaugePainter old) =>
      old.used != used ||
      old.elapsed != elapsed ||
      old.reveal != reveal ||
      old.color != color ||
      old.track != track ||
      old.ink != ink;
}

/// Running total through the period against an even-pace line and the
/// limit, with daily spends as small bars along the bottom and a dotted
/// projection to the end. Tap or drag to read a day; the parent shows the
/// readout and can filter its list to that day.
class BurnChart extends StatelessWidget {
  const BurnChart({
    super.key,
    required this.burn,
    required this.limit,
    required this.color,
    required this.selected,
    required this.onSelect,
    this.height = 150,
  });

  final BudgetBurn burn;
  final Money limit;
  final Color color;
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
    final c = context.colors;
    final t = context.text;
    final hidden = AmountVisibility.hiddenOf(context);
    return LayoutBuilder(
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
              duration: context.reduceMotion ? Duration.zero : const Duration(milliseconds: 1100),
              curve: Curves.easeOutCubic,
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
                  color: color,
                  over: c.negative,
                  ink: c.textPrimary,
                  muted: c.textTertiary,
                  grid: c.border,
                  labelStyle: t.micro,
                ),
              ),
            ),
          ),
        );
      },
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
    required this.color,
    required this.over,
    required this.ink,
    required this.muted,
    required this.grid,
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
  final Color color;
  final Color over;
  final Color ink;
  final Color muted;
  final Color grid;
  final TextStyle labelStyle;

  static const _top = 16.0;
  static const _bottom = 18.0;

  void _dashed(Canvas canvas, Offset a, Offset b, Paint p, {double dash = 5, double gap = 4}) {
    final total = (b - a).distance;
    if (total == 0) return;
    final dir = (b - a) / total;
    for (var d = 0.0; d < total; d += dash + gap) {
      canvas.drawLine(a + dir * d, a + dir * math.min(d + dash, total), p);
    }
  }

  void _text(Canvas canvas, String s, Offset at, {TextAlign align = TextAlign.left, Color? color, bool bold = false}) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: labelStyle.copyWith(color: color ?? muted, fontWeight: bold ? FontWeight.w800 : null),
      ),
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

    // Limit and even-pace guide.
    final limitY = y(limit);
    _dashed(canvas, Offset(0, limitY), Offset(w, limitY), Paint()
      ..color = ink.withValues(alpha: 0.45)
      ..strokeWidth = 1.2);
    _text(canvas, limitLabel, Offset(w, limitY - 14), align: TextAlign.right, color: ink.withValues(alpha: 0.7), bold: true);
    _dashed(canvas, Offset(0, y(0)), Offset(w, limitY), Paint()
      ..color = muted.withValues(alpha: 0.6)
      ..strokeWidth = 1,
        dash: 2, gap: 4);

    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, w * reveal, size.height));

    // Daily spends along the floor.
    final maxDay = daily.fold<int>(0, math.max);
    if (maxDay > 0) {
      final barW = math.max(1.5, w / n * 0.5);
      for (var i = 0; i <= last; i++) {
        if (daily[i] == 0) continue;
        final h = daily[i] / maxDay * 22;
        final sel = i == selected;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x(i) - barW / 2, y(0) - h, barW, h),
            const Radius.circular(1.5),
          ),
          Paint()..color = color.withValues(alpha: sel ? 0.9 : 0.3),
        );
      }
    }

    if (last >= 0) {
      // Running total: area + line, red above the limit.
      final path = Path()..moveTo(x(0), y(cum[0]));
      for (var i = 1; i <= last; i++) {
        path.lineTo(x(i), y(cum[i]));
      }
      final area = Path.from(path)
        ..lineTo(x(last), y(0))
        ..lineTo(x(0), y(0))
        ..close();
      canvas.drawPath(
        area,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(0, _top),
            Offset(0, y(0)),
            [color.withValues(alpha: 0.28), color.withValues(alpha: 0.02)],
          ),
      );
      final line = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round
        ..color = color;
      canvas.drawPath(path, line);
      if (spentToday > limit) {
        canvas.save();
        canvas.clipRect(Rect.fromLTRB(0, 0, w, limitY));
        canvas.drawPath(path, line..color = over);
        canvas.restore();
      }

      // Where it is heading at today's pace.
      if (last < n - 1 && last >= 1) {
        _dashed(
          canvas,
          Offset(x(last), y(spentToday)),
          Offset(x(n - 1), y(projected)),
          Paint()
            ..color = (projected > limit ? over : color).withValues(alpha: 0.75)
            ..strokeWidth = 2
            ..strokeCap = StrokeCap.round,
          dash: 3,
          gap: 4,
        );
      }
      // Today dot.
      final p = Offset(x(last), y(spentToday));
      canvas.drawCircle(p, 5, Paint()..color = color.withValues(alpha: 0.25));
      canvas.drawCircle(p, 3, Paint()..color = spentToday > limit ? over : color);
    }
    canvas.restore();

    // Selection guide.
    final s = selected;
    if (s != null && s >= 0 && s <= last) {
      final sx = x(s);
      canvas.drawLine(Offset(sx, _top - 4), Offset(sx, y(0)), Paint()
        ..color = ink.withValues(alpha: 0.6)
        ..strokeWidth = 1.2);
      final p = Offset(sx, y(cum[s]));
      canvas.drawCircle(p, 6, Paint()..color = ink);
      canvas.drawCircle(p, 3.5, Paint()..color = color);
    }

    // Axis labels: start, today, end.
    final base = size.height - _bottom + 4;
    _text(canvas, startLabel, Offset(0, base));
    _text(canvas, endLabel, Offset(w, base), align: TextAlign.right);
    if (last > 0 && last < n - 1) {
      final tx = x(last).clamp(36.0, w - 36.0);
      _text(canvas, 'Today', Offset(tx, base), align: TextAlign.center, color: ink, bold: true);
    }
  }

  @override
  bool shouldRepaint(_BurnPainter old) =>
      old.reveal != reveal ||
      old.selected != selected ||
      old.limit != limit ||
      old.todayIndex != todayIndex ||
      old.color != color ||
      old.ink != ink ||
      old.limitLabel != limitLabel ||
      !identical(old.daily, daily);
}

/// Spending per period vs the limit, newest on the right. Tap a bar to read
/// it; bars over the limit are red.
class HistoryBars extends StatelessWidget {
  const HistoryBars({super.key, required this.points, required this.color, required this.selected, required this.onSelect});

  final List<BudgetPeriodPoint> points;
  final Color color;
  final int? selected;
  final ValueChanged<int?> onSelect;

  static const _height = 132.0;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final limit = points.isEmpty ? 0 : points.last.limit.paise;
    final maxV = points.fold<int>(limit, (m, p) => math.max(m, p.spent.paise)) * 1.1;
    double h(int v) => maxV <= 0 ? 0 : v / maxV;
    final avg = averageSpentBefore(points);
    final reduce = context.reduceMotion;
    String label(BudgetPeriodPoint p) =>
        points.length > 2 ? DateFormats.shortMonth.format(p.period.start) : (p.isCurrent ? 'Now' : 'Before');
    return SizedBox(
      height: _height,
      child: LayoutBuilder(
        builder: (context, box) {
          const labelH = 18.0;
          final chartH = box.maxHeight - labelH;
          final limitTop = chartH * (1 - h(limit));
          final avgTop = avg == null ? null : chartH * (1 - h(avg.paise));
          return Stack(
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: limitTop,
                child: Row(
                  children: [
                    Expanded(child: Container(height: 1.2, color: c.textPrimary.withValues(alpha: 0.4))),
                  ],
                ),
              ),
              if (avgTop != null)
                Positioned(
                  left: 0,
                  right: 0,
                  top: avgTop,
                  child: Container(height: 1, color: c.textTertiary.withValues(alpha: 0.5)),
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < points.length; i++)
                    Expanded(
                      child: Semantics(
                        button: true,
                        selected: selected == i,
                        label: '${label(points[i])}: ${budgetMoney(context, points[i].spent)}'
                            '${points[i].isOver ? ', over limit' : ''}',
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
                                    duration: reduce ? Duration.zero : Duration(milliseconds: 600 + 70 * i),
                                    curve: Curves.easeOutBack,
                                    builder: (context, v, _) => FractionallySizedBox(
                                      heightFactor: v.clamp(0.0, 1.0),
                                      widthFactor: 0.5,
                                      child: AnimatedContainer(
                                        duration: context.motion.fast,
                                        decoration: BoxDecoration(
                                          color: points[i].isOver
                                              ? c.negative
                                              : color.withValues(
                                                  alpha: points[i].isCurrent || selected == i ? 1 : 0.35),
                                          borderRadius: const BorderRadius.vertical(top: Radius.circular(Radii.sm)),
                                          border: selected == i ? Border.all(color: c.textPrimary, width: 1.5) : null,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(
                                height: labelH,
                                child: Center(
                                  child: Text(
                                    label(points[i]),
                                    style: t.micro.copyWith(
                                      color: points[i].isCurrent || selected == i ? c.textPrimary : c.textSecondary,
                                      fontWeight: points[i].isCurrent || selected == i ? FontWeight.w900 : FontWeight.w600,
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
            ],
          );
        },
      ),
    );
  }
}
