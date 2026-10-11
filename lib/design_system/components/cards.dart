import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../motion/motion.dart';
import '../theme/finn_theme.dart';
import '../tokens/tokens.dart';

/// Scales its child down slightly while pressed (press feedback).
class PressableScale extends StatefulWidget {
  const PressableScale({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scale = 0.97,
    this.haptic = false,
    this.enabled = true,
    this.semanticLabel,
  });

  final Widget child;

  /// When set, this widget handles the tap itself (with button semantics).
  /// Leave null when [child] already handles taps (e.g. an InkWell).
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;

  /// Fire `HapticFeedback.selectionClick` on tap.
  final bool haptic;

  /// Whether press feedback is shown.
  final bool enabled;
  final String? semanticLabel;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _pressed = false;

  void _set(bool value) {
    if (_pressed != value && mounted) setState(() => _pressed = value);
  }

  void _handleTap() {
    if (widget.haptic) HapticFeedback.selectionClick();
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = context.reduceMotion;
    final active = widget.enabled && !reduced;
    Widget child = AnimatedScale(
      scale: active && _pressed ? widget.scale : 1,
      duration: context.motion.fast,
      curve: Curves2.press,
      child: widget.child,
    );
    if (widget.onTap != null || widget.onLongPress != null) {
      child = Semantics(
        button: true,
        label: widget.semanticLabel,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.enabled && widget.onTap != null ? _handleTap : null,
          onLongPress: widget.enabled ? widget.onLongPress : null,
          child: child,
        ),
      );
    }
    if (!active) return child;
    return Listener(
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: child,
    );
  }
}

/// Visual style of a [FinnCard].
enum FinnCardVariant { surface, muted, outlined, gradient }

/// Rounded card surface with optional tap handling and press feedback.
class FinnCard extends StatelessWidget {
  const FinnCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(Space.x4),
    this.onTap,
    this.onLongPress,
    this.variant = FinnCardVariant.surface,
    this.gradient,
    this.radius = Radii.xl,
    this.shadow,
    this.border,
    this.haptic = false,
    this.semanticLabel,
  }) : assert(
          variant != FinnCardVariant.gradient || gradient != null,
          'gradient variant requires a gradient',
        );

  /// Card filled with [gradient] (hero cards).
  const FinnCard.gradient({
    super.key,
    required this.child,
    required Gradient this.gradient,
    this.padding = const EdgeInsets.all(Space.x4),
    this.onTap,
    this.onLongPress,
    this.radius = Radii.xl,
    this.shadow,
    this.border,
    this.haptic = false,
    this.semanticLabel,
  }) : variant = FinnCardVariant.gradient;

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final FinnCardVariant variant;
  final Gradient? gradient;
  final double radius;

  /// Defaults to [Elevation.md] in light mode and none in dark mode.
  final List<BoxShadow>? shadow;

  /// Overrides the variant's border.
  final BorderSide? border;
  final bool haptic;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final br = BorderRadius.circular(radius);
    final (Color? bg, BorderSide side) = switch (variant) {
      FinnCardVariant.surface => (c.surface, BorderSide(color: c.border)),
      FinnCardVariant.muted => (c.surfaceMuted, BorderSide.none),
      FinnCardVariant.outlined => (null, BorderSide(color: c.border, width: 1.5)),
      FinnCardVariant.gradient => (null, BorderSide.none),
    };
    final effectiveSide = border ?? side;
    final defaultShadow = c.isDark ||
            variant == FinnCardVariant.muted ||
            variant == FinnCardVariant.outlined
        ? Elevation.none
        : Elevation.md;
    final interactive = onTap != null || onLongPress != null;

    Widget content = Padding(padding: padding, child: child);
    if (interactive) {
      content = Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: br,
          onTap: onTap == null
              ? null
              : () {
                  if (haptic) HapticFeedback.selectionClick();
                  onTap!();
                },
          onLongPress: onLongPress,
          child: content,
        ),
      );
    }

    Widget card = DecoratedBox(
      decoration: BoxDecoration(
        color: bg,
        gradient: variant == FinnCardVariant.gradient ? gradient : null,
        borderRadius: br,
        border: effectiveSide == BorderSide.none ? null : Border.fromBorderSide(effectiveSide),
        boxShadow: shadow ?? defaultShadow,
      ),
      child: ClipRRect(borderRadius: br, child: content),
    );
    if (semanticLabel != null) {
      card = Semantics(label: semanticLabel, button: interactive, child: card);
    }
    if (!interactive) return card;
    return PressableScale(scale: 0.98, child: card);
  }
}

/// Gradient hero card with an optional large faint watermark icon.
class GradientHeroCard extends StatelessWidget {
  const GradientHeroCard({
    super.key,
    required this.child,
    this.gradient,
    this.watermark,
    this.padding = const EdgeInsets.all(Space.x5),
    this.onTap,
    this.radius = Radii.xxxl,
    this.semanticLabel,
  });

  final Widget child;

  /// Defaults to `colors.heroGradient`.
  final Gradient? gradient;
  final IconData? watermark;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final double radius;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final g = gradient ?? c.heroGradient;
    final tint = g.colors.isNotEmpty ? g.colors.first : c.heroStart;
    return FinnCard.gradient(
      gradient: g,
      padding: EdgeInsets.zero,
      radius: radius,
      onTap: onTap,
      semanticLabel: semanticLabel,
      shadow: c.isDark ? Elevation.none : Elevation.tinted(tint, alpha: 0.35),
      child: Stack(
        children: [
          if (watermark != null)
            Positioned(
              right: -18,
              bottom: -22,
              child: ExcludeSemantics(
                child: Icon(
                  watermark,
                  size: 132,
                  color: Colors.white.withValues(alpha: 0.08),
                ),
              ),
            ),
          Padding(
            padding: padding,
            child: IconTheme.merge(
              data: const IconThemeData(color: Colors.white),
              child: DefaultTextStyle.merge(
                style: const TextStyle(color: Colors.white),
                child: child,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
