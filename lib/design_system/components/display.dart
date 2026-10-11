import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/time/dates.dart';
import '../motion/motion.dart';
import '../theme/finn_theme.dart';
import '../tokens/tokens.dart';
import 'buttons.dart';
import 'cards.dart';
import 'tiles.dart';
import 'tone.dart';

const List<String> _monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June', //
  'July', 'August', 'September', 'October', 'November', 'December',
];

/// Previous/next month switcher with an uppercase "OCTOBER 2026" label.
class MonthSwitcher extends StatelessWidget {
  const MonthSwitcher({
    super.key,
    required this.month,
    required this.onChanged,
    this.min,
    this.max,
  });

  final MonthKey month;
  final ValueChanged<MonthKey> onChanged;
  final MonthKey? min;
  final MonthKey? max;

  @override
  Widget build(BuildContext context) {
    final lo = min;
    final hi = max;
    final canPrev = lo == null || month > lo;
    final canNext = hi == null || month < hi;
    final label = '${_monthNames[month.month - 1]} ${month.year}';
    return Row(
      children: [
        FinnIconButton(
          icon: LucideIcons.chevronLeft,
          tooltip: 'Previous month',
          variant: FinnIconButtonVariant.outline,
          size: FinnButtonSize.sm,
          onPressed: canPrev ? () => onChanged(month.previous) : null,
        ),
        Expanded(
          child: Semantics(
            liveRegion: true,
            label: label,
            excludeSemantics: true,
            child: AnimatedSwitcher(
              duration: context.motion.fast,
              child: Text(
                label.toUpperCase(),
                key: ValueKey<MonthKey>(month),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.text.eyebrow.copyWith(
                  fontSize: 13,
                  letterSpacing: 1.4,
                  color: context.colors.textPrimary,
                ),
              ),
            ),
          ),
        ),
        FinnIconButton(
          icon: LucideIcons.chevronRight,
          tooltip: 'Next month',
          variant: FinnIconButtonVariant.outline,
          size: FinnButtonSize.sm,
          onPressed: canNext ? () => onChanged(month.next) : null,
        ),
      ],
    );
  }
}

/// Uppercase tracked label on the left, bold value on the right.
class KeyValueRow extends StatelessWidget {
  const KeyValueRow({
    super.key,
    required this.label,
    this.value,
    this.valueWidget,
    this.valueColor,
    this.padding = const EdgeInsets.symmetric(vertical: Space.x2_5),
  }) : assert(value != null || valueWidget != null, 'Provide value or valueWidget');

  final String label;
  final String? value;
  final Widget? valueWidget;
  final Color? valueColor;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final t = context.text;
    final v = value;
    return MergeSemantics(
      child: Padding(
        padding: padding,
        child: Row(
          children: [
            Expanded(
              child: Text(label.toUpperCase(), style: t.eyebrow),
            ),
            const SizedBox(width: Space.x3),
            Flexible(
              child: Align(
                alignment: AlignmentDirectional.centerEnd,
                child: valueWidget ??
                    Text(
                      v ?? '',
                      textAlign: TextAlign.end,
                      style: t.bodyStrong.copyWith(fontWeight: FontWeight.w800, color: valueColor),
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small metric card: icon + eyebrow label, value, optional caption.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.caption,
    this.accent,
    this.icon,
    this.onTap,
  });

  final String label;

  /// Typically an [Text] or `AmountText`; default style is amountMedium.
  final Widget value;
  final String? caption;

  /// Defaults to `colors.primary`.
  final Color? accent;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final a = accent ?? c.primary;
    final ic = icon;
    final cap = caption;
    return FinnCard(
      padding: const EdgeInsets.all(Space.x3 + 2),
      onTap: onTap,
      child: MergeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                if (ic != null) ...[
                  IconTile(
                    icon: ic,
                    background: a.withValues(alpha: c.isDark ? 0.2 : 0.12),
                    foreground: a,
                    size: 28,
                    radius: Radii.md,
                    iconSize: 15,
                  ),
                  const SizedBox(width: Space.x2),
                ],
                Expanded(
                  child: Text(
                    label.toUpperCase(),
                    style: t.eyebrow,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: Space.x2_5),
            DefaultTextStyle.merge(style: t.amountMedium, child: value),
            if (cap != null) ...[
              const SizedBox(height: Space.x1),
              Text(cap, style: t.caption),
            ],
          ],
        ),
      ),
    );
  }
}

/// Inline tinted banner for tips, warnings and alerts.
class InfoBanner extends StatelessWidget {
  const InfoBanner({
    super.key,
    required this.message,
    this.tone = FinnTone.info,
    this.title,
    this.icon,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final FinnTone tone;
  final String? title;

  /// Defaults to the tone's icon.
  final IconData? icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final accent = tone.color(c);
    final heading = title;
    final action = actionLabel;
    return Container(
      padding: const EdgeInsets.all(Space.x3 + 2),
      decoration: BoxDecoration(
        color: tone.soft(c),
        borderRadius: Radii.rXl,
        border: Border.all(color: accent.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon ?? tone.icon, size: 20, color: accent),
          ),
          const SizedBox(width: Space.x2_5),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (heading != null) ...[
                  Text(heading, style: t.bodyStrong.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: Space.x0_5),
                ],
                Text(message, style: t.caption.copyWith(color: c.textPrimary)),
                if (action != null && onAction != null)
                  Padding(
                    padding: const EdgeInsets.only(top: Space.x1),
                    child: TextButton(
                      onPressed: onAction,
                      style: TextButton.styleFrom(
                        foregroundColor: accent,
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(Dimens.minTouch, 36),
                        tapTargetSize: MaterialTapTargetSize.padded,
                        textStyle: t.label.copyWith(fontWeight: FontWeight.w900),
                      ),
                      child: Text(action.toUpperCase()),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Small "•" separator for inline metadata.
class DotSeparator extends StatelessWidget {
  const DotSeparator({super.key, this.size = 3, this.color, this.spacing = Space.x1_5});

  final double size;
  final Color? color;
  final double spacing;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: spacing),
          child: SizedBox.square(
            dimension: size,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: color ?? context.colors.textTertiary,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
      );
}

/// Hairline divider using the border token.
class FinnDivider extends StatelessWidget {
  const FinnDivider({super.key, this.indent = 0, this.endIndent = 0, this.height = 1});

  final double indent;
  final double endIndent;

  /// Total vertical space taken (the line is always 1px).
  final double height;

  @override
  Widget build(BuildContext context) => Divider(
        height: height,
        thickness: 1,
        indent: indent,
        endIndent: endIndent,
        color: context.colors.border,
      );
}
