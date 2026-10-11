import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/di/data_providers.dart';
import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/time/dates.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/presentation/category_icons.dart';
import '../application/budget_view.dart';
import '../domain/budget.dart';

/// Visual mapping of budget health. Colour is always paired with an icon
/// and a text label.
extension BudgetHealthUi on BudgetHealth {
  FinnTone get tone => switch (this) {
        BudgetHealth.healthy => FinnTone.positive,
        BudgetHealth.warning => FinnTone.warning,
        BudgetHealth.breached => FinnTone.negative,
        BudgetHealth.paused => FinnTone.info,
      };

  Color color(FinnColors c) => this == BudgetHealth.paused ? c.textTertiary : tone.color(c);

  IconData get icon => this == BudgetHealth.paused ? LucideIcons.circlePause : tone.icon;
}

/// The single status word per budget, as colour + icon.
extension BudgetStateUi on BudgetState {
  Color color(FinnColors c) => switch (this) {
        BudgetState.over => c.negative,
        BudgetState.risk => c.warning,
        BudgetState.onTrack => c.positive,
        BudgetState.paused => c.textTertiary,
      };

  IconData get icon => switch (this) {
        BudgetState.over => LucideIcons.triangleAlert,
        BudgetState.risk => LucideIcons.gauge,
        BudgetState.onTrack => LucideIcons.circleCheck,
        BudgetState.paused => LucideIcons.circlePause,
      };

  /// Short chip label ("2 over").
  String countLabel(int n) => switch (this) {
        BudgetState.over => '$n over',
        BudgetState.risk => '$n at risk',
        BudgetState.onTrack => '$n on track',
        BudgetState.paused => '$n paused',
      };
}

/// Money as text, respecting "hide balances".
String budgetMoney(BuildContext context, Money m, {SignDisplay sign = SignDisplay.auto}) =>
    AmountVisibility.hiddenOf(context) ? MoneyFormatter.masked : m.format(sign: sign);

/// "1 Oct – 31 Oct" (adds the year when the range crosses years).
String periodLabel(DateRange r) {
  final sameYear = r.start.year == r.end.year;
  final start = sameYear ? DateFormats.dayMonth.format(r.start) : DateFormats.dayMonthYear.format(r.start);
  return '$start – ${DateFormats.dayMonthYear.format(r.end)}';
}

/// Days left in [r] counting today (0 when it has ended).
int daysLeftIn(DateRange r, DateTime today) {
  if (today.isAfter(r.end)) return 0;
  if (today.isBefore(r.start)) return r.dayCount;
  return daysBetween(today, r.end) + 1;
}

String daysLeftLabel(int days) => switch (days) {
      0 => 'Period ended',
      1 => 'Last day',
      _ => '$days days left',
    };

/// One line that tells what to do with a budget, e.g. "₹1,800 left ·
/// ₹90/day" or "Runs out ~24 Oct".
String budgetHint(BuildContext context, BudgetPace p) {
  final u = p.usage;
  String m(Money x) => budgetMoney(context, x);
  return switch (p.state) {
    BudgetState.paused => 'Paused · ${m(u.spent)} spent',
    BudgetState.over => 'Over by ${m(-u.remaining)}',
    _ when p.runsOutOn != null => '${m(u.remaining)} left · runs out ~${DateFormats.dayMonth.format(p.runsOutOn!)}',
    _ when p.safePerDay != null => '${m(u.remaining)} left · ${m(p.safePerDay!)}/day',
    _ => '${m(u.remaining)} left',
  };
}

/// Horizontal pace bar: spent so far (solid), where spending is heading at
/// today's pace (hatched), the limit, and a "today" tick showing how much
/// of the limit the calendar allows by now. Solid past the tick = spending
/// faster than the month is passing.
class PaceTrack extends StatelessWidget {
  const PaceTrack({
    super.key,
    required this.used,
    required this.elapsed,
    required this.color,
    this.projected,
    this.height = 6,
    this.showToday = true,
  });

  /// Spent share of the limit (may exceed 1).
  final double used;

  /// Projected share of the limit (may exceed 1).
  final double? projected;

  /// Share of the period gone (0..1).
  final double elapsed;
  final Color color;
  final double height;
  final bool showToday;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return RepaintBoundary(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: context.reduceMotion ? Duration.zero : const Duration(milliseconds: 900),
        curve: Curves2.emphasized,
        builder: (context, t, _) => CustomPaint(
          size: Size(double.infinity, height + (showToday ? 6 : 0)),
          painter: _PacePainter(
            used: used * t,
            projected: projected == null ? null : (used + (projected! - used) * Curves.easeIn.transform(t)),
            elapsed: elapsed,
            todayOpacity: t,
            color: color,
            over: c.negative,
            track: c.surfaceMuted,
            ink: c.textPrimary,
            bar: height,
            showToday: showToday,
          ),
        ),
      ),
    );
  }
}

class _PacePainter extends CustomPainter {
  const _PacePainter({
    required this.used,
    required this.projected,
    required this.elapsed,
    required this.todayOpacity,
    required this.color,
    required this.over,
    required this.track,
    required this.ink,
    required this.bar,
    required this.showToday,
  });

  final double used;
  final double? projected;
  final double elapsed;
  final double todayOpacity;
  final Color color;
  final Color over;
  final Color track;
  final Color ink;
  final double bar;
  final bool showToday;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final top = (size.height - bar) / 2;
    final scale = math.max(1.0, math.max(used, projected ?? 0)).clamp(1.0, 1.6);
    final limitX = w / scale;
    final r = Radius.circular(bar / 2);
    final whole = RRect.fromRectAndRadius(Rect.fromLTWH(0, top, w, bar), r);
    canvas.drawRRect(whole, Paint()..color = track);
    canvas.save();
    canvas.clipRRect(whole);

    final spentX = (used / scale).clamp(0.0, 1.0) * w;
    final projX = projected == null ? spentX : (projected! / scale).clamp(0.0, 1.0) * w;

    // Where spending is heading: hatched, red where it crosses the limit.
    if (projX > spentX + 1) {
      final rect = Rect.fromLTRB(spentX, top, projX, top + bar);
      canvas.drawRect(rect, Paint()..color = color.withValues(alpha: 0.14));
      final stripe = Paint()
        ..color = (projected! > 1 ? over : color).withValues(alpha: 0.5)
        ..strokeWidth = 1.4;
      canvas.save();
      canvas.clipRect(rect);
      for (var x = rect.left - bar; x < rect.right; x += 5) {
        canvas.drawLine(Offset(x, rect.bottom), Offset(x + bar, rect.top), stripe);
      }
      canvas.restore();
    }

    // Spent: in budget colour up to the limit, red beyond it.
    if (spentX > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(0, top, math.min(spentX, limitX), bar), r),
        Paint()..color = color,
      );
      if (spentX > limitX) {
        canvas.drawRect(Rect.fromLTRB(limitX, top, spentX, top + bar), Paint()..color = over);
      }
    }
    canvas.restore();

    // Limit edge when the scale extends past it.
    if (scale > 1.001) {
      canvas.drawLine(
        Offset(limitX, top - 2),
        Offset(limitX, top + bar + 2),
        Paint()
          ..color = ink.withValues(alpha: 0.55)
          ..strokeWidth = 1.5,
      );
    }

    // Today: how much of the limit the calendar allows by now.
    if (showToday && elapsed > 0 && elapsed < 1) {
      final x = elapsed * limitX;
      final p = Paint()
        ..color = ink.withValues(alpha: todayOpacity)
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(x, 1), Offset(x, size.height - 1), p);
    }
  }

  @override
  bool shouldRepaint(_PacePainter old) =>
      old.used != used ||
      old.projected != projected ||
      old.elapsed != elapsed ||
      old.todayOpacity != todayOpacity ||
      old.color != color ||
      old.track != track ||
      old.ink != ink;
}

/// Compact two-and-a-half-line budget: icon in a usage ring, name, spent,
/// pace bar, one hint line. Colour, icon and words all carry the status.
class BudgetRow extends ConsumerWidget {
  const BudgetRow({super.key, required this.pace, required this.onTap, this.onLongPress});

  final BudgetPace pace;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final t = context.text;
    final p = pace;
    final u = p.usage;
    final category = ref.watch(categoryProvider(u.budget.categoryId));
    final name = category?.name ?? 'Deleted category';
    final paused = p.state == BudgetState.paused;
    final color = p.state.color(c);
    final custom = u.budget.periodType == BudgetPeriodType.custom;
    final hint = budgetHint(context, p);
    return Semantics(
      button: true,
      label: '$name budget, ${p.state.label}. Spent ${budgetMoney(context, u.spent)} of '
          '${budgetMoney(context, u.budget.limit)}. $hint.',
      excludeSemantics: true,
      child: PressableScale(
        child: Material(
          color: paused ? c.surfaceMuted : c.surface,
          shape: RoundedRectangleBorder(borderRadius: Radii.rXl, side: BorderSide(color: c.border)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () {
              HapticFeedback.selectionClick();
              onTap();
            },
            onLongPress: onLongPress == null
                ? null
                : () {
                    HapticFeedback.mediumImpact();
                    onLongPress!();
                  },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Space.x3, Space.x3, Space.x3, Space.x2_5),
              child: Row(
                children: [
                  Opacity(
                    opacity: paused ? 0.55 : 1,
                    child: ProgressRing(
                      value: u.utilization,
                      size: 44,
                      strokeWidth: 4,
                      color: color,
                      child: Icon(
                        CategoryIcons.of(category?.iconKey),
                        size: 22,
                        color: AccentSwatches.solid(category?.colorIndex ?? 6),
                      ),
                    ),
                  ),
                  const SizedBox(width: Space.x3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.bodyStrong),
                            ),
                            if (custom) ...[
                              const SizedBox(width: Space.x1),
                              Tooltip(
                                message: periodLabel(u.period),
                                child: Icon(LucideIcons.calendarRange, size: 12, color: c.textTertiary),
                              ),
                            ],
                            const Spacer(),
                            const SizedBox(width: Space.x2),
                            AmountText(
                              u.spent,
                              style: t.amountSmall.copyWith(color: u.isOver ? c.negative : c.textPrimary),
                            ),
                          ],
                        ),
                        const SizedBox(height: Space.x1_5),
                        PaceTrack(
                          used: p.used,
                          projected: paused ? null : p.projectedShare,
                          elapsed: paused ? 0 : p.elapsed,
                          color: color,
                        ),
                        const SizedBox(height: Space.x1_5),
                        Row(
                          children: [
                            Icon(p.state.icon, size: 12, color: color),
                            const SizedBox(width: Space.x1),
                            Expanded(
                              child: Text(
                                hint,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: t.caption.copyWith(
                                  color: p.state == BudgetState.onTrack || paused ? c.textSecondary : color,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(width: Space.x2),
                            Text('of ${budgetMoney(context, u.budget.limit)}', style: t.micro),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
