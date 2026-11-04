import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../design_system/motion/motion.dart';
import '../tokens.dart';

/// Loader timing: wait [_showAfter] before showing (near-instant work never
/// flashes), then keep it up at least [_minVisible] so it never flickers.
const Duration _showAfter = Duration(milliseconds: 120);
const Duration _minVisible = Duration(milliseconds: 450);

int _activeLoaders = 0;

/// Runs [task] behind a blocking, animated loader until it completes.
///
/// Use it for every backend call the user has to wait for: taps, back and
/// barrier dismissal are blocked, so nothing looks done while the request
/// is still running. Nested calls share the loader that is already up.
Future<T> runWithLoader<T>(BuildContext context, Future<T> Function() task) async {
  if (_activeLoaders > 0 || !context.mounted) return task();
  final navigator = Navigator.of(context, rootNavigator: true);
  final c = context.ink;
  _activeLoaders++;

  Route<void>? route;
  DateTime? shownAt;
  final timer = Timer(_showAfter, () {
    if (!navigator.mounted) return;
    shownAt = DateTime.now();
    route = _LoaderRoute(scrim: c.scrim);
    navigator.push(route!);
  });

  try {
    return await task();
  } finally {
    timer.cancel();
    final shown = shownAt;
    if (shown != null) {
      final left = _minVisible - DateTime.now().difference(shown);
      if (left > Duration.zero) await Future<void>.delayed(left);
    }
    final r = route;
    if (r != null && r.isActive && navigator.mounted) navigator.removeRoute(r);
    _activeLoaders--;
  }
}

class _LoaderRoute extends RawDialogRoute<void> {
  _LoaderRoute({required Color scrim})
    : super(
        barrierDismissible: false,
        barrierColor: scrim,
        transitionDuration: const Duration(milliseconds: 180),
        pageBuilder: (_, _, _) => const PopScope(canPop: false, child: Center(child: FinnBusyIndicator())),
        transitionBuilder: (context, animation, _, child) {
          final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
          return FadeTransition(
            opacity: curved,
            child: ScaleTransition(scale: Tween(begin: 0.92, end: 1.0).animate(curved), child: child),
          );
        },
      );
}

/// The loader card: a brand-coloured arc sweeping around a soft track.
class FinnBusyIndicator extends StatefulWidget {
  const FinnBusyIndicator({super.key});

  @override
  State<FinnBusyIndicator> createState() => _FinnBusyIndicatorState();
}

class _FinnBusyIndicatorState extends State<FinnBusyIndicator> with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))
    ..repeat();

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final reduce = context.reduceMotion;
    return Semantics(
      label: 'Please wait',
      liveRegion: true,
      child: Material(
        color: c.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: Rad.rLg, side: BorderSide(color: c.line)),
        child: SizedBox.square(
          dimension: 88,
          child: Center(
            child: AnimatedBuilder(
              animation: _spin,
              builder: (_, _) => CustomPaint(
                size: const Size.square(40),
                painter: _ArcPainter(
                  progress: _spin.value,
                  color: c.brand,
                  track: c.brand.withValues(alpha: 0.14),
                  pulse: !reduce,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ArcPainter extends CustomPainter {
  _ArcPainter({required this.progress, required this.color, required this.track, required this.pulse});

  final double progress;
  final Color color;
  final Color track;
  final bool pulse;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 4.0;
    final rect = Offset.zero & size;
    final arcRect = rect.deflate(stroke / 2);
    canvas.drawArc(
      arcRect,
      0,
      math.pi * 2,
      false,
      Paint()
        ..color = track
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );
    // The arc grows and shrinks while it turns, unless motion is reduced.
    final wave = pulse ? (math.sin(progress * math.pi * 2) + 1) / 2 : 0.5;
    final sweep = math.pi * (0.35 + 0.9 * wave);
    final start = progress * math.pi * 2 - math.pi / 2;
    canvas.drawArc(
      arcRect,
      start,
      sweep,
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = stroke,
    );
  }

  @override
  bool shouldRepaint(_ArcPainter old) => old.progress != progress || old.color != color || old.pulse != pulse;
}
