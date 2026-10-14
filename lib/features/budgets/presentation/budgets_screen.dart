import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/di/data_providers.dart';
import '../../../app/router/routes.dart';
import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/result/result.dart';
import '../../../core/time/dates.dart';
import '../../../design_system/design_system.dart';
import '../../../design_system/luxe/luxe.dart';
import '../../../shared/presentation/action_runner.dart';
import '../../../shared/presentation/category_icons.dart';
import '../../../shared/presentation/luxe_page.dart';
import '../application/budget_actions.dart';
import '../application/budget_view.dart';
import 'budget_widgets.dart';

/// Budgets: "can I keep spending like this?" answered by one dial, then
/// every budget as a calm line, most urgent first.
///
/// Top to bottom: title and "New budget", the month (past months are
/// read-only), the month dial (left to spend in the centre; the arc is what
/// is spent, the ghost arc where spending is heading, the gold tick is
/// today), three figures and status shortcuts, a pinned bar of status tabs
/// with sort & filter, then the budgets.
class BudgetsScreen extends ConsumerStatefulWidget {
  const BudgetsScreen({super.key});

  @override
  ConsumerState<BudgetsScreen> createState() => _BudgetsScreenState();
}

class _BudgetsScreenState extends ConsumerState<BudgetsScreen> {
  BudgetListFilter _filter = const BudgetListFilter();

  /// Budget month shown; null = this month. Past months are read-only.
  MonthKey? _month;

  void _set(BudgetListFilter f) => setState(() => _filter = f);

  void _setMonth(MonthKey m, MonthKey current) => setState(() {
    _month = m >= current ? null : m;
    _filter = _filter.copyWith(state: () => null);
  });

  void _toggleState(BudgetState s) => _set(_filter.copyWith(state: () => _filter.state == s ? null : s));

  Future<void> _openOptions() async {
    final next = await showLuxeSheet<BudgetListFilter>(context, builder: (_) => _OptionsSheet(initial: _filter));
    if (next != null && mounted) _set(next);
  }

  Future<void> _quickActions(BudgetPace p) async {
    final b = p.usage.budget;
    final name = ref.read(categoryProvider(b.categoryId))?.name ?? 'Budget';
    final choice = await showLuxeMenu<int>(
      context,
      eyebrow: 'Budget',
      title: name,
      items: [
        const LuxeMenuItem(
          value: 0,
          label: 'Open details',
          icon: LucideIcons.arrowUpRight,
          hint: 'Daily burn and history',
        ),
        const LuxeMenuItem(value: 1, label: 'Change limit', icon: LucideIcons.pencil),
        LuxeMenuItem(
          value: 2,
          label: b.isPaused ? 'Resume tracking' : 'Pause tracking',
          icon: b.isPaused ? LucideIcons.play : LucideIcons.pause,
          hint: b.isPaused ? 'Count spending again' : 'Stop counting until resumed',
        ),
      ],
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 0:
        context.push(AppRoutes.budget(b.id));
      case 1:
        context.push(AppRoutes.editBudget(b.id));
      case 2:
        await runAction(
          context,
          ref,
          action: const SetBudgetPausedAction(),
          input: SetBudgetPausedInput(id: b.id, paused: !b.isPaused),
          idempotencyKey: newIdempotencyKey(),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(budgetsPulseProvider(_month));
    final o = value.value;
    final List<Widget> body;
    if (o == null) {
      if (value.hasError) {
        final e = value.error;
        body = [
          luxeBox(
            LuxeError(
              title: 'Could not load your budgets',
              message: e is AppFailure ? e.message : null,
              onRetry: () => refreshFinanceData(ref),
            ),
            top: 24,
          ),
        ];
      } else {
        body = [luxeBox(const _BudgetsSkeleton(), top: 8)];
      }
    } else {
      body = _content(context, o);
    }
    return LuxePage(
      storageKey: 'budgets',
      compactTitle: 'Budgets',
      slivers: [
        luxeBox(
          Reveal(
            child: _Header(pulse: o, onMonth: (m) => _setMonth(m, o!.currentMonth)),
          ),
          top: 4,
        ),
        ...body,
      ],
    );
  }

  List<Widget> _content(BuildContext context, BudgetsPulse o) {
    String name(BudgetPace p) => ref.read(categoryProvider(p.usage.budget.categoryId))?.name ?? '';
    final shown = filterBudgets(o.paces, _filter, name);
    if (o.paces.isEmpty) {
      return [
        luxeBox(
          o.isPast
              ? const LuxeEmpty(
                  icon: LucideIcons.calendarX,
                  title: 'No budgets this month',
                  message: 'None of your budgets existed yet in this month.',
                )
              : LuxeEmpty(
                  icon: LucideIcons.chartPie,
                  title: 'No budgets yet',
                  message:
                      'Set a monthly limit for a category like Food or Shopping. '
                      'Every expense in that category counts towards it automatically.',
                  actionLabel: 'Create a budget',
                  actionIcon: LucideIcons.plus,
                  onAction: () => context.push(AppRoutes.newBudget),
                ),
          top: 24,
        ),
      ];
    }
    return [
      if (o.hasTotals)
        luxeBox(
          Reveal(
            key: ValueKey('dial-${o.month}'),
            index: 1,
            child: _MonthDial(pulse: o, filter: _filter, onState: _toggleState),
          ),
          top: 18,
        ),
      PinnedHeaderSliver(
        child: _Controls(
          pulse: o,
          filter: _filter,
          onState: (s) => _set(_filter.copyWith(state: () => s)),
          onOptions: _openOptions,
        ),
      ),
      luxeBox(_ResultLine(count: shown.length, filter: _filter, onSort: _openOptions), top: 6),
      if (shown.isEmpty)
        luxeBox(
          LuxeEmpty(
            icon: LucideIcons.searchX,
            title: 'Nothing here',
            message: 'No budget matches this view.',
            actionLabel: 'Show all budgets',
            onAction: () => _set(const BudgetListFilter()),
          ),
          top: 8,
        )
      else
        SliverList.builder(
          itemCount: shown.length,
          itemBuilder: (context, i) {
            final p = shown[i];
            final id = p.usage.budget.id;
            final line = _BudgetLine(
              key: ValueKey(id),
              pace: p,
              past: o.isPast,
              onTap: () => context.push(AppRoutes.budget(id, month: o.isPast ? o.month : null)),
              onLongPress: o.isPast ? null : () => _quickActions(p),
            );
            return ResponsiveCenter(
              padding: const EdgeInsets.fromLTRB(LuxeSpace.gutter, 0, LuxeSpace.gutter, 10),
              child: i < 10
                  ? Reveal(key: ValueKey('r-$id-${o.month}'), index: i, offset: 14, blur: 0, child: line)
                  : line,
            );
          },
        ),
    ];
  }
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

/// Title, "New budget" (or "This month" when looking back), and the month.
class _Header extends StatelessWidget {
  const _Header({required this.pulse, required this.onMonth});

  final BudgetsPulse? pulse;
  final ValueChanged<MonthKey> onMonth;

  @override
  Widget build(BuildContext context) {
    final p = context.luxe;
    final t = context.lt;
    final o = pulse;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LuxeTopBar(
          actions: [
            if (o == null || !o.isPast)
              LuxeButton(
                label: 'New budget',
                icon: LucideIcons.plus,
                compact: true,
                onPressed: () => context.push(AppRoutes.newBudget),
              )
            else
              LuxeButton(
                key: const ValueKey('budget-this-month'),
                label: 'This month',
                icon: LucideIcons.calendarCheck,
                compact: true,
                variant: LuxeButtonVariant.outline,
                onPressed: () => onMonth(o.currentMonth),
              ),
          ],
        ),
        const SizedBox(height: 18),
        const LuxeTitle(eyebrow: 'Spending limits', title: 'Budgets'),
        if (o != null) ...[
          const SizedBox(height: 14),
          GestureDetector(
            onHorizontalDragEnd: (d) {
              final v = d.primaryVelocity ?? 0;
              if (v > 200 && o.month > o.firstMonth) onMonth(o.month.previous);
              if (v < -200 && o.month < o.currentMonth) onMonth(o.month.next);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              decoration: BoxDecoration(
                color: p.paper,
                borderRadius: BorderRadius.circular(26),
                border: Border.all(color: p.line),
              ),
              child: LuxeMonthStepper(
                month: o.month,
                min: o.firstMonth,
                max: o.currentMonth,
                compact: true,
                onChanged: onMonth,
              ),
            ),
          ),
          const SizedBox(height: 10),
          AnimatedSwitcher(
            duration: context.reduceMotion ? Duration.zero : LuxeDurations.quick,
            child: Row(
              key: ValueKey(o.month),
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(o.isPast ? LucideIcons.lock : LucideIcons.calendarDays, size: 12, color: p.inkMute),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    o.isPast
                        ? 'Read-only · ${periodLabel(o.period)}'
                        : '${periodLabel(o.period)} · ${daysLeftLabel(o.daysLeft)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.caption,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Month dial
// ---------------------------------------------------------------------------

class _MonthDial extends StatelessWidget {
  const _MonthDial({required this.pulse, required this.filter, required this.onState});

  final BudgetsPulse pulse;
  final BudgetListFilter filter;
  final ValueChanged<BudgetState> onState;

  @override
  Widget build(BuildContext context) {
    final p = context.luxe;
    final t = context.lt;
    final o = pulse;
    final past = o.isPast;
    final heading = o.projectedShare;
    final (String verdict, Color tone, IconData icon) = o.isOver
        ? (past ? 'Went over' : 'Over budget', p.negative, LucideIcons.triangleAlert)
        : !past && heading != null && heading > 1
        ? ('Spending fast', p.warning, LucideIcons.gauge)
        : (past ? 'Stayed within' : 'On pace', p.positive, LucideIcons.circleCheck);
    final safe = o.safePerDay;
    final arc = o.isOver ? p.negative : p.ink;
    final shortcuts = [
      for (final s in [BudgetState.over, BudgetState.risk, BudgetState.onTrack])
        if (o.count(s) > 0) s,
    ];
    final semantic = o.isOver
        ? 'Over budget by ${budgetMoney(context, -o.remaining)}'
        : '${budgetMoney(context, o.remaining)} left to spend of ${budgetMoney(context, o.limit)}. $verdict.';

    return LuxeCard(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            past ? 'LEFT UNSPENT THAT MONTH' : 'LEFT TO SPEND THIS MONTH',
            style: t.eyebrow,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          Semantics(
            label: semantic,
            excludeSemantics: true,
            child: Center(
              child: LayoutBuilder(
                builder: (context, box) {
                  final size = math.min(250.0, box.maxWidth);
                  return SizedBox(
                    width: size,
                    height: size * 0.86,
                    child: DrawIn(
                      value: 1,
                      duration: const Duration(milliseconds: 1500),
                      builder: (context, v) => CustomPaint(
                        painter: _DialPainter(
                          used: o.used * v,
                          projected: past ? null : (heading == null ? null : o.used + (heading - o.used) * v),
                          elapsed: past ? null : o.elapsed,
                          intro: v,
                          arc: arc,
                          ghost: o.isOver || (heading ?? 0) > 1 ? p.negative : p.inkSoft,
                          track: p.sunk,
                          tick: p.lineStrong,
                          today: p.gold,
                        ),
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(size * 0.2, size * 0.2, size * 0.2, size * 0.12),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (o.isOver) Text('Over by', style: t.caption.w(650).c(p.negative)),
                              LuxeAmount(
                                o.remaining.abs(),
                                style: t.display.copyWith(fontSize: 42, color: o.isOver ? p.negative : p.ink),
                                countFromZero: true,
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'of ${budgetMoney(context, o.limit)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: t.caption,
                              ),
                              const SizedBox(height: 10),
                              LuxeStatus(label: verdict, color: tone, icon: icon),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _Figure(label: 'Spent', value: _whole(context, o.spent)),
              ),
              _divider(p),
              Expanded(
                child: past
                    ? _Figure(label: 'Limit', value: _whole(context, o.limit))
                    : _Figure(
                        label: 'Safe per day',
                        value: safe == null ? '—' : _whole(context, safe),
                        hint: o.daysLeft > 0 ? '${o.daysLeft} ${o.daysLeft == 1 ? 'day' : 'days'} left' : null,
                      ),
              ),
              _divider(p),
              Expanded(
                child: _Figure(
                  label: past ? 'Result' : 'Heading for',
                  value: past
                      ? (o.isOver ? 'Over' : 'Within')
                      : (o.projected == null ? '—' : _whole(context, o.projected!)),
                  color: !past && (heading ?? 0) > 1 ? p.negative : null,
                ),
              ),
            ],
          ),
          if (!past) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(width: 2, height: 10, color: p.gold),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'Today · ${formatBps((o.elapsed * 10000).round(), decimals: 0)} of the month gone',
                    style: t.micro,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
          if (o.committed.isPositive) ...[
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(LucideIcons.repeat, size: 12, color: p.inkMute),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    '${budgetMoney(context, o.committed)} in subscriptions still to come',
                    style: t.micro,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
          if (shortcuts.isNotEmpty) ...[
            const SizedBox(height: 12),
            const LuxeHairline(),
            const SizedBox(height: 4),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var i = 0; i < shortcuts.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    Reveal(
                      index: i + 4,
                      offset: 0,
                      blur: 0,
                      scale: 0.8,
                      duration: LuxeDurations.base,
                      child: LuxeChip(
                        key: ValueKey('budget-attn:${shortcuts[i].name}'),
                        label: shortcuts[i].countLabel(o.count(shortcuts[i]), past: past),
                        dot: shortcuts[i].luxe(p),
                        height: 34,
                        selected: filter.state == shortcuts[i],
                        semanticLabel:
                            '${shortcuts[i].countLabel(o.count(shortcuts[i]), past: past)}. '
                            '${filter.state == shortcuts[i] ? 'Showing only these' : 'Show only these'}',
                        onTap: () => onState(shortcuts[i]),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _divider(LuxePalette p) => Container(width: 1, height: 34, color: p.line);
}

/// Whole rupees for headline figures (paise add noise, not information).
String _whole(BuildContext context, Money m) => AmountVisibility.hiddenOf(context)
    ? MoneyFormatter.masked
    : MoneyFormatter.format(m, decimals: DecimalDisplay.none);

class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.value, this.hint, this.color});

  final String label;
  final String value;
  final String? hint;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = context.lt;
    return MergeSemantics(
      child: Column(
        children: [
          Text(
            label.toUpperCase(),
            style: t.eyebrow.copyWith(fontSize: 9.5),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value, maxLines: 1, style: t.number.copyWith(color: color)),
          ),
          if (hint != null) Text(hint!, style: t.micro.copyWith(fontSize: 10), maxLines: 1),
        ],
      ),
    );
  }
}

/// 270° gauge: track with fine ticks, spent arc, hatched "heading for"
/// ghost arc and a gold "today" needle.
class _DialPainter extends CustomPainter {
  _DialPainter({
    required this.used,
    required this.projected,
    required this.elapsed,
    required this.intro,
    required this.arc,
    required this.ghost,
    required this.track,
    required this.tick,
    required this.today,
  });

  final double used;
  final double? projected;
  final double? elapsed;
  final double intro;
  final Color arc;
  final Color ghost;
  final Color track;
  final Color tick;
  final Color today;

  static const _start = math.pi * 0.75;
  static const _sweep = math.pi * 1.5;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2 - 14;
    final c = Offset(size.width / 2, size.width / 2);
    final rect = Rect.fromCircle(center: c, radius: r);
    const stroke = 10.0;

    // Ticks outside the ring.
    final tp = Paint()
      ..color = tick
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i <= 40; i++) {
      final a = _start + _sweep * i / 40;
      final major = i % 10 == 0;
      final r0 = r + stroke / 2 + 4;
      final r1 = r0 + (major ? 6 : 3);
      canvas.drawLine(c + Offset(math.cos(a), math.sin(a)) * r0, c + Offset(math.cos(a), math.sin(a)) * r1, tp);
    }

    canvas.drawArc(
      rect,
      _start,
      _sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = track,
    );

    final u = used.clamp(0.0, 1.0);
    final pr = projected;
    if (pr != null && pr > u) {
      final g = pr.clamp(0.0, 1.0);
      final path = Path()..addArc(rect, _start + _sweep * u, _sweep * (g - u));
      final dash = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = ghost.withValues(alpha: 0.28);
      for (final m in path.computeMetrics()) {
        for (var d = 0.0; d < m.length; d += 7) {
          canvas.drawPath(m.extractPath(d, math.min(d + 3, m.length)), dash);
        }
      }
    }

    if (u > 0.002) {
      canvas.drawArc(
        rect,
        _start,
        _sweep * u,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round
          ..shader = SweepGradient(
            startAngle: 0,
            endAngle: math.pi * 2,
            transform: const GradientRotation(_start - 0.1),
            colors: [arc.withValues(alpha: 0.55), arc, arc],
            stops: const [0, 0.5, 1],
          ).createShader(rect),
      );
    }

    final e = elapsed;
    if (e != null && e > 0 && e < 1) {
      final a = _start + _sweep * e;
      final dir = Offset(math.cos(a), math.sin(a));
      final o = Paint()
        ..color = today.withValues(alpha: intro)
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(c + dir * (r - stroke), c + dir * (r + stroke + 6), o);
      canvas.drawCircle(c + dir * (r + stroke + 9), 2.6, Paint()..color = today.withValues(alpha: intro));
    }
  }

  @override
  bool shouldRepaint(_DialPainter o) =>
      o.used != used || o.projected != projected || o.elapsed != elapsed || o.arc != arc || o.track != track;
}

extension _BudgetStateLuxe on BudgetState {
  Color luxe(LuxePalette p) => switch (this) {
    BudgetState.over => p.negative,
    BudgetState.risk => p.warning,
    BudgetState.onTrack => p.positive,
    BudgetState.paused => p.inkMute,
  };
}

// ---------------------------------------------------------------------------
// Pinned controls
// ---------------------------------------------------------------------------

class _Controls extends StatelessWidget {
  const _Controls({required this.pulse, required this.filter, required this.onState, required this.onOptions});

  final BudgetsPulse pulse;
  final BudgetListFilter filter;
  final ValueChanged<BudgetState?> onState;
  final VoidCallback onOptions;

  @override
  Widget build(BuildContext context) {
    final p = context.luxe;
    final counts = pulse.counts;
    final tabs = <(BudgetState?, String, int)>[
      (null, 'All', pulse.paces.length),
      for (final s in BudgetState.values)
        if ((counts[s] ?? 0) > 0 || filter.state == s) (s, s.labelFor(past: pulse.isPast), counts[s] ?? 0),
    ];
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: DecoratedBox(
          decoration: BoxDecoration(color: p.canvas.withValues(alpha: 0.86)),
          child: ResponsiveCenter(
            padding: const EdgeInsets.fromLTRB(LuxeSpace.gutter, 8, LuxeSpace.gutter - 4, 4),
            child: Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (var i = 0; i < tabs.length; i++) ...[
                          if (i > 0) const SizedBox(width: 6),
                          LuxeChip(
                            key: ValueKey('budget-tab:${tabs[i].$1?.name ?? 'all'}'),
                            label: tabs[i].$2,
                            count: tabs[i].$3,
                            dot: tabs[i].$1?.luxe(p),
                            selected: filter.state == tabs[i].$1,
                            onTap: filter.state == tabs[i].$1 ? () {} : () => onState(tabs[i].$1),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                LuxeIconButton(
                  key: const ValueKey('budget-options'),
                  icon: LucideIcons.slidersHorizontal,
                  tooltip: 'Sort & filter',
                  semanticLabel: filter.optionCount == 0
                      ? 'Sort & filter'
                      : 'Sort & filter, ${filter.optionCount} options changed',
                  active: filter.optionCount > 0,
                  badge: filter.optionCount,
                  onPressed: onOptions,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ResultLine extends StatelessWidget {
  const _ResultLine({required this.count, required this.filter, required this.onSort});

  final int count;
  final BudgetListFilter filter;
  final VoidCallback onSort;

  @override
  Widget build(BuildContext context) {
    final t = context.lt;
    final p = context.luxe;
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          Text('$count ${count == 1 ? 'BUDGET' : 'BUDGETS'}', style: t.eyebrow),
          const Spacer(),
          Flexible(
            child: Squish(
              onTap: onSort,
              semanticLabel: 'Sorted by ${filter.sort.label}. Change',
              excludeSemantics: true,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.arrowDownUp, size: 13, color: p.inkSoft),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        filter.sort.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.label.w(650),
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(LucideIcons.chevronDown, size: 14, color: p.inkSoft),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Budget line
// ---------------------------------------------------------------------------

/// One budget: category mark in a usage ring, name and spent, a pace line
/// (ghost = where it is heading, tick = today), one line of advice.
class _BudgetLine extends ConsumerWidget {
  const _BudgetLine({super.key, required this.pace, required this.onTap, this.onLongPress, this.past = false});

  final BudgetPace pace;
  final bool past;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.luxe;
    final t = context.lt;
    final pc = pace;
    final u = pc.usage;
    final category = ref.watch(categoryProvider(u.budget.categoryId));
    final name = category?.name ?? 'Deleted category';
    final paused = pc.state == BudgetState.paused;
    final color = pc.state.luxe(p);
    final accent = p.mute(AccentSwatches.solid(category?.colorIndex ?? 6));
    final hint = budgetHint(context, pc, past: past);
    return LuxeCard(
      radius: LuxeSpace.rTile,
      padding: const EdgeInsets.fromLTRB(14, 14, 16, 12),
      color: paused ? p.sunk : null,
      elevated: !paused,
      onTap: onTap,
      onLongPress: onLongPress,
      semanticLabel:
          '$name budget, ${pc.state.labelFor(past: past)}. Spent ${budgetMoney(context, u.spent)} of '
          '${budgetMoney(context, u.budget.limit)}. $hint.',
      child: Opacity(
        opacity: paused ? 0.62 : 1,
        child: Row(
          children: [
            LuxeRing(
              value: u.utilization.clamp(0.0, 1.0),
              color: color,
              size: 48,
              stroke: 2.5,
              child: Icon(CategoryIcons.of(category?.iconKey), size: 19, color: accent),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.heading.copyWith(fontSize: 15),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 140),
                        child: AmountText(
                          u.spent,
                          fit: true,
                          textAlign: TextAlign.end,
                          style: t.number.c(u.isOver ? p.negative : p.ink),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  LuxeProgressLine(
                    value: pc.used,
                    ghost: paused || past ? null : pc.projectedShare,
                    tick: paused || past ? null : pc.elapsed,
                    tickColor: p.gold,
                    color: color,
                    height: 4,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(pc.state.icon, size: 12, color: color),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          hint,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.caption.w(600).c(pc.state == BudgetState.onTrack || paused ? p.inkSoft : color),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('of ${budgetMoney(context, u.budget.limit)}', style: t.micro),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sort & filter sheet
// ---------------------------------------------------------------------------

class _OptionsSheet extends StatefulWidget {
  const _OptionsSheet({required this.initial});

  final BudgetListFilter initial;

  @override
  State<_OptionsSheet> createState() => _OptionsSheetState();
}

class _OptionsSheetState extends State<_OptionsSheet> {
  late BudgetListFilter _f = widget.initial;

  @override
  Widget build(BuildContext context) {
    final t = context.lt;
    return LuxeSheet(
      eyebrow: 'Budgets',
      title: 'Sort & filter',
      footer: Row(
        children: [
          Expanded(
            child: LuxeButton(
              label: 'Reset',
              variant: LuxeButtonVariant.outline,
              expand: true,
              onPressed: () => setState(() => _f = BudgetListFilter(state: _f.state)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: LuxeButton(
              key: const ValueKey('budget-apply'),
              label: 'Apply',
              expand: true,
              onPressed: () => Navigator.of(context).pop(_f),
            ),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('SORT BY', style: t.eyebrow),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final s in BudgetSort.values)
                LuxeChip(
                  key: ValueKey('budget-sort:${s.name}'),
                  label: s.label,
                  selected: _f.sort == s,
                  onTap: () => setState(() => _f = _f.copyWith(sort: s)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BudgetsSkeleton extends StatelessWidget {
  const _BudgetsSkeleton();

  @override
  Widget build(BuildContext context) => const LuxeShimmer(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LuxeBone(height: 52, radius: 26),
        SizedBox(height: 18),
        LuxeBone(height: 380, radius: LuxeSpace.rCard),
        SizedBox(height: 18),
        LuxeBone(height: 40, radius: 20),
        SizedBox(height: 14),
        LuxeBone(height: 84, radius: LuxeSpace.rTile),
        SizedBox(height: 10),
        LuxeBone(height: 84, radius: LuxeSpace.rTile),
      ],
    ),
  );
}
