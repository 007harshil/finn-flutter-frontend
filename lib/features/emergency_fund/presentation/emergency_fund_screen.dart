import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/di/data_providers.dart';
import '../../../app/router/routes.dart';
import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/time/dates.dart';
import '../../../kit/kit.dart';
import '../../../shared/presentation/async_view.dart';
import '../../goals/domain/goal.dart';
import '../../goals/presentation/savings_widgets.dart';
import '../../savings/presentation/held_on_section.dart';
import '../domain/emergency_fund.dart';

/// Emergency fund: what is set aside, how many months of essentials it
/// covers, add or withdraw, the plan behind the target, and the history.
class EmergencyFundScreen extends ConsumerWidget {
  const EmergencyFundScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(emergencyStatusProvider);
    final configured = (value.value?.level ?? EmergencyFundLevel.notConfigured) != EmergencyFundLevel.notConfigured;
    return LedgerPage(
      appBar: LedgerAppBar(
        title: 'Emergency fund',
        actions: [
          if (configured)
            LedgerIconButton(
              icon: LucideIcons.slidersHorizontal,
              tooltip: 'Edit plan',
              onPressed: () => context.push(AppRoutes.emergencyPlan),
            ),
        ],
      ),
      storageKey: 'emergency-fund',
      slivers: [
        SliverToBoxAdapter(
          child: AsyncView<EmergencyFundStatus>(
            value: value,
            errorTitle: 'Could not load your emergency fund',
            loading: const LedgerPageSkeleton(rows: 3),
            builder: (context, s) => _Body(status: s),
          ),
        ),
      ],
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.status});

  final EmergencyFundStatus status;

  @override
  Widget build(BuildContext context) {
    final s = status;
    final configured = s.level != EmergencyFundLevel.notConfigured && s.plan != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageColumn(top: Sp.xl, child: _Hero(status: s, configured: configured)),
        if (configured) PageColumn(top: Sp.section, child: _PlanSection(status: s)),
        HeldOnSection(
          type: SavingsBucketType.emergencyFund,
          bucketId: SavingsMovement.emergencyFundBucketId,
          movements: s.movements,
        ),
        PageColumn(top: Sp.section, child: _History(movements: s.movements)),
        if (configured)
          const PageColumn(
            top: Sp.section,
            child: LedgerNote(
              text: 'Money here is earmarked from your balance. Adding lowers what is available to spend. '
                  'Withdrawing releases it back. Your net worth stays the same.',
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Hero
// ---------------------------------------------------------------------------

class _Hero extends StatelessWidget {
  const _Hero({required this.status, required this.configured});

  final EmergencyFundStatus status;
  final bool configured;

  @override
  Widget build(BuildContext context) {
    final s = status;
    final c = context.ink;
    final t = context.type;
    final hidden = AmountVisibility.hiddenOf(context);
    final coverage = s.coverageMonths;
    final months = s.plan?.targetMonths;
    final String line;
    if (coverage != null && months != null) {
      line = '${_tenths(coverage)} of $months ${months == 1 ? 'month' : 'months'} covered';
    } else {
      line = '${formatBps(s.progressBps, decimals: 0)} of target saved';
    }
    // Amber while below plan, green once met, red only when nearly empty.
    final color = switch (s.level) {
      EmergencyFundLevel.critical => c.red,
      EmergencyFundLevel.building => c.amber,
      EmergencyFundLevel.funded => c.green,
      EmergencyFundLevel.notConfigured => null,
    };
    final suggestion = s.suggestedEssentialMonthly;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Set aside', style: t.label),
        const SizedBox(height: Sp.xs),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Flexible(
              child: AnimatedAmount(s.saved, style: t.figureXL, decimals: DecimalDisplay.none, fit: true, animateOnMount: true),
            ),
            if (configured) ...[
              const SizedBox(width: Sp.sm),
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Text('of ${savingsMoney(context, s.target)}', style: t.figureSmall),
              ),
            ],
          ],
        ),
        if (configured) ...[
          const SizedBox(height: Sp.lg),
          LedgerBar(
            value: s.progress,
            color: color,
            semanticLabel: 'Emergency fund, ${s.level.label}. $line'
                '${hidden ? '' : '. ${AmountText.spokenLabel(s.saved)} of ${AmountText.spokenLabel(s.target)} saved'}',
          ),
          const SizedBox(height: Sp.md),
          Text(line, style: t.label.copyWith(color: s.level == EmergencyFundLevel.funded ? c.green : null)),
          const SizedBox(height: Sp.xl),
          Row(
            children: [
              Expanded(
                child: LedgerButton(
                  label: 'Add money',
                  icon: LucideIcons.plus,
                  expand: true,
                  onPressed: () => context.push(AppRoutes.emergencyContribute),
                ),
              ),
              const SizedBox(width: Sp.md),
              Expanded(
                child: LedgerButton(
                  label: 'Withdraw',
                  icon: LucideIcons.minus,
                  variant: LedgerButtonVariant.secondary,
                  expand: true,
                  onPressed: s.saved.isPositive ? () => context.push(AppRoutes.emergencyWithdraw) : null,
                ),
              ),
            ],
          ),
        ] else ...[
          const SizedBox(height: Sp.xl),
          LedgerEmpty(
            icon: LucideIcons.shield,
            title: 'Plan your safety net',
            message: suggestion == null
                ? 'Enter your essential monthly spending and how many months to cover. Most people aim for 3 to 6.'
                : 'Your essentials averaged ${savingsMoney(context, suggestion)} a month recently. '
                    'Most people aim to cover 3 to 6 months.',
            actionLabel: 'Set up plan',
            onAction: () => context.push(AppRoutes.emergencyPlan),
          ),
        ],
      ],
    );
  }

  static String _tenths(double v) => v.toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '');
}

// ---------------------------------------------------------------------------
// Plan
// ---------------------------------------------------------------------------

class _PlanSection extends StatelessWidget {
  const _PlanSection({required this.status});

  final EmergencyFundStatus status;

  @override
  Widget build(BuildContext context) {
    final s = status;
    final plan = s.plan!;
    final t = context.type;
    final suggestion = s.suggestedEssentialMonthly;
    return LedgerSection(
      title: 'Plan',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: LedgerStat(
                  label: plan.targetOverride == null ? 'Target' : 'Custom target',
                  value: AmountText(s.target, style: t.figure, decimals: DecimalDisplay.none),
                ),
              ),
              const SizedBox(width: Sp.md),
              Expanded(
                child: LedgerStat(
                  label: 'Monthly expenses',
                  value: AmountText(plan.essentialMonthlyExpenses, style: t.figure, decimals: DecimalDisplay.none),
                ),
              ),
            ],
          ),
          const SizedBox(height: Sp.md),
          Text(
            s.remaining.isPositive ? '${savingsMoney(context, s.remaining)} to go' : 'Target reached',
            style: t.body,
          ),
          if (s.suggestionDiffersFromPlan && suggestion != null) ...[
            const SizedBox(height: Sp.lg),
            LedgerNote(
              text: 'Your essentials averaged ${savingsMoney(context, suggestion)} a month over the last '
                  '3 months. You may want to review your plan.',
            ),
          ],
          const SizedBox(height: Sp.lg),
          LedgerButton(
            label: 'Edit plan',
            icon: LucideIcons.pencil,
            variant: LedgerButtonVariant.secondary,
            expand: true,
            onPressed: () => context.push(AppRoutes.emergencyPlan),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// History
// ---------------------------------------------------------------------------

/// Money in and out, newest first, grouped by month with each month's net.
class _History extends StatelessWidget {
  const _History({required this.movements});

  final List<SavingsMovement> movements;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final t = context.type;
    final groups = <MonthKey, List<SavingsMovement>>{};
    for (final m in movements) {
      groups.putIfAbsent(m.date.monthKey, () => []).add(m);
    }
    return LedgerSection(
      title: 'History',
      count: movements.isEmpty ? null : movements.length,
      child: movements.isEmpty
          ? Text('Nothing set aside yet. Your first contribution will show here.', style: t.label)
          : LedgerPanel(
              children: [
                for (final e in groups.entries) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.md),
                    child: Row(
                      children: [
                        Expanded(
                          child: Semantics(
                            header: true,
                            child: Text(DateFormats.monthYear.format(e.key.start), style: t.labelStrong),
                          ),
                        ),
                        AmountText(
                          Money.sum(e.value.map((m) => m.signedAmount)),
                          sign: SignDisplay.always,
                          decimals: DecimalDisplay.none,
                          style: t.figureSmall,
                        ),
                      ],
                    ),
                  ),
                  for (final m in e.value)
                    LedgerRow(
                      key: ValueKey(m.id),
                      leading: IconWell(
                        icon: m.kind == SavingsMovementKind.contribution ? LucideIcons.plus : LucideIcons.minus,
                      ),
                      title: m.kind == SavingsMovementKind.contribution ? 'Added' : 'Withdrawn',
                      subtitle: [
                        DateFormats.dayMonthYear.format(m.date),
                        if (m.note != null && m.note!.trim().isNotEmpty) m.note!.trim(),
                      ].join(', '),
                      subtitleLines: 2,
                      trailing: AmountText(
                        m.signedAmount,
                        sign: SignDisplay.always,
                        style: t.figure.copyWith(
                          color: m.kind == SavingsMovementKind.contribution ? c.green : c.ink,
                        ),
                      ),
                    ),
                ],
              ],
            ),
    );
  }
}
