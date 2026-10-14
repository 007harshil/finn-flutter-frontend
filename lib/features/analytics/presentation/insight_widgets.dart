import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../design_system/design_system.dart';
import '../application/analytics_providers.dart';

/// Shared building blocks for the Insights sections: entrance animation,
/// KPI strips, gauges, split bars and plain-language takeaways.

extension InsightsSectionUi on InsightsSection {
  IconData get icon => switch (this) {
        InsightsSection.overview => LucideIcons.layoutDashboard,
        InsightsSection.spending => LucideIcons.calendarDays,
        InsightsSection.cashFlow => LucideIcons.arrowLeftRight,
        InsightsSection.categories => LucideIcons.chartPie,
        InsightsSection.payments => LucideIcons.creditCard,
        InsightsSection.budgets => LucideIcons.target,
        InsightsSection.savings => LucideIcons.piggyBank,
        InsightsSection.loans => LucideIcons.landmark,
        InsightsSection.subscriptions => LucideIcons.repeat,
      };

  Color accent(FinnColors c) => switch (this) {
        InsightsSection.overview => c.accentAnalytics,
        InsightsSection.spending => c.info,
        InsightsSection.cashFlow => c.accentNetWorth,
        InsightsSection.categories => c.accentPending,
        InsightsSection.payments => c.accentTransactions,
        InsightsSection.budgets => c.accentBudgets,
        InsightsSection.savings => c.accentGoals,
        InsightsSection.loans => c.accentLoans,
        InsightsSection.subscriptions => c.accentSubscriptions,
      };
}

/// Money as text for generated copy, masked when balances are hidden.
String moneyText(BuildContext context, Money m, {bool compact = false, SignDisplay sign = SignDisplay.auto}) {
  if (AmountVisibility.hiddenOf(context)) return MoneyFormatter.masked;
  return compact
      ? MoneyFormatter.compact(m)
      : MoneyFormatter.format(m, sign: sign, decimals: DecimalDisplay.none);
}

/// Masks rupee amounts inside generated copy when balances are hidden.
String maskAmounts(String s, bool hidden) =>
    hidden ? s.replaceAll(RegExp(r'[−-]?₹[\d,]+(\.\d+)?[KLCr]*'), MoneyFormatter.masked) : s;

/// Plays a 0 → 1 progress once when first built, so charts grow into
/// place. Jumps straight to 1 under reduced motion.
class GrowIn extends StatelessWidget {
  const GrowIn({super.key, required this.builder});

  final Widget Function(BuildContext context, double t) builder;

  @override
  Widget build(BuildContext context) {
    final m = context.motion;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: m.reduced ? 1 : 0, end: 1),
      duration: m.progress,
      curve: Curves2.emphasized,
      builder: (context, t, _) => builder(context, t),
    );
  }
}

/// A big, plain-language sentence that opens a section: the one thing to
/// know before reading any chart.
class TakeawayCard extends StatelessWidget {
  const TakeawayCard({
    super.key,
    required this.icon,
    required this.title,
    this.body,
    this.tone = FinnTone.info,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String? body;
  final FinnTone tone;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final color = tone.color(c);
    final b = body;
    return Container(
      padding: const EdgeInsets.all(Space.x4),
      decoration: BoxDecoration(
        color: tone.soft(c),
        borderRadius: Radii.rXl,
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: MergeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IconTile(
              icon: icon,
              background: color.withValues(alpha: c.isDark ? 0.25 : 0.16),
              foreground: color,
              size: 36,
              radius: Radii.md,
              iconSize: 18,
            ),
            const SizedBox(width: Space.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: t.bodyStrong.copyWith(fontSize: 16, height: 1.3)),
                  if (b != null) ...[
                    const SizedBox(height: Space.x1),
                    Text(b, style: t.caption.copyWith(color: c.textSecondary, height: 1.4)),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: Space.x2), trailing!],
          ],
        ),
      ),
    );
  }
}

/// One number in a [KpiStrip].
@immutable
class Kpi {
  const Kpi({required this.label, required this.value, this.caption, this.captionColor});

  final String label;

  /// Usually an `AmountText` or a `Text`; scaled down to fit.
  final Widget value;
  final String? caption;
  final Color? captionColor;
}

/// Two to three headline numbers side by side in one card.
class KpiStrip extends StatelessWidget {
  const KpiStrip({super.key, required this.items});
  final List<Kpi> items;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    return FinnCard(
      padding: const EdgeInsets.symmetric(vertical: Space.x3 + 2, horizontal: Space.x2),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) VerticalDivider(width: 1, thickness: 1, color: c.border),
              Expanded(
                child: MergeSemantics(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Space.x2),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(items[i].label.toUpperCase(),
                            style: t.micro.copyWith(color: c.textTertiary, letterSpacing: 0.6, fontWeight: FontWeight.w800),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis),
                        const SizedBox(height: Space.x1),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: DefaultTextStyle.merge(style: t.amountSmall, child: items[i].value),
                        ),
                        if (items[i].caption != null) ...[
                          const SizedBox(height: Space.x0_5),
                          Text(
                            items[i].caption!,
                            style: t.micro.copyWith(
                              color: items[i].captionColor ?? c.textSecondary,
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Circular gauge that sweeps to [value] (0–1; values above 1 draw a
/// full ring). An optional [marker] (0–1) draws a tick, e.g. "time passed".
class RingGauge extends StatelessWidget {
  const RingGauge({
    super.key,
    required this.value,
    required this.color,
    this.size = 92,
    this.stroke = 10,
    this.marker,
    this.center,
    this.semanticLabel,
  });

  final double value;
  final Color color;
  final double size;
  final double stroke;
  final double? marker;
  final Widget? center;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      label: semanticLabel,
      excludeSemantics: semanticLabel != null,
      child: GrowIn(
        builder: (context, t) => SizedBox.square(
          dimension: size,
          child: CustomPaint(
            painter: _RingPainter(
              value: value.clamp(0, 1) * t,
              color: color,
              track: c.surfaceMuted,
              stroke: stroke,
              marker: marker,
              markerColor: c.textPrimary,
            ),
            child: center == null
                ? null
                : Center(
                    child: Padding(
                      padding: EdgeInsets.all(stroke + 4),
                      child: FittedBox(fit: BoxFit.scaleDown, child: center),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.value,
    required this.color,
    required this.track,
    required this.stroke,
    required this.marker,
    required this.markerColor,
  });

  final double value;
  final Color color;
  final Color track;
  final double stroke;
  final double? marker;
  final Color markerColor;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final arcRect = rect.deflate(stroke / 2);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(arcRect, 0, math.pi * 2, false, base..color = track);
    if (value > 0) {
      canvas.drawArc(arcRect, -math.pi / 2, math.pi * 2 * value, false, base..color = color);
    }
    final m = marker;
    if (m != null) {
      final angle = -math.pi / 2 + math.pi * 2 * m.clamp(0, 1);
      final r = size.width / 2;
      final c = rect.center;
      final dir = Offset(math.cos(angle), math.sin(angle));
      canvas.drawLine(
        c + dir * (r - stroke - 3),
        c + dir * (r + 1),
        Paint()
          ..color = markerColor
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value || old.color != color || old.track != track || old.marker != marker;
}

/// One part of a [SplitBar].
@immutable
class SplitSegment {
  const SplitSegment(this.value, this.color, {this.label});
  final double value;
  final Color color;
  final String? label;
}

/// Horizontal bar split into proportional coloured parts that slide in.
class SplitBar extends StatelessWidget {
  const SplitBar({super.key, required this.segments, this.height = 14, this.semanticLabel});

  final List<SplitSegment> segments;
  final double height;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final total = segments.fold<double>(0, (a, s) => a + math.max(0, s.value));
    return Semantics(
      label: semanticLabel,
      excludeSemantics: semanticLabel != null,
      child: GrowIn(
        builder: (context, t) => ClipRRect(
          borderRadius: Radii.rFull,
          child: SizedBox(
            height: height,
            child: LayoutBuilder(
              builder: (context, box) {
                final w = box.maxWidth;
                final parts = segments.where((s) => s.value > 0).toList();
                return Stack(
                  children: [
                    Positioned.fill(child: ColoredBox(color: c.surfaceMuted)),
                    if (total > 0)
                      Row(
                        children: [
                          for (var i = 0; i < parts.length; i++) ...[
                            if (i > 0) SizedBox(width: 2 * t),
                            Container(
                              width: math.max(0, w * parts[i].value / total * t - (i > 0 ? 2 : 0)),
                              color: parts[i].color,
                            ),
                          ],
                        ],
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Small coloured dot + label + value used under split bars and gauges.
class LegendValue extends StatelessWidget {
  const LegendValue({super.key, required this.color, required this.label, required this.value, this.dashed = false});

  final Color color;
  final String label;
  final String value;
  final bool dashed;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    return MergeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: dashed ? 3 : 10,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
          ),
          const SizedBox(width: Space.x1_5),
          Text(label, style: t.caption.copyWith(color: c.textSecondary)),
          const SizedBox(width: Space.x1),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value, style: t.caption.copyWith(color: c.textPrimary, fontWeight: FontWeight.w800)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Muted placeholder shown inside a card when there is nothing to chart.
class InsightNoData extends StatelessWidget {
  const InsightNoData({super.key, required this.message, this.icon = LucideIcons.chartNoAxesColumn, this.action});

  final String message;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: Space.x6, horizontal: Space.x4),
          decoration: BoxDecoration(color: c.surfaceMuted, borderRadius: Radii.rLg),
          child: Column(
            children: [
              Icon(icon, size: 22, color: c.textTertiary),
              const SizedBox(height: Space.x2),
              Text(message, textAlign: TextAlign.center, style: context.text.caption.copyWith(color: c.textSecondary)),
            ],
          ),
        ),
        if (action != null) ...[const SizedBox(height: Space.x3), action!],
      ],
    );
  }
}

/// Thin bar showing [value] (0–1) of the widest item, used in ranked lists.
class RelativeBar extends StatelessWidget {
  const RelativeBar({super.key, required this.value, required this.color, this.height = 6, this.marker});

  final double value;
  final Color color;
  final double height;

  /// Optional tick (0–1), e.g. how much of the budget period has passed.
  final double? marker;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GrowIn(
      builder: (context, t) => SizedBox(
        height: height + (marker == null ? 0 : 6),
        child: LayoutBuilder(
          builder: (context, box) {
            final w = box.maxWidth;
            return Stack(
              alignment: Alignment.centerLeft,
              clipBehavior: Clip.none,
              children: [
                Container(
                  height: height,
                  decoration: BoxDecoration(color: c.surfaceMuted, borderRadius: Radii.rFull),
                ),
                Container(
                  height: height,
                  width: w * value.clamp(0, 1) * t,
                  decoration: BoxDecoration(color: color, borderRadius: Radii.rFull),
                ),
                if (marker != null)
                  Positioned(
                    left: (w * marker!.clamp(0, 1) - 1).clamp(0, math.max(0, w - 2)),
                    top: 0,
                    bottom: 0,
                    child: Container(width: 2, decoration: BoxDecoration(color: c.textPrimary, borderRadius: Radii.rFull)),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Tiny bar sparkline for summary tiles.
class SparkBars extends StatelessWidget {
  const SparkBars({super.key, required this.values, required this.color, this.height = 28});

  final List<double> values;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final maxV = values.fold<double>(0, math.max);
    return ExcludeSemantics(
      child: GrowIn(
        builder: (context, t) => SizedBox(
          height: height,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < values.length; i++) ...[
                if (i > 0) const SizedBox(width: 3),
                Expanded(
                  child: Container(
                    height: maxV <= 0 ? 2 : math.max(2, height * (values[i] / maxV) * t),
                    decoration: BoxDecoration(
                      color: i == values.length - 1 ? color : color.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(2),
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
