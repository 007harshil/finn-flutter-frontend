import 'package:flutter/material.dart';

import '../../kit/kit.dart';

/// Lets screens inside the shell open the side drawer (Profile, Net worth,
/// Subscriptions, Settings…) that replaced the old "More" tab. Provided by
/// the app shell; screens built without it simply show no menu button.
class AppDrawerScope extends InheritedWidget {
  const AppDrawerScope({super.key, required this.open, required super.child});

  final VoidCallback open;

  static VoidCallback? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppDrawerScope>()?.open;

  @override
  bool updateShouldNotify(AppDrawerScope oldWidget) => oldWidget.open != open;
}

/// The "menu" button that opens the side drawer from a tab's header.
/// Prefer [LedgerMenuButton]; kept for existing callers.
class AppMenuButton extends StatelessWidget {
  const AppMenuButton({super.key});

  @override
  Widget build(BuildContext context) => const LedgerMenuButton();
}
