import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../kit/kit.dart';
import '../../../shared/presentation/async_view.dart';
import '../application/home_overview.dart';
import 'widgets/attention_section.dart';
import 'widgets/hero_balance_card.dart';
import 'widgets/home_header.dart';
import 'widgets/period_overview.dart';
import 'widgets/quick_access_grid.dart';
import 'widgets/welcome_section.dart';

/// Where money stands (available to spend), how this month is going, what
/// needs the user, what is due soon, and the other money modules. Sections
/// with nothing to say hide themselves.
///
/// Every section watches only its own provider, so a change in one module
/// never rebuilds the rest of the page.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncView<bool>(
      value: ref.watch(isFreshUserProvider),
      loading: Scaffold(backgroundColor: context.ink.paper, body: const SafeArea(child: LedgerPageSkeleton())),
      builder: (context, fresh) => LedgerPage(
        key: ValueKey(fresh),
        storageKey: 'home',
        slivers: fresh
            ? const [
                PageBlock(child: HomeHeader()),
                PageBlock(top: Sp.xxl, child: WelcomeCard()),
                PageBlock(top: Sp.section, child: HeroBalanceCard()),
                PageBlock(top: Sp.section, child: SetupChecklistSection()),
              ]
            : const [
                PageBlock(child: HomeHeader()),
                PageBlock(top: Sp.xxl, child: HeroBalanceCard()),
                PageBlock(top: Sp.section, child: PeriodOverview()),
                PageBlock(child: AttentionSection()),
                PageBlock(child: UpcomingSection()),
                PageBlock(child: QuickAccessGrid()),
              ],
      ),
    );
  }
}
