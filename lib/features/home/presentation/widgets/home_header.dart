import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../app/di/core_providers.dart';
import '../../../../app/di/data_providers.dart';
import '../../../../app/router/routes.dart';
import '../../../../core/time/dates.dart';
import '../../../../design_system/design_system.dart';

/// Greeting, today's date, hide-balances toggle and the alerts bell.
class HomeHeader extends ConsumerWidget {
  const HomeHeader({super.key});

  static String greetingFor(int hour) {
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final t = context.text;
    final name = ref.watch(profileStreamProvider.select((v) => v.value?.displayName.trim()));
    final today = ref.watch(todayProvider);
    final hidden = ref.watch(settingsProvider.select((s) => s.hideBalances));
    final unread = ref.watch(unreadAlertCountProvider);
    final greeting = greetingFor(ref.read(clockProvider).now().hour);
    final title = name == null || name.isEmpty ? greeting : '$greeting, $name';

    return Padding(
      padding: const EdgeInsets.only(top: Space.x2),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(DateFormats.weekdayDayMonth.format(today).toUpperCase(), style: t.eyebrow),
                const SizedBox(height: Space.x1),
                Semantics(
                  header: true,
                  child: Text(title, style: t.pageTitle, maxLines: 2, overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
          const SizedBox(width: Space.x2),
          FinnIconButton(
            icon: LucideIcons.sparkles,
            tooltip: 'Assistant',
            variant: FinnIconButtonVariant.filled,
            onPressed: () => context.push(AppRoutes.assistant),
          ),
          const SizedBox(width: Space.x2),
          FinnIconButton(
            icon: hidden ? LucideIcons.eyeOff : LucideIcons.eye,
            tooltip: hidden ? 'Show balances' : 'Hide balances',
            variant: FinnIconButtonVariant.filled,
            onPressed: () {
              if (ref.read(settingsProvider).hapticsEnabled) HapticFeedback.selectionClick();
              ref.read(settingsProvider.notifier).update((s) => s.copyWith(hideBalances: !s.hideBalances));
            },
          ),
          const SizedBox(width: Space.x2),
          CountBadge(
            count: unread,
            color: c.attention,
            semanticsLabel: '$unread unread alerts',
            child: FinnIconButton(
              icon: LucideIcons.bell,
              tooltip: unread > 0 ? 'Alerts, $unread unread' : 'Alerts',
              variant: FinnIconButtonVariant.filled,
              onPressed: () => context.push(AppRoutes.alerts),
            ),
          ),
        ],
      ),
    );
  }
}
