import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/money/money.dart';
import '../../core/money/money_format.dart';
import '../../core/time/dates.dart';
import '../components/amount_text.dart';
import '../motion/motion.dart';
import 'luxe_motion.dart';
import 'luxe_tokens.dart';

// ---------------------------------------------------------------------------
// Backdrop
// ---------------------------------------------------------------------------

/// Warm canvas with two pools of light that drift with the scroll position
/// (parallax), so the page feels lit rather than flat. Purely scroll-driven:
/// it never animates on its own.
class LuxeBackdrop extends StatelessWidget {
  const LuxeBackdrop({super.key, this.scroll});

  final ScrollController? scroll;

  @override
  Widget build(BuildContext context) {
    final p = context.luxe;
    final s = scroll;
    Widget paint(double offset) => CustomPaint(painter: _AuroraPainter(p, offset));
    return RepaintBoundary(
      child: s == null
          ? paint(0)
          : AnimatedBuilder(
              animation: s,
              builder: (context, _) => paint(s.hasClients && s.positions.length == 1 ? s.offset : 0),
            ),
    );
  }
}

class _AuroraPainter extends CustomPainter {
  _AuroraPainter(this.p, this.offset);

  final LuxePalette p;
  final double offset;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [p.canvas, p.canvasDeep],
        ).createShader(rect),
    );
    final drift = offset.clamp(0.0, 2000.0);
    void pool(Offset c, double r, Color color, double alpha) {
      final shader = RadialGradient(
        colors: [
          color.withValues(alpha: alpha),
          color.withValues(alpha: 0),
        ],
      ).createShader(Rect.fromCircle(center: c, radius: r));
      canvas.drawCircle(c, r, Paint()..shader = shader);
    }

    final w = size.width;
    pool(Offset(w * 0.92, -40 - drift * 0.35), w * 0.95, p.auroraA, p.isDark ? 0.9 : 0.85);
    pool(Offset(-w * 0.1, size.height * 0.42 - drift * 0.18), w * 0.85, p.auroraB, p.isDark ? 0.7 : 0.6);
  }

  @override
  bool shouldRepaint(_AuroraPainter old) => old.offset != offset || old.p != p;
}

// ---------------------------------------------------------------------------
// Surfaces
// ---------------------------------------------------------------------------

/// Paper card: hairline edge, soft long shadow in light mode.
class LuxeCard extends StatelessWidget {
  const LuxeCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(LuxeSpace.card),
    this.onTap,
    this.onLongPress,
    this.radius = LuxeSpace.rCard,
    this.color,
    this.semanticLabel,
    this.elevated = true,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double radius;
  final Color? color;
  final String? semanticLabel;
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    final p = context.luxe;
    final box = DecoratedBox(
      decoration: BoxDecoration(
        color: color ?? p.paper,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: p.line),
        boxShadow: elevated ? p.lift : null,
      ),
      child: Padding(padding: padding, child: child),
    );
    if (onTap == null && onLongPress == null) {
      return semanticLabel == null ? box : Semantics(container: true, label: semanticLabel, child: box);
    }
    return Squish(
      onTap: onTap,
      onLongPress: onLongPress,
      scale: 0.985,
      semanticLabel: semanticLabel,
      excludeSemantics: semanticLabel != null,
      child: box,
    );
  }
}

class LuxeHairline extends StatelessWidget {
  const LuxeHairline({super.key, this.indent = 0, this.endIndent = 0, this.vertical = 0});

  final double indent;
  final double endIndent;
  final double vertical;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsetsDirectional.fromSTEB(indent, vertical, endIndent, vertical),
    child: SizedBox(height: 1, child: ColoredBox(color: context.luxe.line)),
  );
}

// ---------------------------------------------------------------------------
// Buttons
// ---------------------------------------------------------------------------

enum LuxeButtonVariant { ink, gold, outline, ghost }

/// Pill button. One `ink` button per view; everything else is quieter.
class LuxeButton extends StatelessWidget {
  const LuxeButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.variant = LuxeButtonVariant.ink,
    this.compact = false,
    this.expand = false,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final LuxeButtonVariant variant;
  final bool compact;
  final bool expand;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final p = context.luxe;
    final t = context.lt;
    final enabled = onPressed != null && !loading;
    final (Color bg, Color fg, Color? border, Gradient? gradient) = switch (variant) {
      LuxeButtonVariant.ink => (p.ink, p.canvas, null, null),
      LuxeButtonVariant.gold => (p.gold, const Color(0xFF17130C), null, p.goldGradient),
      LuxeButtonVariant.outline => (Colors.transparent, p.ink, p.lineStrong, null),
      LuxeButtonVariant.ghost => (Colors.transparent, p.ink, null, null),
    };
    final h = compact ? 40.0 : 52.0;
    final content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (loading)
          SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 1.6, color: fg))
        else if (icon != null)
          Icon(icon, size: compact ? 16 : 18, color: fg),
        if (loading || icon != null) const SizedBox(width: 8),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: (compact ? t.label : t.button).w(650).c(fg),
          ),
        ),
      ],
    );
    return Opacity(
      opacity: enabled || loading ? 1 : 0.42,
      child: Squish(
        onTap: enabled ? onPressed : null,
        semanticLabel: label,
        excludeSemantics: true,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: math.max(h, 44), minWidth: 44),
          child: Container(
            height: h,
            padding: EdgeInsets.symmetric(horizontal: compact ? 16 : 22),
            decoration: BoxDecoration(
              color: gradient == null ? bg : null,
              gradient: gradient,
              borderRadius: BorderRadius.circular(h / 2),
              border: border == null ? null : Border.all(color: border),
            ),
            child: content,
          ),
        ),
      ),
    );
  }
}

enum LuxeIconStyle { paper, ink, ghost }

/// Round icon button (48 dp target) with tooltip and optional count badge.
class LuxeIconButton extends StatelessWidget {
  const LuxeIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.style = LuxeIconStyle.paper,
    this.badge = 0,
    this.size = 44,
    this.iconColor,
    this.active = false,
    this.semanticLabel,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final LuxeIconStyle style;
  final int badge;
  final double size;
  final Color? iconColor;

  /// Shows the control as "on" (e.g. filters applied).
  final bool active;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final p = context.luxe;
    final on = active || style == LuxeIconStyle.ink;
    final bg = switch (style) {
      _ when on => p.ink,
      LuxeIconStyle.paper => p.paper,
      _ => Colors.transparent,
    };
    final fg = iconColor ?? (on ? p.canvas : p.ink);
    Widget button = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
        border: style == LuxeIconStyle.paper && !on ? Border.all(color: p.line) : null,
        boxShadow: style == LuxeIconStyle.paper && !on && !p.isDark ? p.lift : null,
      ),
      child: Icon(icon, size: size * 0.42, color: onPressed == null ? fg.withValues(alpha: 0.35) : fg),
    );
    if (badge > 0) {
      button = Stack(
        clipBehavior: Clip.none,
        children: [
          button,
          Positioned(top: -3, right: -3, child: LuxeBadge(count: badge)),
        ],
      );
    }
    return Tooltip(
      message: tooltip,
      child: Squish(
        onTap: onPressed,
        scale: 0.92,
        semanticLabel: semanticLabel ?? (badge > 0 ? '$tooltip, $badge' : tooltip),
        excludeSemantics: true,
        child: SizedBox(
          width: math.max(48, size),
          height: math.max(48, size),
          child: Center(child: button),
        ),
      ),
    );
  }
}

/// Small count bubble that lands with a little overshoot.
class LuxeBadge extends StatelessWidget {
  const LuxeBadge({super.key, required this.count, this.color});

  final int count;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final p = context.luxe;
    final bubble = Container(
      constraints: const BoxConstraints(minWidth: 18),
      height: 18,
      padding: const EdgeInsets.symmetric(horizontal: 5),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color ?? p.gold,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: p.canvas, width: 1.5),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        style: context.lt.micro.w(800).c(const Color(0xFF17130C)).copyWith(fontSize: 10, height: 1),
      ),
    );
    if (context.reduceMotion) return ExcludeSemantics(child: bubble);
    return ExcludeSemantics(
      child: TweenAnimationBuilder<double>(
        key: ValueKey(count),
        tween: Tween(begin: 0.4, end: 1),
        duration: LuxeDurations.base,
        curve: LuxeCurves.land,
        builder: (context, s, child) => Transform.scale(scale: s, child: child),
        child: bubble,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Text blocks
// ---------------------------------------------------------------------------

/// Big page title: tracked eyebrow above a serif headline.
class LuxeTitle extends StatelessWidget {
  const LuxeTitle({super.key, required this.title, this.eyebrow, this.subtitle, this.semanticsLabel});

  /// A string or a styled [InlineSpan] list rendered in the headline style.
  final Object title;
  final String? eyebrow;
  final String? subtitle;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final t = context.lt;
    final e = eyebrow;
    final s = subtitle;
    final heading = title is String
        ? Text(title as String, style: t.headline, maxLines: 2, overflow: TextOverflow.ellipsis)
        : Text.rich(TextSpan(children: title as List<InlineSpan>), style: t.headline, maxLines: 2);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (e != null) ...[Text(e.toUpperCase(), style: t.eyebrow, maxLines: 1), const SizedBox(height: 8)],
        Semantics(header: true, label: semanticsLabel, excludeSemantics: semanticsLabel != null, child: heading),
        if (s != null) ...[const SizedBox(height: 6), Text(s, style: t.caption, maxLines: 2)],
      ],
    );
  }
}

/// Section heading: serif name, optional count, a quiet caption and a link.
class LuxeSectionHeader extends StatelessWidget {
  const LuxeSectionHeader({
    super.key,
    required this.title,
    this.caption,
    this.count,
    this.actionLabel,
    this.onAction,
    this.trailing,
  });

  final String title;
  final String? caption;
  final int? count;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final p = context.luxe;
    final t = context.lt;
    final n = count;
    final cap = caption;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Flexible(
                    child: Semantics(
                      header: true,
                      child: Text(title, style: t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                  if (n != null && n > 0) ...[
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: p.goldSoft, borderRadius: BorderRadius.circular(20)),
                      child: Text('$n', style: t.micro.w(800).c(p.goldInk)),
                    ),
                  ],
                ],
              ),
              if (cap != null) ...[
                const SizedBox(height: 4),
                Text(cap, style: t.caption, maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
            ],
          ),
        ),
        ?trailing,
        if (actionLabel != null && onAction != null) LuxeLink(label: actionLabel!, onTap: onAction!),
      ],
    );
  }
}

/// Text link with an arrow that nudges on press.
class LuxeLink extends StatelessWidget {
  const LuxeLink({super.key, required this.label, required this.onTap, this.icon = LucideIcons.arrowRight});

  final String label;
  final VoidCallback onTap;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final p = context.luxe;
    return Squish(
      onTap: onTap,
      semanticLabel: label,
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.lt.label.w(650).c(p.ink),
                ),
              ),
              const SizedBox(width: 6),
              Icon(icon, size: 14, color: p.ink),
            ],
          ),
        ),
      ),
    );
  }
}

/// Coloured dot + word: status never relies on colour alone.
class LuxeStatus extends StatelessWidget {
  const LuxeStatus({super.key, required this.label, required this.color, this.icon, this.filled = true});

  final String label;
  final Color color;
  final IconData? icon;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final p = context.luxe;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: filled ? p.tint(color, 0.1) : Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        border: filled ? null : Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null)
            Icon(icon, size: 12, color: color)
          else
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.lt.micro.w(700).c(color)),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Chips & segmented control
// ---------------------------------------------------------------------------

/// Pill chip for filters and shortcuts. Selected = ink, otherwise paper.
class LuxeChip extends StatelessWidget {
  const LuxeChip({
    super.key,
    required this.label,
    required this.onTap,
    this.selected = false,
    this.dot,
    this.icon,
    this.trailing,
    this.count,
    this.semanticLabel,
    this.height = 36,
  });

  final String label;
  final VoidCallback? onTap;
  final bool selected;
  final Color? dot;
  final IconData? icon;
  final IconData? trailing;
  final int? count;
  final String? semanticLabel;
  final double height;

  @override
  Widget build(BuildContext context) {
    final p = context.luxe;
    final t = context.lt;
    final fg = selected ? p.canvas : p.ink;
    final soft = selected ? p.canvas.withValues(alpha: 0.7) : p.inkMute;
    return Squish(
      onTap: onTap,
      scale: 0.94,
      selected: selected,
      semanticLabel: semanticLabel ?? (count == null ? label : '$label, $count'),
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Center(
          widthFactor: 1,
          child: AnimatedContainer(
            duration: context.reduceMotion ? Duration.zero : LuxeDurations.quick,
            curve: LuxeCurves.glide,
            height: height,
            padding: EdgeInsets.only(left: dot != null || icon != null ? 12 : 14, right: trailing != null ? 10 : 14),
            decoration: BoxDecoration(
              color: selected ? p.ink : p.paper,
              borderRadius: BorderRadius.circular(height / 2),
              border: Border.all(color: selected ? p.ink : p.line),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (dot != null) ...[
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 8),
                ] else if (icon != null) ...[
                  Icon(icon, size: 14, color: fg),
                  const SizedBox(width: 6),
                ],
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 160),
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.label.w(selected ? 700 : 600).c(fg),
                  ),
                ),
                if (count != null) ...[const SizedBox(width: 6), Text('${count!}', style: t.label.w(700).c(soft))],
                if (trailing != null) ...[const SizedBox(width: 6), Icon(trailing, size: 14, color: soft)],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One option of a [LuxeSegmented].
class LuxeSegment<T> {
  const LuxeSegment(this.value, this.label, {this.count, this.key, this.color});
  final T value;
  final String label;
  final int? count;
  final Key? key;
  final Color? color;
}

/// Segmented control with a thumb that glides between options.
class LuxeSegmented<T> extends StatelessWidget {
  const LuxeSegmented({
    super.key,
    required this.segments,
    required this.selected,
    required this.onChanged,
    this.height = 44,
  });

  final List<LuxeSegment<T>> segments;
  final T selected;
  final ValueChanged<T> onChanged;
  final double height;

  @override
  Widget build(BuildContext context) {
    final p = context.luxe;
    final t = context.lt;
    final index = math.max(0, segments.indexWhere((s) => s.value == selected));
    final n = segments.length;
    return Container(
      height: height,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: p.sunk, borderRadius: BorderRadius.circular(height / 2)),
      child: Stack(
        children: [
          AnimatedAlign(
            alignment: Alignment(n == 1 ? 0 : -1 + 2 * index / (n - 1), 0),
            duration: context.reduceMotion ? Duration.zero : LuxeDurations.base,
            curve: LuxeCurves.arrive,
            child: FractionallySizedBox(
              widthFactor: 1 / n,
              heightFactor: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: p.isDark ? p.paperRaised : p.paperRaised,
                  borderRadius: BorderRadius.circular(height / 2),
                  boxShadow: p.isDark
                      ? null
                      : const [BoxShadow(color: Color(0x1A261D10), blurRadius: 8, offset: Offset(0, 2))],
                  border: p.isDark ? Border.all(color: p.lineStrong) : null,
                ),
              ),
            ),
          ),
          Row(
            children: [
              for (final s in segments)
                Expanded(
                  child: Semantics(
                    button: true,
                    selected: s.value == selected,
                    inMutuallyExclusiveGroup: true,
                    label: s.count == null ? s.label : '${s.label}, ${s.count}',
                    excludeSemantics: true,
                    onTap: s.value == selected ? null : () => onChanged(s.value),
                    child: GestureDetector(
                      key: s.key,
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        if (s.value == selected) return;
                        HapticFeedback.selectionClick();
                        onChanged(s.value);
                      },
                      child: Center(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (s.color != null) ...[
                                  Container(
                                    width: 6,
                                    height: 6,
                                    decoration: BoxDecoration(color: s.color, shape: BoxShape.circle),
                                  ),
                                  const SizedBox(width: 6),
                                ],
                                AnimatedDefaultTextStyle(
                                  duration: LuxeDurations.quick,
                                  style: t.label
                                      .w(s.value == selected ? 700 : 550)
                                      .c(s.value == selected ? p.ink : p.inkSoft),
                                  child: Text(s.label, maxLines: 1),
                                ),
                                if (s.count != null) ...[
                                  const SizedBox(width: 5),
                                  Text(
                                    '${s.count}',
                                    style: t.label.w(700).c(s.value == selected ? p.goldInk : p.inkMute),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Month stepper
// ---------------------------------------------------------------------------

const _months = [
  'January', 'February', 'March', 'April', 'May', 'June', //
  'July', 'August', 'September', 'October', 'November', 'December',
];

/// ‹ October 2026 › with the label sliding in from the side you moved to.
class LuxeMonthStepper extends StatefulWidget {
  const LuxeMonthStepper({
    super.key,
    required this.month,
    required this.onChanged,
    this.min,
    this.max,
    this.subtitle,
    this.compact = false,
  });

  final MonthKey month;
  final ValueChanged<MonthKey> onChanged;
  final MonthKey? min;
  final MonthKey? max;

  /// Small line under the month ("so far", "18 days left").
  final String? subtitle;
  final bool compact;

  @override
  State<LuxeMonthStepper> createState() => _LuxeMonthStepperState();
}

class _LuxeMonthStepperState extends State<LuxeMonthStepper> {
  int _dir = 1;

  @override
  void didUpdateWidget(LuxeMonthStepper old) {
    super.didUpdateWidget(old);
    if (old.month != widget.month) _dir = widget.month > old.month ? 1 : -1;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.luxe;
    final t = context.lt;
    final m = widget.month;
    final canPrev = widget.min == null || m > widget.min!;
    final canNext = widget.max == null || m < widget.max!;
    final name = _months[m.month - 1];
    final sub = widget.subtitle;
    final label = Column(
      key: ValueKey<MonthKey>(m),
      mainAxisSize: MainAxisSize.min,
      children: [
        Text.rich(
          TextSpan(
            children: [
              TextSpan(text: name),
              TextSpan(
                text: ' ${m.year}',
                style: TextStyle(color: p.inkMute),
              ),
            ],
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: (widget.compact ? t.heading : t.title.copyWith(fontSize: 22)),
        ),
        if (sub != null) Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.micro),
      ],
    );
    return Row(
      children: [
        LuxeIconButton(
          icon: LucideIcons.chevronLeft,
          tooltip: 'Previous month',
          style: LuxeIconStyle.ghost,
          size: 40,
          onPressed: canPrev ? () => widget.onChanged(m.previous) : null,
        ),
        Expanded(
          child: Semantics(
            liveRegion: true,
            label: '$name ${m.year}${sub == null ? '' : ', $sub'}',
            excludeSemantics: true,
            child: ClipRect(
              child: AnimatedSwitcher(
                duration: context.reduceMotion ? Duration.zero : LuxeDurations.base,
                switchInCurve: LuxeCurves.arrive,
                switchOutCurve: LuxeCurves.leave,
                transitionBuilder: (child, a) {
                  final incoming = child.key == ValueKey<MonthKey>(m);
                  final dx = (incoming ? 0.35 : -0.35) * _dir;
                  return FadeTransition(
                    opacity: a,
                    child: SlideTransition(
                      position: Tween(begin: Offset(dx, 0), end: Offset.zero).animate(a),
                      child: child,
                    ),
                  );
                },
                child: label,
              ),
            ),
          ),
        ),
        LuxeIconButton(
          icon: LucideIcons.chevronRight,
          tooltip: 'Next month',
          style: LuxeIconStyle.ghost,
          size: 40,
          onPressed: canNext ? () => widget.onChanged(m.next) : null,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Money
// ---------------------------------------------------------------------------

/// A money figure typeset like a price: the ₹ set small and raised, paise
/// muted. Counts to new values. Respects "hide balances" and reads as a
/// spoken amount.
class LuxeAmount extends StatefulWidget {
  const LuxeAmount(
    this.amount, {
    super.key,
    required this.style,
    this.sign = SignDisplay.auto,
    this.decimals = DecimalDisplay.none,
    this.color,
    this.animate = true,
    this.countFromZero = false,
    this.fit = true,
    this.textAlign,
    this.symbolScale = 0.52,
  });

  final Money amount;
  final TextStyle style;
  final SignDisplay sign;
  final DecimalDisplay decimals;
  final Color? color;
  final bool animate;
  final bool countFromZero;
  final bool fit;
  final TextAlign? textAlign;
  final double symbolScale;

  @override
  State<LuxeAmount> createState() => _LuxeAmountState();
}

class _LuxeAmountState extends State<LuxeAmount> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
    value: 1,
  );
  late Money _from = widget.amount;
  late Money _to = widget.amount;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (widget.countFromZero && widget.animate && !context.reduceMotion && !widget.amount.isZero) {
      _from = Money.zero;
      _c.forward(from: 0);
    }
  }

  @override
  void didUpdateWidget(LuxeAmount old) {
    super.didUpdateWidget(old);
    if (widget.amount == _to) return;
    _from = _current;
    _to = widget.amount;
    if (!widget.animate || context.reduceMotion) {
      _c.value = 1;
    } else {
      _c.forward(from: 0);
    }
  }

  Money get _current {
    if (_c.value >= 1) return _to;
    final v = LuxeCurves.arrive.transform(_c.value);
    return Money.rupees(((_from.paise + (_to.paise - _from.paise) * v) / 100).round());
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hidden = AmountVisibility.hiddenOf(context);
    final base = widget.color == null ? widget.style : widget.style.copyWith(color: widget.color);
    final spoken = hidden ? 'Amount hidden' : AmountText.spokenLabel(widget.amount, sign: widget.sign);
    return Semantics(
      label: spoken,
      excludeSemantics: true,
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final done = _c.value >= 1;
            final value = done ? _to : _current;
            final text = hidden
                ? MoneyFormatter.masked
                : MoneyFormatter.format(
                    value,
                    sign: widget.sign,
                    decimals: done ? widget.decimals : DecimalDisplay.none,
                  );
            Widget child = Text.rich(_spans(text, base), maxLines: 1, softWrap: false, textAlign: widget.textAlign);
            if (widget.fit) {
              child = FittedBox(
                fit: BoxFit.scaleDown,
                alignment: switch (widget.textAlign) {
                  TextAlign.center => Alignment.center,
                  TextAlign.right || TextAlign.end => Alignment.centerRight,
                  _ => Alignment.centerLeft,
                },
                child: child,
              );
            }
            return child;
          },
        ),
      ),
    );
  }

  /// Splits "−₹1,23,456.78" into sign, small raised symbol, body and muted paise.
  TextSpan _spans(String text, TextStyle base) {
    final i = text.indexOf(MoneyFormatter.symbol);
    if (i < 0) return TextSpan(text: text, style: base);
    final size = base.fontSize ?? 16;
    final symbol = TextStyle(
      fontFamily: LuxeType.sansFamily,
      fontSize: size * widget.symbolScale,
      fontWeight: FontWeight.w500,
      fontVariations: const [FontVariation('wght', 500)],
      letterSpacing: size * 0.06,
      color: (base.color ?? Colors.black).withValues(alpha: 0.72),
    );
    final head = text.substring(0, i);
    var body = text.substring(i + 1);
    String? paise;
    final dot = body.lastIndexOf('.');
    if (dot > 0 && body.length - dot == 3) {
      paise = body.substring(dot);
      body = body.substring(0, dot);
    }
    return TextSpan(
      style: base,
      children: [
        if (head.isNotEmpty) TextSpan(text: head),
        TextSpan(text: MoneyFormatter.symbol, style: symbol),
        TextSpan(text: body),
        if (paise != null)
          TextSpan(
            text: paise,
            style: TextStyle(fontSize: size * 0.6, color: (base.color ?? Colors.black).withValues(alpha: 0.55)),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Progress
// ---------------------------------------------------------------------------

/// Thin track with a fill that draws in, an optional "ghost" (where it is
/// heading) and a tick (where it should be by now).
class LuxeProgressLine extends StatelessWidget {
  const LuxeProgressLine({
    super.key,
    required this.value,
    required this.color,
    this.ghost,
    this.tick,
    this.height = 6,
    this.track,
    this.tickColor,
  });

  final double value;
  final Color color;
  final double? ghost;
  final double? tick;
  final double height;
  final Color? track;
  final Color? tickColor;

  @override
  Widget build(BuildContext context) {
    final p = context.luxe;
    return SizedBox(
      height: height + 8,
      width: double.infinity,
      child: DrawIn(
        value: 1,
        builder: (context, v) => CustomPaint(
          painter: _LinePainter(
            value: value.clamp(0.0, 1.0) * v,
            ghost: ghost == null ? null : ghost!.clamp(0.0, 1.0) * v,
            tick: tick,
            color: color,
            track: track ?? p.sunk,
            tickColor: tickColor ?? p.ink,
            h: height,
            over: value > 1,
          ),
        ),
      ),
    );
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter({
    required this.value,
    required this.ghost,
    required this.tick,
    required this.color,
    required this.track,
    required this.tickColor,
    required this.h,
    required this.over,
  });

  final double value;
  final double? ghost;
  final double? tick;
  final Color color;
  final Color track;
  final Color tickColor;
  final double h;
  final bool over;

  @override
  void paint(Canvas canvas, Size size) {
    final top = (size.height - h) / 2;
    final r = Radius.circular(h / 2);
    final w = size.width;
    canvas.drawRRect(RRect.fromLTRBR(0, top, w, top + h, r), Paint()..color = track);
    final g = ghost;
    if (g != null && g > value) {
      final rect = RRect.fromLTRBR(0, top, w * g, top + h, r);
      canvas.drawRRect(rect, Paint()..color = color.withValues(alpha: 0.18));
      canvas.save();
      canvas.clipRRect(rect);
      final hatch = Paint()
        ..color = color.withValues(alpha: 0.35)
        ..strokeWidth = 1.2;
      for (var x = w * value - h; x < w * g; x += 4) {
        canvas.drawLine(Offset(x, top + h), Offset(x + h, top), hatch);
      }
      canvas.restore();
    }
    if (value > 0) {
      final fill = RRect.fromLTRBR(0, top, math.max(h, w * value), top + h, r);
      canvas.drawRRect(
        fill,
        Paint()..shader = LinearGradient(colors: [color.withValues(alpha: 0.75), color]).createShader(fill.outerRect),
      );
    }
    final k = tick;
    if (k != null && k > 0 && k < 1) {
      final x = (w * k).clamp(1.0, w - 1);
      canvas.drawRRect(
        RRect.fromLTRBR(x - 1, 0, x + 1, size.height, const Radius.circular(1)),
        Paint()..color = tickColor,
      );
    }
  }

  @override
  bool shouldRepaint(_LinePainter o) =>
      o.value != value || o.ghost != ghost || o.tick != tick || o.color != color || o.track != track;
}

/// Thin ring: track, value arc with rounded cap, optional marker notch.
class LuxeRing extends StatelessWidget {
  const LuxeRing({
    super.key,
    required this.value,
    required this.color,
    this.size = 48,
    this.stroke = 3,
    this.child,
    this.marker,
    this.track,
    this.gradient,
  });

  final double value;
  final Color color;
  final double size;
  final double stroke;
  final Widget? child;
  final double? marker;
  final Color? track;
  final List<Color>? gradient;

  @override
  Widget build(BuildContext context) {
    final p = context.luxe;
    return SizedBox.square(
      dimension: size,
      child: DrawIn(
        value: value.clamp(-1.0, 1.0),
        builder: (context, v) => CustomPaint(
          painter: RingPainter(
            value: v,
            color: color,
            track: track ?? p.sunk,
            stroke: stroke,
            marker: marker,
            markerColor: p.ink,
            gradient: gradient,
          ),
          child: Center(child: child),
        ),
      ),
    );
  }
}

class RingPainter extends CustomPainter {
  RingPainter({
    required this.value,
    required this.color,
    required this.track,
    required this.stroke,
    this.marker,
    required this.markerColor,
    this.gradient,
  });

  final double value;
  final Color color;
  final Color track;
  final double stroke;
  final double? marker;
  final Color markerColor;
  final List<Color>? gradient;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(stroke / 2 + 1);
    canvas.drawArc(
      rect,
      0,
      math.pi * 2,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = track,
    );
    if (value.abs() > 0.003) {
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round;
      final g = gradient;
      if (g != null) {
        paint.shader = SweepGradient(colors: g, transform: const GradientRotation(-math.pi / 2)).createShader(rect);
      } else {
        paint.color = color;
      }
      canvas.drawArc(rect, -math.pi / 2, value * math.pi * 2, false, paint);
    }
    final m = marker;
    if (m != null && m > 0 && m < 1) {
      final a = -math.pi / 2 + m * math.pi * 2;
      final c = rect.center;
      final r = rect.width / 2;
      canvas.drawLine(
        c + Offset(math.cos(a), math.sin(a)) * (r - stroke * 1.4),
        c + Offset(math.cos(a), math.sin(a)) * (r + stroke * 1.4),
        Paint()
          ..color = markerColor
          ..strokeWidth = 1.6
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(RingPainter o) =>
      o.value != value || o.color != color || o.track != track || o.marker != marker || o.stroke != stroke;
}

// ---------------------------------------------------------------------------
// Loading, empty and error states
// ---------------------------------------------------------------------------

/// A soft band of light sweeping across placeholder bones while loading.
class LuxeShimmer extends StatefulWidget {
  const LuxeShimmer({super.key, required this.child});

  final Widget child;

  @override
  State<LuxeShimmer> createState() => _LuxeShimmerState();
}

class _LuxeShimmerState extends State<LuxeShimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (context.reduceMotion) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.luxe;
    return Semantics(
      label: 'Loading',
      liveRegion: true,
      child: ExcludeSemantics(
        child: AnimatedBuilder(
          animation: _c,
          child: widget.child,
          builder: (context, child) => ShaderMask(
            blendMode: BlendMode.srcATop,
            shaderCallback: (rect) {
              final x = -1.0 + 3 * Curves.easeInOut.transform(_c.value);
              return LinearGradient(
                begin: Alignment(x - 1, -0.3),
                end: Alignment(x + 1, 0.3),
                colors: [p.sunk, p.shimmer, p.sunk],
                stops: const [0.35, 0.5, 0.65],
              ).createShader(rect);
            },
            child: child,
          ),
        ),
      ),
    );
  }
}

class LuxeBone extends StatelessWidget {
  const LuxeBone({super.key, this.width, required this.height, this.radius = 12});

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(color: context.luxe.sunk, borderRadius: BorderRadius.circular(radius)),
  );
}

/// Icon inside fine concentric rings, a serif line and one action.
class LuxeEmpty extends StatelessWidget {
  const LuxeEmpty({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.actionIcon,
    this.onAction,
    this.tone,
  });

  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final IconData? actionIcon;
  final VoidCallback? onAction;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final p = context.luxe;
    final t = context.lt;
    final accent = tone ?? p.goldInk;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Reveal(
            scale: 0.85,
            child: SizedBox.square(
              dimension: 104,
              child: CustomPaint(
                painter: _HaloPainter(p.line, p.lineStrong),
                child: Center(
                  child: Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(color: p.tint(accent, 0.1), shape: BoxShape.circle),
                    child: Icon(icon, size: 22, color: accent),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(title, textAlign: TextAlign.center, style: t.title.copyWith(fontSize: 22)),
          if (message != null) ...[
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Text(message!, textAlign: TextAlign.center, style: t.bodySoft),
            ),
          ],
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 22),
            LuxeButton(label: actionLabel!, icon: actionIcon, onPressed: onAction, compact: true),
          ],
        ],
      ),
    );
  }
}

class _HaloPainter extends CustomPainter {
  _HaloPainter(this.a, this.b);
  final Color a;
  final Color b;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    canvas.drawCircle(
      c,
      size.width / 2 - 1,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = a,
    );
    final dash = Paint()
      ..style = PaintingStyle.stroke
      ..color = b
      ..strokeWidth = 1;
    final r = size.width / 2 - 12;
    for (var i = 0; i < 48; i += 2) {
      final a0 = i / 48 * math.pi * 2;
      canvas.drawArc(Rect.fromCircle(center: c, radius: r), a0, math.pi / 48, false, dash);
    }
  }

  @override
  bool shouldRepaint(_HaloPainter o) => o.a != a || o.b != b;
}

/// Failure with the reason and a way forward.
class LuxeError extends StatelessWidget {
  const LuxeError({super.key, required this.title, this.message, this.onRetry});

  final String title;
  final String? message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: LuxeEmpty(
      icon: LucideIcons.cloudOff,
      tone: context.luxe.negative,
      title: title,
      message: message ?? 'Please check your connection and try again.',
      actionLabel: onRetry == null ? null : 'Try again',
      actionIcon: LucideIcons.rotateCw,
      onAction: onRetry,
    ),
  );
}
