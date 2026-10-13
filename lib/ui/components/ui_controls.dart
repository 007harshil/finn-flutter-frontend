import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../foundation/ui_colors.dart';
import '../foundation/ui_space.dart';
import '../foundation/ui_type.dart';

/// Bare icon control with a 44 dp target; [tooltip] doubles as its label.
class UiIconButton extends StatelessWidget {
  const UiIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.badge = 0,
    this.haptic = false,
    this.color,
    this.size = 22,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  /// Count shown as a small pill on the icon; 0 hides it.
  final int badge;
  final bool haptic;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = UiColors.of(context);
    final t = UiType.of(context);
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        excludeSemantics: true,
        child: InkResponse(
          radius: 22,
          onTap: () {
            if (haptic) HapticFeedback.selectionClick();
            onPressed();
          },
          child: SizedBox.square(
            dimension: UiSpace.touch,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                Icon(icon, size: size, color: color ?? c.ink),
                if (badge > 0)
                  Positioned(
                    top: 5,
                    right: 3,
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 17),
                      height: 17,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: c.negative,
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(color: c.page, width: 1.5),
                      ),
                      child: Text(
                        badge > 9 ? '9+' : '$badge',
                        style: t.small.copyWith(color: c.page, fontSize: 10, fontWeight: FontWeight.w700, height: 1),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Text-only action with a 44 dp target.
class UiTextButton extends StatelessWidget {
  const UiTextButton({super.key, required this.label, required this.onTap, this.semanticLabel});

  final String label;
  final VoidCallback onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final t = UiType.of(context);
    return Semantics(
      button: true,
      label: semanticLabel,
      excludeSemantics: semanticLabel != null,
      child: InkWell(
        onTap: onTap,
        borderRadius: UiRadius.control,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: UiSpace.touch, minWidth: UiSpace.touch),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: UiSpace.sm),
            child: Center(
              widthFactor: 1,
              child: Text(label, style: t.label.copyWith(fontWeight: FontWeight.w600)),
            ),
          ),
        ),
      ),
    );
  }
}

/// Solid ink button: the single primary action on a screen.
class UiPrimaryButton extends StatelessWidget {
  const UiPrimaryButton({super.key, required this.label, required this.onPressed, this.icon});

  final String label;
  final VoidCallback onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = UiColors.of(context);
    final t = UiType.of(context);
    final ic = icon;
    return Semantics(
      button: true,
      child: Material(
        color: c.ink,
        borderRadius: UiRadius.control,
        child: InkWell(
          onTap: onPressed,
          borderRadius: UiRadius.control,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: UiSpace.lg),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (ic != null) ...[Icon(ic, size: 18, color: c.page), const SizedBox(width: UiSpace.sm)],
                  Flexible(
                    child: Text(
                      label,
                      style: t.body.copyWith(color: c.page, fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Section title with an optional quiet value or text action on the right.
class UiSectionTitle extends StatelessWidget {
  const UiSectionTitle({super.key, required this.title, this.trailing, this.action, this.onAction});

  final String title;

  /// Quiet text after the title, e.g. a total.
  final Widget? trailing;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final t = UiType.of(context);
    final act = action;
    final tail = trailing;
    return Padding(
      padding: const EdgeInsets.only(left: UiSpace.xs, bottom: UiSpace.xs),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: UiSpace.touch),
        child: Row(
          children: [
            Expanded(
              child: Semantics(
                header: true,
                child: Text(title, style: t.section, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ),
            ?tail,
            if (act != null && onAction != null) UiTextButton(label: act, onTap: onAction!),
          ],
        ),
      ),
    );
  }
}

/// A row inside a [UiPanel]: optional leading mark, title (+ optional quiet
/// subtitle), trailing value, chevron. At least 60 dp tall. Without
/// [onTap] it is a plain read-only row (no chevron, no ink).
class UiListRow extends StatelessWidget {
  const UiListRow({
    super.key,
    required this.title,
    required this.onTap,
    this.onLongPress,
    this.leading,
    this.subtitle,
    this.subtitleColor,
    this.trailing,
    this.semanticLabel,
    this.chevron = true,
  });

  final String title;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Widget? leading;
  final String? subtitle;
  final Color? subtitleColor;
  final Widget? trailing;
  final String? semanticLabel;

  /// Shows the trailing chevron on tappable rows.
  final bool chevron;

  @override
  Widget build(BuildContext context) {
    final c = UiColors.of(context);
    final t = UiType.of(context);
    final lead = leading;
    final sub = subtitle;
    final end = trailing;
    final tappable = onTap != null;
    final content = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 60),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: UiSpace.lg, vertical: 10),
        child: Row(
          children: [
            if (lead != null) ...[lead, const SizedBox(width: UiSpace.md)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: t.body, maxLines: 1, overflow: TextOverflow.ellipsis),
                  if (sub != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      sub,
                      style: t.small.copyWith(color: subtitleColor),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            if (end != null) ...[const SizedBox(width: UiSpace.md), end],
            if (tappable && chevron) ...[
              const SizedBox(width: 6),
              ExcludeSemantics(child: Icon(LucideIcons.chevronRight, size: 16, color: c.inkFaint)),
            ],
          ],
        ),
      ),
    );
    if (!tappable) return MergeSemantics(child: Semantics(label: semanticLabel, child: content));
    return Semantics(
      button: true,
      label: semanticLabel,
      child: InkWell(onTap: onTap, onLongPress: onLongPress, child: content),
    );
  }
}

/// Square-ish shortcut: icon over a short name, on a flat surface.
class UiShortcut extends StatelessWidget {
  const UiShortcut({super.key, required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = UiColors.of(context);
    final t = UiType.of(context);
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: c.surface,
        borderRadius: UiRadius.control,
        child: InkWell(
          onTap: onTap,
          borderRadius: UiRadius.control,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 84),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(UiSpace.md, 14, UiSpace.md, UiSpace.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Icon(icon, size: 22, color: c.ink),
                  const SizedBox(height: UiSpace.md),
                  Text(
                    label,
                    style: t.label.copyWith(color: c.ink, fontWeight: FontWeight.w600),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A titled block of a screen. Carries its own top gap, so a section that
/// has nothing to show can return an empty box and leave no hole.
class UiSection extends StatelessWidget {
  const UiSection({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
    this.action,
    this.onAction,
    this.first = false,
  });

  final String title;
  final Widget child;
  final Widget? trailing;
  final String? action;
  final VoidCallback? onAction;

  /// No top gap (the first block under a header).
  final bool first;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: first ? 0 : UiSpace.section - UiSpace.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          UiSectionTitle(title: title, trailing: trailing, action: action, onAction: onAction),
          child,
        ],
      ),
    );
  }
}

/// Icon in a soft round tile: the leading mark of a list row.
class UiMark extends StatelessWidget {
  const UiMark({super.key, required this.icon, this.color, this.size = 36});

  final IconData icon;

  /// Icon colour; the tile is a faint wash of it. Defaults to ink on muted.
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = UiColors.of(context);
    final fg = color ?? c.ink;
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color == null ? c.muted : Color.alphaBlend(fg.withValues(alpha: c.dark ? 0.16 : 0.10), c.surface),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: size * 0.47, color: fg),
      ),
    );
  }
}
