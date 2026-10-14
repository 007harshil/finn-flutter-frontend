import 'package:flutter/material.dart';

import '../theme/finn_theme.dart';
import '../tokens/finn_colors.dart';
import '../tokens/tokens.dart';
import '../vault/vault.dart';
import 'cards.dart';
import 'tone.dart';

/// Colour treatment of a [FinnButton].
enum FinnButtonVariant { primary, secondary, outline, ghost, destructive, positive, attention }

/// Size of a [FinnButton] / [FinnIconButton].
enum FinnButtonSize { sm, md, lg }

/// Variant of a [FinnIconButton].
enum FinnIconButtonVariant { ghost, filled, outline }

typedef _ButtonColors = ({Color bg, Color fg, Color? border});

_ButtonColors _colorsFor(FinnButtonVariant v, FinnColors c) => switch (v) {
      FinnButtonVariant.primary => (bg: c.primary, fg: c.onPrimary, border: null),
      FinnButtonVariant.secondary => (bg: c.surfaceMuted, fg: c.textPrimary, border: null),
      FinnButtonVariant.outline => (bg: Colors.transparent, fg: c.textPrimary, border: c.borderStrong),
      FinnButtonVariant.ghost => (bg: Colors.transparent, fg: c.textPrimary, border: null),
      FinnButtonVariant.destructive => (bg: c.negative, fg: c.onSolid, border: null),
      FinnButtonVariant.positive => (bg: c.positive, fg: c.onSolid, border: null),
      FinnButtonVariant.attention => (bg: c.attention, fg: c.onSolid, border: null),
    };

/// Primary call-to-action button with variants, sizes and a loading state.
class FinnButton extends StatelessWidget {
  const FinnButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.variant = FinnButtonVariant.primary,
    this.size = FinnButtonSize.md,
    this.loading = false,
    this.expand = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final FinnButtonVariant variant;
  final FinnButtonSize size;

  /// Shows a spinner (in place of the icon), keeps width, disables taps.
  final bool loading;

  /// Stretch to the available width.
  final bool expand;

  @override
  Widget build(BuildContext context) {
    if (VaultScope.isActive(context)) {
      return VaultButton(
        label: label,
        onPressed: onPressed,
        icon: icon,
        loading: loading,
        expand: expand,
        height: switch (size) {
          FinnButtonSize.sm => 40,
          FinnButtonSize.md => 54,
          FinnButtonSize.lg => 58,
        },
        tone: switch (variant) {
          FinnButtonVariant.primary => VaultButtonTone.ink,
          FinnButtonVariant.secondary => VaultButtonTone.quiet,
          FinnButtonVariant.outline => VaultButtonTone.outline,
          FinnButtonVariant.ghost => VaultButtonTone.ghost,
          FinnButtonVariant.destructive => VaultButtonTone.negative,
          FinnButtonVariant.positive => VaultButtonTone.positive,
          FinnButtonVariant.attention => VaultButtonTone.accent,
        },
      );
    }
    final c = context.colors;
    final colors = _colorsFor(variant, c);
    final (double height, double padH, double fontSize, double iconSize) = switch (size) {
      FinnButtonSize.sm => (Dimens.buttonHeightSm, Space.x3, 13.0, 16.0),
      FinnButtonSize.md => (Dimens.buttonHeight, Space.x5, 14.0, 18.0),
      FinnButtonSize.lg => (Dimens.buttonHeightLg, Space.x6, 15.0, 20.0),
    };
    final enabled = onPressed != null && !loading;
    final fadedAlpha = loading ? 1.0 : 0.45;

    final style = ButtonStyle(
      backgroundColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.disabled)
            ? colors.bg.withValues(alpha: colors.bg.a * fadedAlpha)
            : colors.bg,
      ),
      foregroundColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.disabled) ? colors.fg.withValues(alpha: fadedAlpha) : colors.fg,
      ),
      overlayColor: WidgetStateProperty.resolveWith((s) {
        if (s.contains(WidgetState.pressed)) return colors.fg.withValues(alpha: 0.12);
        if (s.contains(WidgetState.hovered) || s.contains(WidgetState.focused)) {
          return colors.fg.withValues(alpha: 0.06);
        }
        return null;
      }),
      side: WidgetStatePropertyAll(
        colors.border == null ? BorderSide.none : BorderSide(color: colors.border!, width: 1.5),
      ),
      shape: const WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: Radii.rLg)),
      minimumSize: WidgetStatePropertyAll(Size(height, height)),
      padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: padH, vertical: Space.x2)),
      textStyle: WidgetStatePropertyAll(context.text.button.copyWith(fontSize: fontSize)),
      elevation: const WidgetStatePropertyAll(0),
      tapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
    );

    final spinner = SizedBox.square(
      dimension: iconSize,
      child: CircularProgressIndicator(strokeWidth: 2.2, color: colors.fg),
    );
    final text = Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center);

    Widget content;
    if (icon != null) {
      content = Row(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          loading ? spinner : Icon(icon, size: iconSize),
          const SizedBox(width: Space.x2),
          Flexible(child: text),
        ],
      );
    } else if (loading) {
      content = Stack(
        alignment: Alignment.center,
        children: [
          Opacity(opacity: 0, alwaysIncludeSemantics: true, child: text),
          spinner,
        ],
      );
    } else {
      content = text;
    }

    Widget button = TextButton(
      onPressed: enabled ? onPressed : null,
      style: style,
      child: content,
    );
    if (expand) button = SizedBox(width: double.infinity, child: button);
    if (loading) button = Semantics(label: 'Loading', child: button);
    return PressableScale(enabled: enabled, child: button);
  }
}

/// Icon-only button; [tooltip] is required for accessibility.
class FinnIconButton extends StatelessWidget {
  const FinnIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.tooltip,
    this.variant = FinnIconButtonVariant.ghost,
    this.size = FinnButtonSize.md,
    this.color,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String tooltip;
  final FinnIconButtonVariant variant;

  /// Visual size: sm 32, md 40, lg 48 (touch target is always ≥ 48).
  final FinnButtonSize size;

  /// Icon colour override.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (double dim, double iconSize) = switch (size) {
      FinnButtonSize.sm => (32.0, 16.0),
      FinnButtonSize.md => (40.0, 20.0),
      FinnButtonSize.lg => (48.0, 22.0),
    };
    final (Color bg, Color fg, BorderSide side) = switch (variant) {
      FinnIconButtonVariant.ghost => (Colors.transparent, color ?? c.textPrimary, BorderSide.none),
      FinnIconButtonVariant.filled => (c.surfaceMuted, color ?? c.textPrimary, BorderSide.none),
      FinnIconButtonVariant.outline => (
          Colors.transparent,
          color ?? c.textPrimary,
          BorderSide(color: c.border, width: 1.5),
        ),
    };
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      icon: Icon(icon, size: iconSize),
      style: IconButton.styleFrom(
        backgroundColor: bg,
        foregroundColor: fg,
        disabledForegroundColor: c.textTertiary,
        disabledBackgroundColor: bg,
        side: side,
        fixedSize: Size.square(dim),
        minimumSize: Size.square(dim),
        padding: EdgeInsets.zero,
        shape: VaultScope.isActive(context)
            ? const CircleBorder()
            : RoundedRectangleBorder(borderRadius: BorderRadius.circular(dim * 0.32)),
        tapTargetSize: MaterialTapTargetSize.padded,
      ),
    );
  }
}
