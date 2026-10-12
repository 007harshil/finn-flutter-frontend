import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../design_system/design_system.dart';
import 'more_screen.dart';

/// Side drawer holding what used to be the "More" tab: profile, net worth,
/// money modules and app settings. Every destination closes the drawer
/// before navigating so the page opens on a clean screen.
class MoreDrawer extends StatelessWidget {
  const MoreDrawer({super.key});

  static const _maxWidth = 380.0;

  /// `go`, not `push`: drawer pages live in the `/more` branch, and a page
  /// pushed from another tab would stay in that tab's saved history (tapping
  /// Home would reopen it).
  static void _open(BuildContext context, String route) {
    Scaffold.maybeOf(context)?.closeDrawer();
    context.go(route);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final width = math.min(_maxWidth, MediaQuery.sizeOf(context).width * 0.88);
    return Drawer(
      key: const ValueKey('app-drawer'),
      width: width,
      backgroundColor: c.background,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.horizontal(right: Radius.circular(Radii.xxxl))),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.x5, Space.x3, Space.x2, Space.x1),
              child: Row(
                children: [
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text('Menu', style: t.sectionTitle.copyWith(color: c.textSecondary)),
                    ),
                  ),
                  FinnIconButton(
                    icon: LucideIcons.x,
                    tooltip: 'Close menu',
                    onPressed: () => Scaffold.maybeOf(context)?.closeDrawer(),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                key: const PageStorageKey<String>('app-drawer'),
                padding: const EdgeInsets.fromLTRB(Space.x4, Space.x2, Space.x4, Space.x6),
                children: const [MoreMenu(open: _open)],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
