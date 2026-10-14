import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../motion/motion.dart';

/// Motion vocabulary of Luxe. Everything here is finite (it always comes to
/// rest) and collapses to the final frame under reduced motion.
abstract final class LuxeCurves {
  /// Arrivals: fast start, long silky settle (GSAP "expo.out").
  static const Curve arrive = Cubic(0.16, 1, 0.3, 1);

  /// State changes inside a component.
  static const Curve glide = Cubic(0.65, 0, 0.35, 1);

  /// Departures.
  static const Curve leave = Cubic(0.7, 0, 0.84, 0);

  /// A small overshoot for things that "land" (chips, badges).
  static const Curve land = Cubic(0.34, 1.36, 0.64, 1);
}

abstract final class LuxeDurations {
  static const press = Duration(milliseconds: 120);
  static const quick = Duration(milliseconds: 220);
  static const base = Duration(milliseconds: 420);
  static const reveal = Duration(milliseconds: 760);
  static const draw = Duration(milliseconds: 1300);
  static const stagger = Duration(milliseconds: 70);
}

/// Framer-style entrance: rises, sharpens out of a soft blur and fades in,
/// once, after `index × stagger`.
class Reveal extends StatefulWidget {
  const Reveal({
    super.key,
    required this.child,
    this.index = 0,
    this.delay = Duration.zero,
    this.offset = 18,
    this.blur = 6,
    this.scale = 1,
    this.duration = LuxeDurations.reveal,
  });

  final Widget child;
  final int index;
  final Duration delay;
  final double offset;
  final double blur;

  /// Starting scale (1 = none).
  final double scale;
  final Duration duration;

  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> with SingleTickerProviderStateMixin {
  // The delay lives inside the controller (as a leading interval) rather
  // than in a Timer, so the entrance is one continuous, settle-able ticker.
  late final AnimationController _c = AnimationController(vsync: this);
  late CurvedAnimation _a = CurvedAnimation(parent: _c, curve: LuxeCurves.arrive);
  late CurvedAnimation _fade = CurvedAnimation(parent: _c, curve: Curves.easeOut);
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (context.reduceMotion) {
      _c.value = 1;
      return;
    }
    final wait = widget.delay + LuxeDurations.stagger * widget.index.clamp(0, 12);
    final total = wait + widget.duration;
    final lead = wait.inMicroseconds / total.inMicroseconds;
    _a.dispose();
    _fade.dispose();
    _a = CurvedAnimation(
      parent: _c,
      curve: Interval(lead, 1, curve: LuxeCurves.arrive),
    );
    _fade = CurvedAnimation(
      parent: _c,
      curve: Interval(lead, 1, curve: Curves.easeOut),
    );
    _c.duration = total;
    _c.forward();
  }

  @override
  void dispose() {
    _a.dispose();
    _fade.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        // One fixed widget structure for every frame (including the last):
        // swapping wrappers would remount the child and lose its state.
        final v = _c.value >= 1 ? 1.0 : _a.value;
        final sigma = widget.blur * (1 - v);
        final result = Transform.translate(
          offset: Offset(0, widget.offset * (1 - v)),
          child: Transform.scale(
            scale: widget.scale + (1 - widget.scale) * v,
            child: ImageFiltered(
              enabled: sigma > 0.3,
              imageFilter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
              child: child,
            ),
          ),
        );
        return Opacity(opacity: _c.value >= 1 ? 1 : _fade.value.clamp(0.0, 1.0), child: result);
      },
    );
  }
}

/// Tactile press: sinks slightly while held, lands back with a soft
/// overshoot. Carries button semantics and optional haptics.
class Squish extends StatefulWidget {
  const Squish({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scale = 0.97,
    this.haptic = true,
    this.semanticLabel,
    this.semanticHint,
    this.selected,
    this.excludeSemantics = false,
    this.behavior = HitTestBehavior.opaque,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;
  final bool haptic;
  final String? semanticLabel;
  final String? semanticHint;

  /// Selection state announced to assistive technology (chips, tabs).
  final bool? selected;
  final bool excludeSemantics;
  final HitTestBehavior behavior;

  @override
  State<Squish> createState() => _SquishState();
}

class _SquishState extends State<Squish> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v && mounted) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null || widget.onLongPress != null;
    final reduced = context.reduceMotion;
    return Semantics(
      button: enabled,
      label: widget.semanticLabel,
      hint: widget.semanticHint,
      selected: widget.selected,
      excludeSemantics: widget.excludeSemantics,
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: GestureDetector(
        behavior: widget.behavior,
        excludeFromSemantics: true,
        onTapDown: enabled ? (_) => _set(true) : null,
        onTapUp: enabled ? (_) => _set(false) : null,
        onTapCancel: enabled ? () => _set(false) : null,
        onTap: widget.onTap == null
            ? null
            : () {
                if (widget.haptic) HapticFeedback.selectionClick();
                widget.onTap!();
              },
        onLongPress: widget.onLongPress == null
            ? null
            : () {
                _set(false);
                HapticFeedback.mediumImpact();
                widget.onLongPress!();
              },
        child: AnimatedScale(
          scale: _down ? widget.scale : 1,
          duration: reduced ? Duration.zero : (_down ? LuxeDurations.press : LuxeDurations.quick),
          curve: _down ? Curves.easeOut : LuxeCurves.land,
          child: widget.child,
        ),
      ),
    );
  }
}

/// Draws a value from 0 (or its previous value) to [value] with the
/// "arrive" curve; the builder receives the animated value.
class DrawIn extends StatelessWidget {
  const DrawIn({
    super.key,
    required this.value,
    required this.builder,
    this.duration = LuxeDurations.draw,
    this.delay = Duration.zero,
  });

  final double value;
  final Widget Function(BuildContext context, double v) builder;
  final Duration duration;
  final Duration delay;

  @override
  Widget build(BuildContext context) {
    if (context.reduceMotion) return builder(context, value);
    final total = duration + delay;
    final lead = total.inMicroseconds == 0 ? 0.0 : delay.inMicroseconds / total.inMicroseconds;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value),
      duration: total,
      curve: Interval(lead, 1, curve: LuxeCurves.arrive),
      builder: (context, v, _) => builder(context, v),
    );
  }
}
