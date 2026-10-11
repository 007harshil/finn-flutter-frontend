import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../motion/motion.dart';
import '../theme/finn_theme.dart';
import '../tokens/tokens.dart';

String _percent(double value) => '${(value * 100).round()}%';

/// Rounded linear progress bar that animates its fill.
class FinnProgressBar extends StatelessWidget {
  const FinnProgressBar({
    super.key,
    required this.value,
    this.color,
    this.trackColor,
    this.height = 8,
    this.semanticsLabel,
  });

  /// 0..1; values above 1 render full (the percent is still announced).
  final double value;

  /// Defaults to `colors.positive`.
  final Color? color;

  /// Defaults to `colors.surfaceMuted`.
  final Color? trackColor;
  final double height;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final target = value.isNaN ? 0.0 : value.clamp(0.0, 1.0);
    return Semantics(
      label: semanticsLabel,
      value: _percent(value.isNaN ? 0 : math.max(0, value)),
      child: RepaintBoundary(
        child: ClipRRect(
          borderRadius: Radii.rFull,
          child: SizedBox(
            height: height,
            width: double.infinity,
            child: ColoredBox(
              color: trackColor ?? c.surfaceMuted,
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: target),
                duration: context.motion.progress,
                curve: Curves2.standard,
                builder: (context, t, _) => FractionallySizedBox(
                  alignment: AlignmentDirectional.centerStart,
                  widthFactor: t,
                  heightFactor: 1,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: color ?? c.positive,
                      borderRadius: Radii.rFull,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Animated circular progress ring with an optional centre child.
class ProgressRing extends StatelessWidget {
  const ProgressRing({
    super.key,
    required this.value,
    this.size = 64,
    this.strokeWidth = 6,
    this.color,
    this.trackColor,
    this.child,
    this.semanticsLabel,
  });

  /// 0..1; values above 1 render a full ring.
  final double value;
  final double size;
  final double strokeWidth;

  /// Defaults to `colors.positive`.
  final Color? color;

  /// Defaults to `colors.surfaceMuted`.
  final Color? trackColor;
  final Widget? child;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final target = value.isNaN ? 0.0 : value.clamp(0.0, 1.0);
    final fg = color ?? c.positive;
    final bg = trackColor ?? c.surfaceMuted;
    return Semantics(
      label: semanticsLabel,
      value: _percent(value.isNaN ? 0 : math.max(0, value)),
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              child: RepaintBoundary(
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0, end: target),
                  duration: context.motion.progress,
                  curve: Curves2.standard,
                  builder: (context, t, _) => CustomPaint(
                    painter: _RingPainter(progress: t, color: fg, trackColor: bg, strokeWidth: strokeWidth),
                  ),
                ),
              ),
            ),
            if (child != null)
              Padding(
                padding: EdgeInsets.all(strokeWidth + 2),
                child: FittedBox(fit: BoxFit.scaleDown, child: child),
              ),
          ],
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.progress,
    required this.color,
    required this.trackColor,
    required this.strokeWidth,
  });

  final double progress;
  final Color color;
  final Color trackColor;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final arcRect = rect.deflate(strokeWidth / 2);
    final track = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawArc(arcRect, 0, math.pi * 2, false, track);
    if (progress <= 0) return;
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = progress >= 1 ? StrokeCap.butt : StrokeCap.round;
    canvas.drawArc(arcRect, -math.pi / 2, math.pi * 2 * progress, false, fill);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress ||
      old.color != color ||
      old.trackColor != trackColor ||
      old.strokeWidth != strokeWidth;
}
