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
