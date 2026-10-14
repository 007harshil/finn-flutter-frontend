import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../app/router/routes.dart';
import '../../../../kit/kit.dart';

/// The money modules that are not tabs, as a 3 × 2 grid of plain tiles.
class QuickAccessGrid extends StatelessWidget {
  const QuickAccessGrid({super.key});

  @override
  Widget build(BuildContext context) {
    final tiles = <_Tile>[
      _Tile('Loans & EMIs', LucideIcons.landmark, (c) => c.push(AppRoutes.loans)),
      _Tile('Pending payments', LucideIcons.handCoins, (c) => c.push(AppRoutes.pending)),
      _Tile('Emergency fund', LucideIcons.shield, (c) => c.push(AppRoutes.emergencyFund)),
      // Goals is a tab: switch to it rather than stacking a copy.
      _Tile('Goals', LucideIcons.target, (c) => c.go(AppRoutes.goals)),
      _Tile('Timeline', LucideIcons.calendarDays, (c) => c.push(AppRoutes.timeline)),
      _Tile('Insights', LucideIcons.chartColumn, (c) => c.push(AppRoutes.analytics)),
    ];
    return Padding(
      padding: const EdgeInsets.only(top: Sp.section),
      child: LedgerSection(
        title: 'More',
        child: Column(
          children: [
            for (var r = 0; r < 2; r++) ...[
              if (r > 0) const SizedBox(height: Sp.sm + 2),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < 3; i++) ...[
                      if (i > 0) const SizedBox(width: Sp.sm + 2),
                      Expanded(child: _TileView(tile: tiles[r * 3 + i])),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Tile {
  const _Tile(this.title, this.icon, this.open);

  final String title;
  final IconData icon;
  final void Function(BuildContext) open;
}

class _TileView extends StatelessWidget {
  const _TileView({required this.tile});

  final _Tile tile;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final t = context.type;
    return Semantics(
      key: ValueKey('quick-tile:${tile.title}'),
      button: true,
      label: tile.title,
      excludeSemantics: true,
      child: Material(
        color: c.surface,
        shape: RoundedRectangleBorder(borderRadius: Rad.rLg, side: BorderSide(color: c.line)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            tile.open(context);
          },
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 92),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Sp.md + 2, Sp.md + 2, Sp.sm, Sp.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Icon(tile.icon, size: 22, color: c.ink),
                  const SizedBox(height: Sp.md),
                  Text(tile.title, style: t.labelStrong, maxLines: 2),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
