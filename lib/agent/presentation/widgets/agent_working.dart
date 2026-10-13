import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../design_system/design_system.dart';
import 'agent_visualizer.dart';

/// What the agent is busy with while nothing waits on the user.
enum AgentWork {
  /// Reading the request and planning (waiting for the model).
  understanding,

  /// Checking the plan against the user's data and previewing changes.
  preparing,

  /// Writing approved changes.
  saving,

  /// Closing a review where nothing was approved.
  wrappingUp,

  /// Regenerating a declined change.
  regenerating,
}

/// Colours of each kind of work.
List<Color> agentWorkColors(AgentWork work) => switch (work) {
  AgentWork.understanding => const [AgentLight.cyan, AgentLight.indigo, AgentLight.violet],
  AgentWork.preparing => const [AgentLight.sky, AgentLight.indigo, AgentLight.cyan],
  AgentWork.saving => const [AgentLight.mint, AgentLight.cyan, AgentLight.sky],
  AgentWork.wrappingUp => const [Color(0xFF94A3B8), AgentLight.indigo, Color(0xFFCBD5E1)],
  AgentWork.regenerating => const [AgentLight.magenta, AgentLight.violet, Palette.amber400],
};

/// A clock for painters: one ticker, no widget rebuilds per frame. Reduced
/// motion holds one still frame.
mixin _PainterClock<T extends StatefulWidget> on State<T>, SingleTickerProviderStateMixin<T> {
  late final Ticker _ticker = createTicker((elapsed) => clock.value = elapsed.inMicroseconds / 1e6);
  final clock = ValueNotifier<double>(0.6);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (context.reduceMotion) {
      _ticker.stop();
      clock.value = 0.6;
    } else if (!_ticker.isActive) {
      _ticker.start();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    clock.dispose();
    super.dispose();
  }
}

/// The agent at work: the FiNN wordmark rides a living aurora drawn on a
/// canvas (ribbons of light with particles flowing through them), with a
/// line saying what is happening. Shown in the transcript whenever the
/// agent is busy and nothing waits on the user.
class FinnWorkingIndicator extends StatefulWidget {
  const FinnWorkingIndicator({super.key, required this.work, required this.label});

  final AgentWork work;
  final String label;

  @override
  State<FinnWorkingIndicator> createState() => _FinnWorkingIndicatorState();
}

class _FinnWorkingIndicatorState extends State<FinnWorkingIndicator>
    with SingleTickerProviderStateMixin, _PainterClock {
  @override
  Widget build(BuildContext context) {
    final t = context.text;
    final colors = agentWorkColors(widget.work);
    return Semantics(
      liveRegion: true,
      label: widget.label,
      excludeSemantics: true,
      child: StaggeredEntrance(
        child: Container(
          height: 168,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Radii.xxl),
            color: const Color(0xFF070E26).withValues(alpha: 0.72),
            border: Border.all(color: colors.first.withValues(alpha: 0.28)),
            boxShadow: [BoxShadow(color: colors[1].withValues(alpha: 0.22), blurRadius: 32, offset: const Offset(0, 10))],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              Positioned.fill(
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: _AuroraWordmarkPainter(clock, colors: colors, work: widget.work, font: t.title.fontFamily ?? DefaultTextStyle.of(context).style.fontFamily),
                  ),
                ),
              ),
              Positioned(
                left: Space.x4,
                right: Space.x4,
                bottom: Space.x3,
                child: AnimatedSwitcher(
                  duration: context.motion.fast,
                  child: Text(
                    widget.label,
                    key: ValueKey(widget.label),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.label.copyWith(color: Colors.white.withValues(alpha: 0.72), letterSpacing: 0.3),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AuroraWordmarkPainter extends CustomPainter {
  _AuroraWordmarkPainter(this.clock, {required this.colors, required this.work, this.font}) : super(repaint: clock);

  final ValueNotifier<double> clock;
  final List<Color> colors;
  final AgentWork work;

  /// The app's typeface, so the wordmark matches the rest of the text.
  final String? font;

  static const _word = 'FiNN';
  static const _particles = 34;

  @override
  void paint(Canvas canvas, Size size) {
    final t = clock.value;
    final w = size.width;
    final h = size.height;
    final mid = h * 0.42;

    // Speed and calm differ per kind of work.
    final (double speed, double amp) = switch (work) {
      AgentWork.understanding => (1.0, 0.16),
      AgentWork.preparing => (1.3, 0.13),
      AgentWork.saving => (1.9, 0.10),
      AgentWork.wrappingUp => (0.55, 0.07),
      AgentWork.regenerating => (1.5, 0.18),
    };

    // Soft glow behind the word.
    canvas.drawCircle(
      Offset(w / 2, mid),
      h * 0.62,
      Paint()
        ..shader = RadialGradient(
          colors: [colors[1].withValues(alpha: 0.30), colors[1].withValues(alpha: 0)],
        ).createShader(Rect.fromCircle(center: Offset(w / 2, mid), radius: h * 0.62)),
    );

    // Aurora ribbons: layered sine waves drifting at different speeds.
    double wave(double x, int i) {
      final k = 2 * math.pi / w;
      return mid +
          h * amp * math.sin(x * k * (1.2 + i * 0.35) + t * speed * (1.4 + i * 0.5) + i * 1.7) +
          h * amp * 0.45 * math.sin(x * k * (2.6 - i * 0.4) - t * speed * (0.9 + i * 0.3));
    }

    for (var i = 0; i < 3; i++) {
      final path = Path()..moveTo(0, wave(0, i));
      for (var x = 6.0; x <= w; x += 6) {
        path.lineTo(x, wave(x, i));
      }
      final color = colors[i % colors.length];
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 10 - i * 2.5
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8)
          ..color = color.withValues(alpha: 0.22),
      );
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..shader = LinearGradient(
            colors: [color.withValues(alpha: 0), color.withValues(alpha: 0.85), color.withValues(alpha: 0)],
          ).createShader(Offset.zero & size),
      );
    }

    // Particles flowing along the ribbons; saving pulls them to the centre.
    final dot = Paint();
    for (var p = 0; p < _particles; p++) {
      final seed = p * 0.6180339887;
      final lane = p % 3;
      final progress = (seed + t * speed * (0.06 + (p % 5) * 0.012)) % 1.0;
      var x = progress * w;
      if (work == AgentWork.saving) x = w / 2 + (x - w / 2) * (1 - 0.55 * math.sin(progress * math.pi));
      final y = wave(x, lane) + math.sin(t * 2.2 + p) * 4;
      final fade = math.sin(progress * math.pi);
      final r = 1.1 + (p % 4) * 0.45;
      dot.color = Color.lerp(colors[0], colors[2], (p % 7) / 6)!.withValues(alpha: 0.85 * fade);
      canvas.drawCircle(Offset(x, y), r, dot);
    }

    // The wordmark: each letter bobs on the wave, with a light sweep.
    final style = TextStyle(fontFamily: font, fontSize: h * 0.30, fontWeight: FontWeight.w900, letterSpacing: 1.5, height: 1);
    final letters = [
      for (final ch in _word.split(''))
        TextPainter(text: TextSpan(text: ch, style: style), textDirection: TextDirection.ltr)..layout(),
    ];
    final total = letters.fold<double>(0, (s, l) => s + l.width) + 2 * (letters.length - 1);
    var x = (w - total) / 2;
    final sweep = (t * 0.45 * speed) % 1.6 - 0.3;
    for (var i = 0; i < letters.length; i++) {
      final l = letters[i];
      final bob = math.sin(t * 2.4 * speed + i * 0.9) * h * 0.025;
      final top = mid - l.height / 2 + bob;
      final rect = Rect.fromLTWH(x, top, l.width, l.height);
      final shader = LinearGradient(
        colors: [colors[0], Colors.white, colors[2]],
        stops: [
          (sweep - 0.25).clamp(0.0, 1.0),
          sweep.clamp(0.0, 1.0),
          (sweep + 0.25).clamp(0.0, 1.0),
        ],
      ).createShader(Rect.fromLTWH((w - total) / 2, top, total, l.height));
      // Glow, then the letter itself.
      final glow = TextPainter(
        text: TextSpan(
          text: _word[i],
          style: style.copyWith(
            foreground: Paint()
              ..color = colors[1].withValues(alpha: 0.55)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      glow.paint(canvas, rect.topLeft);
      final fill = TextPainter(
        text: TextSpan(text: _word[i], style: style.copyWith(foreground: Paint()..shader = shader)),
        textDirection: TextDirection.ltr,
      )..layout();
      fill.paint(canvas, rect.topLeft);
      x += l.width + 2;
    }
  }

  @override
  bool shouldRepaint(_AuroraWordmarkPainter old) => old.work != work || old.colors != colors || old.font != font;
}

/// A compact orbit of light, drawn on a canvas: the loader on a single card
/// (saving it, or regenerating it).
class OrbitLoader extends StatefulWidget {
  const OrbitLoader({super.key, this.size = 44, required this.colors});

  final double size;
  final List<Color> colors;

  @override
  State<OrbitLoader> createState() => _OrbitLoaderState();
}

class _OrbitLoaderState extends State<OrbitLoader> with SingleTickerProviderStateMixin, _PainterClock {
  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: widget.size,
    child: RepaintBoundary(child: CustomPaint(painter: _OrbitPainter(clock, colors: widget.colors))),
  );
}

class _OrbitPainter extends CustomPainter {
  _OrbitPainter(this.clock, {required this.colors}) : super(repaint: clock);

  final ValueNotifier<double> clock;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    final t = clock.value;
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;

    // Breathing core.
    final breathe = 0.5 + 0.5 * math.sin(t * 3);
    canvas.drawCircle(
      c,
      r * (0.28 + 0.06 * breathe),
      Paint()
        ..shader = RadialGradient(colors: [Colors.white, colors[0], colors[0].withValues(alpha: 0)])
            .createShader(Rect.fromCircle(center: c, radius: r * 0.4)),
    );

    // Two counter-rotating arcs.
    final rect = Rect.fromCircle(center: c, radius: r * 0.78);
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = r * 0.12;
    final a1 = t * 3.2;
    arc.shader = SweepGradient(
      colors: [colors[0].withValues(alpha: 0), colors[0]],
      transform: GradientRotation(a1),
    ).createShader(rect);
    canvas.drawArc(rect, a1, math.pi * 1.25, false, arc);
    final inner = Rect.fromCircle(center: c, radius: r * 0.55);
    final a2 = -t * 4.4;
    arc
      ..strokeWidth = r * 0.08
      ..shader = SweepGradient(
        colors: [colors[1].withValues(alpha: 0), colors[1]],
        transform: GradientRotation(a2),
      ).createShader(inner);
    canvas.drawArc(inner, a2, math.pi * 0.9, false, arc);

    // Three satellites on the outer orbit.
    for (var i = 0; i < 3; i++) {
      final a = t * 2.1 + i * 2 * math.pi / 3;
      final p = c + Offset(math.cos(a), math.sin(a)) * r * 0.95;
      canvas.drawCircle(p, r * 0.07, Paint()..color = colors[2 % colors.length].withValues(alpha: 0.9));
    }
  }

  @override
  bool shouldRepaint(_OrbitPainter old) => old.colors != colors;
}
