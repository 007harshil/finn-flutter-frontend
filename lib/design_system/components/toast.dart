import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../../kit/tokens.dart';
import '../motion/motion.dart';
import '../tokens/tokens.dart' show Curves2, Durations2;
import 'tone.dart';

/// Top-centre overlay toasts in the ledger look: a quiet panel with one
/// meaning-coloured icon. Only one is visible at a time.
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
            duration: duration ?? (tone == FinnTone.negative ? const Duration(seconds: 4) : const Duration(seconds: 3)),
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
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: Durations2.normal,
    reverseDuration: Durations2.fast,
  );
  late final CurvedAnimation _curve = CurvedAnimation(
    parent: _controller,
    curve: Curves2.standard,
    reverseCurve: Curves2.exit,
  );
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
    final c = context.ink;
    final t = context.type;
    final accent = switch (widget.tone) {
      FinnTone.positive => c.green,
      FinnTone.negative => c.red,
      FinnTone.warning => c.amber,
      FinnTone.info => c.inkSoft,
    };
    final sub = widget.subtitle;
    final card = Container(
      padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md + 2, Sp.lg, Sp.md + 2),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: Rad.rMd,
        border: Border.all(color: c.lineStrong),
        boxShadow: c.isDark
            ? null
            : [BoxShadow(color: c.ink.withValues(alpha: 0.08), offset: const Offset(0, 4), blurRadius: 16)],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(widget.tone.icon, size: 20, color: accent),
          ),
          const SizedBox(width: Sp.md),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.title, style: t.bodyStrong, maxLines: 2, overflow: TextOverflow.ellipsis),
                if (sub != null) ...[
                  const SizedBox(height: 2),
                  Text(sub, style: t.label, maxLines: 3, overflow: TextOverflow.ellipsis),
                ],
              ],
            ),
          ),
        ],
      ),
    );

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Sp.gutter, vertical: Sp.sm),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: AnimatedBuilder(
                animation: _curve,
                builder: (context, child) => Transform.translate(
                  offset: Offset(0, -8 * (1 - _curve.value) + _drag),
                  child: Opacity(opacity: _curve.value.clamp(0.0, 1.0), child: child),
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
