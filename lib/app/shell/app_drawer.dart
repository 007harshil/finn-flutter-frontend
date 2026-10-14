import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../design_system/design_system.dart';

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
class AppMenuButton extends StatelessWidget {
  const AppMenuButton({super.key, this.size = FinnButtonSize.md, this.variant = FinnIconButtonVariant.filled});

  final FinnButtonSize size;
  final FinnIconButtonVariant variant;

  @override
  Widget build(BuildContext context) {
    final open = AppDrawerScope.maybeOf(context);
    if (open == null) return const SizedBox.shrink();
    return FinnIconButton(
      key: const ValueKey('app-menu'),
      icon: LucideIcons.panelLeft,
      tooltip: 'Menu',
      variant: variant,
      size: size,
      onPressed: open,
    );
  }
}
