import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../motion/motion.dart';
import 'vault_motion.dart';
import 'vault_route.dart';
import 'vault_tokens.dart';

/// Layout of every Vault sheet:
///
/// * a grabber and header (eyebrow · serif title · one quiet line of
///   context · close) that can be pulled to dismiss;
/// * a body that scrolls under a hairline which only appears once content
///   has moved beneath the header;
/// * an optional dock pinned above the keyboard for the one primary action,
///   with content fading out beneath it.
///
/// Content rises in a short stagger after the sheet lands.
class VaultSheet extends StatefulWidget {
  const VaultSheet({
    super.key,
    required this.child,
    this.title,
    this.eyebrow,
    this.description,
    this.icon,
    this.footer,
    this.showClose = true,
    this.onClose,
    this.bodyPadding = const EdgeInsets.fromLTRB(VaultShape.gutter, 6, VaultShape.gutter, 24),
    this.headerTrailing,
  });

  final Widget child;
  final String? title;
  final String? eyebrow;
  final String? description;

  /// Optional emblem shown left of the title.
  final IconData? icon;

  /// Pinned primary action(s).
  final Widget? footer;
  final bool showClose;
  final VoidCallback? onClose;
  final EdgeInsetsGeometry bodyPadding;

  /// Extra header control placed before the close button.
  final Widget? headerTrailing;

  @override
  State<VaultSheet> createState() => _VaultSheetState();
}

class _VaultSheetState extends State<VaultSheet> {
  final _scroll = ScrollController();
  final _scrolled = ValueNotifier(false);
  final _moreBelow = ValueNotifier(false);
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_sync);
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  void _sync() {
    if (!_scroll.hasClients || _scroll.positions.length != 1) return;
    final pos = _scroll.position;
    _scrolled.value = pos.pixels > 2;
    _moreBelow.value = pos.maxScrollExtent - pos.pixels > 8;
  }

  @override
  void dispose() {
    _scroll.dispose();
    _scrolled.dispose();
    _moreBelow.dispose();
    super.dispose();
  }

  bool _onScroll(ScrollNotification n, VaultSheetDrag? drag) {
    if (n.depth != 0 || drag == null) return false;
    if (n is OverscrollNotification && n.dragDetails != null && n.overscroll < 0) {
      _dragging = true;
      drag.update(-n.overscroll);
    } else if (n is ScrollUpdateNotification && _dragging && n.dragDetails != null) {
      drag.update(n.scrollDelta ?? 0);
    } else if (n is ScrollEndNotification && _dragging) {
      _dragging = false;
      drag.end(n.dragDetails?.primaryVelocity ?? 0);
    }
    if (n is ScrollMetricsNotification || n is ScrollUpdateNotification) _sync();
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.vault;
    final t = context.vt;
    final drag = VaultSheetDrag.maybeOf(context);
    final foot = widget.footer;
    final title = widget.title;
    final eyebrow = widget.eyebrow;
    final desc = widget.description;
    final hasHeader = title != null || eyebrow != null || widget.showClose;

    Widget header = Padding(
      padding: const EdgeInsets.fromLTRB(VaultShape.gutter, 0, 12, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.icon != null) ...[
            Padding(
              padding: const EdgeInsets.only(top: 6, right: 14),
              child: VaultEmblem(icon: widget.icon!, size: 44),
            ),
          ],
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (eyebrow != null) ...[
                    VaultEyebrow(eyebrow),
                    const SizedBox(height: 8),
                  ],
                  if (title != null)
                    Semantics(
                      header: true,
                      child: VaultRise(
                        delay: const Duration(milliseconds: 60),
                        child: Text(title, style: t.title),
                      ),
                    ),
                  if (desc != null) ...[
                    const SizedBox(height: 6),
                    VaultRise(
                      delay: const Duration(milliseconds: 110),
                      child: Text(desc, style: t.bodySoft),
                    ),
                  ],
                ],
              ),
            ),
          ),
          ?widget.headerTrailing,
          if (widget.showClose)
            VaultIconButton(
              icon: LucideIcons.x,
              tooltip: 'Close',
              onPressed: widget.onClose ?? () => Navigator.of(context).maybePop(),
            ),
        ],
      ),
    );

    // The grabber and header are the sheet's handle.
    final handle = GestureDetector(
      behavior: HitTestBehavior.translucent,
      excludeFromSemantics: true,
      onVerticalDragUpdate: drag == null ? null : (d) => drag.update(d.delta.dy),
      onVerticalDragEnd: drag == null ? null : (d) => drag.end(d.primaryVelocity ?? 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 10),
          Center(
            child: ExcludeSemantics(
              child: Container(
                width: 38,
                height: 4.5,
                decoration: BoxDecoration(color: p.hairlineStrong, borderRadius: BorderRadius.circular(3)),
              ),
            ),
          ),
          SizedBox(height: hasHeader ? 12 : 8),
          if (hasHeader) header,
        ],
      ),
    );

    final body = NotificationListener<ScrollNotification>(
      onNotification: (n) => _onScroll(n, drag),
      child: SingleChildScrollView(
        controller: _scroll,
        physics: const ClampingScrollPhysics(),
        padding: widget.bodyPadding,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
        child: VaultRise(delay: const Duration(milliseconds: 140), offset: 22, child: widget.child),
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        handle,
        ValueListenableBuilder<bool>(
          valueListenable: _scrolled,
          builder: (context, on, _) => AnimatedContainer(
            duration: VaultMotion.state,
            height: 1,
            margin: EdgeInsets.symmetric(horizontal: on ? 0 : VaultShape.gutter),
            color: on ? p.hairline : p.hairline.withValues(alpha: 0),
          ),
        ),
        Flexible(child: body),
        if (foot != null) VaultDock(moreBelow: _moreBelow, child: foot),
      ],
    );
  }
}

/// The pinned action area of a sheet. Content scrolling beneath it fades
/// out behind a soft veil, and a hairline appears while more is below.
class VaultDock extends StatelessWidget {
  const VaultDock({super.key, required this.child, this.moreBelow});

  static final _never = ValueNotifier(false);

  final Widget child;
  final ValueListenable<bool>? moreBelow;

  @override
  Widget build(BuildContext context) {
    final p = context.vault;
    final listen = moreBelow ?? _never;
    return ValueListenableBuilder<bool>(
      valueListenable: listen,
      builder: (context, more, child) => Stack(
        clipBehavior: Clip.none,
        children: [
          // Veil over the last line of content.
          Positioned(
            left: 0,
            right: 0,
            top: -28,
            height: 28,
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: more ? 1 : 0,
                duration: VaultMotion.state,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [p.surface.withValues(alpha: 0), p.surface],
                    ),
                  ),
                ),
              ),
            ),
          ),
          AnimatedContainer(
            duration: VaultMotion.state,
            decoration: BoxDecoration(
              color: p.surface,
              border: Border(top: BorderSide(color: more ? p.hairline : p.hairline.withValues(alpha: 0))),
            ),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: child,
          ),
        ],
      ),
      child: child,
    );
  }
}

/// Small uppercase label with a champagne bead.
class VaultEyebrow extends StatelessWidget {
  const VaultEyebrow(this.text, {super.key, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final p = context.vault;
    final t = context.vt;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ExcludeSemantics(
          child: Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color ?? p.accent),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(child: Text(text.toUpperCase(), style: t.eyebrow, maxLines: 1, overflow: TextOverflow.ellipsis)),
      ],
    );
  }
}

/// Circular emblem: a soft ring around a glyph, tinted by meaning.
class VaultEmblem extends StatelessWidget {
  const VaultEmblem({super.key, required this.icon, this.color, this.size = 48, this.filled = false});

  final IconData icon;
  final Color? color;
  final double size;

  /// Solid tone disc (for strong states: success, destructive).
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final p = context.vault;
    final c = color ?? p.ink;
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: filled ? c : p.tint(c, 0.08),
          gradient: filled ? p.toneGradient(c) : null,
          border: filled ? null : Border.all(color: p.tint(c, 0.2)),
        ),
        child: Icon(icon, size: size * 0.42, color: filled ? p.surface : c),
      ),
    );
  }
}

/// Round 44 dp icon control with a 48 dp target.
class VaultIconButton extends StatelessWidget {
  const VaultIconButton({super.key, required this.icon, required this.tooltip, required this.onPressed, this.filled = true});

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final p = context.vault;
    return Tooltip(
      message: tooltip,
      child: VaultPress(
        onTap: onPressed,
        semanticLabel: tooltip,
        scale: 0.9,
        child: SizedBox.square(
          dimension: 48,
          child: Center(
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(shape: BoxShape.circle, color: filled ? p.well : Colors.transparent),
              child: Icon(icon, size: 18, color: p.inkSoft),
            ),
          ),
        ),
      ),
    );
  }
}

/// Frosted glass panel (used where Vault content overlays imagery).
class VaultGlass extends StatelessWidget {
  const VaultGlass({super.key, required this.child, this.radius = VaultShape.group, this.sigma = 16});

  final Widget child;
  final double radius;
  final double sigma;

  @override
  Widget build(BuildContext context) {
    final p = context.vault;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        enabled: !context.reduceMotion,
        filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: p.surface.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: p.hairline),
          ),
          child: child,
        ),
      ),
    );
  }
}
