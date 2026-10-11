import 'package:flutter/animation.dart';
import 'package:flutter/painting.dart';

/// 4-point spacing scale.
abstract final class Space {
  static const double x0_5 = 2;
  static const double x1 = 4;
  static const double x1_5 = 6;
  static const double x2 = 8;
  static const double x2_5 = 10;
  static const double x3 = 12;
  static const double x4 = 16;
  static const double x5 = 20;
  static const double x6 = 24;
  static const double x8 = 32;
  static const double x10 = 40;
  static const double x12 = 48;
  static const double x16 = 64;

  /// Horizontal page gutter on phones.
  static const double gutter = 16;

  /// Gap between dashboard sections.
  static const double section = 28;

  /// Bottom padding that clears the navigation bar and FAB.
  static const double bottomClearance = 112;

  /// Maximum width of the main content column on tablets/desktop.
  static const double maxContentWidth = 560;
}

abstract final class Radii {
  static const double xs = 4;
  static const double sm = 6;
  static const double md = 8;
  static const double lg = 12;
  static const double xl = 16;
  static const double xxl = 20;
  static const double xxxl = 24;
  static const double full = 999;

  static const BorderRadius rSm = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius rMd = BorderRadius.all(Radius.circular(md));
  static const BorderRadius rLg = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius rXl = BorderRadius.all(Radius.circular(xl));
  static const BorderRadius rXxl = BorderRadius.all(Radius.circular(xxl));
  static const BorderRadius rXxxl = BorderRadius.all(Radius.circular(xxxl));
  static const BorderRadius rFull = BorderRadius.all(Radius.circular(full));
}

/// Elevation as layered, soft shadows. Dark mode uses [none]/[sm] mostly and
/// relies on surface contrast instead.
abstract final class Elevation {
  static const List<BoxShadow> none = [];
  static const List<BoxShadow> sm = [
    BoxShadow(color: Color(0x0D0F172A), blurRadius: 2, offset: Offset(0, 1)),
  ];
  static const List<BoxShadow> md = [
    BoxShadow(color: Color(0x0F0F172A), blurRadius: 6, offset: Offset(0, 2)),
    BoxShadow(color: Color(0x0A0F172A), blurRadius: 2, offset: Offset(0, 1)),
  ];
  static const List<BoxShadow> lg = [
    BoxShadow(color: Color(0x140F172A), blurRadius: 16, spreadRadius: -4, offset: Offset(0, 8)),
    BoxShadow(color: Color(0x0A0F172A), blurRadius: 4, offset: Offset(0, 2)),
  ];
  static const List<BoxShadow> xl = [
    BoxShadow(color: Color(0x1F0F172A), blurRadius: 32, spreadRadius: -8, offset: Offset(0, 16)),
    BoxShadow(color: Color(0x0D0F172A), blurRadius: 6, offset: Offset(0, 3)),
  ];

  static List<BoxShadow> tinted(Color color, {double alpha = 0.25}) => [
        BoxShadow(
          color: color.withValues(alpha: alpha),
          blurRadius: 20,
          spreadRadius: -6,
          offset: const Offset(0, 10),
        ),
      ];
}

/// Centralised motion system. Always read durations through
/// `context.motion` (see motion.dart) so reduced-motion is respected.
abstract final class Durations2 {
  static const Duration instant = Duration(milliseconds: 90);
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration normal = Duration(milliseconds: 240);
  static const Duration slow = Duration(milliseconds: 360);
  static const Duration counter = Duration(milliseconds: 600);
  static const Duration progress = Duration(milliseconds: 900);
  static const Duration stagger = Duration(milliseconds: 60);
  static const Duration pageTransition = Duration(milliseconds: 320);
}

abstract final class Curves2 {
  /// Default for most UI motion.
  static const Curve standard = Curves.easeOutCubic;

  /// Entrances and emphasis.
  static const Curve emphasized = Cubic(0.2, 0.0, 0.0, 1.0);

  /// Exits.
  static const Curve exit = Curves.easeInCubic;

  /// Press feedback.
  static const Curve press = Curves.easeOut;
}

/// Component dimensions.
abstract final class Dimens {
  static const double minTouch = 48;
  static const double buttonHeight = 48;
  static const double buttonHeightLg = 56;
  static const double buttonHeightSm = 36;
  static const double inputHeight = 52;
  static const double iconTile = 40;
  static const double iconTileSm = 32;
  static const double navBarHeight = 64;
  static const double fabSize = 56;
  static const double sheetHandleWidth = 40;
}
