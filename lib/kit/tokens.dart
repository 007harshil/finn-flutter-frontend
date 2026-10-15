import 'package:flutter/material.dart';

/// FiNN "calm ledger" design tokens.
///
/// Paper-toned page, white panels, ink text and a single green. Colour is
/// reserved for meaning: green = money in / progress, red = over or
/// overdue, amber = getting close. Everything else is ink.
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
    required this.green,
    required this.greenSoft,
    required this.red,
    required this.redSoft,
    required this.amber,
    required this.amberSoft,
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

  /// Primary text, expense amounts, primary buttons, selected chips.
  final Color ink;

  /// Secondary text (meets 4.5:1 on paper and surface).
  final Color inkSoft;

  /// Placeholder icons and disabled text only, never for information.
  final Color inkFaint;

  /// Text on [ink] fills.
  final Color onInk;

  /// Money in, progress, healthy.
  final Color green;
  final Color greenSoft;

  /// Over the limit, overdue, overspent.
  final Color red;
  final Color redSoft;

  /// Close to a limit, behind a plan.
  final Color amber;
  final Color amberSoft;

  /// Barrier behind sheets, dialogs and overlays.
  final Color scrim;

  static const light = LedgerColors._(
    isDark: false,
    paper: Color(0xFFF4F4F0),
    surface: Color(0xFFFFFFFF),
    sunken: Color(0xFFEBEBE6),
    line: Color(0xFFE3E2DC),
    lineStrong: Color(0xFFCFCEC7),
    ink: Color(0xFF17191C),
    inkSoft: Color(0xFF5B6068),
    inkFaint: Color(0xFF94979D),
    onInk: Color(0xFFFFFFFF),
    green: Color(0xFF1B6847),
    greenSoft: Color(0xFFE3EFE8),
    red: Color(0xFFB3261E),
    redSoft: Color(0xFFF8E6E4),
    amber: Color(0xFF8F5300),
    amberSoft: Color(0xFFF6EBDA),
    scrim: Color(0x6617191C),
  );

  static const dark = LedgerColors._(
    isDark: true,
    paper: Color(0xFF111213),
    surface: Color(0xFF1A1B1D),
    sunken: Color(0xFF26272A),
    line: Color(0xFF2C2D31),
    lineStrong: Color(0xFF3D3F44),
    ink: Color(0xFFEDECE8),
    inkSoft: Color(0xFFA5A8AE),
    inkFaint: Color(0xFF6F7279),
    onInk: Color(0xFF111213),
    green: Color(0xFF6CC196),
    greenSoft: Color(0xFF1B2D24),
    red: Color(0xFFF2836F),
    redSoft: Color(0xFF3A1F1B),
    amber: Color(0xFFE2A954),
    amberSoft: Color(0xFF33281A),
    scrim: Color(0x99000000),
  );

  static LedgerColors of(BuildContext context) => Theme.of(context).brightness == Brightness.dark ? dark : light;
}

/// One family (Atkinson Hyperlegible Next), sentence case everywhere,
/// tabular figures for money so columns line up.
@immutable
class LedgerType {
  LedgerType._(LedgerColors c)
      : figureXL = _s(40, 640, c.ink, h: 1.05, ls: -1.2, figures: true),
        figureL = _s(28, 620, c.ink, h: 1.1, ls: -0.6, figures: true),
        figure = _s(16, 600, c.ink, h: 1.25, figures: true),
        figureSmall = _s(14, 500, c.inkSoft, h: 1.3, figures: true),
        title = _s(26, 700, c.ink, h: 1.15, ls: -0.5),
        heading = _s(18, 650, c.ink, h: 1.25, ls: -0.2),
        body = _s(16, 420, c.ink, h: 1.4),
        bodyStrong = _s(16, 600, c.ink, h: 1.3),
        label = _s(14, 500, c.inkSoft, h: 1.35),
        labelStrong = _s(14, 600, c.ink, h: 1.3),
        small = _s(13, 500, c.inkSoft, h: 1.3),
        button = _s(15, 600, c.ink, h: 1.2);

  static const family = 'Atkinson';

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
  static const double section = 36;

  /// Widest the content column grows on tablets.
  static const double maxWidth = 560;
}

abstract final class Rad {
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const BorderRadius rSm = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius rMd = BorderRadius.all(Radius.circular(md));
  static const BorderRadius rLg = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius pill = BorderRadius.all(Radius.circular(999));
}

extension LedgerContext on BuildContext {
  LedgerColors get ink => LedgerColors.of(this);
  LedgerType get type => LedgerType.of(this);
}
