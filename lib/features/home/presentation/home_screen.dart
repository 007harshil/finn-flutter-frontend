import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/data_providers.dart';
import '../../../core/result/result.dart';
import '../../../design_system/luxe/luxe.dart';
import '../../../shared/presentation/luxe_page.dart';
import '../application/home_overview.dart';
import 'widgets/attention_section.dart';
import 'widgets/hero_balance_card.dart';
import 'widgets/home_header.dart';
import 'widgets/period_overview.dart';
import 'widgets/quick_access_grid.dart';
import 'widgets/welcome_section.dart';

/// The financial command centre, read top to bottom as one calm story:
/// who and when (greeting) → where money stands (obsidian balance card) →
/// how the month is going (cash flow) → what needs you → what is coming →
/// every money module, one tap away.
///
/// Each section watches only its own provider, so a change in one module
/// never rebuilds the rest of the page.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  static const _sections = <(Widget, double)>[
    (HeroBalanceCard(), 22),
    (PeriodOverview(), 14),
    (AttentionSection(), LuxeSpace.section),
    (UpcomingSection(), LuxeSpace.section),
    (QuickAccessGrid(), LuxeSpace.section),
  ];

  static const _freshSections = <(Widget, double)>[
    (WelcomeCard(), 22),
    (HeroBalanceCard(), 14),
    (SetupChecklistSection(), LuxeSpace.section),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fresh = ref.watch(isFreshUserProvider);
    final List<Widget> body;
    if (fresh.hasValue) {
      final sections = fresh.requireValue ? _freshSections : _sections;
      // One short, fixed set of sections built together (not lazily), so
      // local state such as the cash-flow month and finished entrances
      // survive scrolling away and back.
      body = [
        luxeBox(
          Column(
            key: ValueKey('home-body-${fresh.requireValue}'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < sections.length; i++)
                Padding(
                  padding: EdgeInsets.only(top: sections[i].$2),
                  child: Reveal(index: i + 1, child: sections[i].$1),
                ),
            ],
          ),
        ),
      ];
    } else if (fresh.hasError) {
      final e = fresh.error;
      body = [
        luxeBox(
          LuxeError(
            title: 'Could not load your money',
            message: e is AppFailure ? e.message : null,
            onRetry: () => refreshFinanceData(ref),
          ),
          top: 40,
        ),
      ];
    } else {
      body = [luxeBox(const _HomeSkeleton(), top: 22)];
    }

    return LuxePage(
      storageKey: 'home',
      compactTitle: 'Overview',
      slivers: [
        luxeBox(const Reveal(child: HomeHeader()), top: 4),
        ...body,
      ],
    );
  }
}

/// Placeholder shaped like the page, so nothing jumps when data arrives.
class _HomeSkeleton extends StatelessWidget {
  const _HomeSkeleton();

  @override
  Widget build(BuildContext context) => const LuxeShimmer(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LuxeBone(height: 236, radius: LuxeSpace.rCard),
        SizedBox(height: 14),
        LuxeBone(height: 196, radius: LuxeSpace.rCard),
        SizedBox(height: LuxeSpace.section),
        LuxeBone(width: 180, height: 26),
        SizedBox(height: 14),
        LuxeBone(height: 180, radius: LuxeSpace.rCard),
      ],
    ),
  );
}
