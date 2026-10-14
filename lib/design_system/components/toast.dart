import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../motion/motion.dart';
import '../tokens/tokens.dart';
import '../vault/vault.dart';
import 'safe_insets.dart';
import 'tone.dart';

/// Top-centre overlay toasts. Only one is visible at a time.
abstract final class FinnToast {
  static OverlayEntry? _current;

  /// Success toast (3s, light haptic).
  static void success(BuildContext context, String title, {String? subtitle}) =>
      show(context, tone: FinnTone.positive, title: title, subtitle: subtitle);

  /// Error toast (4s, heavy haptic).
  static void error(BuildContext context, String title, {String? subtitle}) =>
      show(context, tone: FinnTone.negative, title: title, subtitle: subtitle);

  /// Warning toast (3s, medium haptic).
  static void warning(BuildContext context, String title, {String? subtitle}) =>
      show(context, tone: FinnTone.warning, title: title, subtitle: subtitle);

  /// Informational toast (3s).
  static void info(BuildContext context, String title, {String? subtitle}) =>
      show(context, tone: FinnTone.info, title: title, subtitle: subtitle);

  /// Shows a toast of [tone], replacing any visible toast.
  static void show(
    BuildContext context, {
    required FinnTone tone,
    required String title,
    String? subtitle,
    Duration? duration,
  }) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    final theme = Theme.of(context);
    final reduce = context.reduceMotion;
    final direction = Directionality.maybeOf(context) ?? TextDirection.ltr;
    final view = View.maybeOf(context);

    dismiss();
    switch (tone) {
      case FinnTone.positive:
        HapticFeedback.lightImpact();
      case FinnTone.negative:
        HapticFeedback.heavyImpact();
      case FinnTone.warning:
        HapticFeedback.mediumImpact();
      case FinnTone.info:
        break;
    }

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => Theme(
        data: theme,
        child: MotionScope(
          reduceMotion: reduce,
          child: _ToastView(
            tone: tone,
            title: title,
            subtitle: subtitle,
            duration: duration ??
                (tone == FinnTone.negative ? const Duration(seconds: 4) : const Duration(seconds: 3)),
            onDismissed: () {
              if (entry.mounted) entry.remove();
              if (identical(_current, entry)) _current = null;
            },
          ),
        ),
      ),
    );
    _current = entry;
    overlay.insert(entry);

    if (view != null) {
      final message = subtitle == null ? title : '$title. $subtitle';
      unawaited(SemanticsService.sendAnnouncement(view, message, direction));
    }
  }

  /// Removes the visible toast immediately, if any.
  static void dismiss() {
    final current = _current;
    _current = null;
    if (current != null && current.mounted) current.remove();
  }
}

class _ToastView extends StatefulWidget {
  const _ToastView({
    required this.tone,
    required this.title,
    required this.subtitle,
    required this.duration,
    required this.onDismissed,
  });

  final FinnTone tone;
  final String title;
  final String? subtitle;
  final Duration duration;
  final VoidCallback onDismissed;

  @override
  State<_ToastView> createState() => _ToastViewState();
}

class _ToastViewState extends State<_ToastView> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: Durations2.slow, reverseDuration: Durations2.normal);
  late final CurvedAnimation _curve =
      CurvedAnimation(parent: _controller, curve: VaultMotion.spring, reverseCurve: Curves2.exit);
  Timer? _timer;
  double _drag = 0;
  bool _closing = false;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final reduced = context.reduceMotion;
    if (reduced) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
    _timer = Timer(widget.duration, _close);
  }

  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    _timer?.cancel();
    if (!context.reduceMotion) await _controller.reverse();
    if (mounted) widget.onDismissed();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _curve.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.vault;
    final t = context.vt;
    final accent = switch (widget.tone) {
      FinnTone.positive => VaultPalette.dark.positive,
      FinnTone.negative => VaultPalette.dark.negative,
      FinnTone.warning => VaultPalette.dark.warning,
      FinnTone.info => VaultPalette.dark.info,
    };
    final sub = widget.subtitle;
    // An obsidian capsule in both themes: it reads as system feedback, not
    // as part of the page, and carries its tone in a lit emblem + a
    // draining hairline that shows how long it will stay.
    final card = Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 18, 10),
      decoration: BoxDecoration(
        color: p.toast,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: const [
          BoxShadow(color: Color(0x47000000), blurRadius: 30, offset: Offset(0, 14), spreadRadius: -8),
        ],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent.withValues(alpha: 0.16),
                  border: Border.all(color: accent.withValues(alpha: 0.35)),
                ),
                child: Icon(widget.tone.icon, size: 19, color: accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: t.heading.copyWith(fontSize: 14.5, color: p.onToast),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (sub != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        sub,
                        style: t.caption.copyWith(color: p.onToastSoft),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          Positioned(
            left: 56,
            right: 0,
            bottom: -6,
            child: _Drain(duration: widget.duration, color: accent),
          ),
        ],
      ),
    );

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Padding(
        padding: EdgeInsets.only(top: context.safeTop, left: context.safeInsets.left, right: context.safeInsets.right),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.gutter, vertical: Space.x2),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: AnimatedBuilder(
                animation: _curve,
                builder: (context, child) => Transform.translate(
                  offset: Offset(0, -28 * (1 - _curve.value) + _drag),
                  child: Transform.scale(
                    scaleX: 0.86 + 0.14 * _curve.value,
                    scaleY: 0.7 + 0.3 * _curve.value,
                    alignment: Alignment.topCenter,
                    child: Opacity(opacity: _curve.value.clamp(0.0, 1.0), child: child),
                  ),
                ),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _close,
                  onVerticalDragUpdate: (d) => setState(() => _drag = (_drag + d.delta.dy).clamp(-120.0, 8.0)),
                  onVerticalDragEnd: (d) {
                    if (_drag < -24 || (d.primaryVelocity ?? 0) < -300) {
                      _close();
                    } else {
                      setState(() => _drag = 0);
                    }
                  },
                  child: Semantics(
                    container: true,
                    button: true,
                    hint: 'Dismiss',
                    child: Material(type: MaterialType.transparency, child: card),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Hairline that drains over the toast's lifetime.
class _Drain extends StatelessWidget {
  const _Drain({required this.duration, required this.color});

  final Duration duration;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (context.reduceMotion) return const SizedBox.shrink();
    return ExcludeSemantics(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 1, end: 0),
        duration: duration,
        builder: (context, v, _) => Align(
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: v,
            child: Container(
              height: 1.5,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
