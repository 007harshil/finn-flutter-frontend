import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../motion/motion.dart';
import '../theme/finn_theme.dart';
import '../tokens/tokens.dart';
import 'tone.dart';

/// Small rounded chip for quick filters, sort pickers and status shortcuts.
/// Tinted with [color] when given; solid when [selected].
class FinnTapChip extends StatelessWidget {
  const FinnTapChip({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.color,
    this.selected = false,
    this.trailing,
    this.semantics,
    this.height = 30,
  });

  final String label;
  final IconData? icon;
  final IconData? trailing;
  final Color? color;
  final bool selected;
  final VoidCallback onTap;
  final String? semantics;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tone = color ?? c.textSecondary;
    final fg = selected ? c.onSolid : tone;
    final bg = selected
        ? tone
        : (color == null ? c.surfaceMuted : tone.withValues(alpha: c.isDark ? 0.18 : 0.1));
    return Semantics(
      button: true,
      selected: selected,
      label: semantics ?? label,
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: Radii.rFull,
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: AnimatedContainer(
            duration: context.motion.fast,
            height: height,
            padding: const EdgeInsets.symmetric(horizontal: Space.x2_5),
            decoration: BoxDecoration(color: bg, borderRadius: Radii.rFull),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null || selected) ...[
                  Icon(selected && trailing == null ? LucideIcons.check : icon, size: 13, color: fg),
                  const SizedBox(width: Space.x1),
                ],
                Text(label, style: context.text.label.copyWith(color: fg, fontWeight: FontWeight.w800)),
                if (trailing != null) ...[const SizedBox(width: 3), Icon(trailing, size: 12, color: fg)],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
