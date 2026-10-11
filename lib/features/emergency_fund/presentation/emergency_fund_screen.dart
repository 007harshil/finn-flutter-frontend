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
import '../../goals/presentation/savings_widgets.dart';
import '../domain/emergency_fund.dart';
import '../domain/emergency_fund_calculator.dart';

/// Emergency fund: coverage, plan, add/withdraw and history.
class EmergencyFundScreen extends ConsumerWidget {
  const EmergencyFundScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(emergencyStatusProvider);
    final configured = (value.value?.level ?? EmergencyFundLevel.notConfigured) != EmergencyFundLevel.notConfigured;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Emergency fund'),
        actions: [
          if (configured)
            FinnIconButton(
              icon: LucideIcons.slidersHorizontal,
              tooltip: 'Edit plan',
              onPressed: () => context.push(AppRoutes.emergencyPlan),
            ),
          const SizedBox(width: Space.x2),
        ],
      ),
      body: AsyncView<EmergencyFundStatus>(
        value: value,
        errorTitle: 'Could not load your emergency fund',
        loading: const SkeletonPulse(
          child: Padding(
            padding: EdgeInsets.all(Space.gutter),
            child: Column(
              children: [
                CardSkeleton(height: 220, radius: Radii.xxxl),
                SizedBox(height: Space.x4),
                CardSkeleton(height: 48),
                SizedBox(height: Space.x4),
                CardSkeleton(height: 200),
              ],
            ),
          ),
        ),
        builder: (context, s) => _Body(status: s),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.status});

  final EmergencyFundStatus status;

  @override
  Widget build(BuildContext context) {
    final s = status;
    final c = context.colors;
    final movements = s.movements;
    final configured = s.level != EmergencyFundLevel.notConfigured;
    Widget box(Widget child, {double top = Space.x4}) => SliverToBoxAdapter(
          child: ResponsiveCenter(
            padding: EdgeInsets.fromLTRB(Space.gutter, top, Space.gutter, 0),
            child: child,
          ),
        );
    var i = 0;
    return CustomScrollView(
      key: const PageStorageKey('emergency-fund'),
      slivers: [
        box(StaggeredEntrance(index: i++, child: _HeroCard(status: s)), top: Space.x2),
        if (!configured)
          box(StaggeredEntrance(index: i++, child: _SetUpCard(status: s)))
        else ...[
          box(StaggeredEntrance(index: i++, child: _MoneyButtons(status: s))),
          box(StaggeredEntrance(index: i++, child: _GuidanceBanner(status: s))),
          box(StaggeredEntrance(index: i++, child: _PlanCard(status: s))),
        ],
        box(StaggeredEntrance(index: i++, child: const _HowItWorks())),
        box(
          SectionHeader(
            icon: LucideIcons.clock,
            title: 'History',
            subtitle: movements.isEmpty ? null : '${movements.length} movement${movements.length == 1 ? '' : 's'}',
            tileColor: c.accentEmergency,
          ),
          top: Space.section,
        ),
        if (movements.isEmpty)
          box(
            Text(
              'Nothing set aside yet. Your first contribution will show here.',
              style: context.text.body.copyWith(color: c.textSecondary),
            ),
            top: Space.x2,
          )
        else
          SliverList.builder(
            itemCount: movements.length,
            itemBuilder: (context, i) => ResponsiveCenter(
              key: ValueKey(movements[i].id),
              padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
              child: SavingsMovementTile(movement: movements[i]),
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: Space.x12)),
      ],
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.status});

  final EmergencyFundStatus status;

  @override
  Widget build(BuildContext context) {
    final s = status;
    final c = context.colors;
    final t = context.text;
    const soft = Color(0xD9FFFFFF);
    final configured = s.level != EmergencyFundLevel.notConfigured;
    final coverage = s.coverageMonths;
    return GradientHeroCard(
      gradient: emergencyGradient(c, s.level),
      watermark: LucideIcons.shieldCheck,
      semanticLabel: configured
          ? 'Emergency fund, ${s.level.label}. ${savingsMoney(context, s.saved)} set aside of '
              '${savingsMoney(context, s.target)}.'
              '${coverage == null ? '' : ' Covers about ${coverageLabel(coverage)} of essentials.'}'
          : 'Emergency fund not set up. ${savingsMoney(context, s.saved)} set aside.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'EMERGENCY FUND',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.eyebrow.copyWith(color: soft),
                ),
              ),
              const SizedBox(width: Space.x2),
              OnGradientPill(label: s.level.label.toUpperCase(), icon: emergencyLevelIcon(s.level)),
            ],
          ),
          const SizedBox(height: Space.x2),
          AnimatedAmount(s.saved, style: t.amountHero.copyWith(color: Colors.white), fit: true),
          const SizedBox(height: Space.x1),
          if (!configured)
            Text(
              'Set a target based on your essential monthly spending to track your coverage.',
              style: t.body.copyWith(color: soft),
            )
          else ...[
            Text(
              coverage == null ? 'earmarked' : 'earmarked · covers about ${coverageLabel(coverage)} of essentials',
              style: t.label.copyWith(color: soft),
            ),
            const SizedBox(height: Space.x4),
            FinnProgressBar(
              value: s.progress,
              color: Colors.white,
              trackColor: Colors.white24,
              height: 10,
              semanticsLabel: 'Emergency fund ${formatBps(s.progressBps, decimals: 0)} funded',
            ),
            const SizedBox(height: Space.x2),
            Row(
              children: [
                Text(
                  '${formatBps(s.progressBps, decimals: 0)} funded',
                  style: t.label.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
                ),
                const Spacer(),
                Flexible(
                  child: Text(
                    'Target ${savingsMoney(context, s.target)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.label.copyWith(color: soft),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Shown before a plan exists.
class _SetUpCard extends StatelessWidget {
  const _SetUpCard({required this.status});

  final EmergencyFundStatus status;

  @override
  Widget build(BuildContext context) {
    final suggestion = status.suggestedEssentialMonthly;
    return EmptyState(
      icon: LucideIcons.lifeBuoy,
      title: 'Plan your safety net',
      message: suggestion == null
          ? 'Tell us your essential monthly spending and how many months of cover you want. '
              'Most people aim for 3–6 months.'
          : 'Your essentials averaged ${savingsMoney(context, suggestion)} a month recently. '
              'Most people aim to cover 3–6 months of that.',
      actionLabel: 'Set up plan',
      actionIcon: LucideIcons.shieldCheck,
      onAction: () => context.push(AppRoutes.emergencyPlan),
    );
  }
}

class _MoneyButtons extends StatelessWidget {
  const _MoneyButtons({required this.status});

  final EmergencyFundStatus status;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            child: FinnButton(
              label: 'Add money',
              icon: LucideIcons.plus,
              variant: FinnButtonVariant.positive,
              expand: true,
              onPressed: () => context.push(AppRoutes.emergencyContribute),
            ),
          ),
          const SizedBox(width: Space.x3),
          Expanded(
            child: FinnButton(
              label: 'Withdraw',
              icon: LucideIcons.minus,
              variant: FinnButtonVariant.outline,
              expand: true,
              onPressed: status.saved.isPositive ? () => context.push(AppRoutes.emergencyWithdraw) : null,
            ),
          ),
        ],
      );
}

/// Calm, level-specific guidance.
class _GuidanceBanner extends StatelessWidget {
  const _GuidanceBanner({required this.status});

  final EmergencyFundStatus status;

  @override
  Widget build(BuildContext context) {
    final s = status;
    final remaining = savingsMoney(context, s.remaining);
    final (tone, title, message) = switch (s.level) {
      EmergencyFundLevel.funded => (
          FinnTone.positive,
          'Your safety net is in place',
          'You have reached your target. Keep it topped up if your essentials go up.',
        ),
      EmergencyFundLevel.critical => (
          FinnTone.warning,
          'Building your first cushion',
          'You have less than ${EmergencyFundCalculator.criticalMonths} months of essentials covered. '
              'Small, regular top-ups add up — $remaining to go.',
        ),
      _ => (
          FinnTone.info,
          'Steady progress',
          '$remaining to go to reach your target.',
        ),
    };
    return InfoBanner(tone: tone, title: title, message: message);
  }
}

/// Plan assumptions, with a nudge when recent spending has shifted.
class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.status});

  final EmergencyFundStatus status;

  @override
  Widget build(BuildContext context) {
    final s = status;
    final plan = s.plan!;
    final c = context.colors;
    final t = context.text;
    final coverage = s.coverageMonths;
    final suggestion = s.suggestedEssentialMonthly;
    return FinnCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(LucideIcons.target, size: 16, color: c.textSecondary),
              const SizedBox(width: Space.x2),
              Expanded(child: Text('Your plan', style: t.sectionTitle)),
              FinnButton(
                label: 'Edit',
                icon: LucideIcons.pencil,
                variant: FinnButtonVariant.ghost,
                size: FinnButtonSize.sm,
                onPressed: () => context.push(AppRoutes.emergencyPlan),
              ),
            ],
          ),
          const SizedBox(height: Space.x1),
          KeyValueRow(
            label: 'Essentials per month',
            valueWidget: AmountText(plan.essentialMonthlyExpenses, style: t.bodyStrong),
          ),
          KeyValueRow(
            label: 'Months of cover',
            value: '${plan.targetMonths} month${plan.targetMonths == 1 ? '' : 's'}',
          ),
          KeyValueRow(
            label: plan.targetOverride == null ? 'Target' : 'Target (custom)',
            valueWidget: AmountText(s.target, style: t.bodyStrong),
          ),
          const FinnDivider(),
          KeyValueRow(label: 'Set aside', valueWidget: AmountText(s.saved, style: t.bodyStrong)),
          KeyValueRow(label: 'Still to go', valueWidget: AmountText(s.remaining, style: t.bodyStrong)),
          KeyValueRow(label: 'Coverage now', value: coverage == null ? '—' : coverageLabel(coverage)),
          const SizedBox(height: Space.x1),
          Text('Plan updated ${DateFormats.dayMonthYear.format(plan.updatedAt)}', style: t.caption),
          if (s.suggestionDiffersFromPlan && suggestion != null) ...[
            const SizedBox(height: Space.x3),
            InfoBanner(
              icon: LucideIcons.sparkles,
              message: 'Your essentials averaged ${savingsMoney(context, suggestion)} a month over the last '
                  '3 months. You may want to review your plan.',
              actionLabel: 'Review plan',
              onAction: () => context.push(AppRoutes.emergencyPlan),
            ),
          ],
        ],
      ),
    );
  }
}

/// Plain explanation of earmarked money.
class _HowItWorks extends StatelessWidget {
  const _HowItWorks();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    return FinnCard(
      variant: FinnCardVariant.muted,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(LucideIcons.info, size: 16, color: c.textSecondary),
          const SizedBox(width: Space.x2),
          Expanded(
            child: Text(
              'Money here is earmarked from your balance — still yours, not spending. '
              'Adding to it lowers "available to spend"; withdrawing releases it back. '
              'Your net worth stays the same.',
              style: t.caption,
            ),
          ),
        ],
      ),
    );
  }
}
