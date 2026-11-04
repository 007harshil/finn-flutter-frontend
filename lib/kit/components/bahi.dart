import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/money/money.dart';
import '../../core/money/money_format.dart';
import '../../design_system/components/amount_text.dart';
import '../../design_system/motion/motion.dart';
import '../tokens.dart';

/// Bahi detail building blocks: the indigo hero slab every detail page
/// opens with ([BahiSlab]), its ring ([SlabRing]), figures and stats
/// ([SlabFigure], [SlabStat]), status stamp ([SlabStamp]), square stat
/// tiles that replace label/value lists ([StatGrid]) and small fact tags
/// ([FactTags]). Data first, no explanatory sentences.

/// Colours on the slab (the same in light and dark mode).
abstract final class Slab {
  static const ink = Color(0xFFFFFFFF);
  static const soft = Color(0xFFC5C8F0);
  static const faint = Color(0x33FFFFFF);
  static const track = Color(0x24FFFFFF);
  static const good = Color(0xFF7FE0AC);
  static const warn = Color(0xFFFFC24B);
  static const bad = Color(0xFFFF8A80);
  static const cool = Color(0xFF9FC8FF);
  static const lilac = Color(0xFFC8B8FF);
}

enum SlabTone { good, warn, bad, neutral }

Color slabToneColor(SlabTone tone) => switch (tone) {
      SlabTone.good => Slab.good,
      SlabTone.warn => Slab.warn,
      SlabTone.bad => Slab.bad,
      SlabTone.neutral => Slab.soft,
    };

/// The indigo hero of a detail page: label, a big condensed marigold
/// figure, an optional visual on the right (usually a [SlabRing]), an
/// optional stamp, a row of [SlabStat]s and an optional [footer] (a bar or
/// a small chart). Corner seal marks echo the bahi stamp.
class BahiSlab extends StatelessWidget {
  const BahiSlab({
    super.key,
    required this.label,
    required this.figure,
    this.caption,
    this.visual,
    this.stamp,
    this.stats = const [],
    this.footer,
    this.leading,
  });

  final String label;

  /// Usually a [SlabFigure].
  final Widget figure;

  /// One short line under the figure ("of ₹3,00,000").
  final String? caption;
  final Widget? visual;
  final Widget? stamp;
  final List<SlabStat> stats;
  final Widget? footer;

  /// Small icon tile before the label (category, account kind).
  final IconData? leading;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final t = context.type;
    final cap = caption;
    final vis = visual;
    final st = stamp;
    final ft = footer;
    final lead = leading;
    return Container(
      decoration: BoxDecoration(gradient: c.deepGradient, borderRadius: Rad.rLg),
      clipBehavior: Clip.antiAlias,
      child: CustomPaint(
        painter: const _SealMarks(),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Sp.lg + 2, Sp.lg + 2, Sp.lg + 2, Sp.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (lead != null) ...[
                              Container(
                                width: 26,
                                height: 26,
                                decoration: BoxDecoration(color: Slab.faint, borderRadius: Rad.rSm),
                                child: Icon(lead, size: 15, color: Slab.ink),
                              ),
                              const SizedBox(width: Sp.sm),
                            ],
                            Flexible(
                              child: Text(
                                label,
                                style: t.label.copyWith(color: Slab.soft),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: Sp.xs),
                        figure,
                        if (cap != null) ...[
                          const SizedBox(height: 2),
                          Text(cap, style: t.label.copyWith(color: Slab.soft), maxLines: 2),
                        ],
                        if (st != null) ...[const SizedBox(height: Sp.sm + 2), st],
                      ],
                    ),
                  ),
                  if (vis != null) ...[const SizedBox(width: Sp.md), vis],
                ],
              ),
              if (stats.isNotEmpty) ...[
                const SizedBox(height: Sp.lg),
                Container(height: 1, color: Slab.faint),
                const SizedBox(height: Sp.md),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < stats.length; i++) ...[
                      if (i > 0) const SizedBox(width: Sp.md),
                      Expanded(child: stats[i]),
                    ],
                  ],
                ),
              ],
              if (ft != null) ...[const SizedBox(height: Sp.lg), ft],
            ],
          ),
        ),
      ),
    );
  }
}

class _SealMarks extends CustomPainter {
  const _SealMarks();

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..color = const Color(0x1FFFC24B);
    canvas.drawCircle(Offset(size.width - 18, 18), 34, p..strokeWidth = 9);
    canvas.drawCircle(Offset(size.width - 18, 18), 52, p..strokeWidth = 1.2);
  }

  @override
  bool shouldRepaint(_SealMarks old) => false;
}

/// The marigold hero figure on the slab (condensed, tabular).
class SlabFigure extends StatelessWidget {
  const SlabFigure(this.amount,
      {super.key, this.color, this.sign = SignDisplay.auto, this.size = 46, this.decimals = DecimalDisplay.none});

  final Money amount;
  final Color? color;
  final SignDisplay sign;
  final double size;
  final DecimalDisplay decimals;

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    return AnimatedAmount(
      amount,
      style: t.figureXL.copyWith(fontSize: size, color: color ?? context.ink.heroFigure, height: 1),
      sign: sign,
      decimals: decimals,
      fit: true,
      animateOnMount: true,
    );
  }
}

/// Text in place of a money figure on the slab ("12 of 36").
class SlabText extends StatelessWidget {
  const SlabText(this.text, {super.key, this.size = 46});

  final String text;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: AlignmentDirectional.centerStart,
      child: Text(text, style: t.figureXL.copyWith(fontSize: size, color: context.ink.heroFigure, height: 1)),
    );
  }
}

/// A small label over a figure in white, under the slab's rule.
class SlabStat extends StatelessWidget {
  const SlabStat({super.key, required this.label, required this.value});

  /// Money stat; [color] for meaning (red for owed, green for in).
  SlabStat.money({super.key, required this.label, required Money amount, Color? color, SignDisplay sign = SignDisplay.auto})
      : value = _MoneyValue(amount, color: color, sign: sign);

  SlabStat.text({super.key, required this.label, required String text}) : value = _TextValue(text);

  final String label;
  final Widget value;

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    return MergeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: t.small.copyWith(color: Slab.soft), maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          value,
        ],
      ),
    );
  }
}

class _MoneyValue extends StatelessWidget {
  const _MoneyValue(this.amount, {this.color, this.sign = SignDisplay.auto});
  final Money amount;
  final Color? color;
  final SignDisplay sign;

  @override
  Widget build(BuildContext context) => AmountText(
        amount,
        sign: sign,
        decimals: DecimalDisplay.none,
        fit: true,
        style: context.type.figure.copyWith(color: color ?? Slab.ink),
      );
}

class _TextValue extends StatelessWidget {
  const _TextValue(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: context.type.figure.copyWith(color: Slab.ink),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
}

/// Ring gauge drawn for the slab: a faint track, a marigold (or [color])
/// arc and an optional "should be here" tick, label in the middle.
class SlabRing extends StatelessWidget {
  const SlabRing({
    super.key,
    required this.value,
    this.marker,
    this.color,
    this.size = 104,
    this.stroke = 11,
    this.top,
    this.bottom,
    this.semanticLabel,
  });

  final double value;
  final double? marker;
  final Color? color;
  final double size;
  final double stroke;
  final String? top;
  final String? bottom;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    final fill = color ?? (value > 1 ? Slab.bad : Slab.warn);
    final reduced = context.reduceMotion;
    final tp = top;
    final bt = bottom;
    return Semantics(
      label: semanticLabel,
      excludeSemantics: semanticLabel != null,
      child: SizedBox.square(
        dimension: size,
        child: TweenAnimationBuilder<double>(
          key: ValueKey((value * 1000).round()),
          tween: Tween(begin: reduced ? 1 : 0, end: 1),
          duration: reduced ? Duration.zero : const Duration(milliseconds: 650),
          curve: Curves.easeOutCubic,
          builder: (context, p, _) => CustomPaint(
            painter: _SlabRingPainter(value: value.clamp(0.0, 1.0) * p, marker: marker, fill: fill, stroke: stroke),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (tp != null)
                    Text(tp, style: t.figure.copyWith(fontSize: size * 0.18, color: Slab.ink, height: 1.05)),
                  if (bt != null) Text(bt, style: t.small.copyWith(color: Slab.soft, fontSize: 12)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SlabRingPainter extends CustomPainter {
  _SlabRingPainter({required this.value, required this.marker, required this.fill, required this.stroke});

  final double value;
  final double? marker;
  final Color fill;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2 - stroke / 2 - 2;
    final o = size.center(Offset.zero);
    final rect = Rect.fromCircle(center: o, radius: r);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawArc(rect, 0, 2 * math.pi, false, base..color = Slab.track);
    if (value > 0) {
      canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * value, false, base
        ..color = fill
        ..strokeCap = StrokeCap.round);
    }
    final m = marker;
    if (m != null && m > 0 && m < 1) {
      final a = m * 2 * math.pi;
      final dir = Offset(math.sin(a), -math.cos(a));
      canvas.drawLine(
        o + dir * (r - stroke / 2 - 3),
        o + dir * (r + stroke / 2 + 3),
        Paint()
          ..color = Slab.ink
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_SlabRingPainter old) => old.value != value || old.marker != marker || old.fill != fill;
}

/// Tilted double-edge stamp in a light tone that reads on the slab.
class SlabStamp extends StatelessWidget {
  const SlabStamp({super.key, required this.label, this.tone = SlabTone.neutral});

  final String label;
  final SlabTone tone;

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    final color = slabToneColor(tone);
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Transform.rotate(
        angle: -0.07,
        child: Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            border: Border.all(color: color, width: 1.6),
            borderRadius: Rad.rSm,
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: Sp.sm, vertical: 3),
            decoration: BoxDecoration(
              border: Border.all(color: color.withValues(alpha: 0.5)),
              borderRadius: const BorderRadius.all(Radius.circular(Rad.sm - 2)),
            ),
            child: Text(
              label.toUpperCase(),
              maxLines: 1,
              style: t.small.copyWith(color: color, fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 1.1),
            ),
          ),
        ),
      ),
    );
  }
}

/// A thin split bar on the slab (repaid vs left, used vs free).
class SlabBar extends StatelessWidget {
  const SlabBar({super.key, required this.parts, this.height = 8, this.semanticLabel});

  /// (share, colour); shares need not add to 1.
  final List<(double, Color)> parts;
  final double height;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final visible = parts.where((p) => p.$1 > 0).toList();
    return Semantics(
      label: semanticLabel,
      excludeSemantics: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(height / 2),
        child: SizedBox(
          height: height,
          child: visible.isEmpty
              ? const ColoredBox(color: Slab.track)
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < visible.length; i++) ...[
                      if (i > 0) const SizedBox(width: 2),
                      Expanded(
                        flex: (visible[i].$1 * 1000).round().clamp(1, 1000000),
                        child: ColoredBox(color: visible[i].$2),
                      ),
                    ],
                  ],
                ),
        ),
      ),
    );
  }
}

/// One square tile of a [StatGrid].
@immutable
class StatTile {
  const StatTile({required this.label, required this.value, this.icon, this.color, this.onTap, this.key});

  /// Money tile.
  StatTile.money({
    required this.label,
    required Money amount,
    this.icon,
    this.color,
    this.onTap,
    this.key,
    SignDisplay sign = SignDisplay.auto,
  }) : value = _TileMoney(amount, color: color, sign: sign);

  /// Plain text tile.
  StatTile.text({required this.label, required String text, this.icon, this.color, this.onTap, this.key})
      : value = _TileText(text, color: color);

  final String label;
  final Widget value;
  final IconData? icon;

  /// Accent for the icon and value (meaning only).
  final Color? color;
  final VoidCallback? onTap;
  final Key? key;
}

class _TileMoney extends StatelessWidget {
  const _TileMoney(this.amount, {this.color, this.sign = SignDisplay.auto});
  final Money amount;
  final Color? color;
  final SignDisplay sign;

  @override
  Widget build(BuildContext context) => AmountText(
        amount,
        sign: sign,
        decimals: DecimalDisplay.none,
        fit: true,
        style: context.type.figure.copyWith(fontSize: 19, color: color ?? context.ink.ink),
      );
}

class _TileText extends StatelessWidget {
  const _TileText(this.text, {this.color});
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: context.type.figure.copyWith(fontSize: 17, color: color ?? context.ink.ink),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      );
}

/// Bahi stat tiles, two (or [columns]) per row: white, hairline, 14 px.
/// Replaces label/value lists so numbers read at a glance.
class StatGrid extends StatelessWidget {
  const StatGrid({super.key, required this.tiles, this.columns = 2});

  final List<StatTile> tiles;
  final int columns;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final t = context.type;
    return LayoutBuilder(
      builder: (context, box) {
        const gap = Sp.sm + 2;
        final w = (box.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final tile in tiles)
              SizedBox(
                key: tile.key,
                width: w,
                child: Material(
                  color: c.surface,
                  shape: RoundedRectangleBorder(borderRadius: Rad.rMd, side: BorderSide(color: c.line)),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: tile.onTap,
                    child: MergeSemantics(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(Sp.md, Sp.md, Sp.md, Sp.md),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                if (tile.icon != null) ...[
                                  Icon(tile.icon, size: 15, color: tile.color ?? c.inkSoft),
                                  const SizedBox(width: 6),
                                ],
                                Expanded(
                                  child: Text(tile.label, style: t.small, maxLines: 1, overflow: TextOverflow.ellipsis),
                                ),
                              ],
                            ),
                            const SizedBox(height: Sp.xs),
                            tile.value,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Short facts as tags ("Bank account", "····4821", "Default").
class FactTags extends StatelessWidget {
  const FactTags({super.key, required this.tags, this.highlight = const {}});

  final List<String> tags;

  /// Tags drawn in the marigold wash.
  final Set<String> highlight;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final t = context.type;
    return SizedBox(
      width: double.infinity,
      child: Wrap(
      spacing: Sp.sm,
      runSpacing: Sp.sm,
      children: [
        for (final tag in tags)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: Sp.sm + 2, vertical: 5),
            decoration: BoxDecoration(
              color: highlight.contains(tag) ? c.marigoldSoft : c.sunken,
              borderRadius: Rad.rChip,
            ),
            child: Text(
              tag,
              style: t.small.copyWith(color: highlight.contains(tag) ? c.marigoldInk : c.ink, fontWeight: FontWeight.w600),
            ),
          ),
      ],
      ),
    );
  }
}

/// Spoken money for semantics on slab visuals.
String slabSpoken(Money m) => MoneyFormatter.spoken(m);
