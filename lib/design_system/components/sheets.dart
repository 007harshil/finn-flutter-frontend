import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/finn_theme.dart';
import '../tokens/tokens.dart';
import 'buttons.dart';
import 'tiles.dart';

/// Shows a FiNN modal bottom sheet; pair with [FinnSheetScaffold].
Future<T?> showFinnSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool isDismissible = true,
  bool enableDrag = true,
  bool useRootNavigator = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    builder: builder,
    isScrollControlled: true,
    useSafeArea: true,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    useRootNavigator: useRootNavigator,
    constraints: const BoxConstraints(maxWidth: 640),
  );
}

/// Sheet layout: handle, title, close button, scrollable body, sticky footer.
class FinnSheetScaffold extends StatelessWidget {
  const FinnSheetScaffold({
    super.key,
    required this.child,
    this.title,
    this.description,
    this.footer,
    this.showClose = true,
    this.onClose,
    this.bodyPadding = const EdgeInsets.fromLTRB(Space.x5, Space.x2, Space.x5, Space.x5),
  });

  /// Scrollable body.
  final Widget child;
  final String? title;
  final String? description;

  /// Sticky footer kept above the keyboard (e.g. a save button).
  final Widget? footer;
  final bool showClose;

  /// Defaults to `Navigator.maybePop`.
  final VoidCallback? onClose;
  final EdgeInsetsGeometry bodyPadding;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final screen = MediaQuery.sizeOf(context).height;
    final maxHeight = (screen * 0.92 - keyboard).clamp(160.0, screen);
    final heading = title;
    final desc = description;
    final foot = footer;

    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: Space.x2_5, bottom: Space.x1),
              child: Center(
                child: ExcludeSemantics(
                  child: Container(
                    width: Dimens.sheetHandleWidth,
                    height: 4,
                    decoration: BoxDecoration(color: c.borderStrong, borderRadius: Radii.rFull),
                  ),
                ),
              ),
            ),
            if (heading != null || showClose)
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.x5, Space.x1, Space.x2, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: Space.x2_5),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (heading != null)
                              Semantics(header: true, child: Text(heading, style: t.title)),
                            if (desc != null) ...[
                              const SizedBox(height: Space.x1),
                              Text(desc, style: t.caption),
                            ],
                          ],
                        ),
                      ),
                    ),
                    if (showClose)
                      FinnIconButton(
                        icon: LucideIcons.x,
                        tooltip: 'Close',
                        variant: FinnIconButtonVariant.filled,
                        size: FinnButtonSize.sm,
                        onPressed: onClose ?? () => Navigator.of(context).maybePop(),
                      ),
                  ],
                ),
              ),
            Flexible(
              child: SingleChildScrollView(
                padding: bodyPadding,
                child: foot == null ? SafeArea(top: false, child: child) : child,
              ),
            ),
            if (foot != null)
              DecoratedBox(
                decoration: BoxDecoration(
                  color: c.surface,
                  border: Border(top: BorderSide(color: c.border)),
                ),
                child: SafeArea(
                  top: false,
                  minimum: const EdgeInsets.only(bottom: Space.x3),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(Space.x5, Space.x3, Space.x5, 0),
                    child: foot,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Shows a confirmation dialog; resolves true only when confirmed.
Future<bool> showFinnConfirm(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  String cancelLabel = 'Cancel',
  bool destructive = false,
  Widget? details,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      final c = ctx.colors;
      final t = ctx.text;
      return Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: Space.x5, vertical: Space.x6),
        shape: const RoundedRectangleBorder(borderRadius: Radii.rXxxl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Space.x6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (destructive) ...[
                  IconTile(
                    icon: LucideIcons.triangleAlert,
                    background: c.negativeSoft,
                    foreground: c.negative,
                    size: 44,
                    radius: Radii.lg,
                  ),
                  const SizedBox(height: Space.x4),
                ],
                Semantics(header: true, child: Text(title, style: t.title)),
                const SizedBox(height: Space.x2),
                Text(message, style: t.body.copyWith(color: c.textSecondary)),
                if (details != null) ...[const SizedBox(height: Space.x4), details],
                const SizedBox(height: Space.x6),
                Row(
                  children: [
                    Expanded(
                      child: FinnButton(
                        label: cancelLabel,
                        variant: FinnButtonVariant.outline,
                        expand: true,
                        onPressed: () => Navigator.of(ctx).pop(false),
                      ),
                    ),
                    const SizedBox(width: Space.x3),
                    Expanded(
                      child: FinnButton(
                        label: confirmLabel,
                        variant: destructive ? FinnButtonVariant.destructive : FinnButtonVariant.primary,
                        expand: true,
                        onPressed: () => Navigator.of(ctx).pop(true),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
  return result ?? false;
}

/// One entry in [showFinnActionMenu].
@immutable
class FinnMenuItem<T> {
  const FinnMenuItem({
    required this.value,
    required this.label,
    this.icon,
    this.destructive = false,
    this.enabled = true,
  });

  final T value;
  final String label;
  final IconData? icon;
  final bool destructive;
  final bool enabled;
}

/// Bottom-sheet action list; resolves with the chosen item's value.
Future<T?> showFinnActionMenu<T>(
  BuildContext context, {
  String? title,
  required List<FinnMenuItem<T>> items,
}) {
  return showFinnSheet<T>(
    context,
    builder: (ctx) => FinnSheetScaffold(
      title: title,
      showClose: title != null,
      bodyPadding: const EdgeInsets.fromLTRB(Space.x3, Space.x2, Space.x3, Space.x4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [for (final item in items) _MenuTile<T>(item: item)],
      ),
    ),
  );
}

class _MenuTile<T> extends StatelessWidget {
  const _MenuTile({required this.item});

  final FinnMenuItem<T> item;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fg = item.destructive ? c.negative : c.textPrimary;
    final icon = item.icon;
    return Opacity(
      opacity: item.enabled ? 1 : 0.4,
      child: InkWell(
        borderRadius: Radii.rLg,
        onTap: item.enabled ? () => Navigator.of(context).pop(item.value) : null,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.x2, vertical: Space.x1_5),
            child: Row(
              children: [
                if (icon != null) ...[
                  IconTile(
                    icon: icon,
                    background: item.destructive ? c.negativeSoft : c.surfaceMuted,
                    foreground: fg,
                    size: 36,
                    radius: Radii.md + 2,
                    iconSize: 18,
                  ),
                  const SizedBox(width: Space.x3),
                ],
                Expanded(
                  child: Text(item.label, style: context.text.bodyStrong.copyWith(color: fg)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
