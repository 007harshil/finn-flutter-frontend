import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../app/di/core_providers.dart';
import '../../../../app/di/data_providers.dart';
import '../../../../app/router/routes.dart';
import '../../../../app/shell/app_drawer.dart';
import '../../../../ui/ui.dart';

/// Menu, a one-line greeting, and two controls: hide balances and alerts.
class HomeHeader extends ConsumerWidget {
  const HomeHeader({super.key});

  static String greetingFor(int hour) {
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = UiType.of(context);
    final name = ref.watch(profileStreamProvider.select((v) => v.value?.displayName.trim()));
    final hidden = ref.watch(settingsProvider.select((s) => s.hideBalances));
    final unread = ref.watch(unreadAlertCountProvider);
    final greeting = greetingFor(ref.read(clockProvider).now().hour);
    final first = name == null || name.isEmpty ? null : name.split(RegExp(r'\s+')).first;
    final openMenu = AppDrawerScope.maybeOf(context);
    final haptic = ref.watch(settingsProvider.select((s) => s.hapticsEnabled));

    return Row(
      children: [
        if (openMenu != null)
          UiIconButton(
            key: const ValueKey('app-menu'),
            icon: LucideIcons.menu,
            tooltip: 'Menu',
            haptic: haptic,
            onPressed: openMenu,
          )
        else
          const SizedBox(width: 4),
        const SizedBox(width: 4),
        Expanded(
          child: Semantics(
            header: true,
            child: Text(
              first == null ? greeting : '$greeting, $first',
              style: t.section,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        UiIconButton(
          icon: hidden ? LucideIcons.eyeOff : LucideIcons.eye,
          tooltip: hidden ? 'Show balances' : 'Hide balances',
          haptic: haptic,
          onPressed: () => ref.read(settingsProvider.notifier).update((s) => s.copyWith(hideBalances: !s.hideBalances)),
        ),
        UiIconButton(
          icon: LucideIcons.bell,
          tooltip: unread > 0 ? 'Alerts, $unread unread' : 'Alerts',
          haptic: haptic,
          badge: unread,
          onPressed: () => context.push(AppRoutes.alerts),
        ),
      ],
    );
  }
}
