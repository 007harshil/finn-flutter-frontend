import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design_system/design_system.dart';
import '../features/settings/domain/app_settings.dart';
import 'di/core_providers.dart';
import 'router/app_router.dart';

class FinnApp extends ConsumerWidget {
  const FinnApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final theme = ref.watch(settingsProvider.select((s) => s.theme));
    final motion = ref.watch(settingsProvider.select((s) => s.motion));
    final hidden = ref.watch(settingsProvider.select((s) => s.hideBalances));

    return MaterialApp.router(
      title: 'FiNN',
      debugShowCheckedModeBanner: false,
      theme: FinnTheme.light(),
      darkTheme: FinnTheme.dark(),
      themeMode: switch (theme) {
        ThemePreference.light => ThemeMode.light,
        ThemePreference.dark => ThemeMode.dark,
        ThemePreference.system => ThemeMode.system,
      },
      routerConfig: router,
      builder: (context, child) {
        final systemReduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
        final reduce = switch (motion) {
          MotionPreference.reduced => true,
          MotionPreference.full => false,
          MotionPreference.system => systemReduced,
        };
        // Cap extreme text scaling so financial figures stay legible
        // without breaking layouts (still allows 1.6× for accessibility).
        final mq = MediaQuery.of(context);
        // SafeFrame captures the device's safe insets once, at the root,
        // so every screen, sheet and toast derives its clearance of the
        // status bar, cutouts and gesture bar from one source.
        return MediaQuery(
          data: mq.copyWith(textScaler: mq.textScaler.clamp(maxScaleFactor: 1.6)),
          child: SafeFrame(
            child: MotionScope(
              reduceMotion: reduce,
              child: AmountVisibility(hidden: hidden, child: child ?? const SizedBox.shrink()),
            ),
          ),
        );
      },
    );
  }
}
