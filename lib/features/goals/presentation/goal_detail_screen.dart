import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/di/core_providers.dart';
import '../../../app/di/data_providers.dart';
import '../../../app/router/routes.dart';
import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/time/dates.dart';
import '../../../kit/kit.dart';
import '../../../shared/presentation/action_runner.dart';
import '../../../shared/presentation/async_view.dart';
import '../../savings/presentation/held_on_section.dart';
import '../application/goal_actions.dart';
import '../application/goal_view.dart';
import '../domain/goal.dart';
import '../../../shared/presentation/category_icons.dart';
import 'goal_parts.dart';

/// One savings goal: what is saved and whether it is on time, add or
/// withdraw, a monthly plan with a "what if I put in" slider, and the
/// history of money in and out.
class GoalDetailScreen extends ConsumerWidget {
  const GoalDetailScreen({super.key, required this.id});

  final String id;

  Future<void> _menu(BuildContext context, WidgetRef ref, GoalProgress g) async {
    final archived = g.goal.status == GoalStatus.archived;
    final choice = await showFinnActionMenu<int>(
      context,
      items: [
        FinnMenuItem(
          value: 0,
          label: archived ? 'Restore goal' : 'Archive goal',
          icon: archived ? LucideIcons.archiveRestore : LucideIcons.archive,
        ),
        const FinnMenuItem(value: 1, label: 'Delete goal', icon: LucideIcons.trash2, destructive: true),
      ],
    );
    if (!context.mounted || choice == null) return;
    if (choice == 0) {
      await runAction(
        context,
        ref,
        action: const ArchiveGoalAction(),
        input: GoalIdInput(id: g.goal.id),
        idempotencyKey: newIdempotencyKey(),
        successTitle: archived ? 'Goal restored' : 'Goal archived',
        successSubtitle: archived ? null : 'Its money stays earmarked.',
      );
      return;
    }
    final deleted = await runAction(
      context,
      ref,
      action: const DeleteGoalAction(),
      input: GoalIdInput(id: g.goal.id),
      idempotencyKey: newIdempotencyKey(),
      successTitle: 'Goal deleted',
      successSubtitle: g.saved.isPositive ? 'Its money is back in your available balance.' : null,
    );
    if (deleted != null && context.mounted) context.go(AppRoutes.goals);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(goalProgressProvider(id));
    final g = value.value;
    return LedgerPage(
      appBar: LedgerAppBar(
        title: g?.goal.name ?? 'Goal',
        actions: [
          if (g != null) ...[
            LedgerIconButton(
              icon: LucideIcons.pencil,
              tooltip: 'Edit goal',
              onPressed: () => context.push(AppRoutes.editGoal(id)),
            ),
            LedgerIconButton(
              key: const ValueKey('goal-more'),
              icon: LucideIcons.ellipsisVertical,
              tooltip: 'More actions',
              onPressed: () => _menu(context, ref, g),
            ),
          ],
        ],
      ),
      storageKey: 'goal-$id',
      slivers: [
        SliverToBoxAdapter(
          child: AsyncView<GoalProgress?>(
            value: value,
            loading: const LedgerPageSkeleton(rows: 3),
            builder: (context, g) => g == null
                ? PageColumn(
                    top: Sp.xxl,
                    child: LedgerEmpty(
                      title: 'Goal not found',
                      actionLabel: 'Back to goals',
                      onAction: () => context.go(AppRoutes.goals),
                    ),
                  )
                : _GoalBody(progress: g),
          ),
        ),
      ],
    );
  }
}

class _GoalBody extends ConsumerWidget {
  const _GoalBody({required this.progress});

  final GoalProgress progress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = progress;
    final today = ref.watch(todayProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (g.goal.status == GoalStatus.archived)
          const PageColumn(
            top: Sp.sm,
            child: LedgerNote(
              icon: LucideIcons.archive,
              text: 'Archived',
            ),
          ),
        PageColumn(top: Sp.lg, child: _Hero(progress: g, today: today)),
        if (!g.isAchieved)
          PageColumn(
            top: Sp.section,
            child: LedgerSection(title: 'Monthly plan', child: _PlanSection(progress: g, today: today)),
          ),
        HeldOnSection(type: SavingsBucketType.goal, bucketId: g.goal.id, movements: g.movements),
        PageColumn(top: Sp.section, child: _History(movements: g.movements)),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Hero
// ---------------------------------------------------------------------------

class _Hero extends StatelessWidget {
  const _Hero({required this.progress, required this.today});

  final GoalProgress progress;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final g = progress;
    final active = g.goal.status == GoalStatus.active;
    final expected = active && !g.isAchieved ? expectedShare(g, today) : null;
    final hidden = AmountVisibility.hiddenOf(context);
    final date = g.goal.targetDate;
    final finish = g.estimatedCompletion;
    final need = g.requiredMonthly;
    final (stamp, tone) = g.isAchieved
        ? ('Reached', SlabTone.good)
        : g.onTrack == true
            ? ('On track', SlabTone.good)
            : g.onTrack == false
                ? ('Behind', SlabTone.warn)
                : (null, SlabTone.neutral);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BahiSlab(
          leading: CategoryIcons.of(g.goal.category.iconKey),
          label: 'Saved',
          figure: SlabFigure(g.saved),
          caption: 'of ${goalMoney(context, g.goal.target)}',
          stamp: stamp == null ? null : SlabStamp(label: stamp, tone: tone),
          visual: SlabRing(
            value: g.progress,
            marker: expected,
            size: 104,
            color: g.isAchieved ? Slab.good : Slab.warn,
            top: hidden ? '••' : goalPercent(g.progress),
            bottom: 'saved',
            semanticLabel: '${goalPercent(g.progress)} saved'
                '${expected == null || hidden ? '' : '. By now your date needs ${goalPercent(expected)}'}',
          ),
          stats: [
            if (!g.isAchieved) SlabStat.money(label: 'To go', amount: g.remaining),
            if (date != null) SlabStat.text(label: 'Target', text: goalMonth.format(date)),
            if (!g.isAchieved && finish != null)
              SlabStat.text(label: 'At your pace', text: goalMonth.format(finish))
            else if (!g.isAchieved && need != null)
              SlabStat.money(label: 'Needs a month', amount: need),
          ],
        ),
        const SizedBox(height: Sp.md),
        Row(
          children: [
            Expanded(
              child: LedgerButton(
                label: 'Add money',
                icon: LucideIcons.plus,
                expand: true,
                onPressed: active ? () => context.push(AppRoutes.goalContribute(g.goal.id)) : null,
              ),
            ),
            const SizedBox(width: Sp.md),
            Expanded(
              child: LedgerButton(
                label: 'Withdraw',
                icon: LucideIcons.minus,
                variant: LedgerButtonVariant.secondary,
                expand: true,
                onPressed: active && g.saved.isPositive ? () => context.push(AppRoutes.goalWithdraw(g.goal.id)) : null,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Monthly plan
// ---------------------------------------------------------------------------

class _PlanSection extends ConsumerStatefulWidget {
  const _PlanSection({required this.progress, required this.today});

  final GoalProgress progress;
  final DateTime today;

  @override
  ConsumerState<_PlanSection> createState() => _PlanSectionState();
}

class _PlanSectionState extends ConsumerState<_PlanSection> {
  static const _step = 500;

  late int _monthly = _initial();

  /// Starting point for the slider, in whole rupees.
  int _initial() {
    final g = widget.progress;
    final m = g.goal.plannedMonthlyContribution ??
        g.averageMonthlyContribution ??
        g.requiredMonthly ??
        g.remaining.scale(1, 12);
    final r = (m.paise / 100).round();
    return math.max(_step, (r / _step).round() * _step);
  }

  int get _max {
    final g = widget.progress;
    final candidates = [
      _initial() * 2,
      if (g.requiredMonthly != null) (g.requiredMonthly!.paise / 100).round() * 2,
      (g.remaining.paise / 100 / 3).round(),
      10000,
    ];
    final m = candidates.reduce(math.max);
    return ((m / 1000).ceil()) * 1000;
  }

  @override
  void didUpdateWidget(_PlanSection old) {
    super.didUpdateWidget(old);
    if (old.progress.goal.plannedMonthlyContribution != widget.progress.goal.plannedMonthlyContribution) {
      _monthly = _initial();
    }
  }

  /// Monsoon bars: what the date needs a month against the plan (else the
  /// recent average). Null when there is nothing to compare.
  Widget? _compare(BuildContext context) {
    final g = widget.progress;
    final c = context.ink;
    final t = context.type;
    final plan = g.goal.plannedMonthlyContribution;
    final rate = plan ?? g.averageMonthlyContribution;
    final need = g.requiredMonthly;
    if (g.goal.targetDate == null || need == null) return null;
    final short = rate == null || rate < need;
    Widget fig(Money m, Color color) =>
        AmountText(m, decimals: DecimalDisplay.none, style: t.figureSmall.copyWith(color: color));
    return MonsoonBars(
      bars: [
        MonsoonBar('Needed a month', need.paise.toDouble(), c.saffron, trailing: fig(need, c.ink)),
        if (rate != null && rate.isPositive)
          MonsoonBar(
            plan != null ? 'Your plan' : 'Your average',
            rate.paise.toDouble(),
            short ? c.red : c.jade,
            trailing: fig(rate, short ? c.red : c.ink),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.progress;
    final c = context.ink;
    final t = context.type;
    final date = g.goal.targetDate;
    final rate = Money.rupees(_monthly);
    final finish = finishWith(g.remaining, rate, widget.today);
    final max = _max;
    final value = _monthly.clamp(_step, max);
    final compare = _compare(context);

    String whatIf() {
      if (finish == null) return 'Too slow to estimate';
      final base = 'Done by ${DateFormats.monthYear.format(finish)}';
      if (date == null) return base;
      final diff = monthsApart(date, finish);
      return switch (diff) {
        0 => '$base, right on time',
        1 => '$base, a month early',
        > 0 => '$base, $diff months early',
        -1 => '$base, a month late',
        _ => '$base, ${-diff} months late',
      };
    }

    final late = finish != null && date != null && finish.isAfter(date);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (compare != null) ...[
          MonsoonCard(padding: const EdgeInsets.fromLTRB(Sp.sm, Sp.sm, Sp.sm, Sp.xs), child: compare),
          const SizedBox(height: Sp.lg),
        ],
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(child: Text('What if I put in', style: t.label, maxLines: 1, overflow: TextOverflow.ellipsis)),
            const SizedBox(width: Sp.sm),
            AmountText(rate, style: t.figure, decimals: DecimalDisplay.none),
            Text(' a month', style: t.label),
          ],
        ),
        const SizedBox(height: Sp.xs),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: c.rain,
            inactiveTrackColor: c.sunken,
            thumbColor: c.brand,
            overlayColor: c.rain.withValues(alpha: 0.10),
            activeTickMarkColor: Colors.transparent,
            inactiveTickMarkColor: Colors.transparent,
            trackHeight: 4,
            showValueIndicator: ShowValueIndicator.never,
          ),
          child: Slider(
            key: const ValueKey('goal-whatif-slider'),
            // Keep the thumb inside the text column instead of the default inset.
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 16),
            value: value.toDouble(),
            min: _step.toDouble(),
            max: max.toDouble(),
            divisions: ((max - _step) / _step).round().clamp(1, 400),
            semanticFormatterCallback: (v) => '${goalMoney(context, Money.rupees(v.round()))} a month. ${whatIf()}',
            onChanged: (v) {
              final next = v.round();
              if (next != _monthly) HapticFeedback.selectionClick();
              setState(() => _monthly = next);
            },
          ),
        ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.sm),
            decoration: BoxDecoration(
              color: late ? c.amberSoft : c.greenSoft,
              borderRadius: Rad.rChip,
            ),
            child: Text(whatIf(), style: t.labelStrong.copyWith(color: late ? c.amber : c.green)),
          ),
        ),
      ],
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
          ? const LedgerEmpty(icon: LucideIcons.piggyBank, title: 'No money added yet')
          : LedgerPanel(
              khata: true,
              dividerIndent: 0,
              children: [
                for (final e in groups.entries) ...[
                  // Month header inside the one panel: month and its net.
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
