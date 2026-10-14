import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/money/money.dart';
import '../components/layout.dart';
import '../motion/motion.dart';
import 'luxe_motion.dart';
import 'luxe_sheets.dart';
import 'luxe_tokens.dart';
import 'luxe_widgets.dart';

/// Second layer of Luxe: the pieces the commitment screens (loans,
/// subscriptions, money owed, timeline, insights, emergency fund) share.

// ---------------------------------------------------------------------------
// Obsidian hero
// ---------------------------------------------------------------------------

/// The hero surface: near-black obsidian with a champagne hairline, a soft
/// pool of light in one corner and, once on arrival, a band of light that
/// sweeps across it (like light catching a card). Text defaults to
/// [LuxePalette.onObsidian].
class LuxeObsidian extends StatelessWidget {
  const LuxeObsidian({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(22, 22, 22, 22),
    this.radius = LuxeSpace.rCard,
    this.glow,
    this.sheen = true,
    this.onTap,
    this.semanticLabel,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  /// Colour of the corner light (defaults to champagne).
  final Color? glow;
  final bool sheen;
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final p = context.luxe;
    final r = BorderRadius.circular(radius);
    final card = DecoratedBox(
      decoration: BoxDecoration(
        gradient: p.obsidianGradient,
        borderRadius: r,
        border: Border.all(color: p.obsidianEdge),
        boxShadow: p.heroShadow,
      ),
      child: ClipRRect(
        borderRadius: r,
        child: Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(child: CustomPaint(painter: _GlowPainter(glow ?? p.gold))),
            ),
            if (sheen && !context.reduceMotion) const Positioned.fill(child: IgnorePointer(child: _Sheen())),
            Padding(
              padding: padding,
              child: DefaultTextStyle.merge(
                style: TextStyle(color: p.onObsidian),
                child: IconTheme.merge(
                  data: IconThemeData(color: p.onObsidian),
                  child: child,
                ),
              ),
            ),
          ],
        ),
      ),
    );
    if (onTap == null) {
      return semanticLabel == null ? card : Semantics(container: true, label: semanticLabel, child: card);
    }
    return Squish(
      onTap: onTap,
      scale: 0.985,
      semanticLabel: semanticLabel,
      excludeSemantics: semanticLabel != null,
      child: card,
    );
  }
}

class _GlowPainter extends CustomPainter {
  _GlowPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width * 0.95, -size.height * 0.05);
    final r = math.max(size.width, size.height) * 0.75;
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(colors: [color.withValues(alpha: 0.22), color.withValues(alpha: 0)])
            .createShader(Rect.fromCircle(center: c, radius: r)),
    );
  }

  @override
  bool shouldRepaint(_GlowPainter old) => old.color != color;
}

/// One pass of light across the card, then nothing (finite motion).
class _Sheen extends StatefulWidget {
  const _Sheen();

  @override
  State<_Sheen> createState() => _SheenState();
}

class _SheenState extends State<_Sheen> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1900))
    ..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (context, _) {
      final v = const Interval(0.25, 1, curve: Cubic(0.65, 0, 0.35, 1)).transform(_c.value);
      if (v <= 0 || v >= 1) return const SizedBox.shrink();
      return CustomPaint(painter: _SheenPainter(v));
    },
  );
}

class _SheenPainter extends CustomPainter {
  _SheenPainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final x = -w * 0.6 + (w * 2.2) * t;
    final rect = Rect.fromLTWH(x - w * 0.3, 0, w * 0.6, size.height);
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = LinearGradient(
          begin: const Alignment(-1, -0.4),
          end: const Alignment(1, 0.4),
          colors: [
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: 0.07),
            Colors.white.withValues(alpha: 0),
          ],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_SheenPainter old) => old.t != t;
}

/// Eyebrow + figure inside an obsidian or paper surface.
class LuxeFigure extends StatelessWidget {
  const LuxeFigure({
    super.key,
    required this.label,
    required this.child,
    this.onDark = false,
    this.align = CrossAxisAlignment.start,
  });

  final String label;
  final Widget child;
  final bool onDark;
  final CrossAxisAlignment align;

  @override
  Widget build(BuildContext context) {
    final p = context.luxe;
    final t = context.lt;
    return MergeSemantics(
      child: Column(
        crossAxisAlignment: align,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: t.eyebrow.copyWith(fontSize: 10, color: onDark ? p.onObsidianSoft : p.inkMute),
          ),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }
}

/// Figures side by side, separated by hairlines.
class LuxeFigureRow extends StatelessWidget {
  const LuxeFigureRow({super.key, required this.children, this.onDark = false});

  final List<Widget> children;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final p = context.luxe;
    final line = onDark ? p.onObsidian.withValues(alpha: 0.12) : p.line;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: SizedBox(width: 1, child: ColoredBox(color: line)),
              ),
            Expanded(child: children[i]),
          ],
        ],
      ),
    );
  }
}

/// A money figure styled for use as the value of a [LuxeFigure].
class LuxeFigureAmount extends StatelessWidget {
  const LuxeFigureAmount(this.amount, {super.key, this.onDark = false, this.color, this.size = 17});

  final Money amount;
  final bool onDark;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = context.luxe;
    return LuxeAmount(
      amount,
      style: context.lt.number.copyWith(fontSize: size, color: color ?? (onDark ? p.onObsidian : p.ink)),
    );
  }
}

// ---------------------------------------------------------------------------
// Small pieces
// ---------------------------------------------------------------------------

/// Icon in a soft round well.
class LuxeIconDisc extends StatelessWidget {
  const LuxeIconDisc({super.key, required this.icon, this.color, this.size = 40, this.onDark = false});

  final IconData icon;
  final Color? color;
  final double size;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final p = context.luxe;
    final c = color ?? (onDark ? p.gold : p.ink);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: onDark ? p.onObsidian.withValues(alpha: 0.08) : p.tint(c, 0.1),
        border: Border.all(color: onDark ? p.onObsidian.withValues(alpha: 0.1) : c.withValues(alpha: 0.16)),
      ),
      child: Icon(icon, size: size * 0.44, color: c),
    );
  }
}

/// Calm inline message: tone icon, words and an optional action.
class LuxeNote extends StatelessWidget {
  const LuxeNote({
    super.key,
    required this.message,
    this.title,
    this.icon = LucideIcons.info,
    this.tone,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final String? title;
  final IconData icon;
  final Color? tone;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final p = context.luxe;
    final t = context.lt;
    final c = tone ?? p.goldInk;
    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        decoration: BoxDecoration(
          color: p.tint(c, 0.07),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: c.withValues(alpha: 0.18)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(icon, size: 18, color: c),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (title != null) ...[Text(title!, style: t.label.w(700).c(p.ink)), const SizedBox(height: 3)],
                  Text(message, style: t.caption.c(p.inkSoft)),
                  if (actionLabel != null && onAction != null) ...[
                    const SizedBox(height: 4),
                    Transform.translate(
                      offset: const Offset(-12, 0),
                      child: LuxeLink(label: actionLabel!, onTap: onAction!),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One label/value line of a [LuxeFacts] list.
class LuxeFact {
  const LuxeFact(this.label, {this.value, this.child, this.icon});
  final String label;
  final String? value;
  final Widget? child;
  final IconData? icon;
}

/// The big page title, always aligned to the start edge of the column.
class LuxePageTitle extends StatelessWidget {
  const LuxePageTitle({super.key, required this.title, this.eyebrow, this.subtitle});

  final String title;
  final String? eyebrow;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: LuxeTitle(title: title, eyebrow: eyebrow, subtitle: subtitle),
  );
}

/// Section opener: a short champagne rule, a tracked eyebrow, an optional
/// caption and a trailing action. Quieter than a serif title, for dense
/// detail pages.
class LuxeEyebrowHeader extends StatelessWidget {
  const LuxeEyebrowHeader({super.key, required this.label, this.caption, this.trailing});

  final String label;
  final String? caption;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final p = context.luxe;
    final t = context.lt;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 14,
                    height: 1.5,
                    decoration: BoxDecoration(gradient: p.goldGradient, borderRadius: BorderRadius.circular(1)),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Semantics(
                      header: true,
                      child: Text(label.toUpperCase(), style: t.eyebrow.c(p.inkSoft), maxLines: 1),
                    ),
                  ),
                ],
              ),
              if (caption != null) ...[
                const SizedBox(height: 6),
                Text(caption!, style: t.caption, maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }
}

/// Label/value pairs on paper, separated by hairlines. Long lists show
/// the first [initiallyShown] and fold the rest behind "Show all".
class LuxeFacts extends StatefulWidget {
  const LuxeFacts({super.key, required this.facts, this.footer, this.initiallyShown});

  final List<LuxeFact> facts;
  final Widget? footer;
  final int? initiallyShown;

  @override
  State<LuxeFacts> createState() => _LuxeFactsState();
}

class _LuxeFactsState extends State<LuxeFacts> {
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final p = context.luxe;
    final t = context.lt;
    final limit = widget.initiallyShown;
    final folds = limit != null && widget.facts.length > limit + 1;
    final facts = folds && !_all ? widget.facts.take(limit).toList() : widget.facts;
    return LuxeCard(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
      child: MotionAnimatedSize(
        child: Column(
          children: [
            for (var i = 0; i < facts.length; i++) ...[
              if (i > 0) const LuxeHairline(),
              MergeSemantics(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 50),
                  child: Row(
                    children: [
                      if (facts[i].icon != null) ...[
                        Icon(facts[i].icon, size: 15, color: p.inkMute),
                        const SizedBox(width: 10),
                      ],
                      Expanded(child: Text(facts[i].label, style: t.caption)),
                      const SizedBox(width: 12),
                      Flexible(
                        child: Align(
                          alignment: Alignment.centerRight,
                          child:
                              facts[i].child ??
                              Text(facts[i].value ?? '', textAlign: TextAlign.right, style: t.label.w(650).c(p.ink)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (folds) ...[
              const LuxeHairline(),
              Align(
                alignment: Alignment.centerLeft,
                child: LuxeShowMore(
                  expanded: _all,
                  total: widget.facts.length,
                  onToggle: () => setState(() => _all = !_all),
                ),
              ),
            ],
            if (widget.footer != null) ...[const LuxeHairline(), widget.footer!],
          ],
        ),
      ),
    );
  }
}

/// A node on a vertical rail (timelines, schedules, settlement history).
/// The line draws downward once as the node arrives.
class LuxeRailNode extends StatelessWidget {
  const LuxeRailNode({
    super.key,
    required this.child,
    required this.color,
    this.first = false,
    this.last = false,
    this.icon,
    this.hollow = false,
    this.nodeTop = 18,
    this.gutter = 34,
  });

  final Widget child;
  final Color color;
  final bool first;
  final bool last;
  final IconData? icon;

  /// Draws the node as a ring (future / projected items).
  final bool hollow;
  final double nodeTop;
  final double gutter;

  @override
  Widget build(BuildContext context) {
    final p = context.luxe;
    final size = icon == null ? 11.0 : 24.0;
    final x = gutter / 2;
    return Stack(
      children: [
        Positioned(
          left: x - 0.5,
          top: first ? nodeTop : 0,
          bottom: last ? null : 0,
          height: last ? nodeTop : null,
          child: SizedBox(width: 1, child: ColoredBox(color: p.lineStrong)),
        ),
        Positioned(
          left: x - size / 2,
          top: nodeTop - size / 2,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: hollow ? p.canvas : (icon == null ? color : p.paper),
              border: Border.all(color: color, width: icon == null ? 2 : 1.2),
              boxShadow: hollow || icon != null
                  ? null
                  : [BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 8)],
            ),
            child: icon == null ? null : Icon(icon, size: 12, color: color),
          ),
        ),
        Padding(
          padding: EdgeInsets.only(left: gutter + 6),
          child: child,
        ),
      ],
    );
  }
}

/// "Show all 24" / "Show less" toggle with a turning chevron.
class LuxeShowMore extends StatelessWidget {
  const LuxeShowMore({super.key, required this.expanded, required this.total, required this.onToggle});

  final bool expanded;
  final int total;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final p = context.luxe;
    return Squish(
      onTap: onToggle,
      semanticLabel: expanded ? 'Show less' : 'Show all $total',
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(expanded ? 'Show less' : 'Show all $total', style: context.lt.label.w(650).c(p.ink)),
            const SizedBox(width: 6),
            AnimatedRotation(
              turns: expanded ? 0.5 : 0,
              duration: context.reduceMotion ? Duration.zero : LuxeDurations.quick,
              curve: LuxeCurves.glide,
              child: Icon(LucideIcons.chevronDown, size: 15, color: p.ink),
            ),
          ],
        ),
      ),
    );
  }
}

/// Collapsible "how it works" style explanation.
class LuxeDisclosure extends StatefulWidget {
  const LuxeDisclosure({super.key, required this.title, required this.body, this.icon = LucideIcons.info});

  final String title;
  final String body;
  final IconData icon;

  @override
  State<LuxeDisclosure> createState() => _LuxeDisclosureState();
}

class _LuxeDisclosureState extends State<LuxeDisclosure> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final p = context.luxe;
    final t = context.lt;
    final reduced = context.reduceMotion;
    return Semantics(
      expanded: _open,
      child: Squish(
        onTap: () => setState(() => _open = !_open),
        scale: 0.99,
        semanticLabel: widget.title,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: p.line),
          ),
          child: MotionAnimatedSize(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Row(
                    children: [
                      Icon(widget.icon, size: 16, color: p.inkMute),
                      const SizedBox(width: 10),
                      Expanded(child: Text(widget.title, style: t.label.w(650).c(p.ink))),
                      AnimatedRotation(
                        turns: _open ? 0.5 : 0,
                        duration: reduced ? Duration.zero : LuxeDurations.quick,
                        child: Icon(LucideIcons.chevronDown, size: 16, color: p.inkMute),
                      ),
                    ],
                  ),
                ),
                if (_open)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14, left: 26),
                    child: Text(widget.body, style: t.caption),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Pages
// ---------------------------------------------------------------------------

/// Detail-page frame: lit canvas, a top bar (back, title that fades in
/// once the hero scrolls away, actions) that frosts over content, and one
/// scroll view.
class LuxeDetailPage extends StatefulWidget {
  const LuxeDetailPage({
    super.key,
    required this.title,
    required this.slivers,
    this.actions = const [],
    this.storageKey,
    this.cacheExtent = 900,
    this.controller,
  });

  /// Optional external scroll controller (owned by the caller).
  final ScrollController? controller;

  final String title;
  final List<Widget> slivers;
  final List<Widget> actions;
  final String? storageKey;

  /// How far beyond the viewport lists are built ahead (short lists feel
  /// instant and their entrances have already started when they arrive).
  final double cacheExtent;

  @override
  State<LuxeDetailPage> createState() => _LuxeDetailPageState();
}

class _LuxeDetailPageState extends State<LuxeDetailPage> {
  final _own = ScrollController();
  static const _bar = 56.0;

  ScrollController get _scroll => widget.controller ?? _own;

  @override
  void dispose() {
    _own.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.luxe;
    final t = context.lt;
    final top = MediaQuery.paddingOf(context).top;
    // The bar sits above the scroll view (not over it), so content brought
    // into view — by a tap, a screen reader or the keyboard — is never
    // hidden behind it.
    return Scaffold(
      backgroundColor: p.canvas,
      body: Stack(
        fit: StackFit.expand,
        children: [
          LuxeBackdrop(scroll: _scroll),
          Column(
            children: [
              AnimatedBuilder(
                animation: _scroll,
                builder: (context, _) {
                  final offset = _scroll.hasClients && _scroll.positions.length == 1 ? _scroll.offset : 0.0;
                  final f = ((offset - 40) / 60).clamp(0.0, 1.0);
                  return Container(
                    height: top + _bar,
                    padding: EdgeInsets.only(top: top, left: 8, right: 8),
                    decoration: BoxDecoration(
                      color: p.canvas.withValues(alpha: 0.7 * f),
                      border: Border(
                        bottom: BorderSide(color: p.line.withValues(alpha: f)),
                      ),
                    ),
                    child: Row(
                      children: [
                        LuxeIconButton(
                          icon: LucideIcons.arrowLeft,
                          tooltip: 'Back',
                          style: f > 0.5 ? LuxeIconStyle.ghost : LuxeIconStyle.paper,
                          size: 40,
                          onPressed: () => Navigator.of(context).maybePop(),
                        ),
                        Expanded(
                          child: f == 0
                              ? const SizedBox.shrink()
                              : Opacity(
                                  opacity: f,
                                  child: Transform.translate(
                                    offset: Offset(0, 6 * (1 - f)),
                                    child: ExcludeSemantics(
                                      excluding: f < 0.5,
                                      child: Text(
                                        widget.title,
                                        textAlign: TextAlign.center,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: t.heading.copyWith(fontSize: 15),
                                      ),
                                    ),
                                  ),
                                ),
                        ),
                        if (widget.actions.isEmpty) const SizedBox(width: 48) else ...widget.actions,
                      ],
                    ),
                  );
                },
              ),
              Expanded(
                child: CustomScrollView(
                  key: widget.storageKey == null ? null : PageStorageKey<String>(widget.storageKey!),
                  controller: _scroll,
                  scrollCacheExtent: ScrollCacheExtent.pixels(widget.cacheExtent),
                  slivers: [
                    const SliverToBoxAdapter(child: SizedBox(height: 4)),
                    ...widget.slivers,
                    SliverToBoxAdapter(child: SizedBox(height: context.bottomClearance + 12)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Pinned controls row (tabs, search, filters) that frosts over content.
class LuxePinnedBar extends SliverPersistentHeaderDelegate {
  LuxePinnedBar({required this.child, this.height = 60, this.fullBleed = false});

  final Widget child;
  final double height;

  /// Lets [child] (e.g. a horizontal rail) run edge to edge; it then pads
  /// itself.
  final bool fullBleed;

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final p = context.luxe;
    final on = overlapsContent || shrinkOffset > 0;
    final content = AnimatedContainer(
      duration: LuxeDurations.quick,
      decoration: BoxDecoration(
        color: on ? p.canvas.withValues(alpha: 0.82) : Colors.transparent,
        border: Border(bottom: BorderSide(color: on ? p.line : Colors.transparent)),
      ),
      child: ResponsiveCenter(
        padding: EdgeInsets.symmetric(horizontal: fullBleed ? 0 : LuxeSpace.gutter, vertical: 8),
        child: child,
      ),
    );
    // One structure whether pinned or not, so the controls keep their state
    // (scroll position, focus) as the bar starts and stops frosting.
    return ClipRect(
      child: BackdropFilter(enabled: on, filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16), child: content),
    );
  }

  @override
  bool shouldRebuild(LuxePinnedBar old) => old.child != child || old.height != height || old.fullBleed != fullBleed;
}

/// Loading placeholder shaped like a Luxe page: a hero, a control row and
/// a few rows, under one sweeping shimmer.
class LuxePageSkeleton extends StatelessWidget {
  const LuxePageSkeleton({super.key, this.hero = 220, this.rows = 4, this.title = true, this.controls = true});

  final double hero;
  final int rows;
  final bool title;
  final bool controls;

  @override
  Widget build(BuildContext context) {
    return LuxeShimmer(
      child: ResponsiveCenter(
        padding: const EdgeInsets.fromLTRB(LuxeSpace.gutter, 12, LuxeSpace.gutter, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title) ...[
              const LuxeBone(width: 90, height: 11, radius: 6),
              const SizedBox(height: 12),
              const LuxeBone(width: 200, height: 34, radius: 10),
              const SizedBox(height: 24),
            ],
            LuxeBone(height: hero, radius: LuxeSpace.rCard),
            if (controls) ...[const SizedBox(height: 24), const LuxeBone(height: 44, radius: 22)],
            const SizedBox(height: 18),
            for (var i = 0; i < rows; i++) ...[
              const LuxeBone(height: 78, radius: LuxeSpace.rTile),
              const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Dialogs
// ---------------------------------------------------------------------------

/// A Luxe confirmation sheet. Resolves to true only on confirm.
Future<bool> showLuxeConfirm(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  String cancelLabel = 'Not now',
  IconData icon = LucideIcons.circleHelp,
  bool destructive = false,
}) async {
  final ok = await showLuxeSheet<bool>(
    context,
    builder: (context) {
      final p = context.luxe;
      final t = context.lt;
      return LuxeSheet(
        footer: Row(
          children: [
            Expanded(
              child: LuxeButton(
                label: cancelLabel,
                variant: LuxeButtonVariant.outline,
                expand: true,
                onPressed: () => Navigator.of(context).pop(false),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: LuxeButton(label: confirmLabel, expand: true, onPressed: () => Navigator.of(context).pop(true)),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Reveal(
              scale: 0.8,
              blur: 0,
              child: LuxeIconDisc(icon: icon, size: 52, color: destructive ? p.negative : p.goldInk),
            ),
            const SizedBox(height: 18),
            Semantics(header: true, child: Text(title, style: t.title.copyWith(fontSize: 26))),
            const SizedBox(height: 10),
            Text(message, style: t.bodySoft),
          ],
        ),
      );
    },
  );
  return ok ?? false;
}
