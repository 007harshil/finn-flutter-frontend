import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/di/data_providers.dart';
import '../../../app/router/routes.dart';
import '../../../core/money/money_format.dart';
import '../../../core/time/dates.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/presentation/action_runner.dart';
import '../../../shared/presentation/async_view.dart';
import '../../../shared/presentation/category_icons.dart';
import '../application/goal_actions.dart';
import '../domain/goal.dart';
import 'savings_widgets.dart';

/// One savings goal: progress, estimate, actions and history.
class GoalDetailScreen extends ConsumerWidget {
  const GoalDetailScreen({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(goalProgressProvider(id));
    final g = value.value;
    return Scaffold(
      appBar: AppBar(
        title: Text(g?.goal.name ?? 'Goal', maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (g != null)
            FinnIconButton(
              icon: LucideIcons.pencil,
              tooltip: 'Edit goal',
              onPressed: () => context.push(AppRoutes.editGoal(id)),
            ),
          const SizedBox(width: Space.x2),
        ],
      ),
      body: AsyncView<GoalProgress?>(
        value: value,
        loading: const SkeletonPulse(
          child: Padding(
            padding: EdgeInsets.all(Space.gutter),
            child: Column(children: [CardSkeleton(height: 240), SizedBox(height: Space.x4), CardSkeleton(height: 160)]),
          ),
        ),
        builder: (context, g) => g == null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(Space.x6),
                  child: EmptyState(
                    icon: LucideIcons.target,
                    title: 'Goal not found',
                    message: 'It may have been deleted.',
                    actionLabel: 'Back to goals',
                    onAction: () => context.go(AppRoutes.goals),
                  ),
                ),
              )
            : _GoalBody(progress: g),
      ),
    );
  }
}

class _GoalBody extends StatelessWidget {
  const _GoalBody({required this.progress});

  final GoalProgress progress;

  @override
  Widget build(BuildContext context) {
    final g = progress;
    final c = context.colors;
    final movements = g.movements;
    Widget box(Widget child, {double top = Space.x4}) => SliverToBoxAdapter(
          child: ResponsiveCenter(
            padding: EdgeInsets.fromLTRB(Space.gutter, top, Space.gutter, 0),
            child: child,
          ),
        );
    return CustomScrollView(
      key: PageStorageKey('goal-${g.goal.id}'),
      slivers: [
        if (g.goal.status == GoalStatus.archived)
          box(
            const InfoBanner(
              message: 'This goal is archived. Its money stays earmarked. Restore it to add or withdraw.',
              icon: LucideIcons.archive,
            ),
            top: Space.x2,
          ),
        box(StaggeredEntrance(child: _HeroCard(progress: g)), top: Space.x2),
        box(StaggeredEntrance(index: 1, child: _MoneyButtons(progress: g))),
        box(StaggeredEntrance(index: 2, child: _PlanCard(progress: g))),
        box(StaggeredEntrance(index: 3, child: _ManageRow(progress: g))),
        box(
          SectionHeader(
            icon: LucideIcons.clock,
            title: 'History',
            subtitle: movements.isEmpty ? null : '${movements.length} movement${movements.length == 1 ? '' : 's'}',
            tileColor: c.accentGoals,
          ),
          top: Space.section,
        ),
        if (movements.isEmpty)
          box(
            Text('No money added yet. Your first contribution will show here.',
                style: context.text.body.copyWith(color: c.textSecondary)),
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
  const _HeroCard({required this.progress});

  final GoalProgress progress;

  @override
  Widget build(BuildContext context) {
    final g = progress;
    final c = context.colors;
    final t = context.text;
    final accent = AccentSwatches.solid(g.goal.colorIndex);
    return FinnCard(
      padding: const EdgeInsets.all(Space.x5),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CategoryIconTile(icon: CategoryIcons.of(g.goal.category.iconKey), colorIndex: g.goal.colorIndex, size: 28),
              const SizedBox(width: Space.x2),
              Text(g.goal.category.label, style: t.label),
            ],
          ),
          const SizedBox(height: Space.x4),
          ProgressRing(
            value: g.progress,
            size: 180,
            strokeWidth: 12,
            color: g.isAchieved ? c.positive : accent,
            semanticsLabel: '${g.goal.name} progress',
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (g.isAchieved) ...[
                  const SuccessCheck(size: 40),
                  const SizedBox(height: Space.x1),
                ],
                AnimatedAmount(g.saved, style: t.amountLarge),
                Text('of ${savingsMoney(context, g.goal.target)}', style: t.caption),
                const SizedBox(height: Space.x1),
                Text(formatBps(g.progressBps, decimals: 0), style: t.bodyStrong.copyWith(color: c.textSecondary)),
              ],
            ),
          ),
          const SizedBox(height: Space.x4),
          if (g.isAchieved)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(LucideIcons.partyPopper, size: 16, color: c.positive),
                const SizedBox(width: Space.x1_5),
                Flexible(
                  child: Text(
                    'You reached your goal. Well done!',
                    textAlign: TextAlign.center,
                    style: t.bodyStrong.copyWith(color: c.positive),
                  ),
                ),
              ],
            )
          else
            Text(
              '${savingsMoney(context, g.remaining)} to go',
              style: t.bodyStrong,
            ),
          const SizedBox(height: Space.x1),
          Text(
            'Earmarked from your balance — still your money, not spending.',
            textAlign: TextAlign.center,
            style: t.caption,
          ),
        ],
      ),
    );
  }
}

class _MoneyButtons extends StatelessWidget {
  const _MoneyButtons({required this.progress});

  final GoalProgress progress;

  @override
  Widget build(BuildContext context) {
    final g = progress;
    final active = g.goal.status == GoalStatus.active;
    return Row(
      children: [
        Expanded(
          child: FinnButton(
            label: 'Add money',
            icon: LucideIcons.plus,
            variant: FinnButtonVariant.positive,
            expand: true,
            onPressed: active ? () => context.push(AppRoutes.goalContribute(g.goal.id)) : null,
          ),
        ),
        const SizedBox(width: Space.x3),
        Expanded(
          child: FinnButton(
            label: 'Withdraw',
            icon: LucideIcons.minus,
            variant: FinnButtonVariant.outline,
            expand: true,
            onPressed: active && g.saved.isPositive ? () => context.push(AppRoutes.goalWithdraw(g.goal.id)) : null,
          ),
        ),
      ],
    );
  }
}

/// Target date, monthly plan and an honest estimate.
class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.progress});

  final GoalProgress progress;

  @override
  Widget build(BuildContext context) {
    final g = progress;
    final c = context.colors;
    final t = context.text;
    final plan = g.goal.plannedMonthlyContribution;
    final rate = plan ?? g.averageMonthlyContribution;
    final estimate = g.estimatedCompletion;
    final targetDate = g.goal.targetDate;
    final onTrack = g.onTrack;

    String estimateText;
    if (g.isAchieved) {
      estimateText = estimate == null
          ? 'Goal reached.'
          : 'Reached on ${DateFormats.dayMonthYear.format(estimate)}.';
    } else if (estimate != null && rate != null) {
      estimateText = 'At ${savingsMoney(context, rate)}/month you\'ll reach it by '
          '${DateFormats.monthYear.format(estimate)}.';
      if (plan == null) estimateText += ' Based on your average over the last 3 months.';
    } else {
      estimateText = 'Add a monthly plan to see an estimate.';
    }

    return FinnCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(LucideIcons.trendingUp, size: 16, color: c.textSecondary),
              const SizedBox(width: Space.x2),
              Expanded(child: Text('Plan', style: t.sectionTitle)),
              if (!g.isAchieved && onTrack != null)
                StatusPill(
                  label: onTrack ? 'On track' : 'Behind plan',
                  color: onTrack ? c.positive : c.attention,
                  icon: onTrack ? LucideIcons.circleCheck : LucideIcons.clock,
                ),
            ],
          ),
          const SizedBox(height: Space.x3),
          Text(estimateText, style: t.body),
          if (!g.isAchieved && estimate == null) ...[
            const SizedBox(height: Space.x2),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: FinnButton(
                label: 'Set a monthly plan',
                icon: LucideIcons.calendar,
                variant: FinnButtonVariant.ghost,
                size: FinnButtonSize.sm,
                onPressed: () => context.push(AppRoutes.editGoal(g.goal.id)),
              ),
            ),
          ],
          const SizedBox(height: Space.x2),
          const FinnDivider(),
          KeyValueRow(label: 'Saved', valueWidget: AmountText(g.saved, style: t.bodyStrong)),
          KeyValueRow(label: 'Target', valueWidget: AmountText(g.goal.target, style: t.bodyStrong)),
          KeyValueRow(label: 'Remaining', valueWidget: AmountText(g.remaining, style: t.bodyStrong)),
          KeyValueRow(
            label: 'Target date',
            value: targetDate == null ? 'Not set' : DateFormats.dayMonthYear.format(targetDate),
          ),
          KeyValueRow(
            label: 'Monthly plan',
            valueWidget: plan == null
                ? Text('Not set', style: t.bodyStrong.copyWith(color: c.textSecondary))
                : AmountText(plan, style: t.bodyStrong),
          ),
          if (g.requiredMonthly != null && targetDate != null) ...[
            const SizedBox(height: Space.x2),
            InfoBanner(
              tone: onTrack == false ? FinnTone.warning : FinnTone.info,
              message: 'To reach it by ${DateFormats.monthYear.format(targetDate)}, set aside about '
                  '${savingsMoney(context, g.requiredMonthly!)} a month.',
            ),
          ],
        ],
      ),
    );
  }
}

class _ManageRow extends ConsumerStatefulWidget {
  const _ManageRow({required this.progress});

  final GoalProgress progress;

  @override
  ConsumerState<_ManageRow> createState() => _ManageRowState();
}

class _ManageRowState extends ConsumerState<_ManageRow> {
  bool _busy = false;

  Future<void> _archive() async {
    final g = widget.progress.goal;
    setState(() => _busy = true);
    final archiving = g.status == GoalStatus.active;
    await runAction(
      context,
      ref,
      action: const ArchiveGoalAction(),
      input: GoalIdInput(id: g.id),
      idempotencyKey: newIdempotencyKey(),
      successTitle: archiving ? 'Goal archived' : 'Goal restored',
      successSubtitle: archiving ? 'Its money stays earmarked.' : null,
    );
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _delete() async {
    final g = widget.progress.goal;
    setState(() => _busy = true);
    final deleted = await runAction(
      context,
      ref,
      action: const DeleteGoalAction(),
      input: GoalIdInput(id: g.id),
      idempotencyKey: newIdempotencyKey(),
      successTitle: 'Goal deleted',
      successSubtitle: widget.progress.saved.isPositive ? 'Its money is back in your available balance.' : null,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (deleted != null) context.go(AppRoutes.goals);
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.progress.goal;
    final archived = g.status == GoalStatus.archived;
    return Wrap(
      spacing: Space.x2,
      runSpacing: Space.x2,
      children: [
        FinnButton(
          label: 'Edit',
          icon: LucideIcons.pencil,
          variant: FinnButtonVariant.outline,
          size: FinnButtonSize.sm,
          onPressed: _busy ? null : () => context.push(AppRoutes.editGoal(g.id)),
        ),
        FinnButton(
          label: archived ? 'Restore' : 'Archive',
          icon: archived ? LucideIcons.archiveRestore : LucideIcons.archive,
          variant: FinnButtonVariant.outline,
          size: FinnButtonSize.sm,
          onPressed: _busy ? null : _archive,
        ),
        FinnButton(
          label: 'Delete',
          icon: LucideIcons.trash2,
          variant: FinnButtonVariant.ghost,
          size: FinnButtonSize.sm,
          onPressed: _busy ? null : _delete,
        ),
      ],
    );
  }
}
