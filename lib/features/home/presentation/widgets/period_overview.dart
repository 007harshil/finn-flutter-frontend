import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../app/di/core_providers.dart';
import '../../../../app/di/data_providers.dart';
import '../../../../app/router/routes.dart';
import '../../../../core/money/money.dart';
import '../../../../core/money/money_format.dart';
import '../../../../core/time/dates.dart';
import '../../../../design_system/design_system.dart';
import '../../../../finance/ledger.dart';
import '../../../../shared/presentation/async_view.dart';
import '../../../transactions/domain/transaction.dart';

final DateFormat _monthLabel = DateFormat('MMM yyyy');
final DateFormat _monthSpoken = DateFormat('MMMM yyyy');

/// One compact card that reads as an equation: money in, money out, what
/// you kept. Both bars share one scale and the ring shows the share of
/// income kept. Swipe sideways (or use the arrows) to change month; tap a
/// bar for its transactions.
class PeriodOverview extends ConsumerStatefulWidget {
  const PeriodOverview({super.key});

  @override
  ConsumerState<PeriodOverview> createState() => _PeriodOverviewState();
}

class _PeriodOverviewState extends ConsumerState<PeriodOverview> {
  MonthKey? _month;

  /// +1 when moving to a newer month, -1 to an older one: drives the slide.
  int _direction = 1;

  void _go(MonthKey from, MonthKey to, MonthKey min, MonthKey max) {
    if (to < min || to > max) return;
    HapticFeedback.selectionClick();
    setState(() {
      _direction = to > from ? 1 : -1;
      _month = to;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final today = ref.watch(todayProvider);
    final current = today.monthKey;
    final min = current.shift(-35);
    var month = _month ?? current;
    if (month > current) month = current;
    final isCurrent = month == current;
    void go(MonthKey to) => _go(month, to, min, current);

    return FinnCard(
      padding: const EdgeInsets.fromLTRB(Space.x4, Space.x1, Space.x1, Space.x4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconTile(
                icon: LucideIcons.chartColumn,
                background: c.accentTransactions,
                foreground: Colors.white,
                size: 28,
                radius: Radii.md,
                iconSize: 15,
              ),
              const SizedBox(width: Space.x2_5),
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text('CASH FLOW', style: t.sectionTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ),
              FinnIconButton(
                icon: LucideIcons.chevronLeft,
                tooltip: 'Previous month',
                size: FinnButtonSize.sm,
                onPressed: month > min ? () => go(month.previous) : null,
              ),
              _MonthLabel(month: month, direction: _direction, soFar: isCurrent),
              FinnIconButton(
                icon: LucideIcons.chevronRight,
                tooltip: 'Next month',
                size: FinnButtonSize.sm,
                onPressed: isCurrent ? null : () => go(month.next),
              ),
            ],
          ),
          const SizedBox(height: Space.x1),
          Padding(
            padding: const EdgeInsets.only(right: Space.x3),
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onHorizontalDragEnd: (d) {
                final v = d.primaryVelocity ?? 0;
                if (v < -200) go(month.next);
                if (v > 200) go(month.previous);
              },
              child: _MonthFlow(month: month, today: today, isCurrent: isCurrent),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Oct 2026" sliding in from the side the user moved towards.
class _MonthLabel extends StatelessWidget {
  const _MonthLabel({required this.month, required this.direction, required this.soFar});

  final MonthKey month;
  final int direction;
  final bool soFar;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final m = context.motion;
    return Semantics(
      liveRegion: true,
      label: '${_monthSpoken.format(month.start)}${soFar ? ', so far' : ''}',
      excludeSemantics: true,
      child: SizedBox(
        width: 76,
        child: ClipRect(
          child: AnimatedSwitcher(
            duration: m.normal,
            switchInCurve: m.standard,
            switchOutCurve: Curves2.exit,
            transitionBuilder: (child, a) {
              final incoming = child.key == ValueKey<MonthKey>(month);
              final dx = (incoming ? 0.6 : -0.6) * direction;
              return FadeTransition(
                opacity: a,
                child: SlideTransition(
                  position: Tween(begin: Offset(dx, 0), end: Offset.zero).animate(a),
                  child: child,
                ),
              );
            },
            child: Column(
              key: ValueKey<MonthKey>(month),
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _monthLabel.format(month.start),
                  maxLines: 1,
                  style: t.label.copyWith(fontWeight: FontWeight.w800, color: c.textPrimary),
                ),
                Text(
                  soFar ? 'so far' : 'full month',
                  maxLines: 1,
                  style: t.micro.copyWith(color: c.textTertiary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MonthFlow extends ConsumerWidget {
  const _MonthFlow({required this.month, required this.today, required this.isCurrent});

  final MonthKey month;
  final DateTime today;
  final bool isCurrent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Compare like with like: a month in progress is measured against the
    // same days of the month before, a finished month against all of it.
    final prev = month.previous;
    final compare = isCurrent
        ? DateRange(prev.start, DateTime(prev.year, prev.month, math.min(today.day, prev.dayCount)))
        : prev.range;
    final before = ref.watch(rangeSummaryProvider(compare)).value;
    return AsyncView<PeriodSummary>(
      value: ref.watch(monthSummaryProvider(month)),
      loading: const SkeletonPulse(child: CardSkeleton(height: 112)),
      builder: (context, s) => _FlowBody(summary: s, before: before, month: month, isCurrent: isCurrent),
    );
  }
}

class _FlowBody extends StatelessWidget {
  const _FlowBody({required this.summary, required this.before, required this.month, required this.isCurrent});

  final PeriodSummary summary;
  final PeriodSummary? before;
  final MonthKey month;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final hidden = AmountVisibility.hiddenOf(context);
    final income = summary.income;
    final expense = summary.expense;
    final top = math.max(income.paise, expense.paise);
    double share(Money m) => top <= 0 ? 0 : m.paise / top;
    final rate = income.isPositive ? summary.net.paise / income.paise : null;
    final prevName = DateFormats.shortMonth.format(month.previous.start);

    return Row(
      children: [
        _KeptRing(rate: hidden ? null : rate, hidden: hidden),
        const SizedBox(width: Space.x4),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _FlowRow(
                label: 'Income',
                icon: LucideIcons.arrowDownLeft,
                amount: income,
                share: share(income),
                color: c.positive,
                semanticLabel: 'Money in',
                onTap: () => context.push(AppRoutes.transactionsFiltered(type: TransactionType.income, month: month)),
              ),
              _FlowRow(
                label: 'Spent',
                icon: LucideIcons.arrowUpRight,
                amount: expense,
                share: share(expense),
                color: c.negative,
                semanticLabel: 'Money out',
                trailing: hidden ? null : _SpendDelta(now: expense, before: before?.expense, against: prevName),
                onTap: () => context.push(AppRoutes.transactionsFiltered(type: TransactionType.expense, month: month)),
              ),
              const SizedBox(height: Space.x1),
              _KeptLine(summary: summary, isCurrent: isCurrent),
            ],
          ),
        ),
      ],
    );
  }
}

/// Label + amount on one line, bar underneath. Both bars share one scale,
/// so their lengths compare directly.
class _FlowRow extends StatelessWidget {
  const _FlowRow({
    required this.label,
    required this.icon,
    required this.amount,
    required this.share,
    required this.color,
    required this.semanticLabel,
    required this.onTap,
    this.trailing,
  });

  final String label;
  final IconData icon;
  final Money amount;
  final double share;
  final Color color;
  final String semanticLabel;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final m = context.motion;
    final end = trailing;
    return PressableScale(
      onTap: onTap,
      haptic: true,
      semanticLabel: '$semanticLabel. Opens these transactions.',
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.x1),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(icon, size: 14, color: color),
                  const SizedBox(width: Space.x1),
                  Text(label, style: t.caption.copyWith(fontWeight: FontWeight.w700, color: c.textSecondary)),
                  if (end != null) ...[const SizedBox(width: Space.x1_5), Flexible(child: end)],
                  const SizedBox(width: Space.x2),
                  Expanded(
                    flex: 3,
                    child: AnimatedAmount(
                      amount,
                      style: t.amountSmall.copyWith(fontWeight: FontWeight.w800, color: c.textPrimary),
                      decimals: DecimalDisplay.none,
                      fit: true,
                      textAlign: TextAlign.end,
                      animateOnMount: true,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Space.x1_5),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: share.clamp(0.0, 1.0)),
                duration: m.progress,
                curve: Curves2.emphasized,
                builder: (context, v, _) => _Bar(value: v, color: color, track: c.surfaceMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.value, required this.color, required this.track});

  final double value;
  final Color color;
  final Color track;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 6,
      decoration: BoxDecoration(color: track, borderRadius: Radii.rFull),
      alignment: AlignmentDirectional.centerStart,
      child: FractionallySizedBox(
        widthFactor: value,
        heightFactor: 1,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: Radii.rFull,
            gradient: LinearGradient(colors: [color.withValues(alpha: 0.55), color]),
          ),
        ),
      ),
    );
  }
}

/// "↓ 12% vs Sep": spending against the same stretch of last month. Less
/// spending is good news, so it is green.
class _SpendDelta extends StatelessWidget {
  const _SpendDelta({required this.now, required this.before, required this.against});

  final Money now;
  final Money? before;
  final String against;

  @override
  Widget build(BuildContext context) {
    final b = before;
    if (b == null || !b.isPositive) return const SizedBox.shrink();
    final c = context.colors;
    final t = context.text;
    final pct = ((now.paise - b.paise) / b.paise * 100).round();
    final down = pct < 0;
    final color = pct == 0 ? c.textTertiary : (down ? c.positive : c.negative);
    final text = pct == 0 ? 'same as $against' : '${pct.abs()}% vs $against';
    return Semantics(
      label: pct == 0
          ? 'Spending is the same as $against'
          : 'Spending is ${pct.abs()} percent ${down ? 'lower' : 'higher'} than $against',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (pct != 0) Icon(down ? LucideIcons.trendingDown : LucideIcons.trendingUp, size: 12, color: color),
          if (pct != 0) const SizedBox(width: Space.x0_5),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.micro.copyWith(color: color, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

/// The result of the equation: kept or overspent.
class _KeptLine extends StatelessWidget {
  const _KeptLine({required this.summary, required this.isCurrent});

  final PeriodSummary summary;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final net = summary.net;
    if (summary.income.isZero && summary.expense.isZero) {
      return Text(
        isCurrent ? 'Nothing recorded yet this month' : 'Nothing recorded this month',
        style: t.caption.copyWith(color: c.textTertiary),
      );
    }
    final kept = !net.isNegative;
    final color = kept ? c.positive : c.negative;
    return Container(
      padding: const EdgeInsets.only(top: Space.x2),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: c.border))),
      child: MergeSemantics(
        child: Row(
          children: [
            Icon(kept ? LucideIcons.piggyBank : LucideIcons.triangleAlert, size: 14, color: color),
            const SizedBox(width: Space.x1),
            Flexible(
              flex: 2,
              child: Text(
                kept ? (isCurrent ? 'Kept so far' : 'Kept') : 'Overspent by',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.caption.copyWith(fontWeight: FontWeight.w800, color: color),
              ),
            ),
            const SizedBox(width: Space.x2),
            Expanded(
              flex: 3,
              child: AnimatedAmount(
                net.abs(),
                style: t.amountSmall.copyWith(fontWeight: FontWeight.w900, color: color),
                decimals: DecimalDisplay.none,
                fit: true,
                textAlign: TextAlign.end,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Share of income kept. Fills clockwise in green when you kept money,
/// anticlockwise in red when you spent more than came in.
class _KeptRing extends StatelessWidget {
  const _KeptRing({required this.rate, required this.hidden});

  /// net / income; null when there is no income or amounts are hidden.
  final double? rate;
  final bool hidden;

  static const double _size = 72;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final m = context.motion;
    final r = rate;
    final String label;
    if (r == null) {
      label = hidden ? 'Savings rate hidden' : 'No income recorded';
    } else if (r >= 0) {
      label = 'Kept ${(r * 100).round()} percent of income';
    } else {
      label = 'Spent ${(-r * 100).round()} percent more than income';
    }
    return Semantics(
      label: label,
      excludeSemantics: true,
      child: RepaintBoundary(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: (r ?? 0).clamp(-1.0, 1.0)),
          duration: m.progress,
          curve: Curves2.emphasized,
          builder: (context, v, _) {
            final color = v >= 0 ? c.positive : c.negative;
            return SizedBox.square(
              dimension: _size,
              child: CustomPaint(
                painter: _RingPainter(value: v, color: color, track: c.surfaceMuted),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        r == null ? (hidden ? '••' : '—') : '${(v * 100).round()}%',
                        style: t.bodyStrong.copyWith(
                          fontWeight: FontWeight.w900,
                          fontSize: 17,
                          height: 1.1,
                          color: r == null ? c.textTertiary : color,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      Text(
                        r == null ? (hidden ? 'hidden' : 'no income') : (r >= 0 ? 'kept' : 'over'),
                        style: t.micro.copyWith(color: c.textTertiary, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.value, required this.color, required this.track});

  final double value;
  final Color color;
  final Color track;

  static const double _stroke = 7;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(_stroke / 2);
    canvas.drawArc(
      rect,
      0,
      math.pi * 2,
      false,
      Paint()
        ..color = track
        ..style = PaintingStyle.stroke
        ..strokeWidth = _stroke,
    );
    if (value.abs() < 0.002) return;
    final sweep = value * math.pi * 2;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      sweep,
      false,
      Paint()
        ..shader = SweepGradient(
          startAngle: 0,
          endAngle: math.pi * 2,
          transform: const GradientRotation(-math.pi / 2),
          colors: [color.withValues(alpha: 0.6), color],
        ).createShader(rect)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = _stroke,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.value != value || old.color != color || old.track != track;
}
