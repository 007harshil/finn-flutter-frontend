import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../motion/motion.dart';
import 'vault_tokens.dart';

/// One-shot entrance (Framer-style `initial → animate`): rises [offset]
/// px and fades in after [delay] (+ `index × stagger`), then rests.
/// Collapses to the final frame under reduced motion.
class VaultRise extends StatefulWidget {
  const VaultRise({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.index = 0,
    this.offset = 14,
    this.duration = const Duration(milliseconds: 620),
    this.scale = 1,
  });

  final Widget child;
  final Duration delay;
  final int index;
  final double offset;
  final Duration duration;

  /// Starting scale (1 = none).
  final double scale;

  @override
  State<VaultRise> createState() => _VaultRiseState();
}

class _VaultRiseState extends State<VaultRise> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this);
  Curve _curve = VaultMotion.settle;
  Curve _fade = Curves.easeOut;
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
    final wait = widget.delay + VaultMotion.stagger * widget.index.clamp(0, 14);
    final total = wait + widget.duration;
    final lead = wait.inMicroseconds / total.inMicroseconds;
    _curve = Interval(lead, 1, curve: VaultMotion.settle);
    _fade = Interval(lead, math.min(1, lead + 0.55), curve: Curves.easeOut);
    _c.duration = total;
    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        final done = _c.value >= 1;
        final v = done ? 1.0 : _curve.transform(_c.value);
        final o = done ? 1.0 : _fade.transform(_c.value);
        return Opacity(
          opacity: o.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, widget.offset * (1 - v)),
            child: Transform.scale(scale: widget.scale + (1 - widget.scale) * v, child: child),
          ),
        );
      },
    );
  }
}

/// Tactile press: sinks while held, springs back on release, with a
/// selection haptic. Carries button semantics.
class VaultPress extends StatefulWidget {
  const VaultPress({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scale = 0.97,
    this.haptic = true,
    this.semanticLabel,
    this.selected,
    this.excludeSemantics = true,
    this.enabled = true,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;
  final bool haptic;
  final String? semanticLabel;
  final bool? selected;
  final bool excludeSemantics;
  final bool enabled;

  @override
  State<VaultPress> createState() => _VaultPressState();
}

class _VaultPressState extends State<VaultPress> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v && mounted) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.enabled && (widget.onTap != null || widget.onLongPress != null);
    final reduced = context.reduceMotion;
    return Semantics(
      button: true,
      enabled: active,
      label: widget.semanticLabel,
      selected: widget.selected,
      excludeSemantics: widget.excludeSemantics && widget.semanticLabel != null,
      onTap: active ? widget.onTap : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        onTapDown: active ? (_) => _set(true) : null,
        onTapUp: active ? (_) => _set(false) : null,
        onTapCancel: active ? () => _set(false) : null,
        onTap: active && widget.onTap != null
            ? () {
                if (widget.haptic) HapticFeedback.selectionClick();
                widget.onTap!();
              }
            : null,
        onLongPress: active && widget.onLongPress != null
            ? () {
                _set(false);
                HapticFeedback.mediumImpact();
                widget.onLongPress!();
              }
            : null,
        child: AnimatedScale(
          scale: _down ? widget.scale : 1,
          duration: reduced ? Duration.zero : (_down ? const Duration(milliseconds: 110) : VaultMotion.state),
          curve: _down ? Curves.easeOut : VaultMotion.pop,
          child: widget.child,
        ),
      ),
    );
  }
}

/// A band of light that sweeps across its child — once when [trigger]
/// changes, or continuously while [loop] is true (a loader that is
/// genuinely waiting). GSAP-style "shine" for the primary action.
class VaultSheen extends StatefulWidget {
  const VaultSheen({
    super.key,
    required this.child,
    this.loop = false,
    this.trigger,
    this.color = const Color(0x40FFFFFF),
    this.radius = 999,
    this.delay = const Duration(milliseconds: 420),
  });

  final Widget child;
  final bool loop;

  /// Any value; a change replays the sweep once.
  final Object? trigger;
  final Color color;
  final double radius;

  /// Delay before the very first sweep (lets the surface land first).
  final Duration delay;

  @override
  State<VaultSheen> createState() => _VaultSheenState();
}

class _VaultSheenState extends State<VaultSheen> with SingleTickerProviderStateMixin {
  static const _sweep = Duration(milliseconds: 1100);
  late final AnimationController _c = AnimationController(vsync: this);

  /// Fraction of the controller spent waiting before the band moves.
  double _lead = 0;
  bool _started = false;

  void _play({Duration delay = Duration.zero, bool loop = false}) {
    final total = delay + _sweep;
    _lead = delay.inMicroseconds / total.inMicroseconds;
    _c.duration = total;
    loop ? _c.repeat() : _c.forward(from: 0);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (context.reduceMotion) return;
    widget.loop ? _play(loop: true) : _play(delay: widget.delay);
  }

  @override
  void didUpdateWidget(VaultSheen old) {
    super.didUpdateWidget(old);
    if (context.reduceMotion) return;
    if (widget.loop && !old.loop) {
      _play(loop: true);
    } else if (!widget.loop && old.loop) {
      _c.stop();
      _c.value = 0;
    } else if (widget.trigger != old.trigger && !widget.loop) {
      _play();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.passthrough,
      children: [
        widget.child,
        Positioned.fill(
          child: IgnorePointer(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(widget.radius),
              child: AnimatedBuilder(
                animation: _c,
                builder: (context, _) {
                  final raw = _c.value;
                  if (raw <= _lead || raw >= 1) return const SizedBox.shrink();
                  final v = (raw - _lead) / (1 - _lead);
                  final x = -1.6 + 3.2 * Curves.easeInOutCubic.transform(v);
                  return DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment(x - 0.5, -1),
                        end: Alignment(x + 0.5, 1),
                        colors: [widget.color.withValues(alpha: 0), widget.color, widget.color.withValues(alpha: 0)],
                        stops: const [0.3, 0.5, 0.7],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Three beads breathing in sequence — the in-button loader.
class VaultDots extends StatefulWidget {
  const VaultDots({super.key, required this.color, this.size = 6});

  final Color color;
  final double size;

  @override
  State<VaultDots> createState() => _VaultDotsState();
}

class _VaultDotsState extends State<VaultDots> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!context.reduceMotion && !_c.isAnimating) _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading',
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 3; i++) ...[
              if (i > 0) SizedBox(width: widget.size * 0.8),
              Builder(
                builder: (context) {
                  final phase = (_c.value - i * 0.16) % 1;
                  final w = math.sin(phase * math.pi).clamp(0.0, 1.0);
                  return Transform.translate(
                    offset: Offset(0, -3 * w),
                    child: Container(
                      width: widget.size,
                      height: widget.size,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: widget.color.withValues(alpha: 0.35 + 0.65 * w),
                      ),
                    ),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Cross-fade + small vertical slide between children keyed by value.
class VaultSwap extends StatelessWidget {
  const VaultSwap({super.key, required this.child, this.duration = VaultMotion.state, this.alignment = Alignment.centerLeft});

  final Widget child;
  final Duration duration;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: context.reduceMotion ? Duration.zero : duration,
      switchInCurve: VaultMotion.settle,
      switchOutCurve: Curves.easeIn,
      layoutBuilder: (current, previous) => Stack(
        alignment: alignment,
        children: [...previous, ?current],
      ),
      transitionBuilder: (child, a) => FadeTransition(
        opacity: a,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.25), end: Offset.zero).animate(a),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

/// Animates a number from its previous value to [value] (counter roll).
class VaultCount extends StatelessWidget {
  const VaultCount({super.key, required this.value, required this.builder, this.duration = const Duration(milliseconds: 700)});

  final double value;
  final Widget Function(BuildContext context, double v) builder;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    if (context.reduceMotion) return builder(context, value);
    return TweenAnimationBuilder<double>(
      tween: Tween(end: value),
      duration: duration,
      curve: VaultMotion.settle,
      builder: (context, v, _) => builder(context, v),
    );
  }
}

/// A short horizontal shake (an input that was rejected). Replays whenever
/// [trigger] changes to a new non-null value.
class VaultShake extends StatefulWidget {
  const VaultShake({super.key, required this.child, required this.trigger});

  final Widget child;
  final Object? trigger;

  @override
  State<VaultShake> createState() => _VaultShakeState();
}

class _VaultShakeState extends State<VaultShake> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));

  @override
  void didUpdateWidget(VaultShake old) {
    super.didUpdateWidget(old);
    if (widget.trigger != null && widget.trigger != old.trigger && !context.reduceMotion) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    child: widget.child,
    builder: (context, child) {
      final v = _c.value;
      final dx = math.sin(v * math.pi * 5) * 8 * (1 - v);
      return Transform.translate(offset: Offset(dx, 0), child: child);
    },
  );
}
