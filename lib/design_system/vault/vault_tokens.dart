import 'dart:math' as math;

import 'package:flutter/material.dart';

/// "Vault": the visual language of every modal surface — sheets, forms,
/// dialogs, menus and toasts.
///
/// A modal is treated as a precious object lifted out of the page: it
/// floats free of the screen edges on a blurred, dimmed world; it is lit
/// from above (a hairline highlight on its top edge); the one number that
/// matters is set large in serif; everything else is quiet, grouped and
/// generously spaced. Colour is reserved for meaning (money in, money out,
/// warnings) and for the single champagne focus accent.
///
/// Read through `context.vault` (colours) and `context.vt` (type).
@immutable
class VaultPalette {
  const VaultPalette._({
    required this.isDark,
    required this.surface,
    required this.surfaceRaised,
    required this.well,
    required this.wellFocus,
    required this.hairline,
    required this.hairlineStrong,
    required this.highlight,
    required this.ink,
    required this.inkSoft,
    required this.inkMute,
    required this.inkFaint,
    required this.onInk,
    required this.accent,
    required this.accentInk,
    required this.positive,
    required this.negative,
    required this.warning,
    required this.info,
    required this.scrim,
    required this.inkGradientColors,
    required this.toast,
    required this.onToast,
    required this.onToastSoft,
  });

  final bool isDark;

  /// The modal body and its raised layer (popovers, the pressed state).
  final Color surface;
  final Color surfaceRaised;

  /// Inset wells: fields, tracks, unselected chips.
  final Color well;
  final Color wellFocus;
  final Color hairline;
  final Color hairlineStrong;

  /// The lit top edge of a floating surface.
  final Color highlight;

  /// Text: primary, secondary (≥ 4.5:1), tertiary (≥ 4.5:1), decorative.
  final Color ink;
  final Color inkSoft;
  final Color inkMute;
  final Color inkFaint;

  /// Foreground on the ink (primary) button.
  final Color onInk;

  /// Champagne: focus, the active step, the one highlight per view.
  final Color accent;

  /// Text-safe accent.
  final Color accentInk;
  final Color positive;
  final Color negative;
  final Color warning;
  final Color info;
  final Color scrim;
  final List<Color> inkGradientColors;

  /// Toast capsule (near-black in both themes) and its text.
  final Color toast;
  final Color onToast;
  final Color onToastSoft;

  Color tint(Color c, [double alpha = 0.1]) => c.withValues(alpha: isDark ? alpha * 1.7 : alpha);

  LinearGradient get inkGradient =>
      LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: inkGradientColors);

  LinearGradient toneGradient(Color c) => LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color.lerp(c, Colors.white, isDark ? 0.08 : 0.1)!, Color.lerp(c, Colors.black, isDark ? 0.12 : 0.18)!],
  );

  LinearGradient get champagne => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: isDark
        ? const [Color(0xFFF2DCAE), Color(0xFFD9B97F), Color(0xFFAE8A52)]
        : const [Color(0xFFE6CB93), Color(0xFFC29C5E), Color(0xFF94713A)],
  );

  /// Shadow of a surface that floats above the page.
  List<BoxShadow> get float => isDark
      ? const [
          BoxShadow(color: Color(0xA6000000), blurRadius: 60, offset: Offset(0, 30), spreadRadius: -12),
          BoxShadow(color: Color(0x40000000), blurRadius: 8, offset: Offset(0, 2)),
        ]
      : const [
          BoxShadow(color: Color(0x33201608), blurRadius: 60, offset: Offset(0, 30), spreadRadius: -16),
          BoxShadow(color: Color(0x14201608), blurRadius: 10, offset: Offset(0, 3)),
        ];

  /// Soft glow around a focused well.
  List<BoxShadow> focusGlow(Color c) => [
    BoxShadow(color: c.withValues(alpha: isDark ? 0.22 : 0.18), blurRadius: 18, spreadRadius: -2),
  ];

  static const light = VaultPalette._(
    isDark: false,
    surface: Color(0xFFFFFDF9),
    surfaceRaised: Color(0xFFFFFFFF),
    well: Color(0xFFF4F0E9),
    wellFocus: Color(0xFFFFFFFF),
    hairline: Color(0xFFEBE4D8),
    hairlineStrong: Color(0xFFD8CEBE),
    highlight: Color(0xFFFFFFFF),
    ink: Color(0xFF14120F),
    inkSoft: Color(0xFF574F43),
    inkMute: Color(0xFF766C5E),
    inkFaint: Color(0xFFB9AE9D),
    onInk: Color(0xFFFBF8F2),
    accent: Color(0xFFB98F4E),
    accentInk: Color(0xFF85612A),
    positive: Color(0xFF22684A),
    negative: Color(0xFFA6362F),
    warning: Color(0xFF94600F),
    info: Color(0xFF34548A),
    scrim: Color(0x80120E09),
    inkGradientColors: [Color(0xFF2B2722), Color(0xFF0E0D0B)],
    toast: Color(0xFF151412),
    onToast: Color(0xFFF7F2E9),
    onToastSoft: Color(0xFFB8AE9E),
  );

  static const dark = VaultPalette._(
    isDark: true,
    surface: Color(0xFF131315),
    surfaceRaised: Color(0xFF1A1A1D),
    well: Color(0xFF1D1D21),
    wellFocus: Color(0xFF222227),
    hairline: Color(0xFF29292E),
    hairlineStrong: Color(0xFF3A3A41),
    highlight: Color(0x1FFFFFFF),
    ink: Color(0xFFF5F1EA),
    inkSoft: Color(0xFFBDB6AB),
    inkMute: Color(0xFF9B9488),
    inkFaint: Color(0xFF55524D),
    onInk: Color(0xFF121212),
    accent: Color(0xFFD9B97F),
    accentInk: Color(0xFFE3C691),
    positive: Color(0xFF7CCBA3),
    negative: Color(0xFFEE8F85),
    warning: Color(0xFFE8B862),
    info: Color(0xFF98B6E5),
    scrim: Color(0x99000000),
    inkGradientColors: [Color(0xFFFAF6EE), Color(0xFFE2D9C9)],
    toast: Color(0xFF1E1E21),
    onToast: Color(0xFFF7F2E9),
    onToastSoft: Color(0xFFADA595),
  );
}

/// Vault type. Instrument Serif carries the titles and the hero figure;
/// Manrope (variable) everything else. Figures are tabular so values never
/// jitter while they are typed or counted.
@immutable
class VaultType {
  VaultType._(VaultPalette p)
    : hero = _serif(58, p.ink, h: 1.0, ls: -1.6),
      title = _serif(30, p.ink, h: 1.05, ls: -0.5),
      dialogTitle = _serif(28, p.ink, h: 1.08, ls: -0.4),
      figure = _serif(26, p.ink, h: 1.05, ls: -0.3),
      heading = _sans(15.5, 680, p.ink, h: 1.3, ls: -0.15),
      input = _sans(16, 600, p.ink, h: 1.35, ls: -0.1),
      body = _sans(14.5, 500, p.ink, h: 1.5),
      bodySoft = _sans(14, 500, p.inkSoft, h: 1.5),
      label = _sans(12.5, 640, p.inkSoft, h: 1.25, ls: 0.05),
      caption = _sans(12.5, 520, p.inkSoft, h: 1.45),
      eyebrow = _sans(10.5, 760, p.inkMute, h: 1.2, ls: 1.8),
      number = _sans(15, 680, p.ink, h: 1.2, ls: -0.2, tabular: true),
      button = _sans(15, 680, p.ink, h: 1.2, ls: 0.1),
      chip = _sans(13.5, 620, p.ink, h: 1.2);

  static const serif = 'InstrumentSerif';
  static const sans = 'Manrope';

  static TextStyle _serif(double size, Color color, {double? h, double? ls}) => TextStyle(
    fontFamily: serif,
    fontFamilyFallback: const [sans],
    fontSize: size,
    fontWeight: FontWeight.w400,
    height: h,
    letterSpacing: ls,
    color: color,
    fontFeatures: const [FontFeature.liningFigures(), FontFeature.tabularFigures()],
  );

  static TextStyle _sans(double size, double weight, Color color, {double? h, double? ls, bool tabular = false}) =>
      TextStyle(
        fontFamily: sans,
        fontSize: size,
        fontWeight: _weight(weight),
        fontVariations: [FontVariation('wght', weight)],
        height: h,
        letterSpacing: ls,
        color: color,
        fontFeatures: tabular ? const [FontFeature.tabularFigures(), FontFeature.liningFigures()] : null,
      );

  static FontWeight _weight(double w) => FontWeight.values[((w / 100).round() - 1).clamp(0, 8)];

  /// Re-weights a Manrope style, keeping the variation axis in sync.
  static TextStyle weight(TextStyle s, double w) =>
      s.copyWith(fontWeight: _weight(w), fontVariations: [FontVariation('wght', w)]);

  final TextStyle hero;
  final TextStyle title;
  final TextStyle dialogTitle;
  final TextStyle figure;
  final TextStyle heading;
  final TextStyle input;
  final TextStyle body;
  final TextStyle bodySoft;
  final TextStyle label;
  final TextStyle caption;
  final TextStyle eyebrow;
  final TextStyle number;
  final TextStyle button;
  final TextStyle chip;

  static final light = VaultType._(VaultPalette.light);
  static final dark = VaultType._(VaultPalette.dark);
}

/// Geometry. 4-pt grid; continuous, generous corners.
abstract final class VaultShape {
  /// Floating sheet / dialog corner.
  static const double sheet = 34;
  static const double dialog = 32;
  static const double well = 18;
  static const double group = 22;
  static const double control = 999;

  /// Gap between a floating surface and the screen edges.
  static const double float = 10;
  static const double gutter = 22;
  static const double maxWidth = 560;
}

/// Motion vocabulary. Springs for arrivals (they land, they do not stop),
/// quick accelerating exits, and nothing that loops forever except a
/// loader that is genuinely waiting.
abstract final class VaultMotion {
  static const sheetIn = Duration(milliseconds: 680);
  static const sheetOut = Duration(milliseconds: 260);
  static const dialogIn = Duration(milliseconds: 560);
  static const dialogOut = Duration(milliseconds: 200);
  static const state = Duration(milliseconds: 320);
  static const quick = Duration(milliseconds: 180);
  static const stagger = Duration(milliseconds: 55);

  /// A soft spring: lands with a ~3% overshoot.
  static const Curve spring = SpringCurve(damping: 0.78, stiffness: 10.5);

  /// A livelier spring for small things (chips, check marks, capsules).
  static const Curve pop = SpringCurve(damping: 0.62, stiffness: 12);

  /// Departures.
  static const Curve exit = Cubic(0.5, 0, 0.9, 0.4);

  /// Content settling inside a component (GSAP "power3.out").
  static const Curve settle = Cubic(0.215, 0.61, 0.355, 1);
}

/// A critically-under-damped spring expressed as a [Curve] so it composes
/// with Flutter's implicit and route animations. Lands exactly on 1.
class SpringCurve extends Curve {
  const SpringCurve({this.damping = 0.75, this.stiffness = 11});

  /// Damping ratio (0 < ζ < 1 overshoots; closer to 1 is calmer).
  final double damping;

  /// Natural frequency over the unit interval.
  final double stiffness;

  @override
  double transformInternal(double t) {
    final w = stiffness;
    final z = damping;
    final wd = w * math.sqrt(1 - z * z);
    final decay = math.exp(-z * w * t);
    final v = 1 - decay * (math.cos(wd * t) + (z * w / wd) * math.sin(wd * t));
    // Fold the residual at t = 1 so the curve lands exactly on 1.
    final end = 1 - math.exp(-z * w) * (math.cos(wd) + (z * w / wd) * math.sin(wd));
    return v / end;
  }
}

/// Provides the Vault palette to a modal subtree. Legacy components (fields,
/// buttons, chips, banners) look this up to render their Vault form.
class VaultScope extends InheritedWidget {
  const VaultScope({super.key, required this.palette, required super.child});

  final VaultPalette palette;

  static VaultScope? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<VaultScope>();

  /// True inside a Vault sheet or dialog.
  static bool isActive(BuildContext context) => maybeOf(context) != null;

  @override
  bool updateShouldNotify(VaultScope oldWidget) => oldWidget.palette != palette;
}

extension VaultX on BuildContext {
  VaultPalette get vault =>
      VaultScope.maybeOf(this)?.palette ??
      (Theme.of(this).brightness == Brightness.dark ? VaultPalette.dark : VaultPalette.light);

  VaultType get vt => vault.isDark ? VaultType.dark : VaultType.light;
}

extension VaultTextX on TextStyle {
  TextStyle vw(double weight) => VaultType.weight(this, weight);
  TextStyle vc(Color color) => copyWith(color: color);
}
