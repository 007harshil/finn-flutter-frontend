import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/di/data_providers.dart';
import '../../../app/router/routes.dart';
import '../../../core/money/money_format.dart';
import '../../../core/time/dates.dart';
import '../../../design_system/design_system.dart'
    show AmountText, AnimatedAmount, BottomClearanceX, FinnSheetScaffold, showFinnSheet;
import '../../../shared/presentation/async_view.dart';
import '../../../ui/ui.dart';
import '../../goals/domain/goal.dart';
import '../../goals/presentation/savings_widgets.dart' show coverageLabel, savingsMoney;
import '../domain/emergency_fund.dart';

/// Emergency fund: what is set aside and how far it goes, add / withdraw,
/// the plan behind the target, and every movement.
class EmergencyFundScreen extends ConsumerWidget {
  const EmergencyFundScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(emergencyStatusProvider);
    final configured = (value.value?.level ?? EmergencyFundLevel.notConfigured) != EmergencyFundLevel.notConfigured;
    return UiPage(
      title: 'Emergency fund',
      actions: [
        if (configured)
          UiIconButton(
            icon: LucideIcons.slidersHorizontal,
            tooltip: 'Edit plan',
            onPressed: () => context.push(AppRoutes.emergencyPlan),
          ),
      ],
      body: AsyncView<EmergencyFundStatus>(
        value: value,
        errorTitle: 'Could not load your emergency fund',
        loading: const _Placeholder(),
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
    final configured = s.level != EmergencyFundLevel.notConfigured;
    return ListView(
      key: const PageStorageKey('emergency-fund'),
      padding: EdgeInsets.fromLTRB(UiSpace.gutter, UiSpace.sm, UiSpace.gutter, context.bottomClearance),
      children: [
        UiColumnWidth(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              UiReveal(index: 0, child: _Hero(status: s)),
              const SizedBox(height: UiSpace.xl),
              if (configured) ...[
                Row(
                  children: [
                    Expanded(
                      child: UiPrimaryButton(
                        label: 'Add money',
                        icon: LucideIcons.plus,
                        onPressed: () => context.push(AppRoutes.emergencyContribute),
                      ),
                    ),
                    const SizedBox(width: UiSpace.md),
                    Expanded(
                      child: UiSecondaryButton(
                        label: 'Withdraw',
                        icon: LucideIcons.minus,
                        onPressed: s.saved.isPositive ? () => context.push(AppRoutes.emergencyWithdraw) : null,
                      ),
                    ),
                  ],
                ),
                _Plan(status: s),
              ] else
                _SetUp(status: s),
              _History(movements: s.movements),
            ],
          ),
        ),
      ],
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.status});

  final EmergencyFundStatus status;

  @override
  Widget build(BuildContext context) {
    final c = UiColors.of(context);
    final t = UiType.of(context);
    final s = status;
    final configured = s.level != EmergencyFundLevel.notConfigured;
    final coverage = s.coverageMonths;
    final levelColor = switch (s.level) {
      EmergencyFundLevel.notConfigured => c.inkSoft,
      EmergencyFundLevel.critical => c.negative,
      EmergencyFundLevel.building => c.warning,
      EmergencyFundLevel.funded => c.positive,
    };
    return UiHero(
      label: 'Set aside',
      labelTrailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(s.level.label, style: t.small.copyWith(color: levelColor, fontWeight: FontWeight.w600)),
          UiIconButton(
            icon: LucideIcons.info,
            tooltip: 'How the emergency fund works',
            size: 18,
            color: c.inkSoft,
            onPressed: () => showFinnSheet<void>(context, builder: (_) => const _HowItWorks()),
          ),
        ],
      ),
      value: AnimatedAmount(s.saved, style: t.amount, fit: true, animateOnMount: true),
      caption: coverage == null || !configured ? null : 'Covers about ${coverageLabel(coverage)} of essentials',
      footer: !configured
          ? null
          : UiProgressFooter(
              value: s.progress,
              color: c.emergency,
              semanticsLabel: 'Emergency fund funded',
              start: '${formatBps(s.progressBps, decimals: 0)} of ${savingsMoney(context, s.target)}',
              end: s.remaining.isPositive ? '${savingsMoney(context, s.remaining)} to go' : 'Target reached',
            ),
    );
  }
}

/// Before a plan exists: one sentence and one action.
class _SetUp extends StatelessWidget {
  const _SetUp({required this.status});

  final EmergencyFundStatus status;

  @override
  Widget build(BuildContext context) {
    final t = UiType.of(context);
    final suggestion = status.suggestedEssentialMonthly;
    return UiPanel(
      padding: const EdgeInsets.all(UiSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(header: true, child: Text('Plan your safety net', style: t.section)),
          const SizedBox(height: UiSpace.xs),
          Text(
            suggestion == null
                ? 'Most people keep 3–6 months of essential spending aside.'
                : 'Your essentials run about ${savingsMoney(context, suggestion)} a month. Most people keep 3–6 months aside.',
            style: t.label,
          ),
          const SizedBox(height: UiSpace.lg),
          UiPrimaryButton(label: 'Set up plan', onPressed: () => context.push(AppRoutes.emergencyPlan)),
        ],
      ),
    );
  }
}

/// Essentials × months = target, with a nudge when recent spending moved.
class _Plan extends StatelessWidget {
  const _Plan({required this.status});

  final EmergencyFundStatus status;

  @override
  Widget build(BuildContext context) {
    final t = UiType.of(context);
    final s = status;
    final plan = s.plan!;
    final suggestion = s.suggestedEssentialMonthly;
    return UiSection(
      title: 'Plan',
      action: 'Edit',
      onAction: () => context.push(AppRoutes.emergencyPlan),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          UiPanelList(
            children: [
              UiDetailRow(
                label: 'Essentials per month',
                valueWidget: AmountText(plan.essentialMonthlyExpenses, style: t.body),
              ),
              UiDetailRow(
                label: 'Months of cover',
                value: '${plan.targetMonths} month${plan.targetMonths == 1 ? '' : 's'}',
              ),
              UiDetailRow(
                label: plan.targetOverride == null ? 'Target' : 'Target (custom)',
                valueWidget: AmountText(s.target, style: t.body),
              ),
            ],
          ),
          if (s.suggestionDiffersFromPlan && suggestion != null)
            UiNotice(
              icon: LucideIcons.trendingUp,
              text: 'Essentials averaged ${savingsMoney(context, suggestion)} lately',
              action: 'Review',
              onAction: () => context.push(AppRoutes.emergencyPlan),
            ),
        ],
      ),
    );
  }
}

/// Every contribution and withdrawal, newest first; the latest few shown.
class _History extends StatefulWidget {
  const _History({required this.movements});

  final List<SavingsMovement> movements;

  @override
  State<_History> createState() => _HistoryState();
}

class _HistoryState extends State<_History> {
  static const _collapsed = 5;
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final c = UiColors.of(context);
    final t = UiType.of(context);
    final all = widget.movements;
    final shown = _all ? all : all.take(_collapsed).toList();
    final more = all.length > _collapsed;
    return UiSection(
      title: 'History',
      trailing: all.isEmpty
          ? null
          : Padding(
              padding: EdgeInsets.only(right: more ? 0 : UiSpace.sm),
              child: Text('${all.length} movement${all.length == 1 ? '' : 's'}', style: t.label),
            ),
      action: more ? (_all ? 'Less' : 'All') : null,
      onAction: more ? () => setState(() => _all = !_all) : null,
      child: all.isEmpty
          ? Padding(
              padding: const EdgeInsets.only(left: UiSpace.xs),
              child: Text('Nothing set aside yet.', style: t.label),
            )
          : UiPanelList(
              ruleIndent: 64,
              children: [
                for (final m in shown)
                  Builder(
                    key: ValueKey(m.id),
                    builder: (context) {
                      final added = m.kind == SavingsMovementKind.contribution;
                      final note = m.note?.trim() ?? '';
                      return UiListRow(
                        onTap: null,
                        leading: UiMark(
                          icon: added ? LucideIcons.arrowDownLeft : LucideIcons.arrowUpRight,
                          color: added ? c.emergency : null,
                        ),
                        title: added ? 'Added' : 'Withdrawn',
                        subtitle: [DateFormats.dayMonthYear.format(m.date), if (note.isNotEmpty) note].join(' · '),
                        trailing: AmountText(
                          m.signedAmount,
                          sign: SignDisplay.always,
                          style: t.figureSmall.copyWith(color: added ? c.positive : null),
                        ),
                      );
                    },
                  ),
              ],
            ),
    );
  }
}

class _HowItWorks extends StatelessWidget {
  const _HowItWorks();

  @override
  Widget build(BuildContext context) {
    final t = UiType.of(context);
    return FinnSheetScaffold(
      title: 'How the emergency fund works',
      child: Text(
        'Money here is set aside from your balance. It is still yours, just not for spending. '
        'Adding lowers what is available to spend; withdrawing releases it back. Your net worth stays the same.',
        style: t.body.copyWith(fontWeight: FontWeight.w400, height: 1.5),
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(UiSpace.gutter, UiSpace.lg, UiSpace.gutter, 0),
      child: UiColumnWidth(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            UiPlaceholder(width: 80, height: 12),
            SizedBox(height: UiSpace.md),
            UiPlaceholder(width: 200, height: 40),
            SizedBox(height: UiSpace.lg),
            UiPlaceholder(height: 6),
            SizedBox(height: UiSpace.xl),
            UiPlaceholder(height: 52, radius: UiRadius.control),
            SizedBox(height: UiSpace.section),
            UiPlaceholder(height: 160, radius: UiRadius.panel),
          ],
        ),
      ),
    );
  }
}
