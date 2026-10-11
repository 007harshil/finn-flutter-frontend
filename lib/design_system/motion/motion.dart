import 'package:flutter/widgets.dart';

import '../tokens/tokens.dart';

/// Resolved motion settings for a subtree. Provided by the app root from
/// the platform "reduce motion" flag plus the user's in-app preference.
class MotionScope extends InheritedWidget {
  const MotionScope({super.key, required this.reduceMotion, required super.child});

  final bool reduceMotion;

  static bool reduceMotionOf(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<MotionScope>();
    if (scope != null) return scope.reduceMotion;
    return MediaQuery.maybeDisableAnimationsOf(context) ?? false;
  }

  @override
  bool updateShouldNotify(MotionScope oldWidget) => oldWidget.reduceMotion != reduceMotion;
}

/// Motion accessor: `context.motion.normal`. Durations collapse to zero
/// (or near-zero) when reduced motion is requested.
class Motion {
  const Motion(this.reduced);

  final bool reduced;

  Duration _d(Duration d) => reduced ? Duration.zero : d;

  Duration get instant => _d(Durations2.instant);
  Duration get fast => _d(Durations2.fast);
  Duration get normal => _d(Durations2.normal);
  Duration get slow => _d(Durations2.slow);
  Duration get counter => _d(Durations2.counter);
  Duration get progress => _d(Durations2.progress);
  Duration get stagger => _d(Durations2.stagger);
  Duration get page => reduced ? const Duration(milliseconds: 1) : Durations2.pageTransition;

  Curve get standard => Curves2.standard;
  Curve get emphasized => Curves2.emphasized;
}

extension MotionX on BuildContext {
  Motion get motion => Motion(MotionScope.reduceMotionOf(this));
  bool get reduceMotion => MotionScope.reduceMotionOf(this);
}
