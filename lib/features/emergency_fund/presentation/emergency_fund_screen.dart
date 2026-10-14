import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/di/data_providers.dart';
import '../../../app/router/routes.dart';
import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/time/dates.dart';
import '../../../design_system/design_system.dart';
import '../../../design_system/luxe/luxe.dart';
import '../../../shared/presentation/luxe_async.dart';
import '../../../shared/presentation/luxe_page.dart';
import '../../goals/domain/goal.dart';
import '../../goals/presentation/savings_widgets.dart';
import '../domain/emergency_fund.dart';
import '../domain/emergency_fund_calculator.dart';

/// Emergency fund: how full the safety net is, the two things you do with
/// it (add, withdraw), what the plan assumes, and every movement.
///
/// The hero is a vessel that fills to the funded share (the liquid pours
/// in, sloshes and settles; tap it to swirl), with one cell per planned
/// month of cover underneath.
class EmergencyFundScreen extends ConsumerWidget {
  const EmergencyFundScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(emergencyStatusProvider);
    final configured = (value.value?.level ?? EmergencyFundLevel.notConfigured) != EmergencyFundLevel.notConfigured;
    return LuxeDetailPage(
      title: 'Emergency fund',
      storageKey: 'emergency-fund',
      actions: [
        if (configured)
          LuxeIconButton(
            icon: LucideIcons.slidersHorizontal,
            tooltip: 'Edit plan',
            style: LuxeIconStyle.ghost,
            size: 40,
            onPressed: () => context.push(AppRoutes.emergencyPlan),
          ),
      ],
      slivers: [
        luxeBox(
          const Reveal(
            child: LuxePageTitle(eyebrow: 'Safety net', title: 'Emergency fund'),
          ),
          top: 4,
          bottom: 22,
        ),
        SliverToBoxAdapter(
          child: LuxeAsync<EmergencyFundStatus>(
            value: value,
            errorTitle: 'Could not load your emergency fund',
            loading: const LuxePageSkeleton(title: false, hero: 300, rows: 2),
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
    final configured = s.level != EmergencyFundLevel.notConfigured;
    var i = 0;
    Widget r(Widget child) => Reveal(index: i++, child: child);
    return ResponsiveCenter(
      padding: const EdgeInsets.symmetric(horizontal: LuxeSpace.gutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Reveal(
            index: i++,
            scale: 0.97,
            child: _Hero(status: s),
          ),
          const SizedBox(height: 14),
          if (!configured)
            r(_SetUpCard(status: s))
          else ...[
            r(_MoneyButtons(status: s)),
            const SizedBox(height: 14),
            r(_Guidance(status: s)),
            const SizedBox(height: 14),
            r(_PlanCard(status: s)),
          ],
          const SizedBox(height: LuxeSpace.section),
          r(_History(movements: s.movements)),
          const SizedBox(height: 22),
          r(
            const LuxeDisclosure(
              title: 'How earmarking works',
              body:
                  'Money here is earmarked from your balance — still yours, not spending. '
                  'Adding to it lowers "available to spend"; withdrawing releases it back. '
                  'Your net worth stays the same.',
            ),
          ),
        ],
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.status});

  final EmergencyFundStatus status;

  @override
  Widget build(BuildContext context) {
    final p = context.luxe;
    final t = context.lt;
    final s = status;
    final configured = s.level != EmergencyFundLevel.notConfigured;
    final coverage = s.coverageMonths;
    final months = s.plan?.targetMonths;
    final soft = p.onObsidianSoft;
    final levelTone = switch (s.level) {
      EmergencyFundLevel.funded => p.isDark ? p.positive : const Color(0xFF9BD3B5),
      EmergencyFundLevel.critical => p.isDark ? p.negative : const Color(0xFFF0A49B),
      _ => p.gold,
    };
    return LuxeObsidian(
      glow: levelTone,
      semanticLabel: configured
          ? 'Emergency fund, ${s.level.label}. ${savingsMoney(context, s.saved)} set aside of '
                '${savingsMoney(context, s.target)}.'
                '${coverage == null ? '' : ' Covers about ${coverageLabel(coverage)} of essentials.'}'
          : 'Emergency fund not set up. ${savingsMoney(context, s.saved)} set aside.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('EMERGENCY FUND', style: t.eyebrow.copyWith(fontSize: 10, color: soft)),
                    const SizedBox(height: 8),
                    LuxeStatus(label: s.level.label.toUpperCase(), color: levelTone, icon: emergencyLevelIcon(s.level)),
                    const SizedBox(height: 14),
                    LuxeAmount(
                      s.saved,
                      countFromZero: true,
                      style: t.display.copyWith(fontSize: 40, color: p.onObsidian),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      !configured
                          ? 'Set a target from your essential monthly spending to track coverage.'
                          : (coverage == null
                                ? 'earmarked'
                                : 'earmarked · covers about ${coverageLabel(coverage)} of essentials'),
                      style: t.caption.c(soft),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _Vessel(progress: configured ? s.progress : 0, tone: levelTone, empty: !configured),
            ],
          ),
          if (configured) ...[
            const SizedBox(height: 20),
            if (coverage != null && months != null) ...[
              _CoverCells(covered: coverage, months: months, tone: levelTone),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '1 cell = 1 month of essentials',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.micro.c(soft),
                    ),
                  ),
                  Text('$months mo', style: t.micro.w(750).c(p.onObsidian)),
                ],
              ),
              const SizedBox(height: 16),
            ],
            SizedBox(height: 1, child: ColoredBox(color: p.onObsidian.withValues(alpha: 0.1))),
            const SizedBox(height: 14),
            Row(
              children: [
                Text('${formatBps(s.progressBps, decimals: 0)} funded', style: t.label.w(750).c(p.onObsidian)),
                const Spacer(),
                Flexible(
                  child: Text(
                    'Target ${savingsMoney(context, s.target)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.label.c(soft),
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

/// A round vessel whose liquid pours in to the funded share, sloshes and
/// comes to rest. Tapping it swirls the surface again.
class _Vessel extends StatefulWidget {
  const _Vessel({required this.progress, required this.tone, required this.empty});

  final double progress;
  final Color tone;
  final bool empty;

  @override
  State<_Vessel> createState() => _VesselState();
}

class _VesselState extends State<_Vessel> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 4200));
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (context.reduceMotion) {
      _c.value = 1;
    } else {
      _c.forward();
    }
  }

  @override
  void didUpdateWidget(_Vessel old) {
    super.didUpdateWidget(old);
    if (old.progress != widget.progress && !context.reduceMotion) _c.forward(from: 0.35);
  }

  void _swirl() {
    if (context.reduceMotion) return;
    HapticFeedback.lightImpact();
    _c.forward(from: 0.3);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.luxe;
    final t = context.lt;
    final pct = (widget.progress * 100).round();
    return Semantics(
      label: widget.empty ? 'No plan yet' : '$pct percent funded',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: _swirl,
        child: SizedBox.square(
          dimension: 112,
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              final v = _c.value;
              // Level pours in during the first third, then holds.
              final level = widget.progress * LuxeCurves.arrive.transform((v / 0.4).clamp(0.0, 1.0));
              // Wave energy decays to a still surface.
              final energy = math.pow(1 - v, 2).toDouble();
              return CustomPaint(
                painter: _VesselPainter(
                  level: level,
                  phase: v * math.pi * 9,
                  energy: energy,
                  tone: widget.tone,
                  glass: p.onObsidian.withValues(alpha: 0.14),
                  tick: p.onObsidian.withValues(alpha: 0.3),
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.empty ? '—' : '${(level * 100).round()}%',
                        style: t.figure.copyWith(fontSize: 26, color: p.onObsidian),
                      ),
                      Text('FUNDED', style: t.eyebrow.copyWith(fontSize: 8, color: p.onObsidianSoft)),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _VesselPainter extends CustomPainter {
  _VesselPainter({
    required this.level,
    required this.phase,
    required this.energy,
    required this.tone,
    required this.glass,
    required this.tick,
  });

  final double level;
  final double phase;
  final double energy;
  final Color tone;
  final Color glass;
  final Color tick;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 4;
    final inner = r - 5;
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = glass,
    );
    // Quarter marks on the glass.
    for (final f in const [0.25, 0.5, 0.75]) {
      final y = c.dy + inner - 2 * inner * f;
      final half = math.sqrt(math.max(0, inner * inner - (y - c.dy) * (y - c.dy)));
      canvas.drawLine(
        Offset(c.dx + half - 6, y),
        Offset(c.dx + half - 1, y),
        Paint()
          ..color = tick
          ..strokeWidth = 1,
      );
    }
    if (level <= 0.001) return;
    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: inner)));
    final surface = c.dy + inner - 2 * inner * level;
    Path wave(double amp, double shift) {
      final path = Path()..moveTo(c.dx - inner, size.height);
      for (var x = -inner; x <= inner; x += 2) {
        final y = surface + math.sin((x / inner) * math.pi * 1.6 + phase + shift) * amp;
        path.lineTo(c.dx + x, y);
      }
      path
        ..lineTo(c.dx + inner, size.height)
        ..close();
      return path;
    }

    final amp = 1.2 + 6 * energy;
    canvas.drawPath(wave(amp * 0.8, math.pi), Paint()..color = tone.withValues(alpha: 0.35));
    canvas.drawPath(
      wave(amp, 0),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [tone.withValues(alpha: 0.95), tone.withValues(alpha: 0.55)],
        ).createShader(Rect.fromLTRB(0, surface, size.width, size.height)),
    );
    // A gloss line along the surface.
    canvas.drawLine(
      Offset(c.dx - inner * 0.5, surface + 3),
      Offset(c.dx - inner * 0.15, surface + 3),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.25)
        ..strokeWidth = 1.4
        ..strokeCap = StrokeCap.round,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_VesselPainter o) => o.level != level || o.phase != phase || o.energy != energy || o.tone != tone;
}

/// Months of cover as a row of cells, one per planned month, filling in
/// sequence like a battery. A partial cell shows the fraction.
class _CoverCells extends StatelessWidget {
  const _CoverCells({required this.covered, required this.months, required this.tone});

  final double covered;
  final int months;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final p = context.luxe;
    return ExcludeSemantics(
      child: SizedBox(
        height: 14,
        child: DrawIn(
          value: covered.clamp(0, months.toDouble()),
          duration: const Duration(milliseconds: 1500),
          delay: const Duration(milliseconds: 300),
          builder: (context, v) => Row(
            children: [
              for (var i = 0; i < months; i++) ...[
                if (i > 0) const SizedBox(width: 4),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ColoredBox(color: p.onObsidian.withValues(alpha: 0.08)),
                        FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: (v - i).clamp(0.0, 1.0),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(colors: [tone.withValues(alpha: 0.7), tone]),
                            ),
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

/// Shown before a plan exists.
class _SetUpCard extends StatelessWidget {
  const _SetUpCard({required this.status});

  final EmergencyFundStatus status;

  @override
  Widget build(BuildContext context) {
    final p = context.luxe;
    final t = context.lt;
    final suggestion = status.suggestedEssentialMonthly;
    return LuxeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const LuxeEyebrowHeader(label: 'Plan your safety net'),
          const SizedBox(height: 12),
          Text('How many months could you live without income?', style: t.title.copyWith(fontSize: 22)),
          const SizedBox(height: 8),
          Text(
            suggestion == null
                ? 'Tell us your essential monthly spending and how many months of cover you want. '
                      'Most people aim for 3–6 months.'
                : 'Your essentials averaged ${savingsMoney(context, suggestion)} a month recently. '
                      'Most people aim to cover 3–6 months of that.',
            style: t.bodySoft,
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              for (final m in const [3, 6, 9]) ...[
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: m == 6 ? p.goldSoft : p.canvas,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: m == 6 ? p.gold.withValues(alpha: 0.5) : p.line),
                    ),
                    child: Column(
                      children: [
                        Text('$m', style: t.figure.copyWith(fontSize: 22)),
                        Text(
                          m == 3 ? 'MINIMUM' : (m == 6 ? 'TYPICAL' : 'CAUTIOUS'),
                          style: t.eyebrow.copyWith(fontSize: 8.5),
                        ),
                      ],
                    ),
                  ),
                ),
                if (m != 9) const SizedBox(width: 8),
              ],
            ],
          ),
          const SizedBox(height: 18),
          LuxeButton(
            label: 'Set up plan',
            icon: LucideIcons.shieldCheck,
            expand: true,
            onPressed: () => context.push(AppRoutes.emergencyPlan),
          ),
        ],
      ),
    );
  }
}

class _MoneyButtons extends StatelessWidget {
  const _MoneyButtons({required this.status});

  final EmergencyFundStatus status;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        flex: 3,
        child: LuxeButton(
          label: 'Add money',
          icon: LucideIcons.plus,
          expand: true,
          onPressed: () => context.push(AppRoutes.emergencyContribute),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        flex: 2,
        child: LuxeButton(
          label: 'Withdraw',
          icon: LucideIcons.minus,
          variant: LuxeButtonVariant.outline,
          expand: true,
          onPressed: status.saved.isPositive ? () => context.push(AppRoutes.emergencyWithdraw) : null,
        ),
      ),
    ],
  );
}

/// Calm, level-specific guidance.
class _Guidance extends StatelessWidget {
  const _Guidance({required this.status});

  final EmergencyFundStatus status;

  @override
  Widget build(BuildContext context) {
    final p = context.luxe;
    final s = status;
    final remaining = savingsMoney(context, s.remaining);
    final (tone, icon, title, message) = switch (s.level) {
      EmergencyFundLevel.funded => (
        p.positive,
        LucideIcons.circleCheck,
        'Your safety net is in place',
        'You have reached your target. Keep it topped up if your essentials go up.',
      ),
      EmergencyFundLevel.critical => (
        p.warning,
        LucideIcons.shieldAlert,
        'Building your first cushion',
        'You have less than ${EmergencyFundCalculator.criticalMonths} months of essentials covered. '
            'Small, regular top-ups add up — $remaining to go.',
      ),
      _ => (p.goldInk, LucideIcons.trendingUp, 'Steady progress', '$remaining to go to reach your target.'),
    };
    return LuxeNote(icon: icon, tone: tone, title: title, message: message);
  }
}

/// The plan as an equation: essentials × months = target.
class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.status});

  final EmergencyFundStatus status;

  @override
  Widget build(BuildContext context) {
    final p = context.luxe;
    final t = context.lt;
    final s = status;
    final plan = s.plan!;
    final suggestion = s.suggestedEssentialMonthly;
    Widget term(String label, Widget value) => Expanded(
      child: MergeSemantics(
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
          decoration: BoxDecoration(color: p.canvas, borderRadius: BorderRadius.circular(16)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, maxLines: 2, style: t.eyebrow.copyWith(fontSize: 8.5)),
              const SizedBox(height: 6),
              FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: value),
            ],
          ),
        ),
      ),
    );
    Widget op(String s) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(s, style: t.title.copyWith(fontSize: 18, color: p.inkMute)),
    );
    return LuxeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Semantics(header: true, child: Text('Your plan', style: t.title.copyWith(fontSize: 22))),
              ),
              LuxeLink(label: 'Edit', icon: LucideIcons.pencil, onTap: () => context.push(AppRoutes.emergencyPlan)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              term(
                'ESSENTIALS PER MONTH',
                LuxeAmount(plan.essentialMonthlyExpenses, fit: false, style: t.number.copyWith(fontSize: 15)),
              ),
              op('×'),
              term(
                'MONTHS OF COVER',
                Text(
                  '${plan.targetMonths} month${plan.targetMonths == 1 ? '' : 's'}',
                  style: t.number.copyWith(fontSize: 15),
                ),
              ),
              op('='),
              term(
                plan.targetOverride == null ? 'TARGET' : 'TARGET (CUSTOM)',
                LuxeAmount(s.target, fit: false, style: t.number.copyWith(fontSize: 15, color: p.goldInk)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Icon(LucideIcons.flag, size: 13, color: p.inkMute),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  s.remaining.isPositive ? '${savingsMoney(context, s.remaining)} still to go' : 'Target reached',
                  style: t.label.w(700).c(p.ink),
                ),
              ),
              Text('Updated ${DateFormats.dayMonth.format(plan.updatedAt)}', style: t.micro),
            ],
          ),
          if (s.suggestionDiffersFromPlan && suggestion != null) ...[
            const SizedBox(height: 14),
            LuxeNote(
              icon: LucideIcons.sparkles,
              message:
                  'Your essentials averaged ${savingsMoney(context, suggestion)} a month over the last '
                  '3 months. You may want to review your plan.',
              actionLabel: 'Review plan',
              onAction: () => context.push(AppRoutes.emergencyPlan),
            ),
          ],
        ],
      ),
    );
  }
}

enum _Kind { all, added, withdrawn }

/// Movements grouped by month with each month's net, filterable by kind,
/// on a rail.
class _History extends StatefulWidget {
  const _History({required this.movements});

  final List<SavingsMovement> movements;

  @override
  State<_History> createState() => _HistoryState();
}

class _HistoryState extends State<_History> {
  _Kind _kind = _Kind.all;

  @override
  Widget build(BuildContext context) {
    final p = context.luxe;
    final t = context.lt;
    final all = widget.movements;
    final added = all.where((m) => m.kind == SavingsMovementKind.contribution).length;
    final withdrawn = all.length - added;
    final shown = all.where(
      (m) => switch (_kind) {
        _Kind.all => true,
        _Kind.added => m.kind == SavingsMovementKind.contribution,
        _Kind.withdrawn => m.kind == SavingsMovementKind.withdrawal,
      },
    );
    final groups = <MonthKey, List<SavingsMovement>>{};
    for (final m in shown) {
      groups.putIfAbsent(m.date.monthKey, () => []).add(m);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LuxeSectionHeader(
          title: 'History',
          caption: all.isEmpty ? null : '${all.length} movement${all.length == 1 ? '' : 's'}',
        ),
        if (all.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text('Nothing set aside yet. Your first contribution will show here.', style: t.bodySoft),
          )
        else ...[
          if (added > 0 && withdrawn > 0) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final (k, label, n) in [
                  (_Kind.all, 'All', all.length),
                  (_Kind.added, 'Added', added),
                  (_Kind.withdrawn, 'Withdrawn', withdrawn),
                ])
                  LuxeChip(
                    key: ValueKey('savings-history:${k.name}'),
                    label: label,
                    count: n,
                    selected: _kind == k,
                    onTap: () => setState(() => _kind = k),
                  ),
              ],
            ),
          ],
          for (final e in groups.entries) ...[
            Padding(
              padding: const EdgeInsets.only(top: 20, bottom: 8),
              child: Row(
                children: [
                  Text(DateFormats.monthYear.format(DateTime(e.key.year, e.key.month)).toUpperCase(), style: t.eyebrow),
                  const Spacer(),
                  LuxeAmount(
                    Money.sum(e.value.map((m) => m.signedAmount)),
                    sign: SignDisplay.always,
                    fit: false,
                    style: t.micro.w(750).c(p.inkSoft),
                  ),
                ],
              ),
            ),
            for (var k = 0; k < e.value.length; k++)
              LuxeRailNode(
                key: ValueKey(e.value[k].id),
                color: e.value[k].kind == SavingsMovementKind.contribution ? p.positive : p.inkMute,
                icon: e.value[k].kind == SavingsMovementKind.contribution
                    ? LucideIcons.arrowDownLeft
                    : LucideIcons.arrowUpRight,
                first: k == 0,
                last: k == e.value.length - 1,
                child: _MovementRow(movement: e.value[k]),
              ),
          ],
        ],
      ],
    );
  }
}

class _MovementRow extends StatelessWidget {
  const _MovementRow({required this.movement});

  final SavingsMovement movement;

  @override
  Widget build(BuildContext context) {
    final p = context.luxe;
    final t = context.lt;
    final m = movement;
    final contribution = m.kind == SavingsMovementKind.contribution;
    final subtitle = [
      DateFormats.dayMonthYear.format(m.date),
      if (m.note != null && m.note!.isNotEmpty) m.note!,
    ].join(' · ');
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(contribution ? 'Added' : 'Withdrawn', style: t.label.w(700).c(p.ink)),
                  const SizedBox(height: 2),
                  Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.caption),
                ],
              ),
            ),
            const SizedBox(width: 10),
            LuxeAmount(
              m.signedAmount,
              sign: SignDisplay.always,
              fit: false,
              style: t.number.copyWith(fontSize: 14, color: contribution ? p.positive : p.ink),
            ),
          ],
        ),
      ),
    );
  }
}
