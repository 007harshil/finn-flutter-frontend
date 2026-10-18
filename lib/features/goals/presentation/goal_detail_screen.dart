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
                      message: 'It may have been deleted.',
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
              text: 'This goal is archived. Its money stays earmarked. Restore it to add or withdraw.',
            ),
          ),
        PageColumn(top: Sp.xl, child: _Hero(progress: g, today: today)),
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
    final c = context.ink;
    final t = context.type;
    final active = g.goal.status == GoalStatus.active;
    final expected = active && !g.isAchieved ? expectedShare(g, today) : null;
    final (status, tone) = _status(context, g, c);
    final hidden = AmountVisibility.hiddenOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Saved', style: t.label),
        const SizedBox(height: Sp.xs),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Flexible(
              child: AnimatedAmount(g.saved, style: t.figureXL, decimals: DecimalDisplay.none, fit: true, animateOnMount: true),
            ),
            const SizedBox(width: Sp.sm),
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Text('of ${goalMoney(context, g.goal.target)}', style: t.figureSmall),
            ),
          ],
        ),
        const SizedBox(height: Sp.lg),
        LedgerBar(
          value: g.progress,
          marker: expected,
          semanticLabel: '${goalPercent(g.progress)} saved'
              '${expected == null || hidden ? '' : '. By now your date needs ${goalPercent(expected)}'}',
        ),
        const SizedBox(height: Sp.md),
        Text(status, style: t.label.copyWith(color: tone)),
        const SizedBox(height: Sp.xl),
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

  /// One line on where the goal stands, coloured only when it matters.
  static (String, Color?) _status(BuildContext context, GoalProgress g, LedgerColors c) {
    if (g.isAchieved) return ('Target reached', c.green);
    final date = g.goal.targetDate;
    final finish = g.estimatedCompletion;
    if (g.onTrack == true && finish != null) return ('On track, done by ${goalMonth.format(finish)}', null);
    if (g.onTrack == false && finish != null && date != null) {
      final late = monthsApart(finish, date);
      return (late <= 0 ? 'Behind, finishing just after your date' : 'Behind, ${aboutMonths(late)} late', c.amber);
    }
    final need = g.requiredMonthly;
    if (date != null && need != null) {
      return ('Needs ${goalMoney(context, need)} a month to finish by ${goalMonth.format(date)}', null);
    }
    if (finish != null) return ('Done around ${goalMonth.format(finish)} at your pace', null);
    return ('No target date', null);
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
  bool _saving = false;

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

  Future<void> _usePlan() async {
    final goal = widget.progress.goal;
    setState(() => _saving = true);
    await runAction(
      context,
      ref,
      action: const UpdateGoalAction(),
      input: UpdateGoalInput(
        id: goal.id,
        expectedVersion: goal.version,
        data: GoalInput(
          name: goal.name,
          category: goal.category,
          target: goal.target,
          colorIndex: goal.colorIndex,
          targetDate: goal.targetDate,
          plannedMonthlyContribution: Money.rupees(_monthly),
          note: goal.note,
        ),
      ),
      idempotencyKey: newIdempotencyKey(),
      successTitle: 'Monthly plan updated',
    );
    if (mounted) setState(() => _saving = false);
  }

  int _roundUp(Money m) => math.max(_step, ((m.paise / 100) / _step).ceil() * _step);

  void _try(Money m) {
    HapticFeedback.selectionClick();
    setState(() => _monthly = _roundUp(m));
  }

  /// Plan (else recent average) against what the date needs.
  (String, Color?) _verdict(BuildContext context) {
    final g = widget.progress;
    final c = context.ink;
    final plan = g.goal.plannedMonthlyContribution;
    final rate = plan ?? g.averageMonthlyContribution;
    final has = rate != null && rate.isPositive;
    final need = g.requiredMonthly;
    final date = g.goal.targetDate;
    final which = plan != null ? 'Your plan' : 'Your average';
    if (date == null || need == null) {
      return ('No target date. Move the slider to see when you would finish.', null);
    }
    if (!has) return ('${goalMoney(context, need)} a month gets you there by ${goalMonth.format(date)}.', null);
    if (rate >= need) {
      return ('$which of ${goalMoney(context, rate)} a month covers the ${goalMoney(context, need)} needed.', null);
    }
    return ('You need ${goalMoney(context, need)} a month. $which is ${goalMoney(context, rate)}.', c.amber);
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.progress;
    final c = context.ink;
    final t = context.type;
    final date = g.goal.targetDate;
    final rate = Money.rupees(_monthly);
    final finish = finishWith(g.remaining, rate, widget.today);
    final plan = g.goal.plannedMonthlyContribution;
    final need = g.requiredMonthly;
    final avg = g.averageMonthlyContribution;
    final max = _max;
    final value = _monthly.clamp(_step, max);
    final (verdict, tone) = _verdict(context);

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
    Widget money(Money? m, String empty) => m == null
        ? Text(empty, style: t.figure.copyWith(color: c.inkSoft))
        : AmountText(m, style: t.figure, decimals: DecimalDisplay.none);
    bool at(Money? m) => m != null && _roundUp(m) == value;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(verdict, style: t.body.copyWith(color: tone)),
        const SizedBox(height: Sp.xl),
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
            activeTrackColor: c.ink,
            inactiveTrackColor: c.sunken,
            thumbColor: c.ink,
            overlayColor: c.ink.withValues(alpha: 0.08),
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
        Text(whatIf(), style: t.bodyStrong.copyWith(color: late ? c.amber : null)),
        const SizedBox(height: Sp.xl),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: LedgerStat(
                label: 'Needed',
                value: money(need, '—'),
                selected: at(need),
                semanticLabel: need == null ? null : 'Needed, ${goalMoney(context, need)} a month. Try this amount',
                onTap: need == null ? null : () => _try(need),
              ),
            ),
            const SizedBox(width: Sp.md),
            Expanded(
              // Tappable stats carry vertical padding; match it so labels line up.
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: Sp.xs),
                child: LedgerStat(label: 'Your average', value: money(avg, '—')),
              ),
            ),
            const SizedBox(width: Sp.md),
            Expanded(
              child: LedgerStat(
                label: 'Plan',
                value: money(plan, 'Not set'),
                selected: at(plan),
                semanticLabel: plan == null ? null : 'Plan, ${goalMoney(context, plan)} a month. Try this amount',
                onTap: plan == null ? null : () => _try(plan),
              ),
            ),
          ],
        ),
        if (plan != rate && g.goal.status == GoalStatus.active) ...[
          const SizedBox(height: Sp.lg),
          LedgerButton(
            key: const ValueKey('goal-use-plan'),
            label: 'Make it my plan',
            variant: LedgerButtonVariant.secondary,
            expand: true,
            loading: _saving,
            onPressed: _saving ? null : _usePlan,
          ),
        ],
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
          ? Text('No money added yet. Your first contribution will show here.', style: t.label)
          : LedgerPanel(
              children: [
                for (final e in groups.entries) ...[
                  // Month header inside the one panel: month and its net.
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
