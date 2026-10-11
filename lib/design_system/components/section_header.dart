import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/finn_theme.dart';
import '../tokens/tokens.dart';
import 'tiles.dart';

/// Section heading: coloured icon tile, uppercase title, optional action.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.icon,
    required this.title,
    required this.tileColor,
    this.subtitle,
    this.trailing,
    this.onAction,
    this.actionLabel = 'See all',
    this.count,
  });

  final IconData icon;
  final String title;
  final Color tileColor;
  final String? subtitle;

  /// Number shown in a small badge after the title.
  final int? count;

  /// Replaces the action button when provided.
  final Widget? trailing;
  final VoidCallback? onAction;
  final String actionLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final sub = subtitle;
    Widget? end = trailing;
    if (end == null && onAction != null) {
      end = TextButton(
        onPressed: onAction,
        style: TextButton.styleFrom(
          foregroundColor: c.textSecondary,
          minimumSize: const Size(Dimens.minTouch, Dimens.minTouch),
          padding: const EdgeInsets.symmetric(horizontal: Space.x2),
          textStyle: t.label.copyWith(fontWeight: FontWeight.w800),
          shape: const RoundedRectangleBorder(borderRadius: Radii.rMd),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(actionLabel),
            const SizedBox(width: Space.x0_5),
            const Icon(LucideIcons.chevronRight, size: 14),
          ],
        ),
      );
    }
    return Row(
      children: [
        IconTile(icon: icon, background: tileColor, foreground: Colors.white, size: 28, radius: Radii.md, iconSize: 15),
        const SizedBox(width: Space.x2_5),
        Expanded(
          child: Semantics(
            header: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        title.toUpperCase(),
                        style: t.sectionTitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (count != null) ...[
                      const SizedBox(width: Space.x1_5),
                      Semantics(
                        label: '$count items',
                        excludeSemantics: true,
                        child: Container(
                          constraints: const BoxConstraints(minWidth: 20),
                          padding: const EdgeInsets.symmetric(horizontal: Space.x1_5, vertical: 1),
                          decoration: BoxDecoration(color: tileColor, borderRadius: Radii.rFull),
                          child: Text(
                            '$count',
                            textAlign: TextAlign.center,
                            style: t.micro.copyWith(color: Colors.white, fontWeight: FontWeight.w900),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (sub != null) ...[
                  const SizedBox(height: Space.x0_5),
                  Text(sub, style: t.caption, maxLines: 2, overflow: TextOverflow.ellipsis),
                ],
              ],
            ),
          ),
        ),
        if (end != null) ...[const SizedBox(width: Space.x2), end],
      ],
    );
  }
}
