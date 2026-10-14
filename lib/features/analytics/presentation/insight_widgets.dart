import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../kit/kit.dart';
import '../application/analytics_providers.dart';

/// Shared building blocks for the Insights topics: the lead figure that
/// opens a topic, a row of supporting figures, list sections and the
/// one-time chart entrance.

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
      duration: m.slow,
      curve: m.standard,
      builder: (context, t, _) => builder(context, t),
    );
  }
}

/// Whole-rupee amount in a figure style, scaled down to fit.
Widget insightAmount(
  BuildContext context,
  Money m, {
  TextStyle? style,
  Color? color,
  SignDisplay sign = SignDisplay.auto,
}) =>
    AmountText(
      m,
      style: style ?? context.type.figure,
      color: color,
      sign: sign,
      decimals: DecimalDisplay.none,
      compact: m.abs() >= const Money.rupees(10000000),
      fit: true,
    );

/// Green for a gain, red for a loss, ink for zero. Masked amounts stay ink.
Color? signColor(BuildContext context, Money m) {
  if (AmountVisibility.hiddenOf(context)) return null;
  final c = context.ink;
  return m.isNegative ? c.red : (m.isPositive ? c.green : null);
}

/// The figure a topic opens with: a short label, the number, and one
/// plain sentence that explains it.
class InsightLead extends StatelessWidget {
  const InsightLead({
    super.key,
    required this.label,
    required this.value,
    this.sentence,
    this.sentenceColor,
    this.below,
  });

  final String label;

  /// Usually an [AnimatedAmount] in `figureXL` or a `Text` in `figureL`.
  final Widget value;
  final String? sentence;
  final Color? sentenceColor;

  /// Bar or note under the number.
  final Widget? below;

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    final s = sentence;
    final b = below;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MergeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(label, style: t.label),
              const SizedBox(height: Sp.xs),
              Align(alignment: Alignment.centerLeft, child: value),
            ],
          ),
        ),
        if (b != null) ...[const SizedBox(height: Sp.lg), b],
        if (s != null) ...[
          const SizedBox(height: Sp.md),
          Text(s, style: t.label.copyWith(color: sentenceColor)),
        ],
      ],
    );
  }
}

/// Two or three supporting figures side by side, under a lead.
class InsightStats extends StatelessWidget {
  const InsightStats({super.key, required this.stats});

  final List<Widget> stats;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < stats.length; i++) ...[
          if (i > 0) const SizedBox(width: Sp.md),
          Expanded(child: stats[i]),
        ],
      ],
    );
  }
}

/// A [LedgerStat] whose value is a whole-rupee amount, plus an optional
/// small line under it ("per month").
class InsightStat extends StatelessWidget {
  const InsightStat({
    super.key,
    required this.label,
    required this.value,
    this.caption,
    this.captionColor,
  });

  final String label;
  final Widget value;
  final String? caption;
  final Color? captionColor;

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    final cap = caption;
    return LedgerStat(
      label: label,
      value: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          value,
          if (cap != null)
            Text(cap, style: t.small.copyWith(color: captionColor), maxLines: 2, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

/// A titled list: an optional sentence, rows in one panel, and an
/// optional quiet action under it ("See all 12").
class InsightListSection extends StatelessWidget {
  const InsightListSection({
    super.key,
    required this.title,
    required this.rows,
    this.note,
    this.actionLabel,
    this.onAction,
    this.footer,
    this.dividerIndent = Sp.lg + 40 + Sp.md + 2,
  });

  final String title;

  /// Under everything else (a "How this is calculated" disclosure).
  final Widget? footer;
  final String? note;
  final List<Widget> rows;
  final String? actionLabel;
  final VoidCallback? onAction;
  final double dividerIndent;

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    final n = note;
    final a = actionLabel;
    return LedgerSection(
      title: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (n != null) ...[Text(n, style: t.label), const SizedBox(height: Sp.md)],
          LedgerPanel(dividerIndent: dividerIndent, children: rows),
          if (a != null) ...[
            const SizedBox(height: Sp.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: LedgerButton(label: a, onPressed: onAction, variant: LedgerButtonVariant.quiet, small: true),
            ),
          ],
          ?footer,
        ],
      ),
    );
  }
}

/// Ink shades for the parts of a "where it went" bar, darkest first; the
/// remainder uses the sunken tone.
const insightRamp = [1.0, 0.78, 0.6, 0.45, 0.32, 0.22];

Color rampColor(LedgerColors c, int i) => c.ink.withValues(alpha: insightRamp[i % insightRamp.length]);

/// Small square colour key for a chart legend or bar part.
class InsightSwatch extends StatelessWidget {
  const InsightSwatch({super.key, required this.color, this.dashed = false});

  final Color color;
  final bool dashed;

  @override
  Widget build(BuildContext context) {
    if (dashed) {
      return SizedBox(width: 14, height: 10, child: CustomPaint(painter: _DashPainter(color)));
    }
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
    );
  }
}

class _DashPainter extends CustomPainter {
  _DashPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1.5;
    final y = size.height / 2;
    canvas.drawLine(Offset(0, y), Offset(size.width * 0.4, y), p);
    canvas.drawLine(Offset(size.width * 0.6, y), Offset(size.width, y), p);
  }

  @override
  bool shouldRepaint(_DashPainter old) => old.color != color;
}

/// Quiet line inside a chart panel when there is nothing to draw, with an
/// optional next step under it.
class InsightNoData extends StatelessWidget {
  const InsightNoData({super.key, required this.message, this.actionLabel, this.onAction});

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final a = actionLabel;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Sp.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message, style: context.type.label),
          if (a != null) ...[
            const SizedBox(height: Sp.md),
            LedgerButton(label: a, onPressed: onAction, variant: LedgerButtonVariant.secondary, small: true),
          ],
        ],
      ),
    );
  }
}

/// Colour key, label and amount in one line ("■ Spent ₹42,300").
class InsightKeyValue extends StatelessWidget {
  const InsightKeyValue({super.key, required this.color, required this.label, required this.value});

  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    return MergeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InsightSwatch(color: color),
          const SizedBox(width: Sp.sm - 2),
          Text(label, style: t.label),
          const SizedBox(width: Sp.xs + 2),
          Flexible(
            child: Text(
              value,
              style: t.labelStrong.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
