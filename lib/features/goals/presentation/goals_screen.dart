import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
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
import '../../../shared/presentation/category_icons.dart';
import '../../../shared/presentation/luxe_page.dart';
import '../../emergency_fund/domain/emergency_fund.dart';
import '../application/goal_view.dart';
import '../domain/goal.dart';
import 'savings_visuals.dart';
import 'savings_widgets.dart';

/// "Your vision": every goal as an orbit around what you have saved, the
/// emergency fund as one line, then the goals themselves with one-tap
/// "add money".
///
/// Top to bottom: title and "New goal"; the orbit board (saved vs targets,
/// one ring per goal that you can spin, the monthly effort needed vs
/// planned, status shortcuts); the emergency fund; a pinned Active /
/// Completed / Archived switch with sort & filter; the goals.
class GoalsScreen extends ConsumerStatefulWidget {
  const GoalsScreen({super.key});

  @override
  ConsumerState<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends ConsumerState<GoalsScreen> {
  GoalListFilter _filter = const GoalListFilter();

  void _set(GoalListFilter f) => setState(() => _filter = f);

  void _togglePace(GoalPace p) {
    final only = _filter.paces.length == 1 && _filter.paces.contains(p);
    _set(_filter.copyWith(tab: GoalTab.active, paces: only ? const {} : {p}));
  }

  Future<void> _openOptions() async {
    final next = await showLuxeSheet<GoalListFilter>(context, builder: (_) => _OptionsSheet(initial: _filter));
    if (next != null && mounted) _set(next);
  }

  Future<void> _quickActions(GoalProgress g) async {
    final active = g.goal.status == GoalStatus.active;
    final choice = await showLuxeMenu<int>(
      context,
      eyebrow: 'Goal',
      title: g.goal.name,
      items: [
        if (active) const LuxeMenuItem(value: 0, label: 'Add money', icon: LucideIcons.plus, hint: 'Set money aside'),
        if (active && g.saved.isPositive)
          const LuxeMenuItem(value: 1, label: 'Withdraw', icon: LucideIcons.minus, hint: 'Release money back'),
        const LuxeMenuItem(
          value: 2,
          label: 'Open details',
          icon: LucideIcons.arrowUpRight,
          hint: 'Path, history, what-if',
        ),
        const LuxeMenuItem(value: 3, label: 'Edit goal', icon: LucideIcons.pencil),
      ],
    );
    if (!mounted || choice == null) return;
    context.push(switch (choice) {
      0 => AppRoutes.goalContribute(g.goal.id),
      1 => AppRoutes.goalWithdraw(g.goal.id),
      3 => AppRoutes.editGoal(g.goal.id),
      _ => AppRoutes.goal(g.goal.id),
    });
  }

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(goalsBoardProvider);
    final b = value.value;
    final List<Widget> body;
    if (b == null) {
      if (value.hasError) {
        final e = value.error;
        body = [
          luxeBox(
            LuxeError(
              title: 'Could not load your goals',
              message: e is AppFailure ? e.message : null,
              onRetry: () => refreshFinanceData(ref),
            ),
            top: 24,
          ),
        ];
      } else {
        body = [luxeBox(const _GoalsSkeleton(), top: 18)];
      }
    } else {
      body = _content(context, b);
    }
    return LuxePage(
      storageKey: 'goals',
      compactTitle: 'Your vision',
      slivers: [
        luxeBox(const Reveal(child: _Header()), top: 4),
        ...body,
      ],
    );
  }

  List<Widget> _content(BuildContext context, GoalsBoard b) {
    final shown = filterGoals(b.all, _filter);
    return [
      if (b.active.isNotEmpty)
        luxeBox(
          Reveal(
            index: 1,
            child: _OrbitBoard(board: b, filter: _filter, onPace: _togglePace),
          ),
          top: 22,
        ),
      luxeBox(const Reveal(index: 2, child: _EmergencyLine()), top: 12),
      if (b.all.isEmpty)
        luxeBox(
          LuxeEmpty(
            icon: LucideIcons.target,
            title: 'Start your first goal',
            message:
                'A trip, a new laptop, a home down payment — give it a name and a target, '
                'and set money aside at your own pace.',
            actionLabel: 'Create a goal',
            actionIcon: LucideIcons.plus,
            onAction: () => context.push(AppRoutes.newGoal),
          ),
          top: 12,
        )
      else ...[
        luxeBox(const SizedBox.shrink(), top: 10),
        PinnedHeaderSliver(
          child: _Controls(
            counts: b.tabCounts,
            filter: _filter,
            onTab: (t) => _set(_filter.copyWith(tab: t)),
            onOptions: _openOptions,
          ),
        ),
        luxeBox(_ResultLine(count: shown.length, filter: _filter, onChanged: _set, onSort: _openOptions), top: 4),
        if (shown.isEmpty)
          luxeBox(_emptyFor(context), top: 4)
        else
          SliverList.builder(
            itemCount: shown.length,
            itemBuilder: (context, i) {
              final g = shown[i];
              final row = GoalRow(
                key: ValueKey(g.goal.id),
                progress: g,
                today: b.today,
                onLongPress: () => _quickActions(g),
              );
              return ResponsiveCenter(
                padding: const EdgeInsets.fromLTRB(LuxeSpace.gutter, 0, LuxeSpace.gutter, 10),
                child: i < 10
                    ? Reveal(key: ValueKey('r-${g.goal.id}-${_filter.tab}'), index: i, offset: 14, blur: 0, child: row)
                    : row,
              );
            },
          ),
      ],
    ];
  }

  Widget _emptyFor(BuildContext context) {
    if (_filter.paces.isNotEmpty || _filter.categories.isNotEmpty) {
      return LuxeEmpty(
        icon: LucideIcons.searchX,
        title: 'No matches',
        message: 'No goal fits these filters.',
        actionLabel: 'Clear filters',
        onAction: () => _set(_filter.cleared()),
      );
    }
    return switch (_filter.tab) {
      GoalTab.active => LuxeEmpty(
        icon: LucideIcons.target,
        title: 'No active goals',
        message: 'Every goal is done or archived. Start a new one when you are ready.',
        actionLabel: 'Create a goal',
        actionIcon: LucideIcons.plus,
        onAction: () => context.push(AppRoutes.newGoal),
      ),
      GoalTab.completed => const LuxeEmpty(
        icon: LucideIcons.partyPopper,
        title: 'Nothing completed yet',
        message: 'Goals you fully fund will appear here.',
      ),
      GoalTab.archived => const LuxeEmpty(
        icon: LucideIcons.archive,
        title: 'No archived goals',
        message: 'Archive a goal to hide it without losing its history.',
      ),
    };
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final p = context.luxe;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LuxeTopBar(
          actions: [
            LuxeButton(
              label: 'New goal',
              icon: LucideIcons.plus,
              compact: true,
              onPressed: () => context.push(AppRoutes.newGoal),
            ),
          ],
        ),
        const SizedBox(height: 18),
        LuxeTitle(
          eyebrow: 'Savings goals',
          semanticsLabel: 'Your vision',
          title: <InlineSpan>[
            const TextSpan(text: 'Your '),
            TextSpan(
              text: 'vision',
              style: TextStyle(fontStyle: FontStyle.italic, color: p.goldInk),
            ),
          ],
        ),
      ],
    );
  }
}

/// Muted gradient pair for a goal's swatch.
/// Whole rupees for monthly figures.
String _whole(BuildContext context, Money m) => AmountVisibility.hiddenOf(context)
    ? MoneyFormatter.masked
    : MoneyFormatter.format(m, decimals: DecimalDisplay.none);

(Color, Color) _goalColors(LuxePalette p, int index) {
  final (a, b) = AccentSwatches.of(index);
  return (p.mute(a), p.mute(b));
}

// ---------------------------------------------------------------------------
// Orbit board
// ---------------------------------------------------------------------------

class _OrbitBoard extends StatelessWidget {
  const _OrbitBoard({required this.board, required this.filter, required this.onPace});

  final GoalsBoard board;
  final GoalListFilter filter;
  final ValueChanged<GoalPace> onPace;

  @override
  Widget build(BuildContext context) {
    final p = context.luxe;
    final t = context.lt;
    final b = board;
    final need = b.neededMonthly;
    final plan = b.plannedMonthly;
    final short = need.isPositive && plan < need;
    final shortcuts = [
      for (final pace in [GoalPace.behind, GoalPace.onTrack, GoalPace.noPlan])
        if (b.count(pace) > 0) pace,
    ];
    final orbiting = b.active.take(5).toList();
    return LuxeCard(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text('SAVED FOR YOUR GOALS', style: t.eyebrow, maxLines: 1)),
              Text('${b.active.length} active', style: t.micro),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LuxeAmount(b.saved, style: t.display.copyWith(fontSize: 42), countFromZero: true),
                    const SizedBox(height: 2),
                    Text(
                      'of ${savingsMoney(context, b.target)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.caption,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _Orbit(goals: orbiting, total: b.progress),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 4,
            runSpacing: 0,
            children: [
              for (final g in orbiting)
                Squish(
                  onTap: () => context.push(AppRoutes.goal(g.goal.id)),
                  scale: 0.94,
                  semanticLabel: 'Open ${g.goal.name}, ${formatPct(g.progress)}',
                  excludeSemantics: true,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 40),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: _goalColors(p, g.goal.colorIndex).$2,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 120),
                            child: Text(
                              g.goal.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: t.micro.w(650).c(p.ink),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(formatPct(g.progress), style: t.micro),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
          if (need.isPositive || plan.isPositive) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: short ? p.tint(p.warning, 0.1) : p.goldSoft,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Icon(
                    short ? LucideIcons.trendingDown : LucideIcons.trendingUp,
                    size: 16,
                    color: short ? p.warning : p.goldInk,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          if (need.isPositive) ...[
                            TextSpan(
                              text: '${_whole(context, need)}/month',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontVariations: [FontVariation('wght', 800)],
                              ),
                            ),
                            const TextSpan(text: ' keeps every dated goal on time'),
                          ] else
                            const TextSpan(text: 'No target dates set'),
                          TextSpan(
                            text: plan.isPositive
                                ? ' · you put in ~${_whole(context, plan)}'
                                : ' · no monthly plan yet',
                            style: TextStyle(color: p.inkSoft),
                          ),
                        ],
                      ),
                      style: t.caption.c(p.ink),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (shortcuts.isNotEmpty) ...[
            const SizedBox(height: 8),
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
                        key: ValueKey('goal-attn:${shortcuts[i].name}'),
                        label: shortcuts[i].countLabel(b.count(shortcuts[i])),
                        dot: _paceColor(p, shortcuts[i]),
                        height: 34,
                        selected:
                            filter.tab == GoalTab.active &&
                            filter.paces.length == 1 &&
                            filter.paces.contains(shortcuts[i]),
                        onTap: () => onPace(shortcuts[i]),
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
}

Color _paceColor(LuxePalette p, GoalPace pace) => switch (pace) {
  GoalPace.behind => p.warning,
  GoalPace.onTrack || GoalPace.done => p.positive,
  GoalPace.noPlan || GoalPace.archived => p.inkMute,
};

/// Goals as rings on a tilted plane (perspective 3D), each ring's arc the
/// share saved, a bright "planet" where it ends. Drag sideways to spin the
/// system; it glides to rest with friction.
class _Orbit extends StatefulWidget {
  const _Orbit({required this.goals, required this.total});

  final List<GoalProgress> goals;
  final double total;

  @override
  State<_Orbit> createState() => _OrbitState();
}

class _OrbitState extends State<_Orbit> with TickerProviderStateMixin {
  /// Spin angle in radians (unbounded).
  late final AnimationController _spin = AnimationController.unbounded(vsync: this);
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (context.reduceMotion) {
      _intro.value = 1;
    } else {
      _intro.forward();
      // A gentle quarter turn on arrival, coming to rest by itself.
      _spin.animateWith(FrictionSimulation(0.35, 0, 1.6));
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    _intro.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.luxe;
    final t = context.lt;
    final rings = [
      for (final g in widget.goals)
        _Ring(progress: g.progress, colors: _goalColors(p, g.goal.colorIndex), seed: g.goal.id.hashCode),
    ];
    return Semantics(
      label: 'Goals orbit: ${[for (final g in widget.goals) '${g.goal.name} ${formatPct(g.progress)}'].join(', ')}',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: context.reduceMotion
            ? null
            : (d) {
                _spin.stop();
                _spin.value += d.delta.dx / 90;
              },
        onHorizontalDragEnd: context.reduceMotion
            ? null
            : (d) {
                HapticFeedback.selectionClick();
                _spin.animateWith(FrictionSimulation(0.2, _spin.value, (d.primaryVelocity ?? 0) / 90));
              },
        child: SizedBox(
          height: 176,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: Listenable.merge([_spin, _intro]),
                  builder: (context, _) => CustomPaint(
                    painter: _OrbitPainter(
                      rings: rings,
                      spin: _spin.value,
                      intro: Curves.easeOutCubic.transform(_intro.value),
                      track: p.line,
                      core: p.gold,
                      glow: p.auroraA,
                    ),
                  ),
                ),
              ),
              IgnorePointer(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(formatPct(widget.total), style: t.figure.copyWith(fontSize: 24)),
                    Text('overall', style: t.micro),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

@immutable
class _Ring {
  const _Ring({required this.progress, required this.colors, required this.seed});
  final double progress;
  final (Color, Color) colors;
  final int seed;
}

class _OrbitPainter extends CustomPainter {
  _OrbitPainter({
    required this.rings,
    required this.spin,
    required this.intro,
    required this.track,
    required this.core,
    required this.glow,
  });

  final List<_Ring> rings;
  final double spin;
  final double intro;
  final Color track;
  final Color core;
  final Color glow;

  /// Perspective: the orbital plane is tilted towards the viewer.
  static const _tilt = 0.46;

  Offset _project(Offset c, double r, double a) {
    // Point on a circle in the plane, squashed vertically, with a touch of
    // depth scaling so the near side reads larger.
    final x = math.cos(a) * r;
    final y = math.sin(a) * r * _tilt;
    final depth = 1 + math.sin(a) * 0.06;
    return c + Offset(x * depth, y);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final maxR = math.min(size.width / 2 - 8, size.height / 2 / _tilt - 10);
    final n = rings.length;
    if (n == 0) return;
    final step = (maxR - 46) / math.max(1, n);

    // Core glow and sun.
    canvas.drawCircle(
      c,
      58,
      Paint()
        ..shader = RadialGradient(colors: [glow.withValues(alpha: 0.9), glow.withValues(alpha: 0)])
            .createShader(Rect.fromCircle(center: c, radius: 58)),
    );

    for (var i = 0; i < n; i++) {
      final ring = rings[i];
      final r = 52 + step * (i + 0.6);
      final local = ((intro * (n + 2) - i) / 3).clamp(0.0, 1.0);
      final rect = Rect.fromCenter(center: c, width: r * 2, height: r * 2 * _tilt);
      canvas.drawOval(
        rect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = track,
      );
      if (ring.progress <= 0.002 || local <= 0) continue;
      final start = spin * (1 + i * 0.18) + ring.seed % 7 * 0.6;
      final sweep = math.pi * 2 * ring.progress.clamp(0.0, 1.0) * Curves.easeOutCubic.transform(local);
      final path = Path();
      const segs = 72;
      for (var s = 0; s <= segs; s++) {
        final a = start + sweep * s / segs;
        final pt = _project(c, r, a);
        if (s == 0) {
          path.moveTo(pt.dx, pt.dy);
        } else {
          path.lineTo(pt.dx, pt.dy);
        }
      }
      final (a, b) = ring.colors;
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round
          ..shader = LinearGradient(colors: [a.withValues(alpha: 0.35), b]).createShader(rect),
      );
      final end = _project(c, r, start + sweep);
      canvas.drawCircle(end, 7, Paint()..color = b.withValues(alpha: 0.18));
      canvas.drawCircle(end, 3.6, Paint()..color = b);
    }
    canvas.drawCircle(c, 3, Paint()..color = core.withValues(alpha: 0.0));
  }

  @override
  bool shouldRepaint(_OrbitPainter o) => o.spin != spin || o.intro != intro || o.rings != rings || o.track != track;
}

// ---------------------------------------------------------------------------
// Emergency fund
// ---------------------------------------------------------------------------

/// The safety net in one tappable line: a shield filling with its level,
/// months covered and the level word.
class _EmergencyLine extends ConsumerWidget {
  const _EmergencyLine();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(emergencyStatusProvider).value;
    if (s == null) return const LuxeShimmer(child: LuxeBone(height: 76, radius: LuxeSpace.rTile));
    final p = context.luxe;
    final t = context.lt;
    final configured = s.level != EmergencyFundLevel.notConfigured;
    final color = switch (s.level) {
      EmergencyFundLevel.critical => p.negative,
      EmergencyFundLevel.building => p.warning,
      EmergencyFundLevel.funded => p.positive,
      EmergencyFundLevel.notConfigured => p.goldInk,
    };
    final coverage = s.coverageMonths;
    final sub = !configured
        ? 'Not set up · plan a safety net'
        : [
            if (coverage != null) '${coverageLabel(coverage)} of ${s.plan!.targetMonths} covered',
            '${formatPct(s.progress)} of ${savingsMoney(context, s.target)}',
          ].join(' · ');
    return LuxeCard(
      key: const ValueKey('goals-emergency-line'),
      radius: LuxeSpace.rTile,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      onTap: () => context.push(AppRoutes.emergencyFund),
      semanticLabel: configured
          ? 'Emergency fund, ${s.level.label}. ${savingsMoney(context, s.saved)} saved. $sub.'
          : 'Emergency fund not set up. Tap to set it up.',
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(color: p.tint(color, 0.1), shape: BoxShape.circle),
            child: Center(
              child: ShieldFill(progress: configured ? s.progress : 0, color: color, size: 30),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Emergency fund',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.heading.copyWith(fontSize: 15),
                ),
                if (configured) AmountText(s.saved, style: t.number),
                const SizedBox(height: 2),
                Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.caption),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            flex: 0,
            child: LuxeStatus(label: s.level.label, color: color, icon: emergencyLevelIcon(s.level)),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Goal row
// ---------------------------------------------------------------------------

/// One goal: icon in a progress ring, name and share saved, a line with a
/// "should be here by now" tick for dated goals, one line of advice, and
/// "+" to add money.
class GoalRow extends StatelessWidget {
  const GoalRow({super.key, required this.progress, required this.today, this.onLongPress});

  final GoalProgress progress;
  final DateTime today;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final p = context.luxe;
    final t = context.lt;
    final g = progress;
    final pace = goalPaceOf(g);
    final (a, b) = _goalColors(p, g.goal.colorIndex);
    final active = g.goal.status == GoalStatus.active && !g.isAchieved;
    final expected = active ? expectedShare(g, today) : null;
    final date = g.goal.targetDate;
    final hint = [
      if (g.isAchieved) 'Target reached' else '${savingsMoney(context, g.remaining)} to go',
      if (date != null && !g.isAchieved) 'by ${DateFormats.shortMonthYear.format(date)}',
      if (pace == GoalPace.behind && g.requiredMonthly != null) 'needs ${_whole(context, g.requiredMonthly!)}/mo',
    ].join(' · ');
    final archived = g.goal.status == GoalStatus.archived;
    final paceColor = _paceColor(p, pace);
    return Semantics(
      container: true,
      label:
          '${g.goal.name}. ${savingsMoney(context, g.saved)} saved of ${savingsMoney(context, g.goal.target)}, '
          '${formatPct(g.progress)}. ${pace.label}. $hint.',
      child: LuxeCard(
        radius: LuxeSpace.rTile,
        padding: const EdgeInsets.fromLTRB(14, 14, 6, 12),
        color: archived ? p.sunk : null,
        elevated: !archived,
        onTap: () => context.push(AppRoutes.goal(g.goal.id)),
        onLongPress: onLongPress,
        child: Row(
          children: [
            Opacity(
              opacity: archived ? 0.55 : 1,
              child: LuxeRing(
                value: g.progress,
                color: b,
                gradient: [a.withValues(alpha: 0.5), b, b],
                size: 50,
                stroke: 2.5,
                child: Icon(CategoryIcons.of(g.goal.category.iconKey), size: 19, color: b),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Expanded(
                        child: Text(
                          g.goal.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.heading.copyWith(fontSize: 15),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(formatPct(g.progress), style: t.figure.copyWith(fontSize: 20)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  LuxeProgressLine(
                    value: g.progress,
                    tick: expected,
                    tickColor: p.ink,
                    color: pace == GoalPace.done ? p.positive : b,
                    height: 4,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(pace.icon, size: 12, color: paceColor),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          hint,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.caption.w(600).c(pace == GoalPace.behind ? p.warning : p.inkSoft),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (active)
              LuxeIconButton(
                key: ValueKey('goal-add:${g.goal.id}'),
                icon: LucideIcons.plus,
                tooltip: 'Add money to ${g.goal.name}',
                size: 38,
                onPressed: () => context.push(AppRoutes.goalContribute(g.goal.id)),
              )
            else
              const SizedBox(width: 10),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Pinned controls
// ---------------------------------------------------------------------------

class _Controls extends StatelessWidget {
  const _Controls({required this.counts, required this.filter, required this.onTab, required this.onOptions});

  final Map<GoalTab, int> counts;
  final GoalListFilter filter;
  final ValueChanged<GoalTab> onTab;
  final VoidCallback onOptions;

  @override
  Widget build(BuildContext context) {
    final p = context.luxe;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: DecoratedBox(
          decoration: BoxDecoration(color: p.canvas.withValues(alpha: 0.86)),
          child: ResponsiveCenter(
            padding: const EdgeInsets.fromLTRB(LuxeSpace.gutter, 8, LuxeSpace.gutter - 4, 6),
            child: Row(
              children: [
                Expanded(
                  child: LuxeSegmented<GoalTab>(
                    selected: filter.tab,
                    onChanged: onTab,
                    segments: [
                      for (final tab in GoalTab.values)
                        LuxeSegment(tab, tab.label, count: counts[tab] ?? 0, key: ValueKey('goal-tab:${tab.name}')),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                LuxeIconButton(
                  key: const ValueKey('goal-options'),
                  icon: LucideIcons.slidersHorizontal,
                  tooltip: 'Sort & filter',
                  semanticLabel: filter.activeCount == 0
                      ? 'Sort & filter'
                      : 'Sort & filter, ${filter.activeCount} filters on',
                  active: filter.activeCount > 0,
                  badge: filter.activeCount,
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
  const _ResultLine({required this.count, required this.filter, required this.onChanged, required this.onSort});

  final int count;
  final GoalListFilter filter;
  final ValueChanged<GoalListFilter> onChanged;
  final VoidCallback onSort;

  @override
  Widget build(BuildContext context) {
    final p = context.luxe;
    final t = context.lt;
    final f = filter;
    final removable = <(String, VoidCallback)>[
      for (final pace in f.paces) (pace.label, () => onChanged(f.copyWith(paces: {...f.paces}..remove(pace)))),
      for (final k in f.categories) (k.label, () => onChanged(f.copyWith(categories: {...f.categories}..remove(k)))),
    ];
    return SizedBox(
      height: 46,
      child: Row(
        children: [
          Text('$count ${count == 1 ? 'GOAL' : 'GOALS'}', style: t.eyebrow),
          const SizedBox(width: 10),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true,
              child: Row(
                children: [
                  for (final (label, remove) in removable) ...[
                    LuxeChip(
                      label: label,
                      trailing: LucideIcons.x,
                      selected: true,
                      height: 32,
                      semanticLabel: 'Remove filter $label',
                      onTap: remove,
                    ),
                    const SizedBox(width: 6),
                  ],
                  Squish(
                    onTap: onSort,
                    semanticLabel: 'Sorted by ${f.sort.label}. Change',
                    excludeSemantics: true,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 44),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(LucideIcons.arrowDownUp, size: 13, color: p.inkSoft),
                          const SizedBox(width: 6),
                          Text(f.sort.label, style: t.label.w(650)),
                          const SizedBox(width: 2),
                          Icon(LucideIcons.chevronDown, size: 14, color: p.inkSoft),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sort & filter sheet
// ---------------------------------------------------------------------------

class _OptionsSheet extends StatefulWidget {
  const _OptionsSheet({required this.initial});

  final GoalListFilter initial;

  @override
  State<_OptionsSheet> createState() => _OptionsSheetState();
}

class _OptionsSheetState extends State<_OptionsSheet> {
  late GoalListFilter _f = widget.initial;

  @override
  Widget build(BuildContext context) {
    final p = context.luxe;
    final t = context.lt;
    Widget section(String title, List<Widget> chips) => Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: t.eyebrow),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 2, children: chips),
        ],
      ),
    );
    return LuxeSheet(
      eyebrow: 'Goals',
      title: 'Sort & filter',
      footer: Row(
        children: [
          Expanded(
            child: LuxeButton(
              label: 'Reset',
              variant: LuxeButtonVariant.outline,
              expand: true,
              onPressed: () => setState(() => _f = _f.cleared()),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: LuxeButton(
              key: const ValueKey('goal-apply'),
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
          section('SORT BY', [
            for (final s in GoalSort.values)
              LuxeChip(
                key: ValueKey('goal-sort:${s.name}'),
                label: s.label,
                selected: _f.sort == s,
                onTap: () => setState(() => _f = _f.copyWith(sort: s)),
              ),
          ]),
          if (_f.tab == GoalTab.active)
            section('STATUS', [
              for (final pace in [GoalPace.behind, GoalPace.onTrack, GoalPace.noPlan])
                LuxeChip(
                  key: ValueKey('goal-pace:${pace.name}'),
                  label: pace.label,
                  dot: _paceColor(p, pace),
                  selected: _f.paces.contains(pace),
                  onTap: () => setState(() {
                    final next = {..._f.paces};
                    if (!next.remove(pace)) next.add(pace);
                    _f = _f.copyWith(paces: next);
                  }),
                ),
            ]),
          section('CATEGORY', [
            for (final k in GoalCategory.values)
              LuxeChip(
                label: k.label,
                icon: CategoryIcons.of(k.iconKey),
                selected: _f.categories.contains(k),
                onTap: () => setState(() {
                  final next = {..._f.categories};
                  if (!next.remove(k)) next.add(k);
                  _f = _f.copyWith(categories: next);
                }),
              ),
          ]),
        ],
      ),
    );
  }
}

class _GoalsSkeleton extends StatelessWidget {
  const _GoalsSkeleton();

  @override
  Widget build(BuildContext context) => const LuxeShimmer(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LuxeBone(height: 420, radius: LuxeSpace.rCard),
        SizedBox(height: 12),
        LuxeBone(height: 76, radius: LuxeSpace.rTile),
        SizedBox(height: 18),
        LuxeBone(height: 44, radius: 22),
        SizedBox(height: 14),
        LuxeBone(height: 88, radius: LuxeSpace.rTile),
        SizedBox(height: 10),
        LuxeBone(height: 88, radius: LuxeSpace.rTile),
      ],
    ),
  );
}
