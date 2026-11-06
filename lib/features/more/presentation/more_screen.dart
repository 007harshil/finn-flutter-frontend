import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/router/routes.dart';
import '../../../kit/kit.dart';

/// Opens a menu destination. The side drawer closes itself first.
typedef MoreOpen = void Function(BuildContext context, String route);

void _push(BuildContext context, String route) => context.push(route);

/// Full-screen version of the menu at `/more` (deep links). The main entry
/// point is the side drawer ([MoreDrawer]) opened from each tab's header.
class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.ink.paper,
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          key: const PageStorageKey<String>('more'),
          slivers: [
            const PageBlock(top: Sp.lg, bottom: Sp.xxl, child: MoreMenu()),
          ],
        ),
      ),
    );
  }
}

/// The account menu: profile, settings, categories and export. Money
/// modules live on the home "More" grid. Shared by [MoreScreen] and the
/// drawer.
class MoreMenu extends StatelessWidget {
  const MoreMenu({super.key, this.open = _push});

  final MoreOpen open;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final t = context.type;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LedgerSection(
          title: 'Account',
          child: LedgerPanel(
            children: [
              _Item(title: 'Profile', route: AppRoutes.account, open: open),
              _Item(title: 'Settings', route: AppRoutes.settings, open: open),
              _Item(title: 'Categories', route: AppRoutes.categories, open: open),
              _Item(title: 'Export data', route: AppRoutes.export, open: open),
            ],
          ),
        ),
        const SizedBox(height: Sp.lg),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.lock, size: 13, color: c.inkSoft),
            const SizedBox(width: Sp.xs + 2),
            Flexible(child: Text('Private to your FiNN account', style: t.small, textAlign: TextAlign.center)),
          ],
        ),
      ],
    );
  }
}

class _Item extends StatelessWidget {
  const _Item({required this.title, required this.route, required this.open});

  final String title;
  final String route;
  final MoreOpen open;

  @override
  Widget build(BuildContext context) {
    return LedgerRow(
      key: ValueKey('menu:$title'),
      title: title,
      chevron: true,
      onTap: () => open(context, route),
    );
  }
}
