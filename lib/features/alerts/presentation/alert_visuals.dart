import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../design_system/design_system.dart';
import '../domain/alert.dart';

/// Hand-drawn picture of an alert: a calendar for due dates, a gauge for
/// budgets, a filling shield for the emergency fund, a ring or plan line for
/// goals and a tipping scale for a deficit.
///
/// Animations are finite (an intro plus a few ambient beats) so screens
/// settle, and they collapse to the final frame under reduced motion.
class AlertIllustration extends StatefulWidget {
  const AlertIllustration({super.key, required this.visual, required this.accent, this.size = 96});

  final AlertVisual visual;
  final Color accent;
  final double size;

  @override
  State<AlertIllustration> createState() => _AlertIllustrationState();
}

class _AlertIllustrationState extends State<AlertIllustration> with TickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  );
  late final AnimationController _ambient = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );
  bool _started = false;

  /// Only pictures that move after the intro (a wobbling late calendar, a
  /// trembling needle, a liquid wave, a rocking scale) run the ambient beat;
  /// the rest stop repainting as soon as the intro ends.
  static bool _usesAmbient(AlertVisual v) => switch (v) {
    DueVisual() => v.isLate,
    BudgetVisual() => v.isOver,
    SafetyNetVisual() => v.isConfigured && v.fraction > 0 && v.fraction < 1,
    CashFlowVisual() => true,
    _ => false,
  };

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (context.reduceMotion) {
      _intro.value = 1;
      _ambient.value = 0;
    } else {
      _intro.forward().whenComplete(() {
        if (mounted && _usesAmbient(widget.visual)) {
          _ambient.repeat(count: 3).whenComplete(() => _ambient.value = 0);
        }
      });
    }
  }

  @override
  void dispose() {
    _intro.dispose();
    _ambient.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final palette = _Palette(
      accent: widget.accent,
      surface: c.surface,
      track: c.isDark ? c.border : c.surfaceSunken,
      ink: c.textPrimary,
      muted: c.textTertiary,
      positive: c.positive,
      negative: c.negative,
      attention: c.attention,
      info: c.info,
    );
    final v = widget.visual;
    final Listenable repaint = _usesAmbient(v) ? Listenable.merge([_intro, _ambient]) : _intro;
    double intro() => Curves2.emphasized.transform(_intro.value);
    double ambient() => _ambient.value;
    final painter = switch (v) {
      DueVisual() => _CalendarPainter.due(v, palette, intro, ambient, repaint),
      AgedVisual() => _CalendarPainter.aged(v, palette, intro, ambient, repaint),
      BudgetVisual() => _GaugePainter(v, palette, intro, ambient, repaint),
      SafetyNetVisual() => _ShieldPainter(v, palette, intro, ambient, repaint),
      GoalVisual() when v.isBehind => _PlanLinePainter(v, palette, intro, repaint),
      GoalVisual() => _RingPainter(v, palette, intro, repaint),
      CashFlowVisual() => _ScalePainter(v, palette, intro, ambient, repaint),
    };
    final badge = _badgeFor(v, c);
    // Own layer: the badge and icon animations never repaint the card around it.
    return RepaintBoundary(
      child: SizedBox.square(
        dimension: widget.size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: RepaintBoundary(child: CustomPaint(painter: painter)),
            ),
            if (v is GoalVisual && !v.isBehind)
              Center(
                child:
                    Icon(
                      v.isReached ? LucideIcons.trophy : LucideIcons.flag,
                      size: widget.size * 0.3,
                      color: v.isReached ? c.positive : widget.accent,
                    ).maybeAnimate(
                      context,
                      (a) => a.scale(
                        delay: 500.ms,
                        duration: 500.ms,
                        curve: Curves.elasticOut,
                        begin: const Offset(0.3, 0.3),
                      ),
                    ),
              ),
            if (v is SafetyNetVisual && !v.isConfigured)
              Center(
                child: Icon(LucideIcons.plus, size: widget.size * 0.26, color: widget.accent).maybeAnimate(
                  context,
                  (a) => a
                      .scale(duration: 420.ms, curve: Curves.easeOutBack, begin: const Offset(0.4, 0.4))
                      .then(delay: 300.ms)
                      .scaleXY(end: 1.18, duration: 380.ms, curve: Curves.easeInOut)
                      .then()
                      .scaleXY(end: 1 / 1.18, duration: 380.ms, curve: Curves.easeInOut),
                ),
              ),
            if (badge != null)
              PositionedDirectional(
                end: -2,
                bottom: -2,
                child: badge.maybeAnimate(
                  context,
                  (a) => a
                      .scale(delay: 650.ms, duration: 450.ms, curve: Curves.elasticOut, begin: const Offset(0.2, 0.2))
                      .then(delay: 200.ms)
                      .moveY(end: -4, duration: 260.ms, curve: Curves.easeOut)
                      .then()
                      .moveY(end: 4, duration: 320.ms, curve: Curves.bounceOut),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Corner badge that says which way money moves.
  Widget? _badgeFor(AlertVisual v, FinnColors c) {
    final (IconData icon, Color color)? spec = switch (v) {
      DueVisual(recurring: true) => (LucideIcons.repeat, c.accentSubscriptions),
      DueVisual(outgoing: true, party: DueParty.bank) => (LucideIcons.landmark, widget.accent),
      DueVisual(outgoing: true) => (LucideIcons.arrowUpRight, widget.accent),
      AgedVisual(outgoing: true) => (LucideIcons.arrowUpRight, widget.accent),
      DueVisual(outgoing: false) || AgedVisual() => (LucideIcons.arrowDownLeft, c.positive),
      _ => null,
    };
    if (spec == null) return null;
    final s = widget.size * 0.34;
    return Container(
      width: s,
      height: s,
      decoration: BoxDecoration(
        color: spec.$2,
        shape: BoxShape.circle,
        border: Border.all(color: c.surface, width: 2.5),
        boxShadow: Elevation.tinted(spec.$2, alpha: 0.35),
      ),
      child: Icon(spec.$1, size: s * 0.5, color: Colors.white),
    );
  }
}

/// Runs [build] on a flutter_animate chain unless reduced motion is on.
extension MaybeAnimate on Widget {
  Widget maybeAnimate(BuildContext context, Animate Function(Animate a) build) =>
      context.reduceMotion ? this : build(animate());
}

class _Palette {
  const _Palette({
    required this.accent,
    required this.surface,
    required this.track,
    required this.ink,
    required this.muted,
    required this.positive,
    required this.negative,
    required this.attention,
    required this.info,
  });

  final Color accent, surface, track, ink, muted, positive, negative, attention, info;

  @override
  bool operator ==(Object other) =>
      other is _Palette &&
      other.accent == accent &&
      other.surface == surface &&
      other.track == track &&
      other.ink == ink &&
      other.muted == muted &&
      other.positive == positive &&
      other.negative == negative &&
      other.attention == attention &&
      other.info == info;

  @override
  int get hashCode => Object.hash(accent, surface, track, ink, muted, positive, negative, attention, info);
}

typedef _T = double Function();

abstract class _BasePainter extends CustomPainter {
  _BasePainter(this.p, Listenable repaint) : super(repaint: repaint);

  final _Palette p;

  /// The figures being drawn. A rebuilt painter only repaints when these or
  /// the palette change; animation frames repaint through the listenable.
  Object get data;

  /// Laid-out labels, reused across frames while the text and style hold.
  final _labels = <Object, TextPainter>{};

  /// A short decaying wobble over one ambient beat (0 at rest).
  static double wobble(double phase, {double cycles = 2}) => math.sin(phase * math.pi * 2 * cycles) * (1 - phase);

  void text(
    Canvas canvas,
    String s,
    Offset center, {
    required double size,
    required Color color,
    FontWeight weight = FontWeight.w900,
    double letterSpacing = 0,
    double maxWidth = 200,
  }) {
    final key = (s, size, color, weight, letterSpacing, maxWidth);
    var tp = _labels[key];
    if (tp == null) {
      // Intro frames fade and count up, so keys churn; keep the cache tiny.
      if (_labels.length >= 6) {
        for (final old in _labels.values) {
          old.dispose();
        }
        _labels.clear();
      }
      tp = _labels[key] = TextPainter(
        text: TextSpan(
          text: s,
          style: TextStyle(fontSize: size, fontWeight: weight, color: color, letterSpacing: letterSpacing, height: 1),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: maxWidth);
    }
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _BasePainter old) => old.runtimeType != runtimeType || old.p != p || old.data != data;
}

// ---------------------------------------------------------------------------
// Calendar page: days left / days late / days open.
// ---------------------------------------------------------------------------

class _CalendarPainter extends _BasePainter {
  _CalendarPainter.due(DueVisual v, _Palette p, this.intro, this.ambient, Listenable r)
    : days = v.daysUntil.abs(),
      late = v.isLate,
      caption = v.isLate
          ? (v.daysUntil == -1 ? 'DAY LATE' : 'DAYS LATE')
          : v.daysUntil == 0
          ? 'TODAY'
          : v.daysUntil == 1
          ? 'DAY LEFT'
          : 'DAYS LEFT',
      super(p, r);

  _CalendarPainter.aged(AgedVisual v, _Palette p, this.intro, this.ambient, Listenable r)
    : days = v.daysOpen,
      late = false,
      caption = v.daysOpen == 1 ? 'DAY PASSED' : 'DAYS PASSED',
      super(p, r);

  final int days;
  final bool late;
  final String caption;

  @override
  Object get data => (days, late, caption);
  final _T intro, ambient;

  @override
  void paint(Canvas canvas, Size size) {
    final t = intro();
    final w = size.width * 0.72, h = size.height * 0.76;
    final color = late ? p.negative : p.accent;

    canvas.save();
    // Drop in from above, then wobble when late.
    canvas.translate(size.width / 2, size.height / 2 + (1 - t) * -14);
    if (late) canvas.rotate(_BasePainter.wobble(ambient(), cycles: 3) * 0.09);
    final page = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset.zero, width: w, height: h),
      const Radius.circular(12),
    );

    canvas.drawRRect(page.shift(const Offset(0, 3)), Paint()..color = color.withValues(alpha: 0.18 * t));
    canvas.drawRRect(page, Paint()..color = p.surface.withValues(alpha: t));
    canvas.drawRRect(
      page,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = color.withValues(alpha: 0.55 * t),
    );

    // Header band.
    final headerH = h * 0.26;
    canvas.save();
    canvas.clipRRect(page);
    canvas.drawRect(Rect.fromLTWH(-w / 2, -h / 2, w, headerH), Paint()..color = color.withValues(alpha: t));
    canvas.restore();

    // Binder rings.
    final ring = Paint()
      ..color = p.ink.withValues(alpha: 0.7 * t)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    for (final dx in [-w * 0.22, w * 0.22]) {
      canvas.drawLine(Offset(dx, -h / 2 - 5), Offset(dx, -h / 2 + 5), ring);
    }

    // Big count-up number + caption.
    final bodyTop = -h / 2 + headerH;
    final bodyCenter = bodyTop + (h - headerH) * 0.42;
    if (caption == 'TODAY') {
      text(
        canvas,
        '!',
        Offset(0, bodyCenter),
        size: h * 0.36,
        color: color.withValues(alpha: t),
      );
    } else {
      final shown = (days * t).round();
      text(
        canvas,
        '$shown',
        Offset(0, bodyCenter),
        size: h * (shown >= 100 ? 0.28 : 0.36),
        color: color.withValues(alpha: t),
      );
    }
    text(
      canvas,
      caption,
      Offset(0, h / 2 - (h - headerH) * 0.17),
      size: h * 0.105,
      color: p.muted.withValues(alpha: t),
      weight: FontWeight.w800,
      letterSpacing: 0.4,
      maxWidth: w - 6,
    );
    canvas.restore();
  }
}

// ---------------------------------------------------------------------------
// Speedometer gauge for a budget.
// ---------------------------------------------------------------------------

class _GaugePainter extends _BasePainter {
  _GaugePainter(this.v, _Palette p, this.intro, this.ambient, Listenable r) : super(p, r);

  final BudgetVisual v;

  @override
  Object get data => v;
  final _T intro, ambient;

  static const _max = 1.25; // scale runs to 125% of the limit

  @override
  void paint(Canvas canvas, Size size) {
    final t = intro();
    final stroke = size.width * 0.11;
    final r = size.width / 2 - stroke / 2 - 2;
    final center = Offset(size.width / 2, size.height * 0.6);
    final rect = Rect.fromCircle(center: center, radius: r);
    double angleFor(double f) => math.pi + (f.clamp(0, _max) / _max) * math.pi;

    // Track zones: safe / careful / over.
    void zone(double from, double to, Color color, double alpha) => canvas.drawArc(
      rect,
      angleFor(from),
      angleFor(to) - angleFor(from),
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = color.withValues(alpha: alpha),
    );
    zone(0, 0.75, p.positive, 0.16);
    zone(0.75, 1, p.attention, 0.2);
    zone(1, _max, p.negative, 0.2);

    // Filled value.
    final f = math.min(v.fraction, _max) * t;
    final fillColor = v.isOver ? p.negative : (v.fraction >= 0.75 ? p.attention : p.positive);
    canvas.drawArc(
      rect,
      math.pi,
      angleFor(f) - math.pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = fillColor,
    );

    // Limit notch at 100%.
    final limitA = angleFor(1);
    canvas.drawLine(
      center + Offset(math.cos(limitA), math.sin(limitA)) * (r - stroke * 0.9),
      center + Offset(math.cos(limitA), math.sin(limitA)) * (r + stroke * 0.9),
      Paint()
        ..color = p.ink
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round,
    );

    // Needle (trembles when over the limit).
    var a = angleFor(f);
    if (v.isOver) a += _BasePainter.wobble(ambient(), cycles: 4) * 0.08;
    final tip = center + Offset(math.cos(a), math.sin(a)) * (r - stroke * 0.2);
    canvas.drawLine(
      center,
      tip,
      Paint()
        ..color = p.ink
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(center, stroke * 0.42, Paint()..color = p.ink);
    canvas.drawCircle(center, stroke * 0.18, Paint()..color = p.surface);

    final pct = (v.fraction * 100 * t).round();
    text(
      canvas,
      '$pct%',
      Offset(size.width / 2, center.dy + size.height * 0.2),
      size: size.height * 0.17,
      color: fillColor,
    );
  }
}

// ---------------------------------------------------------------------------
// Shield filling with liquid: emergency fund coverage.
// ---------------------------------------------------------------------------

class _ShieldPainter extends _BasePainter {
  _ShieldPainter(this.v, _Palette p, this.intro, this.ambient, Listenable r) : super(p, r);

  final SafetyNetVisual v;

  @override
  Object get data => v;
  final _T intro, ambient;

  Path _shield(Size s) {
    final w = s.width * 0.7, h = s.height * 0.82;
    final l = (s.width - w) / 2, top = (s.height - h) / 2;
    return Path()
      ..moveTo(s.width / 2, top)
      ..cubicTo(l + w * 0.78, top + h * 0.1, l + w, top + h * 0.1, l + w, top + h * 0.14)
      ..lineTo(l + w, top + h * 0.48)
      ..cubicTo(l + w, top + h * 0.76, s.width / 2 + w * 0.12, top + h * 0.92, s.width / 2, top + h)
      ..cubicTo(s.width / 2 - w * 0.12, top + h * 0.92, l, top + h * 0.76, l, top + h * 0.48)
      ..lineTo(l, top + h * 0.14)
      ..cubicTo(l, top + h * 0.1, l + w * 0.22, top + h * 0.1, s.width / 2, top)
      ..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final t = intro();
    final shield = _shield(size);
    final bounds = shield.getBounds();

    if (!v.isConfigured) {
      // Dashed outline: nothing protected yet.
      canvas.drawPath(shield, Paint()..color = p.accent.withValues(alpha: 0.08 * t));
      final dash = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round
        ..color = p.accent;
      for (final metric in shield.computeMetrics()) {
        final drawn = metric.length * t;
        for (double d = 0; d < drawn; d += 9) {
          canvas.drawPath(metric.extractPath(d, math.min(d + 5, drawn)), dash);
        }
      }
      return;
    }

    canvas.drawPath(shield, Paint()..color = p.track);

    // Liquid with a travelling wave.
    final level = v.fraction * t;
    final y = bounds.bottom - bounds.height * level;
    final phase = ambient() * math.pi * 2;
    final amp = level <= 0 || level >= 1 ? 0.0 : 3.2;
    final wave = Path()..moveTo(bounds.left, bounds.bottom);
    for (double x = bounds.left; x <= bounds.right; x += 2) {
      wave.lineTo(x, y + math.sin((x - bounds.left) / bounds.width * math.pi * 2 + phase) * amp);
    }
    wave
      ..lineTo(bounds.right, bounds.bottom)
      ..close();
    canvas.save();
    canvas.clipPath(shield);
    canvas.drawPath(wave, Paint()..color = p.accent.withValues(alpha: 0.85));
    canvas.restore();

    canvas.drawPath(
      shield,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..color = p.accent,
    );

    final months = (v.coverageMonths ?? 0) * t;
    final inkOnFill = level > 0.55;
    text(
      canvas,
      months.toStringAsFixed(1),
      Offset(size.width / 2, bounds.top + bounds.height * 0.42),
      size: size.height * 0.21,
      color: inkOnFill ? Colors.white : p.ink,
    );
    text(
      canvas,
      'MONTHS',
      Offset(size.width / 2, bounds.top + bounds.height * 0.62),
      size: size.height * 0.085,
      color: level > 0.4 ? Colors.white.withValues(alpha: 0.9) : p.muted,
      weight: FontWeight.w800,
      letterSpacing: 0.5,
    );
  }
}

// ---------------------------------------------------------------------------
// Goal progress ring with confetti when reached.
// ---------------------------------------------------------------------------

class _RingPainter extends _BasePainter {
  _RingPainter(this.v, _Palette p, this.intro, Listenable r) : super(p, r);

  final GoalVisual v;

  @override
  Object get data => v;
  final _T intro;

  static const _confetti = [
    Color(0xFFF59E0B), Color(0xFF10B981), Color(0xFF3B82F6), Color(0xFFEC4899), Color(0xFF8B5CF6), //
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final t = intro();
    final center = size.center(Offset.zero);
    final stroke = size.width * 0.1;
    final r = size.width / 2 - stroke / 2 - 4;
    final color = v.isReached ? p.positive : p.accent;

    canvas.drawCircle(
      center,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = p.track,
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: r),
      -math.pi / 2,
      math.pi * 2 * v.fraction * t,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = color,
    );

    if (!v.isReached) return;
    // Confetti burst from the ring outwards, fading as it travels.
    final rnd = math.Random(7);
    for (var i = 0; i < 22; i++) {
      final angle = i / 22 * math.pi * 2 + rnd.nextDouble() * 0.3;
      final dist = r * (0.5 + t * (0.75 + rnd.nextDouble() * 0.35));
      final pos = center + Offset(math.cos(angle), math.sin(angle)) * dist + Offset(0, t * t * 6);
      final paint = Paint()..color = _confetti[i % _confetti.length].withValues(alpha: (1 - t * 0.85).clamp(0.0, 1.0));
      canvas.save();
      canvas.translate(pos.dx, pos.dy);
      canvas.rotate(angle + t * 4);
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: 6, height: 3), const Radius.circular(1)),
        paint,
      );
      canvas.restore();
    }
  }
}

// ---------------------------------------------------------------------------
// Plan vs actual line for a goal falling behind.
// ---------------------------------------------------------------------------

class _PlanLinePainter extends _BasePainter {
  _PlanLinePainter(this.v, _Palette p, this.intro, Listenable r) : super(p, r);

  final GoalVisual v;

  @override
  Object get data => v;
  final _T intro;

  @override
  void paint(Canvas canvas, Size size) {
    final t = intro();
    final pad = size.width * 0.12;
    final chart = Rect.fromLTRB(pad, pad * 1.2, size.width - pad, size.height - pad);
    Offset at(double x, double y) => Offset(chart.left + chart.width * x, chart.bottom - chart.height * y);

    // Baseline.
    canvas.drawLine(
      chart.bottomLeft,
      chart.bottomRight,
      Paint()
        ..color = p.track
        ..strokeWidth = 2,
    );

    // Plan: dashed straight line to the flag.
    final plan = Paint()
      ..color = p.muted
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    const dashes = 14;
    for (var i = 0; i < dashes; i++) {
      final a = i / dashes, b = (i + 0.55) / dashes;
      if (a > t) break;
      canvas.drawLine(at(a, a), at(math.min(b, t), math.min(b, t)), plan);
    }

    // Flag at the target.
    final flagBase = at(1, 1);
    canvas.drawLine(
      flagBase,
      flagBase - const Offset(0, 16),
      Paint()
        ..color = p.ink
        ..strokeWidth = 2,
    );
    canvas.drawPath(
      Path()
        ..moveTo(flagBase.dx, flagBase.dy - 16)
        ..lineTo(flagBase.dx - 11, flagBase.dy - 12)
        ..lineTo(flagBase.dx, flagBase.dy - 8)
        ..close(),
      Paint()..color = p.accent.withValues(alpha: t),
    );

    // You: a flatter line that stops short, leaving a visible gap.
    const x = 0.62;
    final yYou = math.min(v.fraction, x - 0.2).clamp(0.06, 1.0);
    final you = Path()..moveTo(at(0, 0).dx, at(0, 0).dy);
    const steps = 20;
    for (var i = 1; i <= steps; i++) {
      final s = i / steps * t;
      final px = x * s;
      final py = yYou * math.pow(s, 0.8);
      you.lineTo(at(px, py).dx, at(px, py).dy);
    }
    canvas.drawPath(
      you,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = p.accent,
    );

    if (t < 0.95) return;
    final youPt = at(x, yYou);
    final planPt = at(x, x);
    canvas.drawCircle(youPt, 4.5, Paint()..color = p.accent);
    canvas.drawCircle(youPt, 2, Paint()..color = p.surface);
    // Gap bracket.
    final gap = Paint()
      ..color = p.negative
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (double d = planPt.dy + 3; d < youPt.dy - 6; d += 5) {
      canvas.drawLine(Offset(youPt.dx, d), Offset(youPt.dx, math.min(d + 2.5, youPt.dy - 6)), gap);
    }
    text(canvas, 'GAP', Offset(youPt.dx + 14, (planPt.dy + youPt.dy) / 2), size: size.height * 0.1, color: p.negative);
  }
}

// ---------------------------------------------------------------------------
// Balance scale tipping towards spending.
// ---------------------------------------------------------------------------

class _ScalePainter extends _BasePainter {
  _ScalePainter(this.v, _Palette p, this.intro, this.ambient, Listenable r) : super(p, r);

  final CashFlowVisual v;

  @override
  Object get data => v;
  final _T intro, ambient;

  @override
  void paint(Canvas canvas, Size size) {
    final t = intro();
    final ink = Paint()
      ..color = p.ink
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round;
    final pivot = Offset(size.width / 2, size.height * 0.24);
    final arm = size.width * 0.36;

    // Post and base.
    canvas.drawLine(pivot, Offset(pivot.dx, size.height * 0.86), ink);
    canvas.drawLine(Offset(pivot.dx - 14, size.height * 0.86), Offset(pivot.dx + 14, size.height * 0.86), ink);

    // Heavier side (spending) dips; ratio sets the tilt.
    final out = v.expense.paise.toDouble(), inc = math.max(1.0, v.income.paise.toDouble());
    final ratio = ((out - inc) / inc).clamp(0.05, 1.0);
    final tilt = (0.12 + 0.2 * ratio) * t + _BasePainter.wobble(ambient()) * 0.05;
    final dir = Offset(math.cos(tilt), math.sin(tilt));
    final left = pivot - dir * arm, right = pivot + dir * arm;
    canvas.drawLine(left, right, ink);
    canvas.drawCircle(pivot, 4, Paint()..color = p.ink);

    void pan(Offset hook, Color color, String label, int coins) {
      final drop = size.height * 0.28;
      final base = hook + Offset(0, drop);
      final string = Paint()
        ..color = p.muted
        ..strokeWidth = 1.2;
      canvas.drawLine(hook, base + const Offset(-12, 0), string);
      canvas.drawLine(hook, base + const Offset(12, 0), string);
      // Coin stack.
      for (var i = 0; i < coins; i++) {
        final appear = ((t * 1.4) - i * 0.12).clamp(0.0, 1.0);
        if (appear <= 0) continue;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: base + Offset(0, -4.0 - i * 5), width: 16, height: 4.2),
            const Radius.circular(2),
          ),
          Paint()..color = color.withValues(alpha: appear),
        );
      }
      canvas.drawLine(
        base + const Offset(-14, 0),
        base + const Offset(14, 0),
        Paint()
          ..color = color
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round,
      );
      text(canvas, label, base + const Offset(0, 9), size: size.height * 0.1, color: color, letterSpacing: 0.4);
    }

    pan(left, p.positive, 'IN', 2);
    pan(right, p.negative, 'OUT', 2 + (3 * ratio).round());
  }
}
