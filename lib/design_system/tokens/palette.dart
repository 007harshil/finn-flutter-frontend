import 'package:flutter/painting.dart';

/// Raw colour values. Widgets must not use these directly: use the semantic
/// tokens in `FinnColors` (via `context.colors`) so light/dark stay coherent.
abstract final class Palette {
  // Midnight navy foundation.
  static const navy950 = Color(0xFF020817);
  static const navy925 = Color(0xFF060E1F);
  static const navy900 = Color(0xFF0B1426);
  static const navy850 = Color(0xFF0F172A);
  static const navy800 = Color(0xFF16213A);
  static const navy700 = Color(0xFF1E293B);
  static const navy600 = Color(0xFF334155);
  static const navy500 = Color(0xFF475569);

  // Slate neutrals.
  static const slate400 = Color(0xFF94A3B8);
  static const slate500 = Color(0xFF64748B);
  static const slate300 = Color(0xFFCBD5E1);
  static const slate200 = Color(0xFFE2E8F0);
  static const slate100 = Color(0xFFF1F5F9);
  static const slate50 = Color(0xFFF8FAFC);
  static const white = Color(0xFFFFFFFF);

  // Emerald: positive financial progress.
  static const emerald300 = Color(0xFF6EE7B7);
  static const emerald400 = Color(0xFF34D399);
  static const emerald500 = Color(0xFF10B981);
  static const emerald600 = Color(0xFF059669);
  static const emerald700 = Color(0xFF047857);
  static const emerald900 = Color(0xFF064E3B);
  static const teal800 = Color(0xFF115E59);

  // Sunset orange: attention and key actions (used sparingly).
  static const orange300 = Color(0xFFFDBA74);
  static const orange400 = Color(0xFFFB923C);
  static const orange500 = Color(0xFFF97316);
  static const orange600 = Color(0xFFEA580C);
  static const orange700 = Color(0xFFC2410C);

  // Rose: outflows and critical states.
  static const rose300 = Color(0xFFFDA4AF);
  static const rose400 = Color(0xFFFB7185);
  static const rose500 = Color(0xFFF43F5E);
  static const rose600 = Color(0xFFE11D48);
  static const rose700 = Color(0xFFBE123C);

  // Amber: warnings.
  static const amber300 = Color(0xFFFCD34D);
  static const amber400 = Color(0xFFFBBF24);
  static const amber500 = Color(0xFFF59E0B);
  static const amber600 = Color(0xFFD97706);
  static const amber700 = Color(0xFFB45309);

  // Supporting module accents (from the FiNN design reference).
  static const blue400 = Color(0xFF60A5FA);
  static const blue500 = Color(0xFF3B82F6);
  static const blue600 = Color(0xFF2563EB);
  static const indigo400 = Color(0xFF818CF8);
  static const indigo500 = Color(0xFF6366F1);
  static const indigo600 = Color(0xFF4F46E5);
  static const violet400 = Color(0xFFA78BFA);
  static const violet500 = Color(0xFF8B5CF6);
  static const violet600 = Color(0xFF7C3AED);
  static const pink400 = Color(0xFFF472B6);
  static const pink500 = Color(0xFFEC4899);
  static const pink600 = Color(0xFFDB2777);
  static const sky500 = Color(0xFF0EA5E9);
  static const cyan500 = Color(0xFF06B6D4);
  static const lime500 = Color(0xFF84CC16);
  static const yellow300 = Color(0xFFFDE047);
}

/// The FiNN "Bahi" palette: the raw values behind both the kit tokens
/// (`LedgerColors`) and the Material theme (`FinnColors`), so the two can
/// never drift apart. After the bahi-khata ledger: indigo ink, marigold
/// highlights, warm ruled paper and a red margin line. Charts use the
/// "Monsoon" hues (one hue per meaning), deepened for light grounds.
/// Every text pair is at least 4.5:1 on its ground.
abstract final class Hue {
  // Light: cool page, white panels, indigo ink, marigold highlights.
  static const shore = Color(0xFFF7F7FA);
  static const shoreBackdrop = Color(0xFFE9EAF3);
  static const panel = Color(0xFFFFFFFF);
  static const mist = Color(0xFFECEEF6);
  static const hair = Color(0xFFDEE1EE);
  static const hairStrong = Color(0xFFC7CBE0);
  static const ink = Color(0xFF191B3F);
  static const inkSoft = Color(0xFF50547A);
  static const inkFaint = Color(0xFF8A8DAE);
  static const current = Color(0xFF2C3192); // indigo: primary fills, links
  static const currentSoft = Color(0xFFE7E8F8);
  static const edge = Color(0xFF1B1F66); // pressable edge under primary
  static const deep = Color(0xFF23286F); // hero slab
  static const deepEnd = Color(0xFF1B1F66);
  static const onDeepSoft = Color(0xFFC5C8F0);
  static const heroFigure = Color(0xFFFFC24B);
  static const flow = Color(0xFFFFC24B); // highlight that reads on the slab
  static const moneyIn = Color(0xFF11734A);
  static const moneyInSoft = Color(0xFFE0F2E8);
  static const near = Color(0xFF9A5500);
  static const nearSoft = Color(0xFFFCEFD6);
  static const over = Color(0xFFBE2A2F);
  static const overSoft = Color(0xFFFBE6E6);
  static const info = Color(0xFF1F6BCB);
  static const infoSoft = Color(0xFFE3EDFA);

  // Dark: night indigo, marigold becomes the primary fill.
  static const night = Color(0xFF0F1029);
  static const nightBackdrop = Color(0xFF0A0B1E);
  static const nightPanel = Color(0xFF181A3A);
  static const nightRaised = Color(0xFF20234A);
  static const nightHair = Color(0xFF2C2F5A);
  static const nightHairStrong = Color(0xFF3D4170);
  static const nightInk = Color(0xFFEDEDF8);
  static const nightInkSoft = Color(0xFFA9ACCF);
  static const nightInkFaint = Color(0xFF6F7299);
  static const nightCurrent = Color(0xFFFFC24B);
  static const nightCurrentSoft = Color(0xFF3A2E12);
  static const nightOnCurrent = Color(0xFF1A1300);
  static const nightEdge = Color(0xFFC98A12);
  static const nightDeep = Color(0xFF1D2063);
  static const nightDeepEnd = Color(0xFF161850);
  static const nightOnDeepSoft = Color(0xFFC5C8F0);
  static const nightFlow = Color(0xFFFFC24B);
  static const nightIn = Color(0xFF63C995);
  static const nightInSoft = Color(0xFF15302A);
  static const nightNear = Color(0xFFF0B45A);
  static const nightNearSoft = Color(0xFF33291A);
  static const nightOver = Color(0xFFFF8A80);
  static const nightOverSoft = Color(0xFF3A1F2A);
  static const nightInfo = Color(0xFF6DB3FF);
  static const nightInfoSoft = Color(0xFF16254A);

  // Bahi khata: warm ruled paper with a red margin line and marigold ink.
  static const khata = Color(0xFFFFF7E0);
  static const khataRule = Color(0xFFF0DFAF);
  static const khataMargin = Color(0xD9BE2A2F);
  static const marigold = Color(0xFFF4A51C);
  static const marigoldInk = Color(0xFF6E4300);
  static const marigoldSoft = Color(0xFFFFEBC2);
  static const nightKhata = Color(0xFF211E33);
  static const nightKhataRule = Color(0xFF3A3550);
  static const nightKhataMargin = Color(0xB3FF8A80);
  static const nightMarigold = Color(0xFFFFC24B);
  static const nightMarigoldInk = Color(0xFFFFD98A);
  static const nightMarigoldSoft = Color(0xFF3A2E12);

  // Monsoon data hues: light deepened to pass 4.5:1 on white.
  static const rain = Color(0xFF1F6BCB);
  static const jade = Color(0xFF0A7A57);
  static const saffron = Color(0xFFA86400);
  static const rose = Color(0xFFC2335A);
  static const lilac = Color(0xFF6847D6);
  static const nightRain = Color(0xFF6DB3FF);
  static const nightJade = Color(0xFF45D4A4);
  static const nightSaffron = Color(0xFFFFB547);
  static const nightRose = Color(0xFFFF7D9C);
  static const nightLilac = Color(0xFFB7A2FF);

  /// Chart hues, one per meaning (light / dark).
  static const chartLight = [
    rain,
    lilac,
    jade,
    saffron,
    rose,
    Color(0xFF0F7F9E),
    Color(0xFF9A3FA8),
    Color(0xFF6B7090),
  ];
  static const chartDark = [
    nightRain,
    nightLilac,
    nightJade,
    nightSaffron,
    nightRose,
    Color(0xFF7FD3EE),
    Color(0xFFE596D6),
    Color(0xFFB0B3D0),
  ];
}

/// Category tints for icon wells: a deep hue on a soft wash in light mode,
/// a bright hue on a dim wash in dark mode. Index-aligned with
/// [AccentSwatches] (blue, purple, green, yellow, red, indigo, gray, lime,
/// fuchsia, sky, amber, emerald, rose, violet).
abstract final class CategoryTints {
  static const _lightFg = [
    Color(0xFF1F5FBF), Color(0xFF7A3DB8), Color(0xFF1E7A4C), Color(0xFF7D5B00),
    Color(0xFFB23A3A), Color(0xFF4547B8), Color(0xFF4F5A5E), Color(0xFF4A7311),
    Color(0xFFA1308F), Color(0xFF0F6F9E), Color(0xFF945600), Color(0xFF0B7466),
    Color(0xFFB5345A), Color(0xFF6A44C2),
  ];
  static const _lightBg = [
    Color(0xFFE3EDFB), Color(0xFFF0E7FA), Color(0xFFE2F2E8), Color(0xFFF8EFD2),
    Color(0xFFFBE6E6), Color(0xFFE8E8FA), Color(0xFFECEFEF), Color(0xFFEBF3DC),
    Color(0xFFF8E4F4), Color(0xFFE0F0F8), Color(0xFFFAEBD6), Color(0xFFDDF1ED),
    Color(0xFFFBE5EC), Color(0xFFEDE7FB),
  ];
  static const _darkFg = [
    Color(0xFF8DB8F5), Color(0xFFC39BEF), Color(0xFF7FCFA0), Color(0xFFE5C46A),
    Color(0xFFF09A9A), Color(0xFFA3A5F2), Color(0xFFAEB8BB), Color(0xFFB2D77A),
    Color(0xFFE596D6), Color(0xFF7FC6E8), Color(0xFFEDB66B), Color(0xFF6FD3C2),
    Color(0xFFF39AB4), Color(0xFFB9A1F3),
  ];

  static int _i(int index) => index.clamp(0, _lightFg.length - 1);

  /// (icon colour, well colour) for [index].
  static (Color, Color) of(int index, {required bool dark}) {
    final i = _i(index);
    if (!dark) return (_lightFg[i], _lightBg[i]);
    final fg = _darkFg[i];
    return (fg, Color.alphaBlend(fg.withValues(alpha: 0.16), Hue.nightPanel));
  }
}

/// Swatches users can pick for categories, goals and assets. Index-stable:
/// persisted records store the index, so only append new entries.
abstract final class AccentSwatches {
  static const List<(Color, Color)> gradients = [
    (Color(0xFF3B82F6), Color(0xFF06B6D4)), // 0 blue → cyan
    (Color(0xFFA855F7), Color(0xFFEC4899)), // 1 purple → pink
    (Color(0xFF22C55E), Color(0xFF14B8A6)), // 2 green → teal
    (Color(0xFFEAB308), Color(0xFFF97316)), // 3 yellow → orange
    (Color(0xFFEF4444), Color(0xFFEC4899)), // 4 red → pink
    (Color(0xFF6366F1), Color(0xFFA855F7)), // 5 indigo → purple
    (Color(0xFF6B7280), Color(0xFF374151)), // 6 gray
    (Color(0xFF84CC16), Color(0xFF22C55E)), // 7 lime → green
    (Color(0xFFD946EF), Color(0xFFEC4899)), // 8 fuchsia → pink
    (Color(0xFF0EA5E9), Color(0xFF6366F1)), // 9 sky → indigo
    (Color(0xFFF59E0B), Color(0xFFEF4444)), // 10 amber → red
    (Color(0xFF10B981), Color(0xFF3B82F6)), // 11 emerald → blue
    (Color(0xFFF43F5E), Color(0xFFF97316)), // 12 rose → orange
    (Color(0xFF8B5CF6), Color(0xFFD946EF)), // 13 violet → fuchsia
  ];

  static (Color, Color) of(int index) =>
      gradients[index.clamp(0, gradients.length - 1)];

  static Color solid(int index) => of(index).$1;

  static LinearGradient gradient(int index) {
    final (a, b) = of(index);
    return LinearGradient(
      colors: [a, b],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );
  }
}
