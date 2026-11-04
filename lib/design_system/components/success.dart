import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../kit/tokens.dart';
import '../motion/motion.dart';
import '../tokens/tokens.dart' show Durations2;

/// Success mark, stamped like an entry in a ledger: a tilted teal seal
/// with a check lands from slightly larger (220 ms, no bounce) with a firm
/// haptic. Under reduced motion it simply appears. [onCompleted] fires once
/// it has landed.
class SuccessCheck extends StatefulWidget {
  const SuccessCheck({super.key, this.size = 64, this.color, this.onCompleted});

  final double size;

  /// Defaults to the brand teal.
  final Color? color;
  final VoidCallback? onCompleted;

  @override
  State<SuccessCheck> createState() => _SuccessCheckState();
}

class _SuccessCheckState extends State<SuccessCheck> with SingleTickerProviderStateMixin {
  late final AnimationController _stamp = AnimationController(vsync: this, duration: const Duration(milliseconds: 220));
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final done = widget.onCompleted;
    if (context.reduceMotion) {
      _stamp.value = 1;
      if (done != null) WidgetsBinding.instance.addPostFrameCallback((_) => done());
      return;
    }
    _stamp.forward().whenComplete(() {
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      done?.call();
    });
  }

  @override
  void dispose() {
    _stamp.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final color = widget.color ?? c.brand;
    final size = widget.size;
    final seal = Transform.rotate(
      angle: -0.14,
      child: Container(
        width: size,
        height: size,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: color.withValues(alpha: 0.9), width: 2.5),
        ),
        child: Container(
          decoration: BoxDecoration(color: c.brandSoft, shape: BoxShape.circle),
          child: Icon(LucideIcons.check, size: size * 0.42, color: color),
        ),
      ),
    );
    return Semantics(
      label: 'Success',
      image: true,
      child: AnimatedBuilder(
        animation: _stamp,
        builder: (context, child) {
          final v = Curves.easeOutCubic.transform(_stamp.value);
          return Opacity(
            opacity: (_stamp.value * 2).clamp(0.0, 1.0),
            child: Transform.scale(scale: 1.6 - 0.6 * v, child: child),
          );
        },
        child: seal,
      ),
    );
  }
}

/// Shows a brief centred success overlay; completes once it is removed.
Future<void> showSuccessOverlay(
  BuildContext context, {
  required String title,
  String? subtitle,
  Duration duration = const Duration(milliseconds: 1200),
}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return Future<void>.value();
  final theme = Theme.of(context);
  final reduce = context.reduceMotion;
  final view = View.maybeOf(context);
  final direction = Directionality.maybeOf(context) ?? TextDirection.ltr;
  final completer = Completer<void>();

  HapticFeedback.lightImpact();
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => Theme(
      data: theme,
      child: MotionScope(
        reduceMotion: reduce,
        child: _SuccessOverlay(
          title: title,
          subtitle: subtitle,
          duration: duration,
          onDone: () {
            if (entry.mounted) entry.remove();
            if (!completer.isCompleted) completer.complete();
          },
        ),
      ),
    ),
  );
  overlay.insert(entry);
  if (view != null) {
    unawaited(SemanticsService.sendAnnouncement(view, subtitle == null ? title : '$title. $subtitle', direction));
  }
  return completer.future;
}

class _SuccessOverlay extends StatefulWidget {
  const _SuccessOverlay({required this.title, required this.subtitle, required this.duration, required this.onDone});

  final String title;
  final String? subtitle;
  final Duration duration;
  final VoidCallback onDone;

  @override
  State<_SuccessOverlay> createState() => _SuccessOverlayState();
}

class _SuccessOverlayState extends State<_SuccessOverlay> with SingleTickerProviderStateMixin {
  late final AnimationController _fade = AnimationController(vsync: this, duration: Durations2.fast);
  Timer? _timer;
  bool _started = false;
  bool _closing = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (context.reduceMotion) {
      _fade.value = 1;
    } else {
      _fade.forward();
    }
    _timer = Timer(widget.duration, _close);
  }

  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    _timer?.cancel();
    if (!context.reduceMotion) await _fade.reverse();
    widget.onDone();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final t = context.type;
    final sub = widget.subtitle;
    return FadeTransition(
      opacity: _fade,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _close,
        child: ColoredBox(
          color: c.scrim,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(Sp.xxl),
              child: Material(
                type: MaterialType.transparency,
                child: Container(
                  constraints: const BoxConstraints(minWidth: 240, maxWidth: 320),
                  padding: const EdgeInsets.symmetric(horizontal: Sp.xl, vertical: Sp.xl + Sp.xs),
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: Rad.rLg,
                    border: Border.all(color: c.line),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SuccessCheck(),
                      const SizedBox(height: Sp.lg),
                      Text(widget.title, textAlign: TextAlign.center, style: t.heading),
                      if (sub != null) ...[
                        const SizedBox(height: Sp.xs),
                        Text(sub, textAlign: TextAlign.center, style: t.label),
                      ],
                    ],
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
