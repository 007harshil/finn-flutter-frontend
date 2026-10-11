import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/di/data_providers.dart';
import '../../../app/router/routes.dart';
import '../../../core/money/money_format.dart';
import '../../../core/time/dates.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/presentation/async_view.dart';
import '../../../shared/presentation/category_icons.dart';
import '../../emergency_fund/domain/emergency_fund.dart';
import '../domain/goal.dart';
import 'savings_widgets.dart';

enum _GoalTab { active, completed, archived }

/// "Your vision": emergency fund on top, then savings goals.
class GoalsScreen extends ConsumerStatefulWidget {
  const GoalsScreen({super.key});

  @override
  ConsumerState<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends ConsumerState<GoalsScreen> {
  _GoalTab _tab = _GoalTab.active;

  @override
  Widget build(BuildContext context) {
    final goals = ref.watch(goalProgressListProvider);
    final c = context.colors;
    Widget box(Widget child, {double top = 0}) => SliverToBoxAdapter(
          child: ResponsiveCenter(
            padding: EdgeInsets.fromLTRB(Space.gutter, top, Space.gutter, 0),
            child: child,
          ),
        );
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: AsyncView<List<GoalProgress>>(
          value: goals,
          loading: const _GoalsSkeleton(),
          builder: (context, all) {
            final active = <GoalProgress>[];
            final completed = <GoalProgress>[];
            final archived = <GoalProgress>[];
            for (final g in all) {
              if (g.goal.status == GoalStatus.archived) {
                archived.add(g);
              } else if (g.isAchieved) {
                completed.add(g);
              } else {
                active.add(g);
              }
            }
            final visible = switch (_tab) {
              _GoalTab.active => active,
              _GoalTab.completed => completed,
              _GoalTab.archived => archived,
            };
            return CustomScrollView(
              key: const PageStorageKey('goals'),
              slivers: [
                box(const _Header(), top: Space.x4),
                box(const StaggeredEntrance(child: _EmergencyHeroCard()), top: Space.x5),
                box(
                  SectionHeader(
                    icon: LucideIcons.target,
                    title: 'Savings goals',
                    subtitle: 'Money set aside for what matters to you',
                    tileColor: c.accentGoals,
                  ),
                  top: Space.section,
                ),
                box(const StaggeredEntrance(index: 1, child: _EarmarkedSummary()), top: Space.x3),
                box(
                  SegmentedTabs<_GoalTab>(
                    items: [
                      SegmentItem(_GoalTab.active, 'Active', count: active.length),
                      SegmentItem(_GoalTab.completed, 'Completed', count: completed.length),
                      SegmentItem(_GoalTab.archived, 'Archived', count: archived.length),
                    ],
                    selected: _tab,
                    onChanged: (v) => setState(() => _tab = v),
                  ),
                  top: Space.x4,
                ),
                if (visible.isEmpty)
                  box(_emptyFor(context, _tab, hasAny: all.isNotEmpty), top: Space.x4)
                else
                  SliverList.builder(
                    itemCount: visible.length,
                    itemBuilder: (context, i) {
                      final g = visible[i];
                      return ResponsiveCenter(
                        key: ValueKey(g.goal.id),
                        padding: const EdgeInsets.fromLTRB(Space.gutter, Space.x3, Space.gutter, 0),
                        child: StaggeredEntrance(index: i + 2, child: GoalCard(progress: g)),
                      );
                    },
                  ),
                SliverToBoxAdapter(child: SizedBox(height: context.bottomClearance)),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _emptyFor(BuildContext context, _GoalTab tab, {required bool hasAny}) => switch (tab) {
        _GoalTab.active => EmptyState(
            icon: LucideIcons.target,
            title: hasAny ? 'No active goals' : 'Start your first goal',
            message: 'A trip, a new laptop, a home down payment — give it a name and a target, '
                'and set money aside at your own pace.',
            actionLabel: 'Create a goal',
            actionIcon: LucideIcons.plus,
            onAction: () => context.push(AppRoutes.newGoal),
          ),
        _GoalTab.completed => const EmptyState(
            icon: LucideIcons.partyPopper,
            title: 'Nothing completed yet',
            message: 'Goals you fully fund will appear here.',
          ),
        _GoalTab.archived => const EmptyState(
            icon: LucideIcons.archive,
            title: 'No archived goals',
            message: 'Archive a goal to hide it without losing its history.',
          ),
      };
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final t = context.text;
    return Row(
      children: [
        Expanded(
          child: Semantics(
            header: true,
            label: 'Your vision',
            excludeSemantics: true,
            child: Text.rich(
              TextSpan(children: [
                const TextSpan(text: 'Your '),
                TextSpan(text: 'vision', style: TextStyle(color: context.colors.accentGoals)),
              ]),
              style: t.pageTitle,
            ),
          ),
        ),
        FinnButton(
          label: 'New goal',
          icon: LucideIcons.plus,
          size: FinnButtonSize.sm,
          onPressed: () => context.push(AppRoutes.newGoal),
        ),
      ],
    );
  }
}

/// Emergency fund status at the top of the Goals tab.
class _EmergencyHeroCard extends ConsumerWidget {
  const _EmergencyHeroCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(emergencyStatusProvider).value;
    if (status == null) return const CardSkeleton(height: 170, radius: Radii.xxxl);
    final c = context.colors;
    final t = context.text;
    const soft = Color(0xD9FFFFFF);
    final configured = status.level != EmergencyFundLevel.notConfigured;
    final coverage = status.coverageMonths;
    return GradientHeroCard(
      gradient: emergencyGradient(c, status.level),
      watermark: LucideIcons.shieldCheck,
      onTap: () => context.push(AppRoutes.emergencyFund),
      semanticLabel: configured
          ? 'Emergency fund, ${status.level.label}. ${savingsMoney(context, status.saved)} saved of '
              '${savingsMoney(context, status.target)}.'
              '${coverage == null ? '' : ' Covers about ${coverageLabel(coverage)} of essentials.'}'
          : 'Emergency fund not set up. Tap to set it up.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('EMERGENCY FUND', style: t.eyebrow.copyWith(color: soft)),
              const Spacer(),
              OnGradientPill(label: status.level.label.toUpperCase(), icon: emergencyLevelIcon(status.level)),
            ],
          ),
          const SizedBox(height: Space.x2),
          AnimatedAmount(status.saved, style: t.amountHero.copyWith(color: Colors.white), fit: true),
          const SizedBox(height: Space.x1),
          if (!configured)
            Text(
              'Set a safety-net target based on your essential monthly spending.',
              style: t.body.copyWith(color: soft),
            )
          else ...[
            Text(
              coverage == null ? 'saved' : 'saved · covers about ${coverageLabel(coverage)} of essentials',
              style: t.label.copyWith(color: soft),
            ),
            const SizedBox(height: Space.x3),
            FinnProgressBar(
              value: status.progress,
              color: Colors.white,
              trackColor: Colors.white24,
              height: 10,
              semanticsLabel: 'Emergency fund progress',
            ),
            const SizedBox(height: Space.x2),
            Row(
              children: [
                Text('${formatBps(status.progressBps, decimals: 0)} funded',
                    style: t.label.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
                const Spacer(),
                Text('Target ${savingsMoney(context, status.target)}', style: t.label.copyWith(color: soft)),
              ],
            ),
          ],
          const SizedBox(height: Space.x3),
          Row(
            children: [
              Text(configured ? 'View details' : 'Set up now',
                  style: t.label.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
              const SizedBox(width: Space.x1),
              const Icon(LucideIcons.chevronRight, size: 14, color: Colors.white),
            ],
          ),
        ],
      ),
    );
  }
}

/// Total earmarked money with a plain explanation.
class _EarmarkedSummary extends ConsumerWidget {
  const _EarmarkedSummary();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balance = ref.watch(balanceProvider).value;
    if (balance == null) return const SizedBox.shrink();
    final c = context.colors;
    final t = context.text;
    return FinnCard(
      variant: FinnCardVariant.muted,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconTile(
            icon: LucideIcons.piggyBank,
            background: c.accentGoals.withValues(alpha: 0.14),
            foreground: c.accentGoals,
            size: 36,
            radius: Radii.lg,
            iconSize: 18,
          ),
          const SizedBox(width: Space.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text('EARMARKED FOR GOALS', style: t.eyebrow)),
                    AmountText(balance.earmarkedGoals, style: t.amountSmall),
                  ],
                ),
                const SizedBox(height: Space.x1),
                Text(
                  'Earmarked money is still yours, just set aside — it\'s not counted as spending. '
                  'Available to spend: ${savingsMoney(context, balance.available)}.',
                  style: t.caption,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A savings goal on a gradient card.
class GoalCard extends StatelessWidget {
  const GoalCard({super.key, required this.progress});

  final GoalProgress progress;

  @override
  Widget build(BuildContext context) {
    final g = progress;
    final t = context.text;
    const soft = Color(0xD9FFFFFF);
    final archived = g.goal.status == GoalStatus.archived;
    final date = g.goal.targetDate;
    final onTrack = g.onTrack;
    final pct = formatBps(g.progressBps, decimals: 0);
    return Opacity(
      opacity: archived ? 0.7 : 1,
      child: GradientHeroCard(
        gradient: AccentSwatches.gradient(g.goal.colorIndex),
        watermark: CategoryIcons.of(g.goal.category.iconKey),
        padding: const EdgeInsets.all(Space.x4),
        onTap: () => context.push(AppRoutes.goal(g.goal.id)),
        semanticLabel: '${g.goal.name}. ${savingsMoney(context, g.saved)} saved of '
            '${savingsMoney(context, g.goal.target)}, $pct.'
            '${g.isAchieved ? ' Goal reached.' : ' ${savingsMoney(context, g.remaining)} to go.'}'
            '${onTrack == null || g.isAchieved ? '' : (onTrack ? ' On track.' : ' Behind plan.')}',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(Space.x1_5),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: Radii.rMd),
                  child: Icon(CategoryIcons.of(g.goal.category.iconKey), size: 16, color: Colors.white),
                ),
                const SizedBox(width: Space.x2_5),
                Expanded(
                  child: Text(
                    g.goal.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.bodyStrong.copyWith(color: Colors.white, fontWeight: FontWeight.w900),
                  ),
                ),
                const SizedBox(width: Space.x2),
                OnGradientPill(
                  label: date == null ? 'NO DATE' : DateFormats.shortMonthYear.format(date).toUpperCase(),
                  icon: LucideIcons.calendar,
                ),
              ],
            ),
            const SizedBox(height: Space.x4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('SAVED', style: t.eyebrow.copyWith(color: soft)),
                      AmountText(g.saved, style: t.amountLarge.copyWith(color: Colors.white), fit: true),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('TARGET', style: t.eyebrow.copyWith(color: soft)),
                    AmountText(g.goal.target, style: t.bodyStrong.copyWith(color: Colors.white)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: Space.x3),
            FinnProgressBar(
              value: g.progress,
              color: Colors.white,
              trackColor: Colors.white24,
              height: 10,
              semanticsLabel: '${g.goal.name} progress',
            ),
            const SizedBox(height: Space.x2),
            Row(
              children: [
                Text(pct, style: t.label.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
                const SizedBox(width: Space.x2),
                Expanded(
                  child: Text(
                    g.isAchieved ? 'Target reached' : '${savingsMoney(context, g.remaining)} to go',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.label.copyWith(color: soft),
                  ),
                ),
                if (g.isAchieved)
                  const OnGradientPill(label: 'DONE', icon: LucideIcons.partyPopper)
                else if (archived)
                  const OnGradientPill(label: 'ARCHIVED', icon: LucideIcons.archive)
                else if (onTrack != null)
                  OnGradientPill(
                    label: onTrack ? 'ON TRACK' : 'BEHIND PLAN',
                    icon: onTrack ? LucideIcons.circleCheck : LucideIcons.clock,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _GoalsSkeleton extends StatelessWidget {
  const _GoalsSkeleton();

  @override
  Widget build(BuildContext context) => const SkeletonPulse(
        child: ResponsiveCenter(
          padding: EdgeInsets.symmetric(horizontal: Space.gutter),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: Space.x4),
              SkeletonBox(width: 160, height: 28),
              SizedBox(height: Space.x5),
              CardSkeleton(height: 170, radius: Radii.xxxl),
              SizedBox(height: Space.section),
              CardSkeleton(height: 72),
              SizedBox(height: Space.x4),
              CardSkeleton(height: 160, radius: Radii.xxxl),
            ],
          ),
        ),
      );
}
