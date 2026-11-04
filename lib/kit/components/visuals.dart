import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../design_system/motion/motion.dart';
import '../tokens.dart';
import 'data.dart' show BarPart;

/// Bahi visuals: chart-first summaries drawn like a shopkeeper's khata.
/// Warm ruled paper with a red margin line ([KhataPanel]), ring gauges
/// ([KhataRing]), share donuts ([KhataDonut]), ruled columns
/// ([KhataColumns]) and a tilted status stamp ([KhataStamp]). Every chart
/// draws in once (≈600 ms) and appears instantly under reduced motion.

/// Draws [builder] with a 0→1 reveal that runs once per [valueKey].
class _Reveal extends StatelessWidget {
  const _Reveal({required this.valueKey, required this.builder});

  final Object valueKey;
  final Widget Function(double t) builder;

  @override
  Widget build(BuildContext context) {
    final reduced = context.reduceMotion;
    return TweenAnimationBuilder<double>(
      key: ValueKey(valueKey),
      tween: Tween(begin: reduced ? 1 : 0, end: 1),
      duration: reduced ? Duration.zero : const Duration(milliseconds: 650),
      curve: Curves.easeOutCubic,
      builder: (context, t, _) => builder(t),
    );
  }
}

/// Warm ruled paper with a red margin line down the left, like a page of
/// a bahi-khata. Holds a chart-led summary; content sits right of the margin.
class KhataPanel extends StatelessWidget {
  const KhataPanel({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  static const _margin = 22.0;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    return Container(
      decoration: BoxDecoration(
        color: c.khata,
        borderRadius: Rad.rLg,
        border: c.isDark ? null : Border.all(color: c.khataRule),
      ),
      clipBehavior: Clip.antiAlias,
      child: CustomPaint(
        painter: _RulePainter(rule: c.khataRule, margin: c.khataMargin),
        child: Padding(
          padding: padding ?? const EdgeInsets.fromLTRB(_margin + Sp.md, Sp.lg, Sp.lg, Sp.lg),
          child: child,
        ),
      ),
    );
  }
}

class _RulePainter extends CustomPainter {
  const _RulePainter({required this.rule, required this.margin});

  final Color rule;
  final Color margin;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = rule
      ..strokeWidth = 1;
    for (var y = 28.0; y < size.height; y += 28) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
    final m = Paint()
      ..color = margin
      ..strokeWidth = 1.2;
    canvas.drawLine(const Offset(KhataPanel._margin, 0), Offset(KhataPanel._margin, size.height), m);
    canvas.drawLine(const Offset(KhataPanel._margin + 3, 0), Offset(KhataPanel._margin + 3, size.height), m);
  }

  @override
  bool shouldRepaint(_RulePainter old) => old.rule != rule || old.margin != margin;
}

/// Ring gauge: fills clockwise from 12 o'clock to [value] (may pass 1).
/// Colour follows meaning unless [color] is given: teal, amber from 85 %,
/// red past 100 %. [marker] is the "should be here by now" tick. Small
/// ledger ticks ring the track.
class KhataRing extends StatelessWidget {
  const KhataRing({
    super.key,
    required this.value,
    this.marker,
    this.color,
    this.size = 120,
    this.stroke = 12,
    this.center,
    this.semanticLabel,
  });

  final double value;
  final double? marker;
  final Color? color;
  final double size;
  final double stroke;
  final Widget? center;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final fill = color ?? (value > 1 ? c.red : (value >= 0.85 ? c.amber : c.brand));
    return Semantics(
      label: semanticLabel,
      excludeSemantics: semanticLabel != null,
      child: SizedBox.square(
        dimension: size,
        child: _Reveal(
          valueKey: (value * 1000).round(),
          builder: (t) => CustomPaint(
            painter: _RingPainter(
              value: value.clamp(0.0, 1.0) * t,
              marker: marker,
              fill: fill,
              track: c.isDark ? c.sunken : c.surface,
              tick: c.khataRule,
              markerColor: c.ink,
              stroke: stroke,
            ),
            child: Center(child: center),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.value,
    required this.marker,
    required this.fill,
    required this.track,
    required this.tick,
    required this.markerColor,
    required this.stroke,
  });

  final double value;
  final double? marker;
  final Color fill;
  final Color track;
  final Color tick;
  final Color markerColor;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2 - stroke / 2 - 4;
    final o = size.center(Offset.zero);
    final rect = Rect.fromCircle(center: o, radius: r);
    // Ledger ticks just outside the track.
    final tp = Paint()
      ..color = tick
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 40; i++) {
      final a = i / 40 * 2 * math.pi;
      final dir = Offset(math.sin(a), -math.cos(a));
      canvas.drawLine(o + dir * (r + stroke / 2 + 1), o + dir * (r + stroke / 2 + (i % 5 == 0 ? 5 : 3)), tp);
    }
    canvas.drawArc(
      rect,
      0,
      2 * math.pi,
      false,
      Paint()
        ..color = track
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );
    if (value > 0) {
      canvas.drawArc(
        rect,
        -math.pi / 2,
        2 * math.pi * value,
        false,
        Paint()
          ..color = fill
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round,
      );
    }
    final m = marker;
    if (m != null && m > 0 && m < 1) {
      final a = m * 2 * math.pi;
      final dir = Offset(math.sin(a), -math.cos(a));
      canvas.drawLine(
        o + dir * (r - stroke / 2 - 3),
        o + dir * (r + stroke / 2 + 3),
        Paint()
          ..color = markerColor
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value || old.marker != marker || old.fill != fill || old.track != track;
}

/// Share donut: up to six [parts] with small gaps, a label in the middle.
class KhataDonut extends StatelessWidget {
  const KhataDonut({super.key, required this.parts, this.size = 120, this.stroke = 16, this.center, this.semanticLabel});

  final List<BarPart> parts;
  final double size;
  final double stroke;
  final Widget? center;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final visible = parts.where((p) => p.share > 0).toList();
    return Semantics(
      label: semanticLabel,
      excludeSemantics: semanticLabel != null,
      child: SizedBox.square(
        dimension: size,
        child: _Reveal(
          valueKey: Object.hashAll(visible.map((p) => (p.share * 1000).round())),
          builder: (t) => CustomPaint(
            painter: _DonutPainter(parts: visible, t: t, stroke: stroke, track: c.isDark ? c.sunken : c.surface),
            child: Center(child: center),
          ),
        ),
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({required this.parts, required this.t, required this.stroke, required this.track});

  final List<BarPart> parts;
  final double t;
  final double stroke;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2 - stroke / 2;
    final rect = Rect.fromCircle(center: size.center(Offset.zero), radius: r);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawArc(rect, 0, 2 * math.pi, false, base..color = track);
    final total = parts.fold<double>(0, (s, p) => s + p.share);
    if (total <= 0) return;
    const gap = 0.035;
    var start = -math.pi / 2;
    final sweepAll = 2 * math.pi * t;
    for (final p in parts) {
      final sweep = p.share / total * 2 * math.pi;
      final drawn = math.min(sweep, math.max(0.0, -math.pi / 2 + sweepAll - start));
      if (drawn > gap) {
        canvas.drawArc(rect, start + gap / 2, drawn - gap, false, base..color = p.color);
      }
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) => old.parts != parts || old.t != t || old.track != track;
}

/// One column of [KhataColumns].
@immutable
class KhataColumn {
  const KhataColumn(this.label, this.value, {this.color, this.highlight = false});

  final String label;
  final double value;
  final Color? color;
  final bool highlight;
}

/// Short ruled column chart (months, weeks): bars grow from the baseline
/// with a small stagger; the highlighted one is teal, the rest soft ink.
class KhataColumns extends StatelessWidget {
  const KhataColumns({super.key, required this.columns, this.height = 96, this.semanticLabel});

  final List<KhataColumn> columns;
  final double height;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final t = context.type;
    final maxV = columns.fold<double>(0, (m, x) => math.max(m, x.value));
    return Semantics(
      label: semanticLabel,
      excludeSemantics: semanticLabel != null,
      child: _Reveal(
        valueKey: Object.hashAll(columns.map((x) => x.value.round())),
        builder: (p) => Column(
          children: [
            SizedBox(
              height: height,
              child: CustomPaint(
                painter: _RowsPainter(c.khataRule),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (var i = 0; i < columns.length; i++)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 5),
                          child: FractionallySizedBox(
                            heightFactor: maxV <= 0
                                ? 0.02
                                : (columns[i].value / maxV *
                                          ((p * columns.length - i * 0.5) / (columns.length - i * 0.5)).clamp(0.0, 1.0))
                                      .clamp(0.02, 1.0),
                            alignment: Alignment.bottomCenter,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: columns[i].color ??
                                    (columns[i].highlight ? c.brand : c.inkSoft.withValues(alpha: 0.35)),
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: Sp.xs + 2),
            Row(
              children: [
                for (final col in columns)
                  Expanded(
                    child: Text(
                      col.label,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      style: t.small.copyWith(
                        fontSize: 12,
                        color: col.highlight ? c.ink : c.inkSoft,
                        fontWeight: col.highlight ? FontWeight.w700 : null,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RowsPainter extends CustomPainter {
  const _RowsPainter(this.rule);
  final Color rule;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = rule
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = size.height * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }

  @override
  bool shouldRepaint(_RowsPainter old) => old.rule != rule;
}

/// A tilted ink stamp ("On track", "Over", "Done") with a double edge.
class KhataStamp extends StatelessWidget {
  const KhataStamp({super.key, required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    return Transform.rotate(
      angle: -0.08,
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          border: Border.all(color: color.withValues(alpha: 0.85), width: 1.5),
          borderRadius: Rad.rSm,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: Sp.sm, vertical: 3),
          decoration: BoxDecoration(
            border: Border.all(color: color.withValues(alpha: 0.5)),
            borderRadius: const BorderRadius.all(Radius.circular(Rad.sm - 2)),
          ),
          child: Text(
            label.toUpperCase(),
            maxLines: 1,
            style: t.small.copyWith(color: color, fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 1.1),
          ),
        ),
      ),
    );
  }
}

/// Legend line for Bahi charts: colour dot, label, value on the right.
class KhataKey extends StatelessWidget {
  const KhataKey({super.key, required this.color, required this.label, required this.value});

  final Color color;
  final String label;
  final Widget value;

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
          const SizedBox(width: Sp.sm),
          Expanded(child: Text(label, style: t.label, maxLines: 1, overflow: TextOverflow.ellipsis)),
          const SizedBox(width: Sp.sm),
          value,
        ],
      ),
    );
  }
}
