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
import '../../../design_system/design_system.dart'
    show AmountVisibility, AnimatedAmount, BottomClearanceX, FinnMenuItem, showFinnActionMenu;
import '../../../shared/presentation/action_runner.dart';
import '../../../shared/presentation/async_view.dart';
import '../../../ui/ui.dart';
import '../application/goal_actions.dart';
import '../application/goal_view.dart';
import '../domain/goal.dart';
import 'goal_ui.dart';
import 'savings_widgets.dart';

/// One savings goal: what is saved and what is left, add / withdraw, the
/// monthly plan with a live "what if I put in more" slider, and the
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
    return UiPage(
      title: g?.goal.name ?? 'Goal',
      actions: [
        if (g != null) ...[
          UiIconButton(
            icon: LucideIcons.pencil,
            tooltip: 'Edit goal',
            size: 20,
            onPressed: () => context.push(AppRoutes.editGoal(id)),
          ),
          UiIconButton(
            key: const ValueKey('goal-more'),
            icon: LucideIcons.ellipsis,
            tooltip: 'More actions',
            onPressed: () => _menu(context, ref, g),
          ),
        ],
      ],
      body: AsyncView<GoalProgress?>(
        value: value,
        loading: const _Placeholder(),
        builder: (context, g) => g == null
            ? Center(
                child: SingleChildScrollView(
                  child: UiEmpty(
                    icon: LucideIcons.target,
                    title: 'Goal not found',
                    message: 'It may have been deleted.',
                    action: 'Back to goals',
                    onAction: () => context.go(AppRoutes.goals),
                  ),
                ),
              )
            : _GoalBody(progress: g),
      ),
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
    final archived = g.goal.status == GoalStatus.archived;
    Widget box(Widget child, {double top = 0}) => SliverPadding(
      padding: EdgeInsets.fromLTRB(UiSpace.gutter, top, UiSpace.gutter, 0),
      sliver: SliverToBoxAdapter(child: UiColumnWidth(child: child)),
    );
    final movements = g.movements;
    return CustomScrollView(
      key: PageStorageKey('goal-${g.goal.id}'),
      slivers: [
        if (archived) box(const UiNotice(icon: LucideIcons.archive, text: 'Archived · restore it to add or withdraw')),
        box(UiReveal(index: 0, child: _Hero(progress: g)), top: UiSpace.sm),
        if (!g.isAchieved)
          box(
            UiReveal(
              index: 1,
              child: UiSection(title: 'Plan', child: _PlanPanel(progress: g, today: today)),
            ),
            top: UiSpace.sm,
          ),
        box(
          UiSection(
            title: 'History',
            child: movements.isEmpty
                ? const UiNotice(icon: LucideIcons.inbox, text: 'No money added yet')
                : UiPanelList(
                    ruleIndent: 60,
                    children: [
                      for (final m in movements) SavingsMovementRow(key: ValueKey(m.id), movement: m),
                    ],
                  ),
          ),
          top: UiSpace.sm,
        ),
        SliverToBoxAdapter(child: SizedBox(height: context.bottomClearance)),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Hero
// ---------------------------------------------------------------------------

/// Saved so far, what is left and by when, progress to the target, and the
/// two money actions.
class _Hero extends StatelessWidget {
  const _Hero({required this.progress});

  final GoalProgress progress;

  @override
  Widget build(BuildContext context) {
    final c = UiColors.of(context);
    final t = UiType.of(context);
    final g = progress;
    final pace = goalPaceOf(g);
    final active = g.goal.status == GoalStatus.active;
    final date = g.goal.targetDate;
    final caption = g.isAchieved
        ? 'Goal reached'
        : [
            '${savingsMoney(context, g.remaining)} to go',
            if (date != null) 'by ${DateFormats.monthYear.format(date)}',
          ].join(' · ');
    return UiHero(
      label: 'Saved',
      labelTrailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(pace.icon, size: 14, color: pace.color(c)),
          const SizedBox(width: 4),
          Text(pace.label, style: t.label.copyWith(color: pace == GoalPace.behind ? c.warning : null)),
        ],
      ),
      value: AnimatedAmount(g.saved, style: t.amount, decimals: DecimalDisplay.none, fit: true, animateOnMount: true),
      caption: caption,
      captionColor: g.isAchieved ? c.positive : null,
      footer: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          UiProgressFooter(
            value: g.progress,
            color: g.isAchieved ? c.positive : c.goals,
            start: formatPct(g.progress),
            end: 'of ${savingsMoney(context, g.goal.target)}',
            semanticsLabel: 'Saved towards target',
          ),
          if (active) ...[
            const SizedBox(height: UiSpace.xl),
            Row(
              children: [
                Expanded(
                  child: UiPrimaryButton(
                    label: 'Add money',
                    icon: LucideIcons.plus,
                    onPressed: () => context.push(AppRoutes.goalContribute(g.goal.id)),
                  ),
                ),
                const SizedBox(width: UiSpace.md),
                Expanded(
                  child: UiSecondaryButton(
                    label: 'Withdraw',
                    icon: LucideIcons.minus,
                    onPressed: g.saved.isPositive ? () => context.push(AppRoutes.goalWithdraw(g.goal.id)) : null,
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

// ---------------------------------------------------------------------------
// Plan
// ---------------------------------------------------------------------------

/// Where the goal is heading, a slider to try another monthly amount (and
/// keep it as the plan), and the three amounts worth comparing.
class _PlanPanel extends ConsumerStatefulWidget {
  const _PlanPanel({required this.progress, required this.today});

  final GoalProgress progress;
  final DateTime today;

  @override
  ConsumerState<_PlanPanel> createState() => _PlanPanelState();
}

class _PlanPanelState extends ConsumerState<_PlanPanel> {
  static const _step = 500;

  late int _monthly = _initial();
  bool _saving = false;

  /// Starting point for the slider, in whole rupees.
  int _initial() {
    final g = widget.progress;
    final m =
        g.goal.plannedMonthlyContribution ??
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
  void didUpdateWidget(_PlanPanel old) {
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

  String _timing(int months, {required bool early}) => switch (months) {
    0 => 'On track · right on time',
    1 => early ? 'On track · about a month early' : 'Behind · about a month late',
    _ => early ? 'On track · about $months months early' : 'Behind · about $months months late',
  };

  @override
  Widget build(BuildContext context) {
    final c = UiColors.of(context);
    final t = UiType.of(context);
    final g = widget.progress;
    final date = g.goal.targetDate;
    final rate = Money.rupees(_monthly);
    final finish = finishWith(g.remaining, rate, widget.today);
    final plan = g.goal.plannedMonthlyContribution;
    final max = _max;
    final value = _monthly.clamp(_step, max);

    // The honest current estimate (plan, else recent average).
    final current = g.estimatedCompletion;
    final (String verdict, Color? tone) = switch (g.onTrack) {
      true when date != null && current != null => (_timing(monthsApart(date, current), early: true), c.positive),
      false when date != null && current != null => (_timing(monthsApart(current, date), early: false), c.warning),
      _ when current != null => ('Done around ${DateFormats.monthYear.format(current)} at your pace', null),
      _ => ('Set a monthly amount to see when you finish', c.inkSoft),
    };

    String whatIf() {
      if (finish == null) return 'Too slow to estimate';
      final base = 'Done by ${DateFormats.monthYear.format(finish)}';
      if (date == null) return base;
      final diff = monthsApart(date, finish);
      return switch (diff) {
        0 => '$base · right on time',
        > 0 => '$base · $diff mo early',
        _ => '$base · ${-diff} mo late',
      };
    }

    final late = finish != null && date != null && finish.isAfter(date);
    String perMonth(Money? m) => m == null
        ? '—'
        : '${AmountVisibility.hiddenOf(context) ? MoneyFormatter.masked : m.whole}/mo';
    return UiPanel(
      padding: const EdgeInsets.fromLTRB(UiSpace.lg, UiSpace.lg, UiSpace.lg, UiSpace.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(verdict, style: t.body.copyWith(color: tone)),
          const SizedBox(height: UiSpace.lg),
          Row(
            children: [
              Expanded(child: Text('If I put in', style: t.label)),
              Text('${savingsMoney(context, rate)}/mo', style: t.figureSmall),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: c.goals,
              thumbColor: c.goals,
              inactiveTrackColor: c.muted,
              overlayColor: c.goals.withValues(alpha: 0.12),
              trackHeight: 4,
              tickMarkShape: SliderTickMarkShape.noTickMark,
              showValueIndicator: ShowValueIndicator.never,
            ),
            child: Slider(
              key: const ValueKey('goal-whatif-slider'),
              value: value.toDouble(),
              min: _step.toDouble(),
              max: max.toDouble(),
              divisions: ((max - _step) / _step).round().clamp(1, 400),
              semanticFormatterCallback: (v) => '${savingsMoney(context, Money.rupees(v.round()))} a month. ${whatIf()}',
              onChanged: (v) {
                final next = v.round();
                if (next != _monthly) HapticFeedback.selectionClick();
                setState(() => _monthly = next);
              },
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: UiSpace.touch),
            child: Row(
              children: [
                Icon(late ? LucideIcons.clock : LucideIcons.flag, size: 14, color: late ? c.warning : c.inkSoft),
                const SizedBox(width: UiSpace.sm),
                Expanded(
                  child: Text(whatIf(), style: t.label.copyWith(color: late ? c.warning : c.ink)),
                ),
                if (plan != rate && g.goal.status == GoalStatus.active)
                  UiChipButton(
                    key: const ValueKey('goal-use-plan'),
                    label: _saving ? 'Saving…' : 'Make it my plan',
                    onTap: _saving ? () {} : _usePlan,
                  ),
              ],
            ),
          ),
          Container(height: 1, color: c.hairline),
          Row(
            children: [
              Expanded(
                child: UiStat(
                  label: 'Needed',
                  value: Text(perMonth(g.requiredMonthly), style: t.figureSmall),
                  semanticLabel: 'Needed ${perMonth(g.requiredMonthly)}. Try this amount',
                  onTap: g.requiredMonthly == null
                      ? null
                      : () => setState(() => _monthly = _roundUp(g.requiredMonthly!)),
                ),
              ),
              Expanded(
                child: UiStat(
                  label: 'Your average',
                  value: Text(perMonth(g.averageMonthlyContribution), style: t.figureSmall),
                ),
              ),
              Expanded(
                child: UiStat(
                  label: 'Plan',
                  value: Text(plan == null ? 'Not set' : perMonth(plan), style: t.figureSmall),
                  semanticLabel: plan == null ? null : 'Plan ${perMonth(plan)}. Try this amount',
                  onTap: plan == null ? null : () => setState(() => _monthly = _roundUp(plan)),
                ),
              ),
            ],
          ),
        ],
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
            SizedBox(height: UiSpace.xl),
            UiPlaceholder(height: 6),
            SizedBox(height: UiSpace.section),
            UiPlaceholder(height: 220, radius: UiRadius.panel),
          ],
        ),
      ),
    );
  }
}
