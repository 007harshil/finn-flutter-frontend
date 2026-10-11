import 'dart:async';

import 'package:flutter/widgets.dart';

import '../motion/motion.dart';
import '../tokens/tokens.dart';

extension BottomClearanceX on BuildContext {
  /// Bottom scroll padding that clears the floating navigation bar (the
  /// shell reports its height through `MediaQuery.padding`) and the FAB.
  double get bottomClearance => MediaQuery.paddingOf(this).bottom + Space.bottomClearance - Space.x6;
}

/// Fades and slides its child up once, delayed by `index * stagger`.
class StaggeredEntrance extends StatefulWidget {
  const StaggeredEntrance({
    super.key,
    required this.child,
    this.index = 0,
    this.offset = 12,
    this.maxStaggerIndex = 10,
  });

  final Widget child;

  /// Position in the list; drives the delay.
  final int index;

  /// Vertical slide distance in logical pixels.
  final double offset;

  /// Indices beyond this share the same (maximum) delay.
  final int maxStaggerIndex;

  @override
  State<StaggeredEntrance> createState() => _StaggeredEntranceState();
}

class _StaggeredEntranceState extends State<StaggeredEntrance> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: Durations2.slow);
  late final CurvedAnimation _curve = CurvedAnimation(parent: _controller, curve: Curves2.emphasized);
  Timer? _delay;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final motion = context.motion;
    if (motion.reduced) {
      _controller.value = 1;
      return;
    }
    final delay = motion.stagger * widget.index.clamp(0, widget.maxStaggerIndex);
    if (delay == Duration.zero) {
      _controller.forward();
    } else {
      _delay = Timer(delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _delay?.cancel();
    _curve.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _curve,
      child: AnimatedBuilder(
        animation: _curve,
        builder: (context, child) => Transform.translate(
          offset: Offset(0, widget.offset * (1 - _curve.value)),
          child: child,
        ),
        child: widget.child,
      ),
    );
  }
}

/// Constrains content to [maxWidth] and centres it horizontally (tablets).
class ResponsiveCenter extends StatelessWidget {
  const ResponsiveCenter({
    super.key,
    required this.child,
    this.maxWidth = Space.maxContentWidth,
    this.padding = EdgeInsets.zero,
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// [AnimatedSize] that respects reduced motion. With reduced motion the
/// duration is zero, and a zero-duration [AnimatedSize] re-dirties its own
/// layout ("RenderAnimatedSize was mutated in its own performLayout"), so the
/// child is laid out directly instead.
class MotionAnimatedSize extends StatelessWidget {
  const MotionAnimatedSize({super.key, required this.child, this.alignment = Alignment.topCenter});

  final Widget child;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    final motion = context.motion;
    if (motion.normal == Duration.zero) return child;
    return AnimatedSize(duration: motion.normal, curve: motion.standard, alignment: alignment, child: child);
  }
}
