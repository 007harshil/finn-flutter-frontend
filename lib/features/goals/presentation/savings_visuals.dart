import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/time/dates.dart';
import '../../../design_system/design_system.dart';
import '../application/goal_view.dart';
import '../domain/goal.dart';
import 'savings_widgets.dart';

/// Visuals shared by the goals list, goal detail and emergency fund.

extension GoalPaceUi on GoalPace {
  Color color(FinnColors c) => switch (this) {
        GoalPace.behind => c.warning,
        GoalPace.onTrack => c.positive,
        GoalPace.noPlan => c.textTertiary,
        GoalPace.done => c.positive,
        GoalPace.archived => c.textTertiary,
      };

  IconData get icon => switch (this) {
        GoalPace.behind => LucideIcons.clock,
        GoalPace.onTrack => LucideIcons.circleCheck,
        GoalPace.noPlan => LucideIcons.circleDashed,
        GoalPace.done => LucideIcons.partyPopper,
        GoalPace.archived => LucideIcons.archive,
      };

  String countLabel(int n) => switch (this) {
        GoalPace.behind => '$n behind',
        GoalPace.onTrack => '$n on track',
        GoalPace.noPlan => '$n without a plan',
        GoalPace.done => '$n done',
        GoalPace.archived => '$n archived',
      };
}

/// Progress ring with milestone dots at 25/50/75% that light up as the fill
/// passes them, and a notch on the rim where the calendar says the goal
/// should be by now ([expected]). Fill ahead of the notch = ahead of plan.
class GoalRing extends StatelessWidget {
  const GoalRing({
    super.key,
    required this.progress,
    required this.colors,
    required this.child,
    this.expected,
    this.size = 140,
    this.stroke = 12,
    this.milestones = true,
    this.semanticsLabel,
  });

  final double progress;
  final (Color, Color) colors;
  final double? expected;
  final double size;
  final double stroke;
  final bool milestones;
  final Widget child;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      label: semanticsLabel,
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              child: RepaintBoundary(
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: progress.clamp(0.0, 1.0)),
                  duration: context.reduceMotion ? Duration.zero : const Duration(milliseconds: 1300),
                  curve: Curves.easeOutCubic,
                  builder: (context, p, _) => CustomPaint(
                    painter: _GoalRingPainter(
                      progress: p,
                      expected: expected,
                      start: colors.$1,
                      end: colors.$2,
                      track: c.surfaceMuted,
                      ink: c.textPrimary,
                      dot: c.surface,
                      stroke: stroke,
                      milestones: milestones,
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.all(stroke + 8),
              child: FittedBox(fit: BoxFit.scaleDown, child: child),
            ),
          ],
        ),
      ),
    );
  }
}

class _GoalRingPainter extends CustomPainter {
  const _GoalRingPainter({
    required this.progress,
    required this.expected,
    required this.start,
    required this.end,
    required this.track,
    required this.ink,
    required this.dot,
    required this.stroke,
    required this.milestones,
  });

  final double progress;
  final double? expected;
  final Color start;
  final Color end;
  final Color track;
  final Color ink;
  final Color dot;
  final double stroke;
  final bool milestones;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final r = size.width / 2 - stroke / 2 - (expected == null ? 0 : 4);
    final rect = Rect.fromCircle(center: center, radius: r);
    const top = -math.pi / 2;
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = track,
    );
    if (progress > 0) {
      canvas.drawArc(
        rect,
        top,
        2 * math.pi * progress,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round
          ..shader = ui.Gradient.sweep(
            center,
            [start, end, start],
            [0, 0.5, 1],
            TileMode.clamp,
            top,
            top + 2 * math.pi,
          ),
      );
    }
    if (milestones) {
      for (final m in const [0.25, 0.5, 0.75]) {
        final a = top + 2 * math.pi * m;
        final p = center + Offset(math.cos(a), math.sin(a)) * r;
        final reached = progress >= m;
        canvas.drawCircle(p, reached ? stroke * 0.22 : stroke * 0.16, Paint()..color = reached ? dot : ink.withValues(alpha: 0.18));
      }
    }
    final e = expected;
    if (e != null && e > 0 && e < 1) {
      final a = top + 2 * math.pi * e;
      final dir = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(
        center + dir * (r - stroke / 2 - 2),
        center + dir * (r + stroke / 2 + 5),
        Paint()
          ..color = ink
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_GoalRingPainter old) =>
      old.progress != progress ||
      old.expected != expected ||
      old.start != start ||
      old.end != end ||
      old.track != track ||
      old.ink != ink;
}

/// Every active goal as one segment of a bar: segment width = its target,
/// filled part = what is saved. Big goals look big, nearly-done ones look
/// full. Tap a segment to open it.
class GoalMosaic extends StatelessWidget {
  const GoalMosaic({super.key, required this.goals, required this.onOpen, this.height = 22});

  final List<GoalProgress> goals;
  final ValueChanged<GoalProgress> onOpen;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (goals.isEmpty) return const SizedBox.shrink();
    final total = goals.fold<int>(0, (s, g) => s + g.goal.target.paise);
    // Small goals still get a tappable sliver.
    final flexes = [
      for (final g in goals) math.max(60, total == 0 ? 1000 : (g.goal.target.paise * 1000 / total).round()),
    ];
    final reduce = context.reduceMotion;
    return SizedBox(
      height: height,
      child: Row(
        children: [
          for (var i = 0; i < goals.length; i++) ...[
            if (i > 0) const SizedBox(width: 3),
            Expanded(
              flex: flexes[i],
              child: Semantics(
                button: true,
                label: '${goals[i].goal.name}, ${formatPct(goals[i].progress)} saved',
                excludeSemantics: true,
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    onOpen(goals[i]);
                  },
                  child: Tooltip(
                    message: '${goals[i].goal.name} · ${formatPct(goals[i].progress)}',
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(Radii.sm),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          ColoredBox(color: AccentSwatches.solid(goals[i].goal.colorIndex).withValues(alpha: 0.18)),
                          TweenAnimationBuilder<double>(
                            tween: Tween(begin: 0, end: goals[i].progress),
                            duration: reduce ? Duration.zero : Duration(milliseconds: 700 + 90 * i),
                            curve: Curves.easeOutCubic,
                            builder: (context, v, _) => FractionallySizedBox(
                              alignment: Alignment.centerLeft,
                              widthFactor: v.clamp(0.0, 1.0),
                              child: DecoratedBox(
                                decoration: BoxDecoration(gradient: AccentSwatches.gradient(goals[i].goal.colorIndex)),
                              ),
                            ),
                          ),
                          if (goals[i].goal.status == GoalStatus.active && goals[i].onTrack == false)
                            Align(
                              alignment: Alignment.centerRight,
                              child: Padding(
                                padding: const EdgeInsets.only(right: 3),
                                child: Icon(LucideIcons.clock, size: 11, color: c.warning),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

String formatPct(double share) => '${(share * 100).round()}%';

/// Saved amount over time (steps at each movement) against the target.
class SavedGrowthChart extends StatelessWidget {
  const SavedGrowthChart({
    super.key,
    required this.points,
    required this.target,
    required this.color,
    required this.today,
    this.targetDate,
    this.height = 110,
  });

  final List<(DateTime, Money)> points;
  final Money target;
  final Color color;
  final DateTime today;
  final DateTime? targetDate;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    if (points.isEmpty) return const SizedBox.shrink();
    return RepaintBoundary(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: context.reduceMotion ? Duration.zero : const Duration(milliseconds: 1100),
        curve: Curves.easeOutCubic,
        builder: (context, reveal, _) => CustomPaint(
          size: Size(double.infinity, height),
          painter: _GrowthPainter(
            points: points,
            target: target.paise,
            start: points.first.$1,
            end: targetDate != null && targetDate!.isAfter(today) ? targetDate! : today,
            today: today,
            reveal: reveal,
            color: color,
            ink: c.textPrimary,
            muted: c.textTertiary,
            labelStyle: t.micro,
            startLabel: DateFormats.shortMonthYear.format(points.first.$1),
            endLabel: targetDate != null && targetDate!.isAfter(today)
                ? DateFormats.shortMonthYear.format(targetDate!)
                : 'Today',
          ),
        ),
      ),
    );
  }
}

class _GrowthPainter extends CustomPainter {
  const _GrowthPainter({
    required this.points,
    required this.target,
    required this.start,
    required this.end,
    required this.today,
    required this.reveal,
    required this.color,
    required this.ink,
    required this.muted,
    required this.labelStyle,
    required this.startLabel,
    required this.endLabel,
  });

  final List<(DateTime, Money)> points;
  final int target;
  final DateTime start;
  final DateTime end;
  final DateTime today;
  final double reveal;
  final Color color;
  final Color ink;
  final Color muted;
  final TextStyle labelStyle;
  final String startLabel;
  final String endLabel;

  @override
  void paint(Canvas canvas, Size size) {
    const top = 6.0;
    const bottom = 16.0;
    final h = size.height - top - bottom;
    final w = size.width;
    final span = math.max(1, daysBetween(start, end));
    final maxV = points.fold<int>(target, (m, p) => math.max(m, p.$2.paise)) * 1.05;
    double x(DateTime d) => (daysBetween(start, d) / span).clamp(0.0, 1.0) * w;
    double y(int v) => top + h - (maxV <= 0 ? 0 : v / maxV * h);

    // Target line.
    final ty = y(target);
    final dash = Paint()
      ..color = ink.withValues(alpha: 0.4)
      ..strokeWidth = 1.2;
    for (var dx = 0.0; dx < w; dx += 9) {
      canvas.drawLine(Offset(dx, ty), Offset(math.min(dx + 5, w), ty), dash);
    }

    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, w * reveal, size.height));
    final path = Path()..moveTo(0, y(0));
    var prev = 0;
    for (final (d, v) in points) {
      final px = x(d);
      path.lineTo(px, y(prev));
      path.lineTo(px, y(v.paise));
      prev = v.paise;
    }
    final todayX = x(today);
    path.lineTo(todayX, y(prev));
    final area = Path.from(path)
      ..lineTo(todayX, y(0))
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = ui.Gradient.linear(Offset(0, top), Offset(0, top + h), [
          color.withValues(alpha: 0.3),
          color.withValues(alpha: 0.02),
        ]),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );
    canvas.drawCircle(Offset(todayX, y(prev)), 3.5, Paint()..color = color);
    canvas.restore();

    void label(String s, double at, {bool end = false}) {
      final tp = TextPainter(text: TextSpan(text: s, style: labelStyle.copyWith(color: muted)), textDirection: TextDirection.ltr)
        ..layout();
      tp.paint(canvas, Offset(end ? at - tp.width : at, size.height - bottom + 3));
    }

    label(startLabel, 0);
    label(endLabel, w, end: true);
  }

  @override
  bool shouldRepaint(_GrowthPainter old) =>
      old.reveal != reveal || old.points != points || old.target != target || old.color != color || old.ink != ink;
}

enum _HistoryKind { all, added, withdrawn }

/// Movements grouped by month with each month's net, filterable by kind.
class SavingsHistory extends StatefulWidget {
  const SavingsHistory({super.key, required this.movements, required this.accent, required this.emptyText});

  final List<SavingsMovement> movements;
  final Color accent;
  final String emptyText;

  @override
  State<SavingsHistory> createState() => _SavingsHistoryState();
}

class _SavingsHistoryState extends State<SavingsHistory> {
  _HistoryKind _kind = _HistoryKind.all;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final all = widget.movements;
    final added = all.where((m) => m.kind == SavingsMovementKind.contribution).length;
    final withdrawn = all.length - added;
    final shown = all.where((m) => switch (_kind) {
          _HistoryKind.all => true,
          _HistoryKind.added => m.kind == SavingsMovementKind.contribution,
          _HistoryKind.withdrawn => m.kind == SavingsMovementKind.withdrawal,
        });
    final groups = <MonthKey, List<SavingsMovement>>{};
    for (final m in shown) {
      groups.putIfAbsent(m.date.monthKey, () => []).add(m);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('History', style: t.sectionTitle),
            const SizedBox(width: Space.x2),
            Expanded(
              child: Text(
                all.isEmpty ? '' : '${all.length} movement${all.length == 1 ? '' : 's'}',
                style: t.caption,
              ),
            ),
          ],
        ),
        if (all.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: Space.x2),
            child: Text(widget.emptyText, style: t.body.copyWith(color: c.textSecondary)),
          )
        else ...[
          if (added > 0 && withdrawn > 0) ...[
            const SizedBox(height: Space.x2),
            Wrap(
              spacing: Space.x1_5,
              runSpacing: Space.x1_5,
              children: [
                for (final (k, label) in [
                  (_HistoryKind.all, 'All ${all.length}'),
                  (_HistoryKind.added, 'Added $added'),
                  (_HistoryKind.withdrawn, 'Withdrawn $withdrawn'),
                ])
                  FinnTapChip(
                    key: ValueKey('savings-history:${k.name}'),
                    label: label,
                    selected: _kind == k,
                    color: _kind == k ? widget.accent : null,
                    onTap: () => setState(() => _kind = k),
                  ),
              ],
            ),
          ],
          for (final e in groups.entries) ...[
            Padding(
              padding: const EdgeInsets.only(top: Space.x4, bottom: Space.x1),
              child: Row(
                children: [
                  Text(DateFormats.monthYear.format(DateTime(e.key.year, e.key.month)).toUpperCase(), style: t.eyebrow),
                  const Spacer(),
                  AmountText(
                    Money.sum(e.value.map((m) => m.signedAmount)),
                    sign: SignDisplay.always,
                    style: t.label.copyWith(fontWeight: FontWeight.w800, color: c.textSecondary),
                  ),
                ],
              ),
            ),
            for (final m in e.value) KeyedSubtree(key: ValueKey(m.id), child: SavingsMovementTile(movement: m)),
          ],
        ],
      ],
    );
  }
}

/// Months of cover as a row of cells, one per planned month, filling up in
/// sequence like a battery. Partial cells show the fraction.
class CoverCells extends StatefulWidget {
  const CoverCells({super.key, required this.covered, required this.months, this.onGradient = true, this.height = 14});

  final double covered;
  final int months;
  final bool onGradient;
  final double height;

  @override
  State<CoverCells> createState() => _CoverCellsState();
}

class _CoverCellsState extends State<CoverCells> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_c.isAnimating || _c.isCompleted) return;
    if (context.reduceMotion) {
      _c.value = 1;
    } else {
      _c
        ..duration = Duration(milliseconds: 500 + 90 * widget.months.clamp(1, 24))
        ..forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final n = widget.months.clamp(1, 24);
    final fill = widget.onGradient ? Colors.white : c.accentEmergency;
    final track = widget.onGradient ? Colors.white24 : c.surfaceMuted;
    final h = widget.height;
    return Semantics(
      label: '${coverageLabel(widget.covered)} of $n months covered',
      excludeSemantics: true,
      child: SizedBox(
        height: h,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) => Row(
            children: [
              for (var i = 0; i < n; i++) ...[
                if (i > 0) SizedBox(width: n > 12 ? 2 : 4),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(h / 3),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ColoredBox(color: track),
                        // Each cell fills in its own slice of the timeline.
                        TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: (widget.covered - i).clamp(0.0, 1.0)),
                          duration: context.motion.slow,
                          builder: (context, v, _) => FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: (v *
                                    Interval(i / n * 0.7, math.min(1, i / n * 0.7 + 0.3), curve: Curves.easeOutCubic)
                                        .transform(_c.value))
                                .clamp(0.0, 1.0),
                            child: ColoredBox(color: fill),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Small shield that fills from the bottom with the emergency fund level.
class ShieldFill extends StatelessWidget {
  const ShieldFill({super.key, required this.progress, required this.color, this.size = 40});

  final double progress;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return RepaintBoundary(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: progress.clamp(0.0, 1.0)),
        duration: context.reduceMotion ? Duration.zero : const Duration(milliseconds: 1200),
        curve: Curves.easeOutCubic,
        builder: (context, p, _) => CustomPaint(
          size: Size.square(size),
          painter: _ShieldPainter(progress: p, color: color, track: c.surfaceMuted, ink: color),
        ),
      ),
    );
  }
}

class _ShieldPainter extends CustomPainter {
  const _ShieldPainter({required this.progress, required this.color, required this.track, required this.ink});

  final double progress;
  final Color color;
  final Color track;
  final Color ink;

  Path _shield(Size s) {
    final w = s.width;
    final h = s.height;
    return Path()
      ..moveTo(w * 0.5, h * 0.04)
      ..lineTo(w * 0.9, h * 0.18)
      ..lineTo(w * 0.9, h * 0.48)
      ..cubicTo(w * 0.9, h * 0.74, w * 0.7, h * 0.88, w * 0.5, h * 0.97)
      ..cubicTo(w * 0.3, h * 0.88, w * 0.1, h * 0.74, w * 0.1, h * 0.48)
      ..lineTo(w * 0.1, h * 0.18)
      ..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final shield = _shield(size);
    canvas.drawPath(shield, Paint()..color = track);
    canvas.save();
    canvas.clipPath(shield);
    final level = size.height * (1 - progress);
    // A gentle wave on the surface of the fill.
    final wave = Path()..moveTo(0, level);
    for (var x = 0.0; x <= size.width; x += 2) {
      wave.lineTo(x, level + math.sin(x / size.width * 2 * math.pi + progress * 6) * 1.6);
    }
    wave
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(wave, Paint()..color = color.withValues(alpha: 0.85));
    canvas.restore();
    canvas.drawPath(
      shield,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = ink,
    );
  }

  @override
  bool shouldRepaint(_ShieldPainter old) => old.progress != progress || old.color != color || old.track != track;
}
