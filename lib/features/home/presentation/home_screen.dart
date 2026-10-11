import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design_system/design_system.dart';
import '../../../shared/presentation/async_view.dart';
import '../application/home_overview.dart';
import 'widgets/attention_section.dart';
import 'widgets/hero_balance_card.dart';
import 'widgets/home_header.dart';
import 'widgets/module_sections.dart';
import 'widgets/period_overview.dart';
import 'widgets/story_sections.dart';
import 'widgets/welcome_section.dart';

/// The financial command centre: where money stands, what needs attention,
/// what is coming up, and how the month is going.
///
/// Every section is its own widget watching only its own provider, so a
/// change in one module never rebuilds the rest of the dashboard.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  static const _sections = <Widget>[
    HomeHeader(),
    HeroBalanceCard(),
    PeriodOverview(),
    AttentionSection(),
    UpcomingSection(),
    NarrativeSection(),
    RecentStorySection(),
    DebtSnapshotSection(),
    GoalsProgressSection(),
    EmergencyFundSection(),
    PendingSummarySection(),
  ];

  static const _freshSections = <Widget>[HomeHeader(), WelcomeCard(), HeroBalanceCard(), SetupChecklistSection()];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: context.colors.background,
      body: SafeArea(
        bottom: false,
        child: AsyncView<bool>(
          value: ref.watch(isFreshUserProvider),
          loading: const _HomeSkeleton(),
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
          padding: EdgeInsets.fromLTRB(Space.gutter, Space.x2, Space.gutter, context.bottomClearance),
          // A fixed, short set of sections: kept alive together so local
          // state (selected month) and entrance animations survive scrolling.
          sliver: SliverToBoxAdapter(
            child: ResponsiveCenter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < sections.length; i++) ...[
                    // The header flows straight into the first card; every
                    // other pair of sections gets a visible divider with
                    // breathing room on both sides.
                    if (i > 1) const _SectionDivider(),
                    Padding(
                      padding: EdgeInsets.only(bottom: i == 0 ? Space.x5 : 0),
                      child: StaggeredEntrance(index: i, child: sections[i]),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Line between dashboard sections. Stronger than the in-card hairline so
/// it reads clearly on the page background in both themes.
class _SectionDivider extends StatelessWidget {
  const _SectionDivider();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.x6),
      child: Container(
        height: 1.5,
        decoration: BoxDecoration(
          color: c.textTertiary.withValues(alpha: c.isDark ? 0.45 : 0.5),
          borderRadius: Radii.rFull,
        ),
      ),
    );
  }
}

/// Placeholder shaped like the dashboard to avoid layout shift.
class _HomeSkeleton extends StatelessWidget {
  const _HomeSkeleton();

  @override
  Widget build(BuildContext context) {
    return const SkeletonPulse(
      child: SingleChildScrollView(
        physics: NeverScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(Space.gutter, Space.x4, Space.gutter, Space.x4),
        child: ResponsiveCenter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 110, height: 10),
              SizedBox(height: Space.x2),
              SkeletonBox(width: 220, height: 26),
              SizedBox(height: Space.x5),
              CardSkeleton(height: 196, radius: Radii.xxxl),
              SizedBox(height: Space.section),
              SkeletonBox(width: 160, height: 24),
              SizedBox(height: Space.x3),
              SkeletonBox(height: 32),
              SizedBox(height: Space.x3),
              Row(
                children: [
                  Expanded(child: CardSkeleton(height: 104)),
                  SizedBox(width: Space.x3),
                  Expanded(child: CardSkeleton(height: 104)),
                ],
              ),
              SizedBox(height: Space.section),
              SkeletonBox(width: 180, height: 24),
              SizedBox(height: Space.x3),
              CardSkeleton(height: 220),
            ],
          ),
        ),
      ),
    );
  }
}
