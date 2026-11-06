import 'package:flutter/material.dart';

import '../design_system/tokens/palette.dart';

export '../design_system/tokens/palette.dart' show CategoryTints;

/// FiNN "Bahi" design tokens.
///
/// After the bahi-khata ledger: a cool page, white panels, indigo ink,
/// marigold highlights and warm ruled khata paper with a red margin line.
/// Colour is reserved for meaning: green = money in / progress, red = over
/// a limit you set, amber = getting close, indigo = the thing you can do
/// next. Charts use the Monsoon hues ([rain], [jade], [saffron], [rose],
/// [lilac]), one hue per meaning.
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
    required this.marigoldInk,
    required this.marigoldSoft,
    required this.edge,
    required this.onDeepSoft,
    required this.heroFigure,
    required this.rain,
    required this.jade,
    required this.saffron,
    required this.rose,
    required this.lilac,
    required this.chart,
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

  /// Indigo (marigold in dark): primary buttons, selected tabs, links, focus.
  final Color brand;

  /// Soft wash behind selected or branded content.
  final Color brandSoft;

  /// Text and icons on [brand] fills.
  final Color onBrand;

  /// The hero slab ("Available to spend"): deep indigo from [deep] to
  /// [deepEnd]. Text on it is white, the hero figure is [heroFigure].
  final Color deep;
  final Color deepEnd;

  /// Marigold accent that reads on [deep] (free money, highlights).
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

  /// Text on [marigoldSoft] (selected chips, tags, owed-to-you rows).
  final Color marigoldInk;
  final Color marigoldSoft;

  /// The pressable edge drawn under primary buttons and the Add key.
  final Color edge;

  /// Secondary text on the [deep] hero slab.
  final Color onDeepSoft;

  /// Marigold hero figure on the [deep] slab.
  final Color heroFigure;

  /// Monsoon data hues: rain = this period / primary series, jade = in /
  /// saved, saffron = plan / pace, rose = spent over, lilac = fixed costs.
  final Color rain;
  final Color jade;
  final Color saffron;
  final Color rose;
  final Color lilac;

  /// Ordered categorical chart series.
  final List<Color> chart;

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
    marigoldInk: Hue.marigoldInk,
    marigoldSoft: Hue.marigoldSoft,
    edge: Hue.edge,
    onDeepSoft: Hue.onDeepSoft,
    heroFigure: Hue.heroFigure,
    rain: Hue.rain,
    jade: Hue.jade,
    saffron: Hue.saffron,
    rose: Hue.rose,
    lilac: Hue.lilac,
    chart: Hue.chartLight,
    scrim: Color(0x66191B3F),
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
    marigoldInk: Hue.nightMarigoldInk,
    marigoldSoft: Hue.nightMarigoldSoft,
    edge: Hue.nightEdge,
    onDeepSoft: Hue.nightOnDeepSoft,
    heroFigure: Hue.heroFigure,
    rain: Hue.nightRain,
    jade: Hue.nightJade,
    saffron: Hue.nightSaffron,
    rose: Hue.nightRose,
    lilac: Hue.nightLilac,
    chart: Hue.chartDark,
    scrim: Color(0x99000000),
  );

  static LedgerColors of(BuildContext context) => Theme.of(context).brightness == Brightness.dark ? dark : light;
}

/// Anek Latin (Ek Type, India), one variable family: condensed width for
/// big figures, wide for headings, sentence case everywhere and tabular
/// figures for money so columns line up. Anek Devanagari covers the
/// Hinglish assistant; Manrope fills symbols Anek lacks (→).
@immutable
class LedgerType {
  LedgerType._(LedgerColors c)
      : figureXL = _s(54, 700, c.ink, h: 0.98, ls: -0.4, figures: true, w: 78),
        figureL = _s(32, 700, c.ink, h: 1.0, ls: -0.3, figures: true, w: 82),
        figure = _s(17, 620, c.ink, h: 1.2, figures: true, w: 92),
        figureSmall = _s(14, 560, c.inkSoft, h: 1.3, figures: true, w: 95),
        title = _s(26, 650, c.ink, h: 1.1, ls: -0.2, w: 112),
        heading = _s(18, 650, c.ink, h: 1.2, ls: -0.1, w: 108),
        body = _s(16, 450, c.ink, h: 1.4),
        bodyStrong = _s(16, 600, c.ink, h: 1.3),
        label = _s(14, 500, c.inkSoft, h: 1.35),
        labelStrong = _s(14, 620, c.ink, h: 1.3),
        small = _s(13, 550, c.inkSoft, h: 1.3),
        button = _s(16, 650, c.ink, h: 1.2, w: 104);

  static const family = 'AnekLatin';
  static const fallback = ['AnekDevanagari', 'Manrope'];

  /// Hero money ("Available to spend"), condensed.
  final TextStyle figureXL;

  /// Secondary hero money (detail screens).
  final TextStyle figureL;

  /// Row amounts.
  final TextStyle figure;

  /// Supporting amounts ("of ₹40,000").
  final TextStyle figureSmall;

  /// Page title, wide.
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

  static TextStyle _s(double size, int weight, Color color,
          {double? h, double ls = 0, bool figures = false, double w = 100}) =>
      TextStyle(
        fontFamily: family,
        fontFamilyFallback: fallback,
        fontSize: size,
        fontWeight: FontWeight.values[((weight / 100).round() - 1).clamp(0, 8)],
        // Variable font: drive the axes directly so in-between weights and
        // widths render.
        fontVariations: [FontVariation.weight(weight.toDouble()), FontVariation.width(w)],
        height: h,
        letterSpacing: ls,
        color: color,
        fontFeatures: figures ? const [FontFeature.tabularFigures()] : null,
      );

  static final _light = LedgerType._(LedgerColors.light);
  static final _dark = LedgerType._(LedgerColors.dark);

  static LedgerType of(BuildContext context) => Theme.of(context).brightness == Brightness.dark ? _dark : _light;
}

/// Anek width axis helpers: `style.condensed()` for big figures,
/// `style.wide()` for display headings. Keeps the weight axis.
extension AnekWidth on TextStyle {
  TextStyle withWidth(double w) {
    final weight = fontVariations?.where((v) => v.axis == 'wght').firstOrNull;
    return copyWith(fontVariations: [?weight, FontVariation.width(w)]);
  }

  TextStyle condensed([double w = 80]) => withWidth(w);
  TextStyle wide([double w = 112]) => withWidth(w);
}

/// 4-point spacing, sized for phones: tight enough that a screen shows
/// real content above the fold, never below the 8 px touch gap.
abstract final class Sp {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 10;
  static const double lg = 12;
  static const double xl = 16;
  static const double xxl = 24;

  /// Horizontal page margin.
  static const double gutter = 16;

  /// Space between page sections.
  static const double section = 20;

  /// Widest the content column grows on tablets.
  static const double maxWidth = 560;
}

/// Bahi ledger geometry, shared by [LedgerRow], panel dividers, khata month
/// headers and the red margin line so they can never drift apart.
abstract final class Khata {
  /// Row inset from the panel edge.
  static const double inset = Sp.lg;

  /// The icon column (an `IconWell`/`CategoryMark` at its default size).
  static const double lead = 40;

  /// Space between the icon column and the row text.
  static const double gap = Sp.lg;

  /// Where row text starts; dividers and headers align here.
  static const double textX = inset + lead + gap;

  /// Left stroke of the red double margin line, centred in [gap]
  /// (two 1.2 px strokes, 3 px apart).
  static const double margin = inset + lead + gap / 2 - 2.1;
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

  /// Bahi shapes: buttons 12, chips 8, icon tiles 10, pressable edge 3.
  static const double btn = 12;
  static const double chip = 8;
  static const double tile = 10;
  static const double edge = 3;
  static const BorderRadius rBtn = BorderRadius.all(Radius.circular(btn));
  static const BorderRadius rChip = BorderRadius.all(Radius.circular(chip));
  static const BorderRadius rTile = BorderRadius.all(Radius.circular(tile));
}

extension LedgerContext on BuildContext {
  LedgerColors get ink => LedgerColors.of(this);
  LedgerType get type => LedgerType.of(this);
}
