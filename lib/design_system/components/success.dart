import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../motion/motion.dart';
import '../theme/finn_theme.dart';
import '../tokens/tokens.dart';
import 'tone.dart';

/// Animated emerald checkmark (circle scales in, check draws on).
class SuccessCheck extends StatefulWidget {
  const SuccessCheck({super.key, this.size = 72, this.color, this.onCompleted});

  final double size;

  /// Defaults to `colors.positive`.
  final Color? color;
  final VoidCallback? onCompleted;

  @override
  State<SuccessCheck> createState() => _SuccessCheckState();
}

class _SuccessCheckState extends State<SuccessCheck> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (context.reduceMotion) {
      _controller.value = 1;
      final done = widget.onCompleted;
      if (done != null) WidgetsBinding.instance.addPostFrameCallback((_) => done());
    } else {
      _controller.forward().whenCompleteOrCancel(() {
        if (mounted && _controller.isCompleted) widget.onCompleted?.call();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = widget.color ?? c.positive;
    return Semantics(
      label: 'Success',
      image: true,
      child: RepaintBoundary(
        child: SizedBox.square(
          dimension: widget.size,
          child: CustomPaint(
            painter: _CheckPainter(
              animation: _controller,
              color: color,
              halo: color.withValues(alpha: 0.16),
              checkColor: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

class _CheckPainter extends CustomPainter {
  _CheckPainter({
    required this.animation,
    required this.color,
    required this.halo,
    required this.checkColor,
  }) : super(repaint: animation);

  final Animation<double> animation;
  final Color color;
  final Color halo;
  final Color checkColor;

  static const Interval _circle = Interval(0, 0.5, curve: Curves.easeOutBack);
  static const Interval _check = Interval(0.35, 1, curve: Curves.easeOutCubic);

  @override
  void paint(Canvas canvas, Size size) {
    final t = animation.value;
    final circleT = _circle.transform(t);
    final checkT = _check.transform(t);
    final center = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    canvas.drawCircle(center, r * circleT, Paint()..color = halo);
    canvas.drawCircle(center, r * 0.76 * circleT, Paint()..color = color);
    if (checkT <= 0) return;
    final w = size.width;
    final h = size.height;
    final path = Path()
      ..moveTo(w * 0.34, h * 0.52)
      ..lineTo(w * 0.45, h * 0.63)
      ..lineTo(w * 0.67, h * 0.40);
    final paint = Paint()
      ..color = checkColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.shortestSide * 0.07
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final metric in path.computeMetrics()) {
      canvas.drawPath(metric.extractPath(0, metric.length * checkT), paint);
    }
  }

  @override
  bool shouldRepaint(_CheckPainter old) =>
      old.animation != animation || old.color != color || old.halo != halo || old.checkColor != checkColor;
}

/// Shows a brief centred success overlay; completes once it is removed.
Future<void> showSuccessOverlay(
  BuildContext context, {
  required String title,
  String? subtitle,
  Duration duration = const Duration(milliseconds: 1200),
}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return Future<void>.value();
  final theme = Theme.of(context);
  final reduce = context.reduceMotion;
  final view = View.maybeOf(context);
  final direction = Directionality.maybeOf(context) ?? TextDirection.ltr;
  final completer = Completer<void>();

  HapticFeedback.lightImpact();
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => Theme(
      data: theme,
      child: MotionScope(
        reduceMotion: reduce,
        child: _SuccessOverlay(
          title: title,
          subtitle: subtitle,
          duration: duration,
          onDone: () {
            if (entry.mounted) entry.remove();
            if (!completer.isCompleted) completer.complete();
          },
        ),
      ),
    ),
  );
  overlay.insert(entry);
  if (view != null) {
    unawaited(SemanticsService.sendAnnouncement(view, subtitle == null ? title : '$title. $subtitle', direction));
  }
  return completer.future;
}

class _SuccessOverlay extends StatefulWidget {
  const _SuccessOverlay({
    required this.title,
    required this.subtitle,
    required this.duration,
    required this.onDone,
  });

  final String title;
  final String? subtitle;
  final Duration duration;
  final VoidCallback onDone;

  @override
  State<_SuccessOverlay> createState() => _SuccessOverlayState();
}

class _SuccessOverlayState extends State<_SuccessOverlay> with SingleTickerProviderStateMixin {
  late final AnimationController _fade =
      AnimationController(vsync: this, duration: Durations2.normal);
  Timer? _timer;
  bool _started = false;
  bool _closing = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (context.reduceMotion) {
      _fade.value = 1;
    } else {
      _fade.forward();
    }
    _timer = Timer(widget.duration, _close);
  }

  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    _timer?.cancel();
    if (!context.reduceMotion) await _fade.reverse();
    widget.onDone();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final sub = widget.subtitle;
    return FadeTransition(
      opacity: _fade,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _close,
        child: ColoredBox(
          color: c.scrim.withValues(alpha: c.scrim.a * 0.5),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(Space.x8),
              child: Material(
                type: MaterialType.transparency,
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 320),
                  padding: const EdgeInsets.symmetric(horizontal: Space.x6, vertical: Space.x8),
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: Radii.rXxxl,
                    border: Border.all(color: FinnTone.positive.color(c).withValues(alpha: 0.25), width: 2),
                    boxShadow: Elevation.xl,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SuccessCheck(size: 88),
                      const SizedBox(height: Space.x4),
                      Text(
                        widget.title,
                        textAlign: TextAlign.center,
                        style: t.title.copyWith(fontWeight: FontWeight.w900),
                      ),
                      if (sub != null) ...[
                        const SizedBox(height: Space.x1),
                        Text(sub, textAlign: TextAlign.center, style: t.caption),
                      ],
                    ],
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
