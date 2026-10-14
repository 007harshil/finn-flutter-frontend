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
import '../../../core/time/dates.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/presentation/action_runner.dart';
import '../../../shared/presentation/async_view.dart';
import '../../../shared/presentation/category_icons.dart';
import '../application/goal_actions.dart';
import '../application/goal_view.dart';
import '../domain/goal.dart';
import 'savings_visuals.dart';
import 'savings_widgets.dart';

/// One savings goal: a milestone ring (with a "where you should be" notch),
/// add / withdraw, the path to the target with a live "what if I add more"
/// slider, the saved-over-time chart and the history.
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
    return Scaffold(
      appBar: AppBar(
        title: Text(g?.goal.name ?? 'Goal', maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (g != null) ...[
            FinnIconButton(
              icon: LucideIcons.pencil,
              tooltip: 'Edit goal',
              onPressed: () => context.push(AppRoutes.editGoal(id)),
            ),
            FinnIconButton(
              key: const ValueKey('goal-more'),
              icon: LucideIcons.ellipsisVertical,
              tooltip: 'More actions',
              onPressed: () => _menu(context, ref, g),
            ),
          ],
          const SizedBox(width: Space.x2),
        ],
      ),
      body: AsyncView<GoalProgress?>(
        value: value,
        loading: const SkeletonPulse(
          child: Padding(
            padding: EdgeInsets.all(Space.gutter),
            child: Column(children: [CardSkeleton(height: 240), SizedBox(height: Space.x4), CardSkeleton(height: 220)]),
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

class _GoalBody extends ConsumerWidget {
  const _GoalBody({required this.progress});

  final GoalProgress progress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = progress;
    final today = ref.watch(todayProvider);
    final accent = AccentSwatches.solid(g.goal.colorIndex);
    final growth = savedOverTime(g.movements);
    Widget box(Widget child, {double top = Space.x3}) => SliverToBoxAdapter(
          child: ResponsiveCenter(padding: EdgeInsets.fromLTRB(Space.gutter, top, Space.gutter, 0), child: child),
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
        box(StaggeredEntrance(child: _HeroCard(progress: g, today: today)), top: Space.x2),
        if (!g.isAchieved) box(StaggeredEntrance(index: 1, child: _PathCard(progress: g, today: today))),
        if (growth.length >= 2)
          box(
            StaggeredEntrance(
              index: 2,
              child: FinnCard(
                radius: Radii.xxl,
                padding: const EdgeInsets.fromLTRB(Space.x4, Space.x3, Space.x4, Space.x3),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text('SAVED OVER TIME', style: context.text.eyebrow)),
                        Text('dashed = target', style: context.text.micro),
                      ],
                    ),
                    const SizedBox(height: Space.x2),
                    SavedGrowthChart(
                      points: growth,
                      target: g.goal.target,
                      color: accent,
                      today: today,
                      targetDate: g.goal.targetDate,
                    ),
                  ],
                ),
              ),
            ),
          ),
        box(
          SavingsHistory(
            movements: g.movements,
            accent: accent,
            emptyText: 'No money added yet. Your first contribution will show here.',
          ),
          top: Space.section,
        ),
        SliverToBoxAdapter(child: SizedBox(height: Space.x12 + context.safeBottom)),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Hero
// ---------------------------------------------------------------------------

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.progress, required this.today});

  final GoalProgress progress;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final g = progress;
    final c = context.colors;
    final t = context.text;
    final pace = goalPaceOf(g);
    final active = g.goal.status == GoalStatus.active;
    final date = g.goal.targetDate;
    final expected = active && !g.isAchieved ? expectedShare(g, today) : null;
    final months = date == null ? null : monthsUntil(today, date);
    return FinnCard(
      radius: Radii.xxl,
      padding: const EdgeInsets.all(Space.x4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  GoalRing(
                    progress: g.progress,
                    colors: AccentSwatches.of(g.goal.colorIndex),
                    expected: expected,
                    size: 136,
                    semanticsLabel: '${g.goal.name}, ${formatPct(g.progress)} saved'
                        '${expected == null ? '' : '. By now you planned ${formatPct(expected)}'}',
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (g.isAchieved) ...[
                          const SuccessCheck(size: 30),
                          const SizedBox(height: Space.x1),
                        ],
                        AnimatedAmount(g.saved, style: t.amountMedium, animateOnMount: true),
                        Text('of ${savingsMoney(context, g.goal.target)}', style: t.micro),
                      ],
                    ),
                  ),
                  if (g.isAchieved && !context.reduceMotion)
                    const IgnorePointer(child: SizedBox.square(dimension: 136, child: _Confetti())),
                ],
              ),
              const SizedBox(width: Space.x4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(CategoryIcons.of(g.goal.category.iconKey), size: 13, color: c.textTertiary),
                        const SizedBox(width: Space.x1),
                        Text(g.goal.category.label, style: t.micro),
                      ],
                    ),
                    const SizedBox(height: Space.x2),
                    if (g.isAchieved) ...[
                      Text('GOAL REACHED', style: t.eyebrow.copyWith(color: c.positive)),
                      Text('Well done!', style: t.title),
                    ] else ...[
                      Text('TO GO', style: t.eyebrow),
                      AmountText(g.remaining, style: t.amountLarge, fit: true),
                    ],
                    const SizedBox(height: Space.x1),
                    Text(
                      date == null
                          ? 'No target date'
                          : 'by ${DateFormats.monthYear.format(date)}'
                              '${g.isAchieved || months == null ? '' : ' · ${months == 0 ? 'this month' : '$months mo left'}'}',
                      style: t.caption,
                    ),
                    const SizedBox(height: Space.x2),
                    StatusPill(label: pace.label, color: pace.color(c), icon: pace.icon),
                  ],
                ),
              ),
            ],
          ),
          if (expected != null) ...[
            const SizedBox(height: Space.x2),
            Row(
              children: [
                Container(width: 2, height: 10, color: c.textPrimary),
                const SizedBox(width: Space.x1_5),
                Expanded(
                  child: Text(
                    'Notch = where your date says you should be (${formatPct(expected)}). Dots mark 25 · 50 · 75%.',
                    style: t.micro,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: Space.x3),
          Row(
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
                  onPressed:
                      active && g.saved.isPositive ? () => context.push(AppRoutes.goalWithdraw(g.goal.id)) : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One finite burst for a reached goal.
class _Confetti extends StatelessWidget {
  const _Confetti();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final colors = [c.positive, c.accentGoals, c.warning, c.primary, c.accentEmergency];
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 1600),
      builder: (context, t, _) => CustomPaint(painter: _ConfettiPainter(t: t, colors: colors)),
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  const _ConfettiPainter({required this.t, required this.colors});

  final double t;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    if (t >= 1) return;
    final center = size.center(Offset.zero);
    final rnd = math.Random(7);
    final ease = Curves.easeOutCubic.transform(t);
    for (var i = 0; i < 26; i++) {
      final a = rnd.nextDouble() * 2 * math.pi;
      final dist = size.width * (0.35 + rnd.nextDouble() * 0.45) * ease;
      final p = center + Offset(math.cos(a), math.sin(a)) * dist + Offset(0, 40 * t * t);
      final paint = Paint()..color = colors[i % colors.length].withValues(alpha: (1 - t).clamp(0.0, 1.0));
      canvas.save();
      canvas.translate(p.dx, p.dy);
      canvas.rotate(a + t * 6);
      canvas.drawRRect(
        RRect.fromRectAndRadius(const Rect.fromLTWH(-3, -1.5, 6, 3), const Radius.circular(1)),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.t != t;
}

// ---------------------------------------------------------------------------
// Path to the goal
// ---------------------------------------------------------------------------

class _PathCard extends ConsumerStatefulWidget {
  const _PathCard({required this.progress, required this.today});

  final GoalProgress progress;
  final DateTime today;

  @override
  ConsumerState<_PathCard> createState() => _PathCardState();
}

class _PathCardState extends ConsumerState<_PathCard> {
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
  void didUpdateWidget(_PathCard old) {
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

  @override
  Widget build(BuildContext context) {
    final g = widget.progress;
    final today = widget.today;
    final c = context.colors;
    final t = context.text;
    final accent = AccentSwatches.solid(g.goal.colorIndex);
    final date = g.goal.targetDate;
    final rate = Money.rupees(_monthly);
    final finish = finishWith(g.remaining, rate, today);
    final plan = g.goal.plannedMonthlyContribution;
    final max = _max;
    final value = _monthly.clamp(_step, max);

    // The honest current estimate (plan, else recent average).
    final current = g.estimatedCompletion;
    final (String verdict, Color tone) = switch (g.onTrack) {
      true when date != null && current != null => (_timing(monthsApart(date, current), early: true), c.positive),
      false when date != null && current != null => (_timing(monthsApart(current, date), early: false), c.warning),
      _ when current != null => ('Done around ${DateFormats.monthYear.format(current)} at your current pace', c.textPrimary),
      _ => ('Set a monthly amount to see when you finish', c.textSecondary),
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
    return FinnCard(
      radius: Radii.xxl,
      padding: const EdgeInsets.fromLTRB(Space.x4, Space.x3, Space.x4, Space.x4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('PATH TO YOUR GOAL', style: t.eyebrow),
          const SizedBox(height: Space.x1),
          Text(verdict, style: t.bodyStrong.copyWith(color: tone)),
          const SizedBox(height: Space.x3),
          _PathLine(
            start: g.goal.createdAt,
            today: today,
            target: date,
            finish: finish,
            color: accent,
          ),
          const SizedBox(height: Space.x3),
          const FinnDivider(),
          const SizedBox(height: Space.x2_5),
          Row(
            children: [
              Flexible(child: Text('WHAT IF I PUT IN', maxLines: 1, overflow: TextOverflow.ellipsis, style: t.eyebrow)),
              const Spacer(),
              Text(
                '${savingsMoney(context, rate)}/mo',
                style: t.bodyStrong.copyWith(fontWeight: FontWeight.w900, color: accent),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: accent,
              thumbColor: accent,
              inactiveTrackColor: accent.withValues(alpha: 0.18),
              overlayColor: accent.withValues(alpha: 0.12),
              trackHeight: 6,
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
          Row(
            children: [
              Icon(late ? LucideIcons.clock : LucideIcons.flag, size: 14, color: late ? c.warning : c.positive),
              const SizedBox(width: Space.x1_5),
              Expanded(
                child: Text(
                  whatIf(),
                  style: t.label.copyWith(fontWeight: FontWeight.w800, color: late ? c.warning : c.textPrimary),
                ),
              ),
              if (plan != rate && g.goal.status == GoalStatus.active)
                FinnButton(
                  key: const ValueKey('goal-use-plan'),
                  label: 'Make it my plan',
                  size: FinnButtonSize.sm,
                  variant: FinnButtonVariant.secondary,
                  loading: _saving,
                  onPressed: _saving ? null : _usePlan,
                ),
            ],
          ),
          const SizedBox(height: Space.x3),
          Row(
            children: [
              _Mini(
                label: 'NEEDED',
                value: g.requiredMonthly == null ? '—' : '${savingsMoney(context, g.requiredMonthly!)}/mo',
                onTap: g.requiredMonthly == null
                    ? null
                    : () => setState(() => _monthly = _roundUp(g.requiredMonthly!)),
              ),
              _Mini(
                label: 'YOUR AVERAGE',
                value: g.averageMonthlyContribution == null
                    ? '—'
                    : '${savingsMoney(context, g.averageMonthlyContribution!)}/mo',
              ),
              _Mini(
                label: 'PLAN',
                value: plan == null ? 'Not set' : '${savingsMoney(context, plan)}/mo',
                onTap: plan == null ? null : () => setState(() => _monthly = _roundUp(plan)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  int _roundUp(Money m) => math.max(_step, ((m.paise / 100) / _step).ceil() * _step);

  String _timing(int months, {required bool early}) => switch (months) {
        0 => 'On track — right on time',
        1 => early ? 'On track — about a month early' : 'Behind — about a month late',
        _ => early ? 'On track — about $months months early' : 'Behind — about $months months late',
      };
}

class _Mini extends StatelessWidget {
  const _Mini({required this.label, required this.value, this.onTap});

  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.text;
    final c = context.colors;
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, maxLines: 1, style: t.eyebrow.copyWith(fontSize: 10)),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            maxLines: 1,
            style: t.label.copyWith(fontWeight: FontWeight.w800, color: onTap == null ? c.textPrimary : c.primary),
          ),
        ),
      ],
    );
    return Expanded(
      child: Semantics(
        button: onTap != null,
        hint: onTap == null ? null : 'Try this amount',
        child: InkWell(
          borderRadius: Radii.rMd,
          onTap: onTap,
          child: Padding(padding: const EdgeInsets.symmetric(vertical: Space.x1, horizontal: 2), child: body),
        ),
      ),
    );
  }
}

/// Timeline from the day the goal began to whichever comes last of its
/// target date and the finish date at the chosen monthly amount. The gap
/// between target and a later finish is shown in warning colour. The
/// finish marker glides as the slider moves.
class _PathLine extends StatelessWidget {
  const _PathLine({required this.start, required this.today, required this.target, required this.finish, required this.color});

  final DateTime start;
  final DateTime today;
  final DateTime? target;
  final DateTime? finish;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    var end = today.add(const Duration(days: 30));
    for (final d in [target, finish]) {
      if (d != null && d.isAfter(end)) end = d;
    }
    final span = math.max(1, daysBetween(start, end)).toDouble();
    double at(DateTime d) => (daysBetween(start, d) / span).clamp(0.0, 1.0);
    return Semantics(
      label: [
        'Today',
        if (target != null) 'target ${DateFormats.monthYear.format(target!)}',
        if (finish != null) 'finish ${DateFormats.monthYear.format(finish!)}',
      ].join(', '),
      excludeSemantics: true,
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: finish == null ? 1 : at(finish!)),
        duration: context.motion.slow,
        curve: Curves2.emphasized,
        builder: (context, f, _) => CustomPaint(
          size: const Size(double.infinity, 52),
          painter: _PathPainter(
            today: at(today),
            target: target == null ? null : at(target!),
            finish: finish == null ? null : f,
            startLabel: DateFormats.shortMonthYear.format(start),
            targetLabel: target == null ? null : 'Target ${DateFormats.shortMonthYear.format(target!)}',
            finishLabel: finish == null ? null : 'Done ${DateFormats.shortMonthYear.format(finish!)}',
            color: color,
            late: c.warning,
            track: c.surfaceMuted,
            ink: c.textPrimary,
            muted: c.textTertiary,
            labelStyle: t.micro,
          ),
        ),
      ),
    );
  }
}

class _PathPainter extends CustomPainter {
  const _PathPainter({
    required this.today,
    required this.target,
    required this.finish,
    required this.startLabel,
    required this.targetLabel,
    required this.finishLabel,
    required this.color,
    required this.late,
    required this.track,
    required this.ink,
    required this.muted,
    required this.labelStyle,
  });

  final double today;
  final double? target;
  final double? finish;
  final String startLabel;
  final String? targetLabel;
  final String? finishLabel;
  final Color color;
  final Color late;
  final Color track;
  final Color ink;
  final Color muted;
  final TextStyle labelStyle;

  void _label(Canvas canvas, String s, double x, double y, double w, {Color? color, bool bold = false}) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: labelStyle.copyWith(color: color ?? muted, fontWeight: bold ? FontWeight.w800 : null)),
      textDirection: TextDirection.ltr,
    )..layout();
    final dx = (x - tp.width / 2).clamp(0.0, math.max(0.0, w - tp.width)).toDouble();
    tp.paint(canvas, Offset(dx, y));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    const lineY = 22.0;
    const bar = 6.0;
    double x(double v) => v * w;
    final rr = RRect.fromRectAndRadius(Rect.fromLTWH(0, lineY - bar / 2, w, bar), const Radius.circular(bar / 2));
    canvas.drawRRect(rr, Paint()..color = track);

    // Travelled so far.
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(0, lineY - bar / 2, x(today), bar), const Radius.circular(bar / 2)),
      Paint()..color = color,
    );
    // Planned stretch to the finish.
    final f = finish;
    if (f != null && f > today) {
      final p = Paint()
        ..color = color.withValues(alpha: 0.55)
        ..strokeWidth = bar
        ..strokeCap = StrokeCap.round;
      for (var d = x(today) + 4.0; d < x(f); d += 10) {
        canvas.drawLine(Offset(d, lineY), Offset(math.min(d + 4, x(f)), lineY), p);
      }
    }
    // Late gap.
    final tg = target;
    if (tg != null && f != null && f > tg) {
      canvas.drawRect(Rect.fromLTRB(x(tg), lineY - bar / 2, x(f), lineY + bar / 2), Paint()..color = late.withValues(alpha: 0.45));
    }

    // Target flag above the line.
    if (tg != null) {
      final tx = x(tg);
      canvas.drawLine(Offset(tx, 4), Offset(tx, lineY + bar), Paint()
        ..color = ink
        ..strokeWidth = 1.6);
      final flag = Path()
        ..moveTo(tx, 4)
        ..lineTo(tx + 9, 7.5)
        ..lineTo(tx, 11)
        ..close();
      canvas.drawPath(flag, Paint()..color = ink);
    }
    // Today dot.
    canvas.drawCircle(Offset(x(today), lineY), 5.5, Paint()..color = ink);
    canvas.drawCircle(Offset(x(today), lineY), 2.5, Paint()..color = track);
    // Finish marker.
    if (f != null) {
      final fx = x(f);
      final c = tg != null && f > tg ? late : color;
      canvas.drawCircle(Offset(fx, lineY), 8, Paint()..color = c.withValues(alpha: 0.25));
      canvas.drawCircle(Offset(fx, lineY), 5, Paint()..color = c);
    }

    // Labels: start + today under the line at the left, target and finish
    // under their markers (target above when the two would collide).
    const below = lineY + 10;
    _label(canvas, startLabel, 0, below, w);
    final fl = finishLabel;
    if (f != null && fl != null) _label(canvas, fl, x(f), below, w, color: ink, bold: true);
    final tl = targetLabel;
    if (tg != null && tl != null) {
      final collide = f != null && (x(f) - x(tg)).abs() < 80;
      if (collide) {
        _label(canvas, tl, x(tg) + 46, 0, w, color: ink);
      } else {
        _label(canvas, tl, x(tg), below, w, color: ink);
      }
    }
  }

  @override
  bool shouldRepaint(_PathPainter old) =>
      old.today != today ||
      old.target != target ||
      old.finish != finish ||
      old.finishLabel != finishLabel ||
      old.color != color ||
      old.ink != ink;
}
