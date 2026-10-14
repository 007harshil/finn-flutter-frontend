import 'package:flutter/material.dart';

/// "Luxe": the quiet-luxury visual language of the money screens (Home,
/// Activity, Budgets, Goals).
///
/// Principles: warm paper and obsidian instead of blue-grey; one champagne
/// accent used sparingly; serif figures for the numbers that matter, a
/// precise sans for everything else; hairlines instead of boxes; motion that
/// explains cause and effect and always comes to rest.
///
/// Read through `context.luxe` (colours) and `context.lt` (type).
@immutable
class LuxePalette {
  const LuxePalette._({
    required this.isDark,
    required this.canvas,
    required this.canvasDeep,
    required this.paper,
    required this.paperRaised,
    required this.sunk,
    required this.line,
    required this.lineStrong,
    required this.ink,
    required this.inkSoft,
    required this.inkMute,
    required this.gold,
    required this.goldInk,
    required this.goldSoft,
    required this.positive,
    required this.negative,
    required this.warning,
    required this.info,
    required this.obsidian,
    required this.obsidianEdge,
    required this.onObsidian,
    required this.onObsidianSoft,
    required this.auroraA,
    required this.auroraB,
    required this.scrim,
    required this.shimmer,
  });

  final bool isDark;

  /// Page background and its slightly deeper lower edge.
  final Color canvas;
  final Color canvasDeep;

  /// Cards and sheets.
  final Color paper;

  /// Popovers and pressed surfaces.
  final Color paperRaised;

  /// Tracks, wells, inputs.
  final Color sunk;
  final Color line;
  final Color lineStrong;

  /// Text: primary, secondary (≥ 4.5:1), tertiary (≥ 4.5:1 on canvas).
  final Color ink;
  final Color inkSoft;
  final Color inkMute;

  /// Champagne accent; [goldInk] is the text-safe variant.
  final Color gold;
  final Color goldInk;
  final Color goldSoft;

  /// Financial meaning (always paired with a sign, icon or word).
  final Color positive;
  final Color negative;
  final Color warning;
  final Color info;

  /// The hero "card" surface: near-black in both themes.
  final Color obsidian;
  final Color obsidianEdge;
  final Color onObsidian;
  final Color onObsidianSoft;

  /// Soft light pooled behind the page.
  final Color auroraA;
  final Color auroraB;
  final Color scrim;
  final Color shimmer;

  Color tint(Color c, [double alpha = 0.12]) => c.withValues(alpha: isDark ? alpha * 1.6 : alpha);

  /// Quietens a saturated category/goal colour so it sits in the palette.
  Color mute(Color c) => Color.lerp(c, isDark ? ink : const Color(0xFF6F6658), isDark ? 0.18 : 0.28)!;

  LinearGradient get obsidianGradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: isDark
        ? const [Color(0xFF221F1B), Color(0xFF141311), Color(0xFF0E0D0C)]
        : const [Color(0xFF2A2621), Color(0xFF171512), Color(0xFF0F0E0C)],
    stops: const [0, 0.55, 1],
  );

  LinearGradient get goldGradient => LinearGradient(
    colors: isDark
        ? const [Color(0xFFF1D9A6), Color(0xFFD7B67A), Color(0xFFB08A4E)]
        : const [Color(0xFFE9CF98), Color(0xFFC9A465), Color(0xFF9C7840)],
  );

  List<BoxShadow> get lift => isDark
      ? const [BoxShadow(color: Color(0x66000000), blurRadius: 24, offset: Offset(0, 12), spreadRadius: -10)]
      : const [
          BoxShadow(color: Color(0x14261D10), blurRadius: 30, offset: Offset(0, 16), spreadRadius: -14),
          BoxShadow(color: Color(0x0A261D10), blurRadius: 3, offset: Offset(0, 1)),
        ];

  List<BoxShadow> get heroShadow => isDark
      ? const [BoxShadow(color: Color(0x99000000), blurRadius: 40, offset: Offset(0, 24), spreadRadius: -16)]
      : const [
          BoxShadow(color: Color(0x401E160A), blurRadius: 44, offset: Offset(0, 26), spreadRadius: -18),
          BoxShadow(color: Color(0x1A1E160A), blurRadius: 6, offset: Offset(0, 2)),
        ];

  static const light = LuxePalette._(
    isDark: false,
    canvas: Color(0xFFF5F2EC),
    canvasDeep: Color(0xFFEEE9E0),
    paper: Color(0xFFFCFBF8),
    paperRaised: Color(0xFFFFFFFF),
    sunk: Color(0xFFEAE5DB),
    line: Color(0xFFE3DDD2),
    lineStrong: Color(0xFFCFC6B7),
    ink: Color(0xFF15130F),
    inkSoft: Color(0xFF575045),
    inkMute: Color(0xFF746B5E),
    gold: Color(0xFFB8925A),
    goldInk: Color(0xFF85652F),
    goldSoft: Color(0xFFF1E7D4),
    positive: Color(0xFF2E6A4D),
    negative: Color(0xFFA23A33),
    warning: Color(0xFF9A6210),
    info: Color(0xFF3A5884),
    obsidian: Color(0xFF161412),
    obsidianEdge: Color(0x33D7B67A),
    onObsidian: Color(0xFFF6F1E7),
    onObsidianSoft: Color(0xFFBDB3A3),
    auroraA: Color(0xFFF2DFBC),
    auroraB: Color(0xFFDCE6DE),
    scrim: Color(0x8C0E0C0A),
    shimmer: Color(0xFFF7F3EC),
  );

  static const dark = LuxePalette._(
    isDark: true,
    canvas: Color(0xFF0B0B0C),
    canvasDeep: Color(0xFF070708),
    paper: Color(0xFF141416),
    paperRaised: Color(0xFF1B1B1E),
    sunk: Color(0xFF1E1E21),
    line: Color(0xFF26262A),
    lineStrong: Color(0xFF36363C),
    ink: Color(0xFFF3EFE7),
    inkSoft: Color(0xFFB7B1A7),
    inkMute: Color(0xFF948E84),
    gold: Color(0xFFD7B67A),
    goldInk: Color(0xFFDDBF88),
    goldSoft: Color(0xFF2A241A),
    positive: Color(0xFF7DC5A1),
    negative: Color(0xFFEA8C82),
    warning: Color(0xFFE5B45E),
    info: Color(0xFF94B3E2),
    obsidian: Color(0xFF181715),
    obsidianEdge: Color(0x40D7B67A),
    onObsidian: Color(0xFFF6F1E7),
    onObsidianSoft: Color(0xFFB0A797),
    auroraA: Color(0xFF2B2316),
    auroraB: Color(0xFF15211B),
    scrim: Color(0xB3000000),
    shimmer: Color(0xFF232326),
  );
}

/// Type scale. Serif (Instrument Serif) for hero figures and page titles;
/// Manrope for UI. Numbers use tabular lining figures so columns align and
/// counters never jitter.
@immutable
class LuxeType {
  LuxeType._(LuxePalette p)
    : display = _serif(46, p.ink, h: 1.0, ls: -1.2),
      headline = _serif(34, p.ink, h: 1.05, ls: -0.6),
      title = _serif(24, p.ink, h: 1.12, ls: -0.3),
      figure = _serif(28, p.ink, h: 1.05, ls: -0.4),
      heading = _sans(16, 650, p.ink, h: 1.3, ls: -0.15),
      body = _sans(14.5, 500, p.ink, h: 1.45),
      bodySoft = _sans(14, 500, p.inkSoft, h: 1.45),
      label = _sans(13, 600, p.ink, h: 1.3, ls: -0.05),
      caption = _sans(12.5, 500, p.inkSoft, h: 1.4),
      eyebrow = _sans(11, 700, p.inkMute, h: 1.2, ls: 1.6),
      micro = _sans(11, 600, p.inkMute, h: 1.25, ls: 0.1),
      number = _sans(15, 650, p.ink, h: 1.2, ls: -0.2, tabular: true),
      numberSmall = _sans(13, 650, p.ink, h: 1.2, ls: -0.1, tabular: true),
      button = _sans(14, 650, p.ink, h: 1.2, ls: 0.05);

  static const serifFamily = 'InstrumentSerif';
  static const sansFamily = 'Manrope';

  static const _tabular = [FontFeature.tabularFigures(), FontFeature.liningFigures()];

  static TextStyle _serif(double size, Color color, {double? h, double? ls}) => TextStyle(
    fontFamily: serifFamily,
    // The serif has no ₹ glyph; Manrope supplies it.
    fontFamilyFallback: const [sansFamily],
    fontSize: size,
    fontWeight: FontWeight.w400,
    height: h,
    letterSpacing: ls,
    color: color,
    fontFeatures: const [FontFeature.liningFigures()],
  );

  static TextStyle _sans(double size, double weight, Color color, {double? h, double? ls, bool tabular = false}) =>
      TextStyle(
        fontFamily: sansFamily,
        fontSize: size,
        fontWeight: _weight(weight),
        fontVariations: [FontVariation('wght', weight)],
        height: h,
        letterSpacing: ls,
        color: color,
        fontFeatures: tabular ? _tabular : null,
      );

  static FontWeight _weight(double w) => FontWeight.values[((w / 100).round() - 1).clamp(0, 8)];

  /// Re-weights a Manrope style (keeps the variation axis in sync).
  static TextStyle weight(TextStyle s, double w) =>
      s.copyWith(fontWeight: _weight(w), fontVariations: [FontVariation('wght', w)]);

  final TextStyle display;
  final TextStyle headline;
  final TextStyle title;
  final TextStyle figure;
  final TextStyle heading;
  final TextStyle body;
  final TextStyle bodySoft;
  final TextStyle label;
  final TextStyle caption;
  final TextStyle eyebrow;
  final TextStyle micro;
  final TextStyle number;
  final TextStyle numberSmall;
  final TextStyle button;

  static final light = LuxeType._(LuxePalette.light);
  static final dark = LuxeType._(LuxePalette.dark);
}

/// Spacing and shape. 4-pt grid; generous section rhythm.
abstract final class LuxeSpace {
  static const double gutter = 20;
  static const double section = 36;
  static const double card = 20;
  static const double rCard = 28;
  static const double rTile = 22;
  static const double rControl = 16;
}

extension LuxeX on BuildContext {
  LuxePalette get luxe => Theme.of(this).brightness == Brightness.dark ? LuxePalette.dark : LuxePalette.light;
  LuxeType get lt => Theme.of(this).brightness == Brightness.dark ? LuxeType.dark : LuxeType.light;
}

extension LuxeTextX on TextStyle {
  TextStyle w(double weight) => LuxeType.weight(this, weight);
  TextStyle c(Color color) => copyWith(color: color);
}
