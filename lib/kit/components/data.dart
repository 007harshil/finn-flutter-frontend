import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../design_system/motion/motion.dart';
import '../../features/categories/domain/category.dart';
import '../../shared/presentation/category_icons.dart';
import '../tokens.dart';

/// Round icon well. Monochrome by default; pass [color] only when the
/// colour means something (overdue, over the limit).
class IconWell extends StatelessWidget {
  const IconWell({super.key, required this.icon, this.color, this.background, this.size = 40});

  final IconData icon;
  final Color? color;
  final Color? background;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: background ?? c.sunken, shape: BoxShape.circle),
      child: Icon(icon, size: size * 0.48, color: color ?? c.ink),
    );
  }
}

/// A category's icon in an [IconWell]. Handles deleted categories.
class CategoryMark extends StatelessWidget {
  const CategoryMark({super.key, required this.category, this.size = 40});

  final TransactionCategory? category;
  final double size;

  @override
  Widget build(BuildContext context) =>
      IconWell(icon: category == null ? LucideIcons.tag : CategoryIcons.of(category!.iconKey), size: size);
}

/// The list row of the kit: leading well, title + subtitle, amount on the
/// right. Rows sit inside a [LedgerPanel].
class LedgerRow extends StatelessWidget {
  const LedgerRow({
    super.key,
    required this.title,
    this.leading,
    this.subtitle,
    this.subtitleColor,
    this.trailing,
    this.trailingSub,
    this.below,
    this.onTap,
    this.onLongPress,
    this.semanticLabel,
    this.chevron = false,
    this.titleLines = 1,
    this.subtitleLines = 1,
  });

  final String title;

  /// Allow wrapping for sentence-like titles (alerts).
  final int titleLines;
  final int subtitleLines;
  final Widget? leading;
  final String? subtitle;

  /// Use only for meaning (red when overdue).
  final Color? subtitleColor;

  /// Usually an [AmountText] with `type.figure`.
  final Widget? trailing;

  /// Small line under the trailing widget.
  final Widget? trailingSub;

  /// Full-width content under the text (a progress bar).
  final Widget? below;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final String? semanticLabel;
  final bool chevron;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final t = context.type;
    final lead = leading;
    final sub = subtitle;
    final tr = trailing;
    final trs = trailingSub;
    final bl = below;
    final body = Padding(
      padding: const EdgeInsets.symmetric(horizontal: Sp.lg, vertical: Sp.md + 2),
      child: Row(
        children: [
          if (lead != null) ...[lead, const SizedBox(width: Sp.md + 2)],
          Expanded(
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
                          Text(
                            title,
                            style: t.body.copyWith(fontWeight: FontWeight.w500, fontVariations: const [FontVariation.weight(540)]),
                            maxLines: titleLines,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (sub != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              sub,
                              style: t.label.copyWith(color: subtitleColor),
                              maxLines: subtitleLines,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (tr != null || trs != null) ...[
                      const SizedBox(width: Sp.md),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [?tr, if (trs != null) ...[const SizedBox(height: 2), trs]],
                      ),
                    ],
                  ],
                ),
                if (bl != null) ...[const SizedBox(height: Sp.sm + 2), bl],
              ],
            ),
          ),
          if (chevron) ...[
            const SizedBox(width: Sp.sm),
            Icon(LucideIcons.chevronRight, size: 18, color: c.inkFaint),
          ],
        ],
      ),
    );
    final interactive = onTap != null || onLongPress != null;
    return Semantics(
      button: onTap != null,
      label: semanticLabel,
      excludeSemantics: semanticLabel != null,
      child: interactive
          ? InkWell(
              onTap: onTap == null
                  ? null
                  : () {
                      HapticFeedback.selectionClick();
                      onTap!();
                    },
              onLongPress: onLongPress == null
                  ? null
                  : () {
                      HapticFeedback.mediumImpact();
                      onLongPress!();
                    },
              child: ConstrainedBox(constraints: const BoxConstraints(minHeight: 60), child: body),
            )
          : MergeSemantics(child: ConstrainedBox(constraints: const BoxConstraints(minHeight: 60), child: body)),
    );
  }
}

/// The kit's one progress shape: a thin bar, optionally with a tick that
/// marks where you should be by now (today's share of a month, the share
/// a dated goal should have reached). Over 1.0 the whole bar turns red.
class LedgerBar extends StatelessWidget {
  const LedgerBar({
    super.key,
    required this.value,
    this.marker,
    this.color,
    this.height = 6,
    this.semanticLabel,
  });

  /// Filled share; may exceed 1 (over the limit).
  final double value;

  /// 0..1 position of the "should be here" tick; null for none.
  final double? marker;
  final Color? color;
  final double height;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final motion = context.motion;
    final over = value > 1;
    final fill = over ? c.red : (color ?? c.green);
    final m = marker;
    final tick = m != null && m > 0 && m < 1;
    return Semantics(
      label: semanticLabel,
      excludeSemantics: true,
      child: SizedBox(
        height: tick ? height + 8 : height,
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: value.clamp(0.0, 1.0)),
          duration: motion.slow,
          curve: motion.standard,
          builder: (context, v, _) => CustomPaint(
            painter: _BarPainter(
              value: v,
              marker: tick ? m : null,
              fill: fill,
              track: c.sunken,
              tickColor: c.ink,
              barHeight: height,
            ),
          ),
        ),
      ),
    );
  }
}

class _BarPainter extends CustomPainter {
  _BarPainter({
    required this.value,
    required this.marker,
    required this.fill,
    required this.track,
    required this.tickColor,
    required this.barHeight,
  });

  final double value;
  final double? marker;
  final Color fill;
  final Color track;
  final Color tickColor;
  final double barHeight;

  @override
  void paint(Canvas canvas, Size size) {
    final top = (size.height - barHeight) / 2;
    final r = Radius.circular(barHeight / 2);
    final bar = Rect.fromLTWH(0, top, size.width, barHeight);
    canvas.drawRRect(RRect.fromRectAndRadius(bar, r), Paint()..color = track);
    if (value > 0) {
      final w = (size.width * value).clamp(barHeight, size.width);
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(0, top, w, barHeight), r), Paint()..color = fill);
    }
    final m = marker;
    if (m != null) {
      final x = (size.width * m).clamp(1.0, size.width - 1);
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(x, size.height / 2), width: 2, height: size.height), const Radius.circular(1)),
        Paint()..color = tickColor,
      );
    }
  }

  @override
  bool shouldRepaint(_BarPainter old) =>
      old.value != value || old.marker != marker || old.fill != fill || old.track != track || old.tickColor != tickColor;
}

/// One part of a [LedgerStackBar].
@immutable
class BarPart {
  const BarPart(this.share, this.color);

  final double share;
  final Color color;
}

/// Thin bar split into parts (where money went, cash vs set aside).
/// Parts are separated by a 2px gap in the page colour.
class LedgerStackBar extends StatelessWidget {
  const LedgerStackBar({super.key, required this.parts, this.height = 8, this.semanticLabel, this.gapColor});

  final List<BarPart> parts;
  final double height;
  final String? semanticLabel;

  /// Colour between parts; defaults to the surface the bar sits on.
  final Color? gapColor;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final visible = parts.where((p) => p.share > 0).toList();
    return Semantics(
      label: semanticLabel,
      excludeSemantics: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(height / 2),
        child: SizedBox(
          height: height,
          child: visible.isEmpty
              ? ColoredBox(color: c.sunken)
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < visible.length; i++) ...[
                      if (i > 0) Container(width: 2, color: gapColor ?? c.surface),
                      Expanded(
                        flex: (visible[i].share * 1000).round().clamp(1, 1000000),
                        child: ColoredBox(color: visible[i].color),
                      ),
                    ],
                  ],
                ),
        ),
      ),
    );
  }
}

/// Small label over a value ("Spent" / ₹12,400). Tappable when [onTap].
class LedgerStat extends StatelessWidget {
  const LedgerStat({
    super.key,
    required this.label,
    required this.value,
    this.end = false,
    this.onTap,
    this.selected = false,
    this.semanticLabel,
  });

  final String label;
  final Widget value;
  final bool end;
  final VoidCallback? onTap;
  final bool selected;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    final body = Column(
      crossAxisAlignment: end ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: t.label, maxLines: 1, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 2),
        value,
      ],
    );
    final tap = onTap;
    if (tap == null) return MergeSemantics(child: body);
    return Semantics(
      button: true,
      selected: selected,
      label: semanticLabel,
      excludeSemantics: semanticLabel != null,
      child: InkWell(
        borderRadius: Rad.rSm,
        onTap: () {
          HapticFeedback.selectionClick();
          tap();
        },
        child: Padding(padding: const EdgeInsets.symmetric(vertical: Sp.xs), child: body),
      ),
    );
  }
}

/// One label and value line: details panels, terms, sheet summaries.
/// Pass [text] for plain values or [value] for money/custom widgets.
/// [stacked] puts long values (notes) under the label. Set [inset] false
/// when the row is not inside a [LedgerPanel] (e.g. in a sheet).
class LedgerFact extends StatelessWidget {
  const LedgerFact({super.key, required this.label, this.text, this.value, this.stacked = false, this.inset = true})
      : assert(text != null || value != null);

  final String label;
  final String? text;
  final Widget? value;
  final bool stacked;
  final bool inset;

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    final v = value ?? Text(text!, style: t.body, textAlign: stacked ? TextAlign.start : TextAlign.end);
    return MergeSemantics(
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: inset ? Sp.lg : 0, vertical: Sp.md),
          child: stacked
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [Text(label, style: t.label), const SizedBox(height: Sp.xs), v],
                )
              : Row(
                  children: [
                    Expanded(child: Text(label, style: t.label)),
                    const SizedBox(width: Sp.md),
                    Flexible(
                      flex: 2,
                      child: Align(alignment: AlignmentDirectional.centerEnd, child: v),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
