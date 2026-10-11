import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../motion/motion.dart';
import '../theme/finn_theme.dart';
import '../tokens/tokens.dart';
import 'buttons.dart';

/// Dashed-border empty state with icon, title, message and optional action.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
    this.actionIcon,
  });

  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final IconData? actionIcon;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final msg = message;
    final label = actionLabel;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: context.motion.slow,
      curve: Curves2.emphasized,
      builder: (context, v, child) => Opacity(
        opacity: v.clamp(0.0, 1.0),
        child: Transform.scale(scale: 0.96 + 0.04 * v, child: child),
      ),
      child: CustomPaint(
        painter: _DashedBorderPainter(color: c.borderStrong, radius: Radii.xxxl),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.x6, vertical: Space.x8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ExcludeSemantics(
                child: DecoratedBox(
                  decoration: BoxDecoration(color: c.surfaceMuted, shape: BoxShape.circle),
                  child: SizedBox.square(
                    dimension: 64,
                    child: Icon(icon, size: 28, color: c.textTertiary),
                  ),
                ),
              ),
              const SizedBox(height: Space.x4),
              Semantics(
                header: true,
                child: Text(
                  title.toUpperCase(),
                  textAlign: TextAlign.center,
                  style: t.sectionTitle.copyWith(fontSize: 14, letterSpacing: 0.8),
                ),
              ),
              if (msg != null) ...[
                const SizedBox(height: Space.x1_5),
                Text(msg, textAlign: TextAlign.center, style: t.caption),
              ],
              if (label != null && onAction != null) ...[
                const SizedBox(height: Space.x5),
                FinnButton(
                  label: label,
                  icon: actionIcon,
                  onPressed: onAction,
                  size: FinnButtonSize.sm,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({required this.color, required this.radius});

  final Color color;
  final double radius;
  static const double _stroke = 2;
  static const double _dash = 6;
  static const double _gap = 5;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(_stroke / 2);
    final path = Path()..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)));
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke
      ..strokeCap = StrokeCap.round;
    final dashed = Path();
    for (final ui.PathMetric metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        dashed.addPath(metric.extractPath(d, d + _dash), Offset.zero);
        d += _dash + _gap;
      }
    }
    canvas.drawPath(dashed, paint);
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) => old.color != color || old.radius != radius;
}

/// Error placeholder with a "Try again" action.
class ErrorState extends StatelessWidget {
  const ErrorState({
    super.key,
    this.title = 'Something went wrong',
    this.message,
    this.onRetry,
    this.retryLabel = 'Try again',
  });

  final String title;
  final String? message;
  final VoidCallback? onRetry;
  final String retryLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final msg = message;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.x6, vertical: Space.x8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ExcludeSemantics(
            child: DecoratedBox(
              decoration: BoxDecoration(color: c.negativeSoft, shape: BoxShape.circle),
              child: SizedBox.square(
                dimension: 64,
                child: Icon(LucideIcons.circleAlert, size: 28, color: c.negative),
              ),
            ),
          ),
          const SizedBox(height: Space.x4),
          Semantics(
            header: true,
            child: Text(title, textAlign: TextAlign.center, style: t.title),
          ),
          if (msg != null) ...[
            const SizedBox(height: Space.x1_5),
            Text(msg, textAlign: TextAlign.center, style: t.caption),
          ],
          if (onRetry != null) ...[
            const SizedBox(height: Space.x5),
            FinnButton(
              label: retryLabel,
              icon: LucideIcons.refreshCw,
              onPressed: onRetry,
              variant: FinnButtonVariant.outline,
              size: FinnButtonSize.sm,
            ),
          ],
        ],
      ),
    );
  }
}

/// Provides one shared pulse animation to every [SkeletonBox] below it.
class SkeletonPulse extends StatefulWidget {
  const SkeletonPulse({super.key, required this.child});

  final Widget child;

  @override
  State<SkeletonPulse> createState() => _SkeletonPulseState();
}

class _SkeletonPulseState extends State<SkeletonPulse> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  );
  late final Animation<double> _opacity = Tween<double>(begin: 1, end: 0.55)
      .animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (context.reduceMotion) {
      _controller
        ..stop()
        ..value = 0;
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _PulseScope(opacity: _opacity, child: widget.child);
}

class _PulseScope extends InheritedWidget {
  const _PulseScope({required this.opacity, required super.child});

  final Animation<double> opacity;

  static Animation<double>? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_PulseScope>()?.opacity;

  @override
  bool updateShouldNotify(_PulseScope oldWidget) => oldWidget.opacity != opacity;
}

/// Pulsing placeholder block. Shares the nearest [SkeletonPulse] animation.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({super.key, this.width, required this.height, this.radius = Radii.md});

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final box = _SkeletonFade(
      child: SizedBox(
        width: width,
        height: height,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: context.colors.skeleton,
            borderRadius: BorderRadius.circular(radius),
          ),
        ),
      ),
    );
    if (_PulseScope.maybeOf(context) != null) return box;
    return SkeletonPulse(child: box);
  }
}

class _SkeletonFade extends StatelessWidget {
  const _SkeletonFade({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final opacity = _PulseScope.maybeOf(context);
    final excluded = ExcludeSemantics(child: child);
    if (opacity == null) return excluded;
    return FadeTransition(opacity: opacity, child: excluded);
  }
}

/// Placeholder list shaped like transaction rows (icon, two lines, amount).
class ListSkeleton extends StatelessWidget {
  const ListSkeleton({
    super.key,
    this.count = 5,
    this.rowHeight = 64,
    this.padding = const EdgeInsets.symmetric(horizontal: Space.x4),
  });

  final int count;

  /// Match the real row height to avoid layout shift.
  final double rowHeight;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading',
      child: SkeletonPulse(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < count; i++)
              SizedBox(
                height: rowHeight,
                child: Padding(
                  padding: padding,
                  child: Row(
                    children: [
                      const SkeletonBox(width: Dimens.iconTile, height: Dimens.iconTile, radius: Radii.lg),
                      const SizedBox(width: Space.x3),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SkeletonBox(width: i.isEven ? 140 : 110, height: 12),
                            const SizedBox(height: Space.x2),
                            SkeletonBox(width: i.isEven ? 84 : 100, height: 10),
                          ],
                        ),
                      ),
                      const SizedBox(width: Space.x3),
                      SkeletonBox(width: i.isEven ? 64 : 52, height: 14),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Card-shaped placeholder of a fixed [height].
class CardSkeleton extends StatelessWidget {
  const CardSkeleton({super.key, this.height = 120, this.radius = Radii.xl});

  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Loading',
        child: SkeletonBox(width: double.infinity, height: height, radius: radius),
      );
}
