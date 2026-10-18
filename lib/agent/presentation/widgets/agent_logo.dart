import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../design_system/design_system.dart';
import '../../../kit/kit.dart' show LedgerContext;

/// The FiNN agent mark: a fin cresting a wave on an ink disc, with a small
/// spark for "assistant". Flat ink and paper like the rest of the ledger kit,
/// deliberately not a gradient, sparkle or robot.
///
/// [phase] (0..1) drives the wave so callers can animate it; the static mark
/// uses 0.
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
      painter: _MarkPainter(disc: c.ink, glyph: c.onInk, phase: phase),
    );
    if (semanticLabel == null) return ExcludeSemantics(child: mark);
    return Semantics(label: semanticLabel, image: true, child: mark);
  }
}

class _MarkPainter extends CustomPainter {
  const _MarkPainter({required this.disc, required this.glyph, required this.phase});

  final Color disc;
  final Color glyph;
  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    canvas.drawCircle(Offset(s / 2, s / 2), s / 2, Paint()..color = disc);

    Offset p(double x, double y) => Offset(x * s, y * s);
    final white = Paint()..color = glyph;

    // Dorsal fin: convex leading edge, concave trailing edge.
    final fin = Path()
      ..moveTo(0.30 * s, 0.64 * s)
      ..cubicTo(0.36 * s, 0.48 * s, 0.46 * s, 0.30 * s, 0.62 * s, 0.22 * s)
      ..quadraticBezierTo(0.56 * s, 0.44 * s, 0.72 * s, 0.64 * s)
      ..close();
    canvas.drawPath(fin, white);

    // Wave the fin rides on.
    final wave = Path();
    const steps = 28;
    for (var i = 0; i <= steps; i++) {
      final x = 0.18 + 0.64 * i / steps;
      final y = 0.665 + 0.035 * math.sin((x * 3.2 + phase) * 2 * math.pi);
      i == 0 ? wave.moveTo(x * s, y * s) : wave.lineTo(x * s, y * s);
    }
    canvas.drawPath(
      wave,
      Paint()
        ..color = glyph
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = math.max(1.4, s * 0.06),
    );

    // Four-point spark beside the fin tip.
    final sc = p(0.30, 0.30);
    final r = s * 0.085;
    final spark = Path()
      ..moveTo(sc.dx, sc.dy - r)
      ..quadraticBezierTo(sc.dx, sc.dy, sc.dx + r, sc.dy)
      ..quadraticBezierTo(sc.dx, sc.dy, sc.dx, sc.dy + r)
      ..quadraticBezierTo(sc.dx, sc.dy, sc.dx - r, sc.dy)
      ..quadraticBezierTo(sc.dx, sc.dy, sc.dx, sc.dy - r)
      ..close();
    canvas.drawPath(spark, white..color = glyph.withValues(alpha: 0.92));
  }

  @override
  bool shouldRepaint(_MarkPainter old) => old.phase != phase || old.disc != disc || old.glyph != glyph;
}

/// The animated agent orb used as the centre button of the navigation bar.
///
/// A rotating green ring, a pulse halo and a flowing wave make it read as
/// "alive" and catch the eye. Idle, it plays an attention burst
/// ([idleLoops] loops) when it appears and again whenever [attentionKey]
/// changes (e.g. on tab switches), then rests, so it never drains the
/// battery in the background. [active] (agent mode on) or [listening] keep
/// it animating with a faster ring and stronger glow. Reduced motion shows
/// the static mark.
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

  /// Voice capture is running: the halo pulses faster.
  final bool listening;

  /// Replays the idle attention burst when it changes.
  final Object? attentionKey;
  final int idleLoops;

  @override
  State<AgentOrb> createState() => _AgentOrbState();
}

class _AgentOrbState extends State<AgentOrb> with SingleTickerProviderStateMixin {
  late final AnimationController _loop = AnimationController(vsync: this, duration: const Duration(seconds: 6));
  bool _reduced = false;

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
    final continuous = widget.active || widget.listening;
    if (continuous != (old.active || old.listening) || widget.attentionKey != old.attentionKey) {
      _syncAnimation(restartBurst: true);
    }
  }

  void _syncAnimation({required bool restartBurst}) {
    if (_reduced) {
      _loop
        ..stop()
        ..value = 0;
    } else if (widget.active || widget.listening) {
      if (!_loop.isAnimating) _loop.repeat();
    } else if (restartBurst && widget.idleLoops > 0) {
      _loop
        ..value = 0
        ..repeat(count: widget.idleLoops);
    } else {
      _loop.stop();
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
    final ringColors = [c.green.withValues(alpha: 0), c.green, c.green.withValues(alpha: 0)];
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _loop,
        builder: (context, _) {
          final t = _loop.value;
          // Ring turns once per loop idle, three times when active.
          final spin = t * (widget.active ? 3 : 1);
          // Halo pulses 3x per loop idle, 6x while active or listening.
          final pulses = widget.listening ? 8 : (widget.active ? 6 : 3);
          final pulse = (t * pulses) % 1;
          final glow = widget.active || widget.listening ? 0.6 : 0.4;
          return SizedBox.square(
            dimension: size,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                if (!context.reduceMotion)
                  // Expanding, fading pulse ring.
                  Transform.scale(
                    scale: 1 + 0.45 * Curves.easeOut.transform(pulse),
                    child: Container(
                      width: size,
                      height: size,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: c.green.withValues(alpha: (1 - pulse) * glow),
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                // Rotating green arc.
                Transform.rotate(
                  angle: spin * 2 * math.pi,
                  child: Container(
                    width: size,
                    height: size,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: SweepGradient(colors: ringColors, stops: const [0, 0.75, 1]),
                    ),
                  ),
                ),
                // Gap between ring and mark.
                Container(
                  width: size - 5,
                  height: size - 5,
                  decoration: BoxDecoration(color: c.surface, shape: BoxShape.circle),
                ),
                FinnAgentMark(size: size - 9, phase: t * 4),
              ],
            ),
          );
        },
      ),
    );
  }
}
