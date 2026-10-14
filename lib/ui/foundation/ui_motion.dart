import 'package:flutter/widgets.dart';

import '../../design_system/motion/motion.dart' show MotionScope;

/// Motion tokens (new UI kit). Subtle by default; every duration collapses
/// to zero when the user or platform asks for reduced motion.
class UiMotion {
  const UiMotion._(this.reduced);

  final bool reduced;

  static UiMotion of(BuildContext context) => UiMotion._(MotionScope.reduceMotionOf(context));

  Duration _d(int ms) => reduced ? Duration.zero : Duration(milliseconds: ms);

  /// Press feedback, toggles.
  Duration get quick => _d(160);

  /// Content swaps, fades.
  Duration get normal => _d(240);

  /// Entrances.
  Duration get enter => _d(380);

  /// Bars and figures settling to a new value.
  Duration get settle => _d(700);

  static const Curve ease = Cubic(0.2, 0, 0, 1);
  static const Curve exit = Curves.easeInCubic;
}
