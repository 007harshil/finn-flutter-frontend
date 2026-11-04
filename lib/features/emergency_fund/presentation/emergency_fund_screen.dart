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
        PageColumn(top: Sp.lg, child: _Hero(status: s, configured: configured)),
        if (configured) PageColumn(top: Sp.section, child: _PlanSection(status: s)),
        HeldOnSection(
          type: SavingsBucketType.emergencyFund,
          bucketId: SavingsMovement.emergencyFundBucketId,
          movements: s.movements,
        ),
        PageColumn(top: Sp.section, child: _History(movements: s.movements)),
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
    // Marigold while below plan, green once met, red only when nearly empty.
    final tone = switch (s.level) {
      EmergencyFundLevel.critical => SlabTone.bad,
      EmergencyFundLevel.building => SlabTone.warn,
      EmergencyFundLevel.funded => SlabTone.good,
      EmergencyFundLevel.notConfigured => null,
    };
    final fill = tone == null ? Slab.good : slabToneColor(tone);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BahiSlab(
          leading: LucideIcons.shield,
          label: 'Set aside',
          figure: SlabFigure(s.saved),
          caption: configured ? 'of ${savingsMoney(context, s.target)}' : null,
          stamp: tone == null ? null : SlabStamp(label: s.level.label, tone: tone),
          visual: !configured
              ? null
              : SlabRing(
                  value: s.progress,
                  size: 100,
                  color: fill,
                  top: coverage == null ? formatBps(s.progressBps, decimals: 0) : _tenths(coverage),
                  bottom: coverage == null ? 'saved' : 'months',
                  semanticLabel: 'Emergency fund, ${s.level.label}. $line'
                      '${hidden ? '' : '. ${AmountText.spokenLabel(s.saved)} of ${AmountText.spokenLabel(s.target)} saved'}',
                ),
          footer: !configured || months == null || months <= 0
              ? null
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // One box per planned month, filled as far as savings cover.
                    ExcludeSemantics(
                      child: Row(
                        children: [
                          for (var i = 0; i < months; i++)
                            Expanded(
                              child: Container(
                                height: 24,
                                margin: const EdgeInsets.symmetric(horizontal: 2),
                                decoration: BoxDecoration(
                                  color: Slab.track,
                                  borderRadius: BorderRadius.circular(5),
                                ),
                                clipBehavior: Clip.antiAlias,
                                alignment: Alignment.centerLeft,
                                child: FractionallySizedBox(
                                  widthFactor: ((coverage ?? 0) - i).clamp(0.0, 1.0),
                                  heightFactor: 1,
                                  child: ColoredBox(color: fill),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: Sp.sm),
                    Text(line, style: t.small.copyWith(color: Slab.soft)),
                  ],
                ),
        ),
        if (configured) ...[
          const SizedBox(height: Sp.md),
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
    final c = context.ink;
    final suggestion = s.suggestedEssentialMonthly;
    return LedgerSection(
      title: 'Plan',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          StatGrid(
            tiles: [
              StatTile.money(
                label: plan.targetOverride == null ? 'Target' : 'Custom target',
                amount: s.target,
                icon: LucideIcons.flag,
              ),
              StatTile.money(label: 'Monthly expenses', amount: plan.essentialMonthlyExpenses, icon: LucideIcons.receipt),
              s.remaining.isPositive
                  ? StatTile.money(label: 'To go', amount: s.remaining, icon: LucideIcons.hourglass, color: c.amber)
                  : StatTile.text(label: 'To go', text: 'Target reached', icon: LucideIcons.circleCheck, color: c.green),
              if (s.suggestionDiffersFromPlan && suggestion != null)
                StatTile.money(
                  label: 'Essentials, 3-month avg',
                  amount: suggestion,
                  icon: LucideIcons.chartLine,
                  color: c.rain,
                ),
            ],
          ),
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
          ? const LedgerEmpty(icon: LucideIcons.piggyBank, title: 'Nothing set aside yet')
          : LedgerPanel(
              khata: true,
              dividerIndent: 0,
              children: [
                for (final e in groups.entries) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(70, Sp.md, Sp.lg, Sp.sm),
                    child: Row(
                      children: [
                        Expanded(
                          child: Semantics(
                            header: true,
                            child: Text(DateFormats.monthYear.format(e.key.start), style: t.labelStrong.copyWith(color: c.red)),
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
                        color: m.kind == SavingsMovementKind.contribution ? c.green : c.ink,
                        background: m.kind == SavingsMovementKind.contribution ? c.greenSoft : c.sunken,
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
