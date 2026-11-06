import 'dart:math' as math;
import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';

import '../../../design_system/design_system.dart';
import '../../../kit/kit.dart' show LedgerContext;

/// The FiNN agent mark: an indigo key (the rounded-square icon well of the
/// Bahi kit, standing on its darker edge) carrying an "F" drawn as ledger
/// strokes over a double "total" rule, with a marigold spark for
/// "assistant". Geometric and flat like the rest of the kit: no gradient,
/// no robot, no play-button triangle.
///
/// [phase] (0..1) twinkles the spark so callers can animate it; the static
/// mark uses 0.
class FinnAgentMark extends StatelessWidget {
  const FinnAgentMark({super.key, this.size = 40, this.phase = 0, this.semanticLabel});

  final double size;
  final double phase;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final mark = CustomPaint(
      size: Size.square(size),
      painter: _MarkPainter(
        tile: c.deep,
        // A deeper shade of the tile in both themes (the kit's dark `edge`
        // is marigold, which would read as a second shape here).
        edge: Color.lerp(c.deep, const Color(0xFF000000), 0.35)!,
        glyph: const Color(0xFFFFFFFF),
        spark: c.marigold,
        phase: phase,
      ),
    );
    if (semanticLabel == null) return ExcludeSemantics(child: mark);
    return Semantics(label: semanticLabel, image: true, child: mark);
  }
}

/// Corner radius of the mark's tile as a share of its side.
const _tileRadius = 0.26;

class _MarkPainter extends CustomPainter {
  const _MarkPainter({
    required this.tile,
    required this.edge,
    required this.glyph,
    required this.spark,
    required this.phase,
  });

  final Color tile;
  final Color edge;
  final Color glyph;
  final Color spark;
  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final radius = Radius.circular(s * _tileRadius);
    // The key stands on a darker edge, like the kit's pressable buttons.
    final lip = math.max(1.0, s * 0.06);
    canvas.drawRRect(RRect.fromRectAndRadius(Offset.zero & Size.square(s), radius), Paint()..color = edge);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, s, s - lip), radius), Paint()..color = tile);

    final h = s - lip;
    Offset p(double x, double y) => Offset(x * s, y * h);

    // "F" monogram as ledger strokes: stem, top arm, shorter middle arm.
    final stroke = Paint()
      ..color = glyph
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = math.max(1.6, s * 0.085);
    final f = Path()
      ..moveTo(p(0.64, 0.25).dx, p(0.64, 0.25).dy)
      ..lineTo(p(0.33, 0.25).dx, p(0.33, 0.25).dy)
      ..lineTo(p(0.33, 0.68).dx, p(0.33, 0.68).dy)
      ..moveTo(p(0.33, 0.465).dx, p(0.33, 0.465).dy)
      ..lineTo(p(0.54, 0.465).dx, p(0.54, 0.465).dy);
    canvas.drawPath(f, stroke);

    // Double rule under the figure: the ledger's "total" line. One rule at
    // small sizes, where two would blur into one.
    final rule = Paint()
      ..color = glyph.withValues(alpha: 0.72)
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(1.0, s * 0.04);
    final ruleY = s < 32 ? [0.82] : [0.80, 0.88];
    for (final y in ruleY) {
      canvas.drawLine(p(0.27, y), p(0.73, y), rule);
    }

    // Four-point marigold spark: the assistant. Twinkles with [phase].
    final twinkle = 1 + 0.16 * math.sin(phase * 2 * math.pi);
    final c = p(0.74, 0.50);
    final r = s * 0.115 * twinkle;
    final k = r * 0.22; // waist of the spark
    final sparkPath = Path()
      ..moveTo(c.dx, c.dy - r)
      ..quadraticBezierTo(c.dx + k, c.dy - k, c.dx + r, c.dy)
      ..quadraticBezierTo(c.dx + k, c.dy + k, c.dx, c.dy + r)
      ..quadraticBezierTo(c.dx - k, c.dy + k, c.dx - r, c.dy)
      ..quadraticBezierTo(c.dx - k, c.dy - k, c.dx, c.dy - r)
      ..close();
    canvas.drawPath(sparkPath, Paint()..color = spark);
  }

  @override
  bool shouldRepaint(_MarkPainter old) =>
      old.phase != phase || old.tile != tile || old.edge != edge || old.glyph != glyph || old.spark != spark;
}

/// The agent button mark with its working states.
///
/// At rest it is the plain [FinnAgentMark]. A marigold trace runs once
/// around the key when it appears and again whenever [attentionKey] changes
/// ([idleLoops] laps), then fades out, so nothing moves in the background.
/// [active] (agent mode on) keeps a faint outline with the trace running;
/// [listening] adds a soft halo that breathes outward. Continuous motion is
/// reserved for those two working states. Reduced motion shows the static
/// mark, with a still outline while active or listening so the state stays
/// visible.
class AgentOrb extends StatefulWidget {
  const AgentOrb({
    super.key,
    this.size = 54,
    this.active = false,
    this.listening = false,
    this.attentionKey,
    this.idleLoops = 2,
  });

  final double size;
  final bool active;

  /// Voice capture is running: the halo breathes.
  final bool listening;

  /// Replays the idle attention trace when it changes.
  final Object? attentionKey;
  final int idleLoops;

  @override
  State<AgentOrb> createState() => _AgentOrbState();
}

class _AgentOrbState extends State<AgentOrb> with SingleTickerProviderStateMixin {
  late final AnimationController _loop = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400));
  bool _reduced = false;

  bool get _working => widget.active || widget.listening;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = context.reduceMotion;
    if (reduced != _reduced || !_loop.isAnimating) {
      _reduced = reduced;
      _syncAnimation(restartBurst: true);
    }
  }

  @override
  void didUpdateWidget(AgentOrb old) {
    super.didUpdateWidget(old);
    if (_working != (old.active || old.listening) || widget.attentionKey != old.attentionKey) {
      _syncAnimation(restartBurst: true);
    }
  }

  void _syncAnimation({required bool restartBurst}) {
    if (_reduced) {
      _loop
        ..stop()
        ..value = 0;
    } else if (_working) {
      if (!_loop.isAnimating) _loop.repeat();
    } else if (restartBurst && widget.idleLoops > 0) {
      _loop
        ..value = 0
        ..repeat(count: widget.idleLoops);
    } else {
      _loop
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final size = widget.size;
    // Room for the trace outside the key: stroke plus a hairline gap.
    final inset = math.max(3.0, size * 0.075);
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _loop,
        builder: (context, _) {
          final t = _loop.value;
          return SizedBox.square(
            dimension: size,
            child: CustomPaint(
              painter: _TracePainter(
                t: t,
                color: c.marigold,
                inset: inset,
                working: _working,
                listening: widget.listening,
                reduced: _reduced,
                running: _loop.isAnimating,
              ),
              child: Padding(
                padding: EdgeInsets.all(inset),
                child: FinnAgentMark(size: size - inset * 2, phase: _loop.isAnimating ? (t * 2) % 1 : 0),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// The marigold outline around the key: a travelling segment while the
/// orb animates, a faint track while working, a breathing halo while
/// listening.
class _TracePainter extends CustomPainter {
  const _TracePainter({
    required this.t,
    required this.color,
    required this.inset,
    required this.working,
    required this.listening,
    required this.reduced,
    required this.running,
  });

  final double t;
  final Color color;
  final double inset;
  final bool working;
  final bool listening;
  final bool reduced;
  final bool running;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final markSide = s - inset * 2;
    final stroke = math.max(1.5, s * 0.04);
    final half = stroke / 2;
    final rect = Rect.fromLTWH(half, half, s - stroke, s - stroke);
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(markSide * _tileRadius + inset - half));
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;

    if (reduced) {
      if (working) canvas.drawRRect(rrect, paint..color = color);
      return;
    }

    if (working) canvas.drawRRect(rrect, paint..color = color.withValues(alpha: 0.22));

    if (listening) {
      // Halo breathes outward twice per loop.
      final b = (t * 2) % 1;
      final grow = Curves.easeOut.transform(b) * inset * 1.6;
      canvas.drawRRect(
        rrect.inflate(grow),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.0, stroke * 0.7)
          ..color = color.withValues(alpha: 0.45 * (1 - b)),
      );
    }

    if (!running) return;
    // Idle laps fade in and out so the trace never cuts off abruptly.
    final strength = working ? 1.0 : math.sin(t * math.pi);
    if (strength <= 0.01) return;
    final metric = (Path()..addRRect(rrect)).computeMetrics().first;
    _segment(canvas, metric, t, 0.26, paint..color = color.withValues(alpha: strength));
  }

  /// Draws [share] of the outline ending at [t] (wraps past the start).
  void _segment(Canvas canvas, PathMetric m, double t, double share, Paint paint) {
    final len = m.length;
    final end = t * len;
    final start = end - share * len;
    if (start >= 0) {
      canvas.drawPath(m.extractPath(start, end), paint);
    } else {
      canvas.drawPath(m.extractPath(len + start, len), paint);
      canvas.drawPath(m.extractPath(0, end), paint);
    }
  }

  @override
  bool shouldRepaint(_TracePainter old) =>
      old.t != t ||
      old.color != color ||
      old.inset != inset ||
      old.working != working ||
      old.listening != listening ||
      old.reduced != reduced ||
      old.running != running;
}
