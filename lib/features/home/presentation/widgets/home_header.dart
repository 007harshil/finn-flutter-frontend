import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../app/di/core_providers.dart';
import '../../../../app/di/data_providers.dart';
import '../../../../app/router/routes.dart';
import '../../../../core/time/dates.dart';
import '../../../../kit/kit.dart';

/// Menu, hide-balances and alerts on one line; date and greeting below.
class HomeHeader extends ConsumerWidget {
  const HomeHeader({super.key});

  static String greetingFor(int hour) {
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.type;
    final name = ref.watch(profileStreamProvider.select((v) => v.value?.displayName.trim()));
    final today = ref.watch(todayProvider);
    final hidden = ref.watch(settingsProvider.select((s) => s.hideBalances));
    final unread = ref.watch(unreadAlertCountProvider);
    final greeting = greetingFor(ref.read(clockProvider).now().hour);
    final title = name == null || name.isEmpty ? greeting : '$greeting, $name';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: Sp.sm),
          child: Row(
            children: [
              Transform.translate(offset: const Offset(-10, 0), child: const LedgerMenuButton()),
              const Spacer(),
              LedgerIconButton(
                icon: hidden ? LucideIcons.eyeOff : LucideIcons.eye,
                tooltip: hidden ? 'Show balances' : 'Hide balances',
                onPressed: () {
                  if (ref.read(settingsProvider).hapticsEnabled) HapticFeedback.selectionClick();
                  ref.read(settingsProvider.notifier).update((s) => s.copyWith(hideBalances: !s.hideBalances));
                },
              ),
              Transform.translate(
                offset: const Offset(8, 0),
                child: LedgerIconButton(
                  icon: LucideIcons.bell,
                  tooltip: unread > 0 ? 'Alerts, $unread unread' : 'Alerts',
                  badge: unread,
                  badgeLabel: '$unread unread alerts',
                  onPressed: () => context.push(AppRoutes.alerts),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: Sp.md),
        Text(DateFormats.weekdayDayMonth.format(today), style: t.label),
        const SizedBox(height: 2),
        Semantics(
          header: true,
          child: Text(title, style: t.title, maxLines: 2, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}
