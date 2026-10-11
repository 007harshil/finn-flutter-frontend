import 'package:flutter/material.dart';

import '../theme/finn_theme.dart';
import '../tokens/palette.dart';
import '../tokens/tokens.dart';
import 'tone.dart';

/// Rounded square tile holding an icon on a solid background.
class IconTile extends StatelessWidget {
  const IconTile({
    super.key,
    required this.icon,
    required this.background,
    required this.foreground,
    this.size = Dimens.iconTile,
    this.radius,
    this.iconSize,
    this.gradient,
  });

  final IconData icon;
  final Color background;
  final Color foreground;
  final double size;

  /// Defaults to 30% of [size].
  final double? radius;

  /// Defaults to 50% of [size].
  final double? iconSize;

  /// Paints over [background] when provided.
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          gradient: gradient,
          borderRadius: BorderRadius.circular(radius ?? size * 0.3),
        ),
        child: Center(child: Icon(icon, size: iconSize ?? size * 0.5, color: foreground)),
      ),
    );
  }
}

/// Category/goal icon on an accent gradient ([colorIndex]) or a solid [color].
class CategoryIconTile extends StatelessWidget {
  const CategoryIconTile({
    super.key,
    required this.icon,
    this.colorIndex,
    this.color,
    this.size = Dimens.iconTile,
    this.radius = Radii.lg,
    this.iconSize,
  }) : assert(colorIndex != null || color != null, 'Provide colorIndex or color');

  final IconData icon;

  /// Index into [AccentSwatches].
  final int? colorIndex;
  final Color? color;
  final double size;
  final double radius;
  final double? iconSize;

  @override
  Widget build(BuildContext context) {
    final index = colorIndex;
    final solid = color ?? AccentSwatches.solid(index ?? 0);
    return IconTile(
      icon: icon,
      background: solid,
      gradient: color == null && index != null ? AccentSwatches.gradient(index) : null,
      foreground: Colors.white,
      size: size,
      radius: radius,
      iconSize: iconSize,
    );
  }
}

/// Small rounded status label (e.g. "PAID", "OVERDUE").
class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    required this.color,
    this.icon,
    this.filled = false,
  });

  final String label;
  final Color color;
  final IconData? icon;

  /// Solid fill instead of a soft tint.
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fg = filled ? c.onSolid : color;
    final bg = filled ? color : color.withValues(alpha: c.isDark ? 0.18 : 0.12);
    return DecoratedBox(
      decoration: BoxDecoration(color: bg, borderRadius: Radii.rFull),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.x2, vertical: Space.x0_5 + 1),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 11, color: fg),
              const SizedBox(width: Space.x1),
            ],
            Flexible(
              child: Text(
                label.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.text.micro.copyWith(
                  color: fg,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.6,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Notification count badge; hidden at 0 and capped at "9+".
class CountBadge extends StatelessWidget {
  const CountBadge({
    super.key,
    required this.count,
    this.child,
    this.color,
    this.semanticsLabel,
  });

  final int count;

  /// When provided, the badge is overlaid at the top-right of [child].
  final Widget? child;

  /// Defaults to `colors.negative`.
  final Color? color;

  /// Defaults to "[count] new".
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final host = child;
    if (count <= 0) return host ?? const SizedBox.shrink();
    final c = context.colors;
    final badge = Semantics(
      label: semanticsLabel ?? '$count new',
      excludeSemantics: true,
      child: Container(
        constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
        padding: const EdgeInsets.symmetric(horizontal: Space.x1),
        decoration: BoxDecoration(
          color: color ?? c.negative,
          borderRadius: Radii.rFull,
          border: Border.all(color: c.surface, width: 2),
        ),
        alignment: Alignment.center,
        child: Text(
          count > 9 ? '9+' : '$count',
          style: context.text.micro.copyWith(
            color: c.onSolid,
            fontWeight: FontWeight.w900,
            fontSize: 9.5,
            height: 1.1,
          ),
        ),
      ),
    );
    if (host == null) return badge;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        host,
        Positioned(top: -4, right: -4, child: badge),
      ],
    );
  }
}
