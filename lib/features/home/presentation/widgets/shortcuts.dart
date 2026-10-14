import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../app/router/routes.dart';
import '../../../../ui/ui.dart';

/// One-tap entry to the modules that have no tab of their own. Icon and
/// name only: the figures live on each module's screen.
class HomeShortcuts extends StatelessWidget {
  const HomeShortcuts({super.key});

  static const columns = 3;

  static const _items = <(String, IconData, String)>[
    ('Loans', LucideIcons.landmark, AppRoutes.loans),
    ('Pending', LucideIcons.handCoins, AppRoutes.pending),
    ('Subscriptions', LucideIcons.repeat, AppRoutes.subscriptions),
    ('Emergency fund', LucideIcons.shieldCheck, AppRoutes.emergencyFund),
    ('Insights', LucideIcons.chartColumn, AppRoutes.analytics),
    ('Timeline', LucideIcons.history, AppRoutes.timeline),
  ];

  @override
  Widget build(BuildContext context) {
    final rows = <List<(String, IconData, String)>>[
      for (var i = 0; i < _items.length; i += columns) _items.sublist(i, (i + columns).clamp(0, _items.length)),
    ];
    return UiSection(
      title: 'Shortcuts',
      child: Column(
        children: [
          for (var r = 0; r < rows.length; r++) ...[
            if (r > 0) const SizedBox(height: UiSpace.sm),
            // Equal heights per row, growing with the text size.
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < columns; i++) ...[
                    if (i > 0) const SizedBox(width: UiSpace.sm),
                    Expanded(
                      child: i < rows[r].length
                          ? UiShortcut(
                              key: ValueKey('quick-tile:${rows[r][i].$1}'),
                              icon: rows[r][i].$2,
                              label: rows[r][i].$1,
                              onTap: () => context.push(rows[r][i].$3),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
