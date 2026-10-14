import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../app/di/core_providers.dart';
import '../../../../app/di/data_providers.dart';
import '../../../../app/router/routes.dart';
import '../../../../core/time/dates.dart';
import '../../../../design_system/luxe/luxe.dart';
import '../../../../shared/presentation/luxe_page.dart';

/// Menu, privacy toggle and alerts on one quiet line; below, today's date
/// and a serif greeting with the user's name set in italic.
class HomeHeader extends ConsumerWidget {
  const HomeHeader({super.key});

  static String greetingFor(int hour) {
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.luxe;
    final name = ref.watch(profileStreamProvider.select((v) => v.value?.displayName.trim()));
    final today = ref.watch(todayProvider);
    final hidden = ref.watch(settingsProvider.select((s) => s.hideBalances));
    final unread = ref.watch(unreadAlertCountProvider);
    final greeting = greetingFor(ref.read(clockProvider).now().hour);
    final hasName = name != null && name.isNotEmpty;
    final first = hasName ? name.split(RegExp(r'\s+')).first : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LuxeTopBar(
          actions: [
            LuxeIconButton(
              icon: hidden ? LucideIcons.eyeOff : LucideIcons.eye,
              tooltip: hidden ? 'Show balances' : 'Hide balances',
              active: hidden,
              onPressed: () {
                if (ref.read(settingsProvider).hapticsEnabled) HapticFeedback.selectionClick();
                ref.read(settingsProvider.notifier).update((s) => s.copyWith(hideBalances: !s.hideBalances));
              },
            ),
            LuxeIconButton(
              icon: LucideIcons.bell,
              tooltip: unread > 0 ? 'Alerts, $unread unread' : 'Alerts',
              badge: unread,
              onPressed: () => context.push(AppRoutes.alerts),
            ),
          ],
        ),
        const SizedBox(height: 18),
        LuxeTitle(
          eyebrow: DateFormats.weekdayDayMonth.format(today),
          semanticsLabel: hasName ? '$greeting, $name' : greeting,
          title: <InlineSpan>[
            TextSpan(text: hasName ? '$greeting,\n' : greeting),
            if (hasName)
              TextSpan(
                text: first,
                style: TextStyle(fontStyle: FontStyle.italic, color: p.goldInk),
              ),
          ],
        ),
      ],
    );
  }
}
