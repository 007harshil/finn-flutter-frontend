import 'package:flutter/material.dart';

import '../vault/vault.dart';

/// Shows a FiNN modal sheet (a floating Vault sheet); pair with
/// [FinnSheetScaffold].
Future<T?> showFinnSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool isDismissible = true,
  bool enableDrag = true,
  bool useRootNavigator = true,
}) {
  return showVaultSheet<T>(
    context,
    builder: builder,
    dismissible: isDismissible,
    enableDrag: enableDrag && isDismissible,
    useRootNavigator: useRootNavigator,
  );
}

/// Sheet layout: grabber, serif title, close, scrolling body and a pinned
/// action dock. See [VaultSheet].
class FinnSheetScaffold extends StatelessWidget {
  const FinnSheetScaffold({
    super.key,
    required this.child,
    this.title,
    this.eyebrow,
    this.description,
    this.icon,
    this.footer,
    this.showClose = true,
    this.onClose,
    this.bodyPadding = const EdgeInsets.fromLTRB(VaultShape.gutter, 6, VaultShape.gutter, 24),
  });

  /// Scrollable body.
  final Widget child;
  final String? title;
  final String? eyebrow;
  final String? description;
  final IconData? icon;

  /// Sticky footer kept above the keyboard (e.g. a save button).
  final Widget? footer;
  final bool showClose;

  /// Defaults to `Navigator.maybePop`.
  final VoidCallback? onClose;
  final EdgeInsetsGeometry bodyPadding;

  @override
  Widget build(BuildContext context) => VaultSheet(
    title: title,
    eyebrow: eyebrow,
    description: description,
    icon: icon,
    footer: footer,
    showClose: showClose,
    onClose: onClose,
    bodyPadding: bodyPadding,
    child: child,
  );
}

/// Shows a confirmation card; resolves true only when confirmed.
Future<bool> showFinnConfirm(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  String cancelLabel = 'Cancel',
  bool destructive = false,
  Widget? details,
}) => showVaultConfirm(
  context,
  title: title,
  message: message,
  confirmLabel: confirmLabel,
  cancelLabel: cancelLabel,
  destructive: destructive,
  details: details,
);

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

/// Action list in a floating sheet; resolves with the chosen item's value.
Future<T?> showFinnActionMenu<T>(
  BuildContext context, {
  String? title,
  required List<FinnMenuItem<T>> items,
}) {
  return showVaultMenu<T>(
    context,
    title: title,
    items: [
      for (final i in items)
        VaultMenuEntry<T>(
          value: i.value,
          label: i.label,
          icon: i.icon,
          destructive: i.destructive,
          enabled: i.enabled,
        ),
    ],
  );
}
