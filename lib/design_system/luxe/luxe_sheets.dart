import 'package:flutter/material.dart';

import '../vault/vault.dart';

/// Opens a floating Vault sheet. Pair with [LuxeSheet].
Future<T?> showLuxeSheet<T>(BuildContext context, {required WidgetBuilder builder, bool dismissible = true}) =>
    showVaultSheet<T>(context, builder: builder, dismissible: dismissible, enableDrag: dismissible);

/// Sheet layout (eyebrow, serif title, close, scrolling body, pinned
/// footer). See [VaultSheet].
class LuxeSheet extends StatelessWidget {
  const LuxeSheet({
    super.key,
    required this.child,
    this.title,
    this.eyebrow,
    this.description,
    this.footer,
    this.bodyPadding = const EdgeInsets.fromLTRB(VaultShape.gutter, 6, VaultShape.gutter, 24),
  });

  final Widget child;
  final String? title;
  final String? eyebrow;
  final String? description;
  final Widget? footer;
  final EdgeInsetsGeometry bodyPadding;

  @override
  Widget build(BuildContext context) => VaultSheet(
    title: title,
    eyebrow: eyebrow,
    description: description,
    footer: footer,
    bodyPadding: bodyPadding,
    child: child,
  );
}

/// One choice of [showLuxeMenu].
class LuxeMenuItem<T> {
  const LuxeMenuItem({
    required this.value,
    required this.label,
    required this.icon,
    this.hint,
    this.destructive = false,
  });
  final T value;
  final String label;
  final IconData icon;
  final String? hint;
  final bool destructive;
}

/// Contextual actions (long-press menus) in a floating sheet.
Future<T?> showLuxeMenu<T>(
  BuildContext context, {
  required String title,
  String? eyebrow,
  required List<LuxeMenuItem<T>> items,
}) {
  return showVaultMenu<T>(
    context,
    title: title,
    eyebrow: eyebrow,
    items: [
      for (final i in items)
        VaultMenuEntry<T>(value: i.value, label: i.label, icon: i.icon, hint: i.hint, destructive: i.destructive),
    ],
  );
}
