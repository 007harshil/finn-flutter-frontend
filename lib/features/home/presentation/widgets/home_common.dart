import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../design_system/design_system.dart';

/// Dashboard section: header + body with consistent spacing.
class HomeSection extends StatelessWidget {
  const HomeSection({
    super.key,
    required this.icon,
    required this.title,
    required this.tileColor,
    required this.child,
    this.subtitle,
    this.onAction,
    this.actionLabel = 'See all',
    this.count,
  });

  final IconData icon;
  final String title;
  final Color tileColor;
  final String? subtitle;
  final int? count;
  final VoidCallback? onAction;
  final String actionLabel;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          icon: icon,
          title: title,
          tileColor: tileColor,
          subtitle: subtitle,
          onAction: onAction,
          actionLabel: actionLabel,
          count: count,
        ),
        const SizedBox(height: Space.x3),
        child,
      ],
    );
  }
}

/// A tappable list row inside a card (≥ 56 dp tall).
class HomeRow extends StatelessWidget {
  const HomeRow({
    super.key,
    required this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.semanticLabel,
    this.showChevron = false,
    this.subtitleColor,
  });

  final Widget leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final String? semanticLabel;
  final bool showChevron;
  final Color? subtitleColor;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final sub = subtitle;
    final end = trailing;
    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.x3 + 2, vertical: Space.x2_5),
        child: Row(
          children: [
            leading,
            const SizedBox(width: Space.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: t.bodyStrong, maxLines: 1, overflow: TextOverflow.ellipsis),
                  if (sub != null) ...[
                    const SizedBox(height: Space.x0_5),
                    Text(
                      sub,
                      style: t.caption.copyWith(color: subtitleColor),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            if (end != null) ...[const SizedBox(width: Space.x2), end],
            if (showChevron) ...[
              const SizedBox(width: Space.x1),
              Icon(LucideIcons.chevronRight, size: 16, color: c.textTertiary),
            ],
          ],
        ),
      ),
    );
    if (onTap == null) return MergeSemantics(child: row);
    return Semantics(
      button: true,
      label: semanticLabel,
      child: InkWell(onTap: onTap, child: row),
    );
  }
}

/// Card with rows separated by hairlines.
class HomeListCard extends StatelessWidget {
  const HomeListCard({super.key, required this.children, this.footer});

  final List<Widget> children;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final f = footer;
    return FinnCard(
      padding: EdgeInsets.zero,
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const FinnDivider(indent: Space.x4, endIndent: Space.x4),
              children[i],
            ],
            if (f != null) ...[const FinnDivider(), f],
          ],
        ),
      ),
    );
  }
}

/// Small calm message card used for empty sections.
class HomeNoteCard extends StatelessWidget {
  const HomeNoteCard({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.color,
    this.actionLabel,
    this.onAction,
    this.actionIcon,
  });

  final IconData icon;
  final String title;
  final String message;
  final Color? color;
  final String? actionLabel;
  final VoidCallback? onAction;
  final IconData? actionIcon;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final accent = color ?? c.textSecondary;
    final label = actionLabel;
    return FinnCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconTile(
                icon: icon,
                background: accent.withValues(alpha: c.isDark ? 0.2 : 0.12),
                foreground: accent,
                size: 36,
                radius: Radii.lg,
                iconSize: 18,
              ),
              const SizedBox(width: Space.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: t.bodyStrong),
                    const SizedBox(height: Space.x0_5),
                    Text(message, style: t.caption),
                  ],
                ),
              ),
            ],
          ),
          if (label != null && onAction != null) ...[
            const SizedBox(height: Space.x3),
            FinnButton(
              label: label,
              icon: actionIcon,
              onPressed: onAction,
              variant: FinnButtonVariant.outline,
              size: FinnButtonSize.sm,
              expand: true,
            ),
          ],
        ],
      ),
    );
  }
}

/// Footer link row inside a [HomeListCard].
class HomeCardLink extends StatelessWidget {
  const HomeCardLink({super.key, required this.label, required this.onTap, this.icon = LucideIcons.arrowRight});

  final String label;
  final VoidCallback onTap;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: Dimens.minTouch),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.x4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: context.text.label.copyWith(color: c.textPrimary, fontWeight: FontWeight.w800),
                ),
                const SizedBox(width: Space.x1_5),
                Icon(icon, size: 14, color: c.textPrimary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "in 3 days" / "today" / "2 days overdue".
String relativeDue(int days) {
  if (days < -1) return '${-days} days overdue';
  if (days == -1) return '1 day overdue';
  if (days == 0) return 'Due today';
  if (days == 1) return 'Due tomorrow';
  return 'In $days days';
}
