import 'package:flutter/material.dart';

import '../foundation/ui_colors.dart';
import '../foundation/ui_motion.dart';
import '../foundation/ui_space.dart';

/// Flat rounded panel on the page background. No border, no shadow:
/// surface contrast alone lifts it.
class UiPanel extends StatelessWidget {
  const UiPanel({super.key, required this.child, this.padding = EdgeInsets.zero});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(color: UiColors.of(context).surface, borderRadius: UiRadius.panel),
      child: ClipRRect(
        borderRadius: UiRadius.panel,
        child: Material(
          type: MaterialType.transparency,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// Hairline between rows of a [UiPanel], inset to the text.
class UiRule extends StatelessWidget {
  const UiRule({super.key, this.indent = UiSpace.lg});

  final double indent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsetsDirectional.only(start: indent, end: UiSpace.lg),
      child: Container(height: 1, color: UiColors.of(context).hairline),
    );
  }
}

/// Grey block standing in for content while it loads (no layout shift).
class UiPlaceholder extends StatelessWidget {
  const UiPlaceholder({super.key, this.width = double.infinity, required this.height, this.radius = UiRadius.chip});

  final double width;
  final double height;
  final BorderRadius radius;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(color: UiColors.of(context).muted, borderRadius: radius),
      ),
    );
  }
}

/// One soft fade-and-rise when content first appears, staggered by
/// [index]. Renders the child as-is under reduced motion.
class UiReveal extends StatelessWidget {
  const UiReveal({super.key, required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final m = UiMotion.of(context);
    if (m.reduced) return child;
    final start = (index * 0.08).clamp(0.0, 0.5);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: m.enter + Duration(milliseconds: index * 50),
      curve: Interval(start, 1, curve: Curves.easeOutCubic),
      builder: (context, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(0, 10 * (1 - v)), child: child),
      ),
      child: child,
    );
  }
}

/// Centres content and caps its width on tablets.
class UiColumnWidth extends StatelessWidget {
  const UiColumnWidth({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: UiSpace.maxWidth),
        child: child,
      ),
    );
  }
}
