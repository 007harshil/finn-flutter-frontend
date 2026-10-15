import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../tokens.dart';
import 'controls.dart';

/// Shared chrome for every bottom sheet: modal sheets opened with
/// [showFinnSheet] and routed sheets (`SheetPage`).
abstract final class LedgerSheet {
  static const double cornerRadius = 20;
  static const ShapeBorder shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(cornerRadius)),
  );

  /// Sheets stay readable on tablets instead of stretching edge to edge.
  static const double maxWidth = 640;

  /// Default body padding of [FinnSheetScaffold].
  static const EdgeInsets bodyPadding = EdgeInsets.fromLTRB(Sp.gutter, Sp.sm, Sp.gutter, Sp.xl);
}

/// Shows a modal bottom sheet; pair with [FinnSheetScaffold].
Future<T?> showFinnSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool isDismissible = true,
  bool enableDrag = true,
  bool useRootNavigator = true,
}) {
  final c = context.ink;
  return showModalBottomSheet<T>(
    context: context,
    builder: builder,
    isScrollControlled: true,
    useSafeArea: true,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    useRootNavigator: useRootNavigator,
    showDragHandle: false,
    backgroundColor: c.surface,
    barrierColor: c.scrim,
    elevation: 0,
    shape: LedgerSheet.shape,
    clipBehavior: Clip.antiAlias,
    constraints: const BoxConstraints(maxWidth: LedgerSheet.maxWidth),
  );
}

/// Sheet layout: grabber, title with an optional close button, a scrolling
/// body and a sticky footer that stays above the keyboard.
///
/// The footer holds the sheet's one primary [LedgerButton] (`expand: true`).
/// Keep [description] for facts the user needs before acting; never repeat
/// the title.
class FinnSheetScaffold extends StatelessWidget {
  const FinnSheetScaffold({
    super.key,
    required this.child,
    this.title,
    this.description,
    this.footer,
    this.showClose = true,
    this.onClose,
    this.bodyPadding = LedgerSheet.bodyPadding,
  });

  /// Scrollable body.
  final Widget child;
  final String? title;
  final String? description;

  /// Sticky footer kept above the keyboard (the save button).
  final Widget? footer;
  final bool showClose;

  /// Defaults to `Navigator.maybePop`.
  final VoidCallback? onClose;
  final EdgeInsetsGeometry bodyPadding;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final t = context.type;
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
              padding: const EdgeInsets.only(top: Sp.sm, bottom: Sp.xs),
              child: Center(
                child: ExcludeSemantics(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(color: c.lineStrong, borderRadius: Rad.pill),
                  ),
                ),
              ),
            ),
            if (heading != null || showClose)
              Padding(
                padding: EdgeInsets.fromLTRB(Sp.gutter, Sp.xs, showClose ? Sp.sm : Sp.gutter, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: Sp.sm + 2),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (heading != null) Semantics(header: true, child: Text(heading, style: t.heading)),
                            if (desc != null) ...[const SizedBox(height: Sp.xs), Text(desc, style: t.label)],
                          ],
                        ),
                      ),
                    ),
                    if (showClose)
                      LedgerIconButton(
                        icon: LucideIcons.x,
                        tooltip: 'Close',
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
                  border: Border(top: BorderSide(color: c.line)),
                ),
                child: SafeArea(
                  top: false,
                  minimum: const EdgeInsets.only(bottom: Sp.md),
                  child: Padding(padding: const EdgeInsets.fromLTRB(Sp.gutter, Sp.md, Sp.gutter, 0), child: foot),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Shows a confirmation dialog; resolves true only when confirmed.
///
/// [destructive] draws the confirm button as red text on a red outline
/// (never a red slab): the user should read the consequence, not be
/// pushed towards it.
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
    barrierColor: context.ink.scrim,
    builder: (ctx) {
      final c = ctx.ink;
      final t = ctx.type;
      return Dialog(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: Sp.xl, vertical: Sp.xl),
        shape: RoundedRectangleBorder(
          borderRadius: Rad.rLg,
          side: BorderSide(color: c.line),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(Sp.xl, Sp.xl, Sp.xl, Sp.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(header: true, child: Text(title, style: t.heading)),
                const SizedBox(height: Sp.sm),
                Text(message, style: t.body.copyWith(color: c.inkSoft)),
                if (details != null) ...[const SizedBox(height: Sp.lg), details],
                const SizedBox(height: Sp.xl),
                OverflowBar(
                  alignment: MainAxisAlignment.end,
                  overflowAlignment: OverflowBarAlignment.end,
                  overflowDirection: VerticalDirection.up,
                  spacing: Sp.sm,
                  overflowSpacing: Sp.sm,
                  children: [
                    LedgerButton(
                      label: cancelLabel,
                      variant: LedgerButtonVariant.secondary,
                      onPressed: () => Navigator.of(ctx).pop(false),
                    ),
                    LedgerButton(
                      label: confirmLabel,
                      variant: destructive ? LedgerButtonVariant.secondary : LedgerButtonVariant.primary,
                      color: destructive ? c.red : null,
                      onPressed: () => Navigator.of(ctx).pop(true),
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
Future<T?> showFinnActionMenu<T>(BuildContext context, {String? title, required List<FinnMenuItem<T>> items}) {
  return showFinnSheet<T>(
    context,
    builder: (ctx) => FinnSheetScaffold(
      title: title,
      showClose: title != null,
      bodyPadding: const EdgeInsets.fromLTRB(Sp.sm, Sp.xs, Sp.sm, Sp.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [for (final item in items) _MenuRow<T>(item: item)],
      ),
    ),
  );
}

class _MenuRow<T> extends StatelessWidget {
  const _MenuRow({required this.item});

  final FinnMenuItem<T> item;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final t = context.type;
    final fg = item.destructive ? c.red : c.ink;
    final icon = item.icon;
    return Semantics(
      button: true,
      enabled: item.enabled,
      child: Opacity(
        opacity: item.enabled ? 1 : 0.4,
        child: InkWell(
          borderRadius: Rad.rMd,
          onTap: item.enabled ? () => Navigator.of(context).pop(item.value) : null,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.sm),
              child: Row(
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 20, color: item.destructive ? c.red : c.inkSoft),
                    const SizedBox(width: Sp.lg),
                  ],
                  Expanded(
                    child: Text(item.label, style: t.body.copyWith(color: fg)),
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
