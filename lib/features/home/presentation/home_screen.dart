import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design_system/design_system.dart' show BottomClearanceX;
import '../../../shared/presentation/async_view.dart';
import '../../../ui/ui.dart';
import '../application/home_overview.dart';
import 'widgets/attention_section.dart';
import 'widgets/hero_balance_card.dart';
import 'widgets/home_header.dart';
import 'widgets/period_overview.dart';
import 'widgets/shortcuts.dart';
import 'widgets/welcome_section.dart';

/// Home: where money stands, one-tap entry to every module, what needs
/// acting on, and how the month is going. Sections with nothing to say
/// disappear instead of showing empty cards.
///
/// Every section is its own widget watching only its own provider, so a
/// change in one module never rebuilds the rest of the page.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  static const _sections = <Widget>[
    HeroBalanceCard(),
    HomeShortcuts(),
    AttentionSection(),
    PeriodOverview(),
    UpcomingSection(),
  ];

  static const _freshSections = <Widget>[HeroBalanceCard(), GetStartedSection(), HomeShortcuts()];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: UiColors.of(context).page,
      body: SafeArea(
        bottom: false,
        child: AsyncView<bool>(
          value: ref.watch(isFreshUserProvider),
          loading: const _HomePlaceholder(),
          builder: (context, fresh) => _HomeBody(key: ValueKey(fresh), sections: fresh ? _freshSections : _sections),
        ),
      ),
    );
  }
}

class _HomeBody extends StatelessWidget {
  const _HomeBody({super.key, required this.sections});

  final List<Widget> sections;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      key: const PageStorageKey<String>('home'),
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            UiSpace.gutter - UiSpace.xs,
            UiSpace.xs,
            UiSpace.gutter,
            context.bottomClearance,
          ),
          // A short, fixed set of sections kept alive together so local
          // state (selected month, expanded lists) survives scrolling.
          sliver: SliverToBoxAdapter(
            child: UiColumnWidth(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const UiReveal(index: 0, child: HomeHeader()),
                  const SizedBox(height: UiSpace.md),
                  for (var i = 0; i < sections.length; i++) UiReveal(index: i + 1, child: sections[i]),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Shaped like the page, so nothing jumps when data arrives.
class _HomePlaceholder extends StatelessWidget {
  const _HomePlaceholder();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(UiSpace.gutter, UiSpace.lg, UiSpace.gutter, 0),
      child: UiColumnWidth(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            UiPlaceholder(width: 180, height: 20),
            SizedBox(height: UiSpace.xl + UiSpace.sm),
            UiPlaceholder(width: 120, height: 12),
            SizedBox(height: UiSpace.md),
            UiPlaceholder(width: 220, height: 40),
            SizedBox(height: UiSpace.xl),
            UiPlaceholder(height: 6),
            SizedBox(height: UiSpace.section),
            UiPlaceholder(height: 176, radius: UiRadius.panel),
          ],
        ),
      ),
    );
  }
}
