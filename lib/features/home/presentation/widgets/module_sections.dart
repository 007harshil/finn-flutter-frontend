import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../app/di/data_providers.dart';
import '../../../../app/router/routes.dart';
import '../../../../core/money/money.dart';
import '../../../../core/money/money_format.dart';
import '../../../../core/time/dates.dart';
import '../../../../design_system/design_system.dart';
import '../../../../shared/presentation/async_view.dart';
import '../../../emergency_fund/domain/emergency_fund.dart';
import '../../../goals/domain/goal.dart';
import '../../../pending/domain/pending_payment.dart';
import '../../application/home_overview.dart';
import 'home_common.dart';

/// Eyebrow label + amount + caption block.
class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.amount, this.caption, this.color});

  final String label;
  final Money amount;
  final String? caption;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = context.text;
    final cap = caption;
    return MergeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(), style: t.eyebrow),
          const SizedBox(height: Space.x1),
          AmountText(amount, decimals: DecimalDisplay.none, color: color, style: t.amountLarge, fit: true),
          if (cap != null) ...[
            const SizedBox(height: Space.x0_5),
            Text(cap, style: t.caption, maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
        ],
      ),
    );
  }
}

/// Borrowed loans: outstanding principal and the next EMI.
class DebtSnapshotSection extends ConsumerWidget {
  const DebtSnapshotSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    return HomeSection(
      icon: LucideIcons.landmark,
      title: 'Loans & EMIs',
      tileColor: c.accentLoans,
      onAction: () => context.push(AppRoutes.loans),
      child: AsyncView<DebtOverview>(
        value: ref.watch(debtOverviewProvider),
        loading: const SkeletonPulse(child: CardSkeleton(height: 120)),
        builder: (context, d) {
          if (!d.hasDebt) {
            return HomeNoteCard(
              icon: LucideIcons.badgeCheck,
              color: c.positive,
              title: 'No active loans',
              message: 'You are not repaying any borrowed money right now.',
            );
          }
          final nextDate = d.nextDueDate;
          final nextAmount = d.nextAmount;
          final nextId = d.nextLoanId;
          return FinnCard(
            onTap: () => context.push(AppRoutes.loans),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _Figure(
                        label: 'Outstanding',
                        amount: d.totalOutstanding,
                        caption: d.activeLoans == 1 ? 'Across 1 loan' : 'Across ${d.activeLoans} loans',
                      ),
                    ),
                    const SizedBox(width: Space.x3),
                    if (nextDate != null && nextAmount != null)
                      Expanded(
                        child: _Figure(
                          label: 'Next EMI',
                          amount: nextAmount,
                          caption: '${d.nextLoanName ?? 'Loan'} · ${DateFormats.dayMonth.format(nextDate)}',
                        ),
                      ),
                  ],
                ),
                if (d.overdueCount > 0) ...[
                  const SizedBox(height: Space.x3),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: StatusPill(
                      label: d.overdueCount == 1 ? '1 instalment overdue' : '${d.overdueCount} instalments overdue',
                      color: c.negative,
                      icon: LucideIcons.circleAlert,
                    ),
                  ),
                ],
                if (nextId != null) ...[
                  const SizedBox(height: Space.x3),
                  FinnButton(
                    label: 'View next loan',
                    icon: LucideIcons.arrowRight,
                    variant: FinnButtonVariant.outline,
                    size: FinnButtonSize.sm,
                    expand: true,
                    onPressed: () => context.push(AppRoutes.loan(nextId)),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Progress on the top three active goals.
class GoalsProgressSection extends ConsumerWidget {
  const GoalsProgressSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    return HomeSection(
      icon: LucideIcons.target,
      title: 'Goals',
      tileColor: c.accentGoals,
      onAction: () => context.go(AppRoutes.goals),
      child: AsyncView<List<GoalProgress>>(
        value: ref.watch(topGoalsProvider),
        loading: const SkeletonPulse(child: CardSkeleton(height: 180)),
        builder: (context, goals) {
          if (goals.isEmpty) {
            return HomeNoteCard(
              icon: LucideIcons.target,
              color: c.accentGoals,
              title: 'Give your savings a purpose',
              message: 'Set aside money for a trip, a gadget or a down payment and watch it grow.',
              actionLabel: 'Create a goal',
              actionIcon: LucideIcons.plus,
              onAction: () => context.push(AppRoutes.newGoal),
            );
          }
          return HomeListCard(
            children: [for (final g in goals) _GoalRow(key: ValueKey(g.goal.id), progress: g)],
          );
        },
      ),
    );
  }
}

class _GoalRow extends StatelessWidget {
  const _GoalRow({super.key, required this.progress});

  final GoalProgress progress;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final g = progress;
    final color = AccentSwatches.solid(g.goal.colorIndex);
    return Semantics(
      button: true,
      child: InkWell(
        onTap: () => context.push(AppRoutes.goal(g.goal.id)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.x4, vertical: Space.x3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(g.goal.name, style: t.bodyStrong, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  Text(formatBps(g.progressBps, decimals: 0), style: t.label.copyWith(color: c.textPrimary)),
                ],
              ),
              const SizedBox(height: Space.x2),
              FinnProgressBar(
                value: g.progress,
                color: color,
                height: 6,
                semanticsLabel: '${g.goal.name} ${formatBps(g.progressBps, decimals: 0)} saved',
              ),
              const SizedBox(height: Space.x1_5),
              Row(
                children: [
                  AmountText(g.saved, decimals: DecimalDisplay.none, style: t.amountSmall),
                  Text(' saved of ', style: t.caption),
                  Flexible(
                    child: AmountText(g.goal.target, decimals: DecimalDisplay.none, style: t.caption),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Emergency fund coverage, or a set-up prompt.
class EmergencyFundSection extends ConsumerWidget {
  const EmergencyFundSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final t = context.text;
    return HomeSection(
      icon: LucideIcons.shieldCheck,
      title: 'Emergency fund',
      tileColor: c.accentEmergency,
      actionLabel: 'Open',
      onAction: () => context.push(AppRoutes.emergencyFund),
      child: AsyncView<EmergencyFundStatus>(
        value: ref.watch(emergencyStatusProvider),
        loading: const SkeletonPulse(child: CardSkeleton(height: 140)),
        builder: (context, s) {
          if (s.level == EmergencyFundLevel.notConfigured) {
            return HomeNoteCard(
              icon: LucideIcons.shield,
              color: c.accentEmergency,
              title: 'Build your safety net',
              message: 'Aim for 3–6 months of essential expenses, set aside for the unexpected.',
              actionLabel: 'Set up emergency fund',
              actionIcon: LucideIcons.arrowRight,
              onAction: () => context.push(AppRoutes.emergencyPlan),
            );
          }
          final (color, icon) = switch (s.level) {
            EmergencyFundLevel.funded => (c.positive, LucideIcons.circleCheck),
            EmergencyFundLevel.building => (c.attention, LucideIcons.sprout),
            _ => (c.negative, LucideIcons.triangleAlert),
          };
          final months = s.coverageMonths;
          final targetMonths = s.plan?.targetMonths;
          return FinnCard(
            onTap: () => context.push(AppRoutes.emergencyFund),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('COVERAGE', style: t.eyebrow),
                          const SizedBox(height: Space.x1),
                          Text(months == null ? '—' : '${months.toStringAsFixed(1)} months', style: t.amountLarge),
                          if (targetMonths != null)
                            Text('of essentials · target $targetMonths months', style: t.caption),
                        ],
                      ),
                    ),
                    StatusPill(label: s.level.label, color: color, icon: icon),
                  ],
                ),
                const SizedBox(height: Space.x3),
                FinnProgressBar(
                  value: s.progress,
                  color: c.accentEmergency,
                  semanticsLabel: 'Emergency fund ${formatBps(s.progressBps, decimals: 0)} funded',
                ),
                const SizedBox(height: Space.x2),
                Row(
                  children: [
                    AmountText(s.saved, decimals: DecimalDisplay.none, style: t.amountSmall),
                    Text(' set aside of ', style: t.caption),
                    Flexible(
                      child: AmountText(s.target, decimals: DecimalDisplay.none, style: t.caption),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Money owed to and by the user (not yet part of the cash balance).
class PendingSummarySection extends ConsumerWidget {
  const PendingSummarySection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final t = context.text;
    return HomeSection(
      icon: LucideIcons.handCoins,
      title: 'Pending payments',
      tileColor: c.accentPending,
      onAction: () => context.push(AppRoutes.pending),
      child: AsyncView<PendingOverview>(
        value: ref.watch(pendingOverviewProvider),
        loading: const SkeletonPulse(child: CardSkeleton(height: 168)),
        builder: (context, p) {
          return FinnCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _Figure(
                        label: 'To pay',
                        amount: p.toPay,
                        caption: p.payCount == 1 ? '1 open item' : '${p.payCount} open items',
                      ),
                    ),
                    const SizedBox(width: Space.x3),
                    Expanded(
                      child: _Figure(
                        label: 'To collect',
                        amount: p.toCollect,
                        color: p.toCollect.isPositive ? c.positive : null,
                        caption: p.collectCount == 1 ? '1 open item' : '${p.collectCount} open items',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Space.x2),
                Text(
                  p.activeCount == 0
                      ? 'All settled up. Nothing pending either way.'
                      : 'Pending amounts are not part of your balance until settled.',
                  style: t.caption,
                ),
                if (p.longPending.isNotEmpty) ...[
                  const SizedBox(height: Space.x3),
                  _LongPendingNote(items: p.longPending),
                ],
                const SizedBox(height: Space.x3),
                Row(
                  children: [
                    Expanded(
                      child: FinnButton(
                        label: 'View all',
                        variant: FinnButtonVariant.outline,
                        size: FinnButtonSize.sm,
                        expand: true,
                        onPressed: () => context.push(AppRoutes.pending),
                      ),
                    ),
                    const SizedBox(width: Space.x2),
                    Expanded(
                      child: FinnButton(
                        label: 'Add item',
                        icon: LucideIcons.plus,
                        size: FinnButtonSize.sm,
                        expand: true,
                        onPressed: () => context.push(AppRoutes.newPending()),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Items open longer than [PendingView.longPendingDays], with how long.
/// A calm, informative note: pending items are never "late".
class _LongPendingNote extends StatelessWidget {
  const _LongPendingNote({required this.items});

  final List<PendingView> items;

  static const maxShown = 3;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final shown = items.take(maxShown).toList();
    final more = items.length - shown.length;
    return Container(
      decoration: BoxDecoration(color: c.infoSoft, borderRadius: Radii.rLg),
      padding: const EdgeInsets.fromLTRB(Space.x3, Space.x2_5, Space.x3, Space.x1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(LucideIcons.info, size: 14, color: c.info),
              const SizedBox(width: Space.x1_5),
              Expanded(
                child: Text(
                  'Open for over ${PendingView.longPendingDays} days',
                  style: t.label.copyWith(color: c.info, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.x1),
          for (final v in shown) _LongPendingRow(view: v),
          if (more > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.x1_5),
              child: Text('+ $more more', style: t.caption),
            ),
        ],
      ),
    );
  }
}

class _LongPendingRow extends StatelessWidget {
  const _LongPendingRow({required this.view});

  final PendingView view;

  @override
  Widget build(BuildContext context) {
    final t = context.text;
    final p = view.payment;
    final owe = p.direction == PendingDirection.iOwe;
    final who = owe ? 'You owe ${p.counterparty}' : '${p.counterparty} owes you';
    return Semantics(
      button: true,
      child: InkWell(
        onTap: () => context.push(AppRoutes.pendingItem(p.id)),
        borderRadius: Radii.rMd,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: Dimens.minTouch),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(who, style: t.bodyStrong, maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(
                      '${p.purpose} · pending ${view.daysOpen} days',
                      style: t.caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Space.x2),
              AmountText(view.outstanding, decimals: DecimalDisplay.none, style: t.amountSmall),
            ],
          ),
        ),
      ),
    );
  }
}
