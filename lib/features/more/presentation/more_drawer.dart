import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../kit/kit.dart';
import 'more_screen.dart';

/// Side drawer holding what used to be the "More" tab: profile, money
/// modules, insights and account settings. Every destination closes the
/// drawer before navigating so the page opens on a clean screen.
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
    final c = context.ink;
    final t = context.type;
    final width = math.min(_maxWidth, MediaQuery.sizeOf(context).width * 0.88);
    return Drawer(
      key: const ValueKey('app-drawer'),
      width: width,
      backgroundColor: c.paper,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Sp.xl - 4, Sp.sm, Sp.sm, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Semantics(header: true, child: Text('Menu', style: t.heading)),
                  ),
                  LedgerIconButton(
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
                padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.sm, Sp.lg, Sp.xl),
                children: const [MoreMenu(open: _open)],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
