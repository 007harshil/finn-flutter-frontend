import 'package:flutter/material.dart';

import 'ui_colors.dart';

/// FiNN type scale (new UI kit): one sans family, tight tracking on large
/// sizes, tabular figures for money so amounts never jitter. Body text is
/// never below 12.
@immutable
class UiType {
  UiType._(UiColors c)
    : amount = TextStyle(
        fontSize: 40,
        fontWeight: FontWeight.w600,
        letterSpacing: -1.6,
        height: 1.05,
        color: c.ink,
        fontFeatures: _tabular,
      ),
      figure = TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.5,
        height: 1.15,
        color: c.ink,
        fontFeatures: _tabular,
      ),
      figureSmall = TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        height: 1.2,
        color: c.ink,
        fontFeatures: _tabular,
      ),
      title = TextStyle(fontSize: 20, fontWeight: FontWeight.w600, letterSpacing: -0.4, height: 1.2, color: c.ink),
      section = TextStyle(fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: -0.2, height: 1.25, color: c.ink),
      body = TextStyle(fontSize: 15, fontWeight: FontWeight.w500, letterSpacing: -0.1, height: 1.3, color: c.ink),
      label = TextStyle(fontSize: 13, fontWeight: FontWeight.w500, height: 1.3, color: c.inkSoft),
      small = TextStyle(fontSize: 12, fontWeight: FontWeight.w500, height: 1.3, color: c.inkSoft);

  static const _tabular = [FontFeature.tabularFigures(), FontFeature.liningFigures()];

  static final _light = UiType._(UiColors.light);
  static final _dark = UiType._(UiColors.darkMode);

  static UiType of(BuildContext context) => UiColors.of(context).dark ? _dark : _light;

  /// The one big number on a screen.
  final TextStyle amount;

  /// Secondary money figures (section totals).
  final TextStyle figure;

  /// Money inside rows and stats.
  final TextStyle figureSmall;
  final TextStyle title;
  final TextStyle section;
  final TextStyle body;
  final TextStyle label;
  final TextStyle small;
}
