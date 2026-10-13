import 'package:flutter/material.dart';

import 'ui_colors.dart';
import 'ui_type.dart';

/// 4-point spacing and radii (new UI kit).
abstract final class UiSpace {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;

  /// Page side gutter on phones.
  static const double gutter = 16;

  /// Between sections of a screen. Space alone separates them: no dividers.
  static const double section = 32;

  /// Minimum touch target.
  static const double touch = 44;

  /// Widest content column on tablets.
  static const double maxWidth = 560;
}

abstract final class UiRadius {
  static const BorderRadius panel = BorderRadius.all(Radius.circular(20));
  static const BorderRadius control = BorderRadius.all(Radius.circular(14));
  static const BorderRadius chip = BorderRadius.all(Radius.circular(8));
}

extension UiContext on BuildContext {
  UiColors get ui => UiColors.of(this);
  UiType get uiType => UiType.of(this);
}
