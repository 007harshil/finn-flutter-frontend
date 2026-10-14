import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../design_system/design_system.dart';
import 'agent_logo.dart';

/// What the agent is doing, as the visualizer and atmosphere express it.
enum AgentPresence { idle, listening, transcribing, thinking, reviewing, executing }

/// Palette of the immersive agent experience: deep midnight with cyan and
/// violet light. Shared by the atmosphere, visualizer and glass surfaces.
abstract final class AgentLight {
  static const midnight = Color(0xFF030817);
  static const midnightDeep = Color(0xFF01030B);
  static const cyan = Color(0xFF22D3EE);
  static const sky = Color(0xFF38BDF8);
  static const violet = Color(0xFFA78BFA);
  static const indigo = Color(0xFF6366F1);
  static const magenta = Color(0xFFD946EF);
  static const mint = Color(0xFF34D399);

  static const spectrum = [cyan, sky, indigo, violet, magenta, cyan];
}

/// Per-state targets the animation eases towards, so moving between states
/// always morphs instead of snapping.
class _Targets {
  const _Targets({
    required this.energy,
    required this.spin,
    required this.amp,
    required this.think,
    required this.execute,
    required this.wait,
  });

  /// Overall brightness and glow (0..1).
  final double energy;

  /// Ring rotation speed (radians per second).
  final double spin;

  /// Ring deformation, as a fraction of the visualizer size.
  final double amp;

  /// Orbiting comets (0..1).
  final double think;

  /// Sweeping action arc and inward particle flow (0..1).
  final double execute;

  /// Slow "your turn" breathing ring (0..1).
  final double wait;

  static _Targets of(AgentPresence p, double level) => switch (p) {
    AgentPresence.idle => const _Targets(energy: 0.32, spin: 0.22, amp: 0.010, think: 0, execute: 0, wait: 0),
    AgentPresence.listening => _Targets(
      energy: 0.55 + 0.45 * level,
      spin: 0.45 + 0.6 * level,
      amp: 0.018 + 0.075 * level,
      think: 0,
      execute: 0,
      wait: 0,
    ),
    AgentPresence.transcribing => const _Targets(energy: 0.6, spin: 1.1, amp: 0.016, think: 0.55, execute: 0, wait: 0),
    AgentPresence.thinking => const _Targets(energy: 0.72, spin: 1.6, amp: 0.022, think: 1, execute: 0, wait: 0),
    AgentPresence.reviewing => const _Targets(energy: 0.42, spin: 0.3, amp: 0.012, think: 0, execute: 0, wait: 1),
    AgentPresence.executing => const _Targets(energy: 0.9, spin: 2.4, amp: 0.008, think: 0.3, execute: 1, wait: 0),
  };
}

/// Live, smoothed animation values read by the painters every frame.
class _Frame extends ChangeNotifier {
  double t = 0;
  double energy = 0.32;
  double spin = 0.22;
  double angle = 0;
  double amp = 0.010;
  double think = 0;
  double execute = 0;
  double wait = 0;

  /// Start times (in [t]) of ripples still on screen.
  final ripples = <double>[];

  void tick() => notifyListeners();
}

/// The agent's original visualizer: liquid aurora rings, orbiting light
/// particles, voice ripples, thinking comets and an action arc, wrapped
/// around the existing animated FiNN agent logo ([AgentOrb]).
///
/// Everything is drawn by two painters driven by one ticker, so the widget
/// tree never rebuilds per frame. Reduced motion paints one still frame.
class AgentVisualizer extends StatefulWidget {
  const AgentVisualizer({
    super.key,
    required this.size,
    required this.presence,
    this.level = 0,
    this.pulse = 0,
    this.onTap,
    this.semanticLabel,
  });

  final double size;
  final AgentPresence presence;

  /// Current microphone level (0..1) while listening.
  final double level;

  /// Bumped when the agent answers: sends out a burst of ripples.
  final int pulse;
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  State<AgentVisualizer> createState() => _AgentVisualizerState();
}

class _AgentVisualizerState extends State<AgentVisualizer> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_onTick);
  final _frame = _Frame();
  Duration _last = Duration.zero;
  double _level = 0;
  double _nextListenRipple = 0;
  bool _reduced = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = context.reduceMotion;
    if (_reduced) {
      _ticker.stop();
      _snapToTargets();
    } else if (!_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    }
  }

  @override
  void didUpdateWidget(AgentVisualizer old) {
    super.didUpdateWidget(old);
    if (_reduced) {
      _snapToTargets();
      return;
    }
    if (widget.pulse != old.pulse) {
      _frame.ripples
        ..add(_frame.t)
        ..add(_frame.t + 0.28);
    }
  }

  void _snapToTargets() {
    final g = _Targets.of(widget.presence, widget.level);
    _frame
      ..energy = g.energy
      ..spin = g.spin
      ..amp = g.amp
      ..think = g.think
      ..execute = g.execute
      ..wait = g.wait
      ..ripples.clear()
      ..tick();
  }

  void _onTick(Duration elapsed) {
    final dt = ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _last = elapsed;
    final f = _frame;
    f.t += dt;

    // Voice level rises fast and falls slowly, like a VU meter.
    final target = widget.presence == AgentPresence.listening ? widget.level.clamp(0.0, 1.0) : 0.0;
    _level += (target - _level) * (1 - math.exp(-dt * (target > _level ? 18 : 5)));

    final g = _Targets.of(widget.presence, _level);
    double ease(double v, double to, double speed) => v + (to - v) * (1 - math.exp(-dt * speed));
    f
      ..energy = ease(f.energy, g.energy, 4)
      ..spin = ease(f.spin, g.spin, 2.5)
      ..amp = ease(f.amp, g.amp, 7)
      ..think = ease(f.think, g.think, 3)
      ..execute = ease(f.execute, g.execute, 3)
      ..wait = ease(f.wait, g.wait, 2.5);
    f.angle += f.spin * dt;

    // Listening sends out a ripple on a rhythm that quickens with the voice.
    if (widget.presence == AgentPresence.listening && f.t >= _nextListenRipple) {
      f.ripples.add(f.t);
      _nextListenRipple = f.t + lerpDouble(1.1, 0.45, _level)!;
    }
    f.ripples.removeWhere((start) => f.t - start > _RingsPainter.rippleLife);
    f.tick();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _frame.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final orb = size * 0.36;
    final listening = widget.presence == AgentPresence.listening;
    Widget content = SizedBox.square(
      dimension: size,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(painter: _RingsPainter(_frame, orbRadius: orb / 2)),
            ),
          ),
          // The existing animated agent logo, untouched, at the heart.
          AgentOrb(size: orb, active: true, listening: listening),
        ],
      ),
    );
    if (widget.onTap != null) {
      content = GestureDetector(behavior: HitTestBehavior.opaque, onTap: widget.onTap, child: content);
    }
    return Semantics(button: widget.onTap != null, label: widget.semanticLabel, excludeSemantics: true, child: content);
  }
}

class _RingsPainter extends CustomPainter {
  _RingsPainter(this.f, {required this.orbRadius}) : super(repaint: f);

  final _Frame f;
  final double orbRadius;

  static const rippleLife = 1.8;
  static const _particles = 46;
  static final _seeds = List.generate(_particles, (i) {
    final r = math.Random(i * 7919 + 17);
    return (
      orbit: 1.45 + r.nextDouble() * 1.15,
      angle: r.nextDouble() * 2 * math.pi,
      speed: (0.35 + r.nextDouble() * 0.9) * (r.nextBool() ? 1 : -1),
      size: 0.6 + r.nextDouble() * 1.6,
      phase: r.nextDouble(),
      tilt: 0.55 + r.nextDouble() * 0.45,
    );
  });

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final c = size.center(Offset.zero);
    final r0 = orbRadius;
    final e = f.energy;

    // 1. Ambient bloom behind everything.
    canvas.drawCircle(
      c,
      s * 0.5,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Color.lerp(AgentLight.cyan, AgentLight.mint, f.execute * 0.6)!.withValues(alpha: 0.10 + 0.22 * e),
            AgentLight.violet.withValues(alpha: 0.06 + 0.12 * e),
            AgentLight.violet.withValues(alpha: 0),
          ],
          stops: const [0.18, 0.55, 1],
        ).createShader(Rect.fromCircle(center: c, radius: s * 0.5)),
    );

    // 2. Ripples (voice rhythm, answers).
    for (final start in f.ripples) {
      final age = (f.t - start) / rippleLife;
      if (age < 0 || age > 1) continue;
      final eased = Curves.easeOutCubic.transform(age);
      final radius = lerpDouble(r0 * 1.05, s * 0.49, eased)!;
      canvas.drawCircle(
        c,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = lerpDouble(2.4, 0.6, age)!
          ..color = Color.lerp(AgentLight.cyan, AgentLight.violet, age)!.withValues(alpha: (1 - age) * 0.55),
      );
    }

    // 3. "Your turn" breathing ring while a review waits.
    if (f.wait > 0.01) {
      final breath = 0.5 + 0.5 * math.sin(f.t * 2.2);
      canvas.drawCircle(
        c,
        r0 * (1.32 + 0.06 * breath),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = AgentLight.sky.withValues(alpha: f.wait * (0.25 + 0.35 * breath)),
      );
    }

    // 4. Liquid aurora rings.
    for (var k = 0; k < 3; k++) {
      final base = r0 * (1.38 + 0.24 * k);
      final dir = k.isOdd ? -1.0 : 1.0;
      final rot = f.angle * dir * (1 - 0.18 * k);
      final amp = f.amp * s * (1 + 0.35 * k);
      final path = Path();
      const steps = 96;
      for (var i = 0; i <= steps; i++) {
        final th = i / steps * 2 * math.pi;
        final wobble =
            0.6 * math.sin(3 * th + f.t * (1.3 + 0.4 * k) + k * 1.7) +
            0.4 * math.sin(5 * th - f.t * (1.9 - 0.3 * k) + k * 2.9);
        final r = base + amp * wobble;
        final p = c + Offset(math.cos(th + rot), math.sin(th + rot)) * r;
        i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
      }
      path.close();
      final rect = Rect.fromCircle(center: c, radius: base + amp);
      final shader = SweepGradient(
        colors: AgentLight.spectrum,
        transform: GradientRotation(f.angle * 0.7 + k),
      ).createShader(rect);
      final alpha = (0.55 - 0.13 * k) * (0.45 + 0.55 * e);
      canvas
        ..drawPath(
          path,
          Paint()
            ..shader = shader
            ..style = PaintingStyle.stroke
            ..strokeWidth = 5 + 5 * e
            ..color = Colors.white.withValues(alpha: alpha * 0.45)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
        )
        ..drawPath(
          path,
          Paint()
            ..shader = shader
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.3 - 0.25 * k
            ..color = Colors.white.withValues(alpha: alpha),
        );
    }

    // 5. Thinking comets orbiting the core.
    if (f.think > 0.01) {
      final orbit = r0 * 2.05;
      final rect = Rect.fromCircle(center: c, radius: orbit);
      for (var i = 0; i < 3; i++) {
        final head = f.angle * 1.6 + i * 2 * math.pi / 3;
        const tail = 1.1;
        final paint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 2.2
          ..shader = SweepGradient(
            colors: [
              AgentLight.violet.withValues(alpha: 0),
              (i == 1 ? AgentLight.cyan : AgentLight.violet).withValues(alpha: 0.9 * f.think),
            ],
            stops: const [0, 1],
            transform: GradientRotation(head - tail),
            endAngle: tail,
          ).createShader(rect);
        canvas.drawArc(rect, head - tail, tail, false, paint);
        canvas.drawCircle(
          c + Offset(math.cos(head), math.sin(head)) * orbit,
          2.6,
          Paint()
            ..color = Colors.white.withValues(alpha: 0.9 * f.think)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
        );
      }
    }

    // 6. Action arc: a bright sweep closing around the core.
    if (f.execute > 0.01) {
      final rect = Rect.fromCircle(center: c, radius: r0 * 1.16);
      final start = f.angle * 1.3;
      final sweep = math.pi * (0.9 + 0.6 * math.sin(f.t * 3));
      canvas.drawArc(
        rect,
        start,
        sweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 3
          ..shader = SweepGradient(
            colors: [AgentLight.mint.withValues(alpha: 0), AgentLight.mint, AgentLight.cyan],
            stops: const [0, 0.6, 1],
            transform: GradientRotation(start),
            endAngle: sweep,
          ).createShader(rect)
          ..color = Colors.white.withValues(alpha: f.execute),
      );
    }

    // 7. Light particles: orbit freely, spiral inwards while acting.
    final dot = Paint();
    for (var i = 0; i < _particles; i++) {
      final p = _seeds[i];
      final flow = (f.t * 0.45 + p.phase) % 1;
      final pull = 1 - (f.execute * 0.55 + f.think * 0.2) * flow;
      final radius = r0 * p.orbit * pull + f.amp * s * 1.4 * math.sin(f.t * 3 + i);
      final a = p.angle + f.angle * p.speed * 0.6;
      final pos = c + Offset(math.cos(a), math.sin(a) * p.tilt) * radius;
      final twinkle = 0.45 + 0.55 * math.sin(f.t * (1.5 + p.speed.abs()) + i).abs();
      final front = math.sin(a) > 0 ? 1.0 : 0.6;
      dot.color = Color.lerp(
        AgentLight.cyan,
        AgentLight.violet,
        i / _particles,
      )!.withValues(alpha: (0.25 + 0.6 * e) * twinkle * front);
      canvas.drawCircle(pos, p.size * (0.8 + 0.5 * e) * front, dot);
    }
  }

  @override
  bool shouldRepaint(_RingsPainter old) => old.f != f || old.orbRadius != orbRadius;
}

/// Full-bleed cinematic backdrop: a translucent midnight veil with slowly
/// drifting cyan and violet nebulae, floating dust and a breathing aurora
/// horizon. Its intensity follows [presence].
class AgentAtmosphere extends StatefulWidget {
  const AgentAtmosphere({super.key, required this.presence, this.opaque = false});

  final AgentPresence presence;

  /// Paints a solid midnight base (full-screen route) instead of a veil
  /// over the blurred app.
  final bool opaque;

  @override
  State<AgentAtmosphere> createState() => _AgentAtmosphereState();
}

class _AgentAtmosphereState extends State<AgentAtmosphere> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_onTick);
  final _frame = _Frame();
  Duration _last = Duration.zero;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (context.reduceMotion) {
      _ticker.stop();
      _frame
        ..energy = _Targets.of(widget.presence, 0).energy
        ..tick();
    } else if (!_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    }
  }

  @override
  void didUpdateWidget(AgentAtmosphere old) {
    super.didUpdateWidget(old);
    if (context.reduceMotion) {
      _frame
        ..energy = _Targets.of(widget.presence, 0).energy
        ..tick();
    }
  }

  void _onTick(Duration elapsed) {
    final dt = ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _last = elapsed;
    final target = _Targets.of(widget.presence, 0.5).energy;
    _frame
      ..t += dt
      ..energy += (target - _frame.energy) * (1 - math.exp(-dt * 2))
      ..tick();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _frame.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(
      painter: _AtmospherePainter(_frame, opaque: widget.opaque),
      size: Size.infinite,
    ),
  );
}

class _AtmospherePainter extends CustomPainter {
  _AtmospherePainter(this.f, {required this.opaque}) : super(repaint: f);

  final _Frame f;
  final bool opaque;

  static const _dust = 64;
  static final _dustSeeds = List.generate(_dust, (i) {
    final r = math.Random(i * 104729 + 3);
    return (
      x: r.nextDouble(),
      y: r.nextDouble(),
      size: 0.4 + r.nextDouble() * 1.2,
      speed: 0.004 + r.nextDouble() * 0.012,
      phase: r.nextDouble() * 6,
    );
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final w = size.width;
    final h = size.height;
    final e = f.energy;
    final t = f.t;

    // Midnight veil: lets the blurred app glow through, deepest at the edges.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: opaque
              ? const [Color(0xFF050C22), AgentLight.midnight, AgentLight.midnightDeep]
              : [
                  const Color(0xFF050C22).withValues(alpha: 0.70),
                  AgentLight.midnight.withValues(alpha: 0.62),
                  AgentLight.midnightDeep.withValues(alpha: 0.88),
                ],
          stops: const [0, 0.5, 1],
        ).createShader(rect),
    );

    // Nebulae drifting on slow, out-of-phase orbits.
    void nebula(Offset center, double radius, Color color, double alpha) {
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [
              color.withValues(alpha: alpha),
              color.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: center, radius: radius)),
      );
    }

    nebula(
      Offset(w * (0.18 + 0.06 * math.sin(t * 0.11)), h * (0.16 + 0.04 * math.cos(t * 0.09))),
      w * 0.85,
      AgentLight.cyan,
      0.10 + 0.08 * e,
    );
    nebula(
      Offset(w * (0.86 + 0.05 * math.cos(t * 0.08)), h * (0.62 + 0.05 * math.sin(t * 0.07))),
      w * 0.95,
      AgentLight.violet,
      0.12 + 0.10 * e,
    );
    nebula(Offset(w * (0.5 + 0.1 * math.sin(t * 0.05)), h * 1.02), w * 0.9, AgentLight.indigo, 0.14 + 0.08 * e);

    // Floating dust.
    final dot = Paint();
    for (final d in _dustSeeds) {
      final y = (d.y - t * d.speed) % 1;
      final twinkle = 0.3 + 0.7 * (0.5 + 0.5 * math.sin(t * 1.3 + d.phase));
      dot.color = Colors.white.withValues(alpha: 0.05 + 0.22 * twinkle * (0.6 + 0.4 * e));
      canvas.drawCircle(Offset(d.x * w + 6 * math.sin(t * 0.3 + d.phase), y * h), d.size, dot);
    }

    // Aurora horizon: two soft ribbons breathing near the bottom.
    for (var k = 0; k < 2; k++) {
      final baseY = h * (0.80 + 0.035 * k);
      final amp = h * (0.012 + 0.018 * e) * (k == 0 ? 1 : 0.7);
      final path = Path()..moveTo(0, baseY);
      const steps = 40;
      for (var i = 1; i <= steps; i++) {
        final x = w * i / steps;
        final y = baseY + amp * math.sin(i / steps * 2 * math.pi * (1.2 + 0.3 * k) + t * (0.6 + 0.25 * k) + k * 2);
        path.lineTo(x, y);
      }
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 18
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14)
          ..shader = LinearGradient(
            colors: [
              AgentLight.cyan.withValues(alpha: 0),
              (k == 0 ? AgentLight.cyan : AgentLight.violet).withValues(alpha: 0.10 + 0.14 * e),
              AgentLight.violet.withValues(alpha: 0),
            ],
          ).createShader(rect),
      );
    }
  }

  @override
  bool shouldRepaint(_AtmospherePainter old) => old.f != f || old.opaque != opaque;
}
