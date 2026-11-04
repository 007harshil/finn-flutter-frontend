import 'package:flutter/material.dart';

import '../design_system/tokens/palette.dart';

export '../design_system/tokens/palette.dart' show CategoryTints;

/// FiNN "Current" design tokens.
///
/// A quiet shore-toned page, white panels, ink text and one deep teal
/// drawn from the logo. Colour is reserved for meaning: green = money in /
/// progress, red = over a limit you set, amber = getting close, teal = the
/// thing you can do next. Ordinary spending stays ink.
///
/// Raw values live in [Hue] so the Material theme (`FinnColors`) and these
/// tokens always match.
@immutable
class LedgerColors {
  const LedgerColors._({
    required this.isDark,
    required this.paper,
    required this.surface,
    required this.sunken,
    required this.line,
    required this.lineStrong,
    required this.ink,
    required this.inkSoft,
    required this.inkFaint,
    required this.onInk,
    required this.brand,
    required this.brandSoft,
    required this.onBrand,
    required this.deep,
    required this.deepEnd,
    required this.flow,
    required this.green,
    required this.greenSoft,
    required this.red,
    required this.redSoft,
    required this.amber,
    required this.amberSoft,
    required this.info,
    required this.infoSoft,
    required this.khata,
    required this.khataRule,
    required this.khataMargin,
    required this.marigold,
    required this.scrim,
  });

  final bool isDark;

  /// Page background.
  final Color paper;

  /// Panels and rows.
  final Color surface;

  /// Bar tracks, icon wells, pressed rows, skeletons.
  final Color sunken;

  /// Hairlines between rows and around panels.
  final Color line;

  /// Outlines of secondary buttons and unselected chips.
  final Color lineStrong;

  /// Primary text and expense amounts.
  final Color ink;

  /// Secondary text (meets 4.5:1 on paper and surface).
  final Color inkSoft;

  /// Placeholder icons and disabled text only, never for information.
  final Color inkFaint;

  /// Text on [ink] fills.
  final Color onInk;

  /// Deep teal: primary buttons, selected chips and tabs, links, focus.
  final Color brand;

  /// Soft teal wash behind selected or branded content.
  final Color brandSoft;

  /// Text and icons on [brand] fills.
  final Color onBrand;

  /// The hero slab ("Available to spend"): a deep teal gradient
  /// from [deep] to [deepEnd]. Text on it is white.
  final Color deep;
  final Color deepEnd;

  /// Bright teal accent that reads on [deep] (free money, highlights).
  final Color flow;

  /// Money in, progress, healthy.
  final Color green;
  final Color greenSoft;

  /// Over the limit, overspent.
  final Color red;
  final Color redSoft;

  /// Close to a limit, behind a plan.
  final Color amber;
  final Color amberSoft;

  /// Neutral information (tips, "how it's calculated").
  final Color info;
  final Color infoSoft;

  /// Bahi khata paper behind chart-led summaries: warm ground, ruled
  /// lines, a red margin line and marigold highlights.
  final Color khata;
  final Color khataRule;
  final Color khataMargin;
  final Color marigold;

  /// Barrier behind sheets, dialogs and overlays.
  final Color scrim;

  LinearGradient get deepGradient =>
      LinearGradient(colors: [deep, deepEnd], begin: Alignment.topLeft, end: Alignment.bottomRight);

  /// (icon colour, well colour) for a category or goal colour index.
  (Color, Color) tint(int colorIndex) => CategoryTints.of(colorIndex, dark: isDark);

  static const light = LedgerColors._(
    isDark: false,
    paper: Hue.shore,
    surface: Hue.panel,
    sunken: Hue.mist,
    line: Hue.hair,
    lineStrong: Hue.hairStrong,
    ink: Hue.ink,
    inkSoft: Hue.inkSoft,
    inkFaint: Hue.inkFaint,
    onInk: Hue.panel,
    brand: Hue.current,
    brandSoft: Hue.currentSoft,
    onBrand: Hue.panel,
    deep: Hue.deep,
    deepEnd: Hue.deepEnd,
    flow: Hue.flow,
    green: Hue.moneyIn,
    greenSoft: Hue.moneyInSoft,
    red: Hue.over,
    redSoft: Hue.overSoft,
    amber: Hue.near,
    amberSoft: Hue.nearSoft,
    info: Hue.info,
    infoSoft: Hue.infoSoft,
    khata: Hue.khata,
    khataRule: Hue.khataRule,
    khataMargin: Hue.khataMargin,
    marigold: Hue.marigold,
    scrim: Color(0x660F1F21),
  );

  static const dark = LedgerColors._(
    isDark: true,
    paper: Hue.night,
    surface: Hue.nightPanel,
    sunken: Hue.nightRaised,
    line: Hue.nightHair,
    lineStrong: Hue.nightHairStrong,
    ink: Hue.nightInk,
    inkSoft: Hue.nightInkSoft,
    inkFaint: Hue.nightInkFaint,
    onInk: Hue.night,
    brand: Hue.nightCurrent,
    brandSoft: Hue.nightCurrentSoft,
    onBrand: Hue.nightOnCurrent,
    deep: Hue.nightDeep,
    deepEnd: Hue.nightDeepEnd,
    flow: Hue.nightFlow,
    green: Hue.nightIn,
    greenSoft: Hue.nightInSoft,
    red: Hue.nightOver,
    redSoft: Hue.nightOverSoft,
    amber: Hue.nightNear,
    amberSoft: Hue.nightNearSoft,
    info: Hue.nightInfo,
    infoSoft: Hue.nightInfoSoft,
    khata: Hue.nightKhata,
    khataRule: Hue.nightKhataRule,
    khataMargin: Hue.nightKhataMargin,
    marigold: Hue.nightMarigold,
    scrim: Color(0x99000000),
  );

  static LedgerColors of(BuildContext context) => Theme.of(context).brightness == Brightness.dark ? dark : light;
}

/// One family (Manrope), sentence case everywhere, tabular figures for
/// money so columns line up. Manrope has the rupee sign, a plain zero that
/// never reads as Ø, and a tall x-height that stays legible at 13.
@immutable
class LedgerType {
  LedgerType._(LedgerColors c)
      : figureXL = _s(40, 760, c.ink, h: 1.05, ls: -1.4, figures: true),
        figureL = _s(28, 740, c.ink, h: 1.1, ls: -0.8, figures: true),
        figure = _s(16, 680, c.ink, h: 1.25, ls: -0.2, figures: true),
        figureSmall = _s(14, 560, c.inkSoft, h: 1.3, figures: true),
        title = _s(26, 760, c.ink, h: 1.15, ls: -0.7),
        heading = _s(18, 720, c.ink, h: 1.25, ls: -0.3),
        body = _s(16, 480, c.ink, h: 1.45),
        bodyStrong = _s(16, 650, c.ink, h: 1.3, ls: -0.1),
        label = _s(14, 520, c.inkSoft, h: 1.4),
        labelStrong = _s(14, 650, c.ink, h: 1.3),
        small = _s(13, 540, c.inkSoft, h: 1.3),
        button = _s(15, 680, c.ink, h: 1.2);

  static const family = 'Manrope';

  /// Hero money ("Available to spend").
  final TextStyle figureXL;

  /// Secondary hero money (detail screens).
  final TextStyle figureL;

  /// Row amounts.
  final TextStyle figure;

  /// Supporting amounts ("of ₹40,000").
  final TextStyle figureSmall;

  /// Page title.
  final TextStyle title;

  /// Section titles.
  final TextStyle heading;
  final TextStyle body;
  final TextStyle bodyStrong;

  /// Supporting text, row subtitles.
  final TextStyle label;
  final TextStyle labelStrong;

  /// Smallest text in the app; never below 13.
  final TextStyle small;
  final TextStyle button;

  static TextStyle _s(double size, int weight, Color color, {double? h, double ls = 0, bool figures = false}) =>
      TextStyle(
        fontFamily: family,
        fontSize: size,
        fontWeight: FontWeight.values[((weight / 100).round() - 1).clamp(0, 8)],
        // Variable font: drive the axis directly so in-between weights render.
        fontVariations: [FontVariation.weight(weight.toDouble())],
        height: h,
        letterSpacing: ls,
        color: color,
        fontFeatures: figures ? const [FontFeature.tabularFigures()] : null,
      );

  static final _light = LedgerType._(LedgerColors.light);
  static final _dark = LedgerType._(LedgerColors.dark);

  static LedgerType of(BuildContext context) => Theme.of(context).brightness == Brightness.dark ? _dark : _light;
}

/// 4-point spacing.
abstract final class Sp {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;

  /// Horizontal page margin.
  static const double gutter = 20;

  /// Space between page sections.
  static const double section = 32;

  /// Widest the content column grows on tablets.
  static const double maxWidth = 560;
}

abstract final class Rad {
  static const double sm = 8;
  static const double md = 14;
  static const double lg = 18;

  /// Hero slab and sheets.
  static const double xl = 24;
  static const BorderRadius rSm = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius rMd = BorderRadius.all(Radius.circular(md));
  static const BorderRadius rLg = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius rXl = BorderRadius.all(Radius.circular(xl));
  static const BorderRadius pill = BorderRadius.all(Radius.circular(999));
}

extension LedgerContext on BuildContext {
  LedgerColors get ink => LedgerColors.of(this);
  LedgerType get type => LedgerType.of(this);
}
