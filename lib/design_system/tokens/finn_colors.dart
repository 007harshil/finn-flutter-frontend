import 'package:flutter/material.dart';

import 'palette.dart';

/// Semantic colour tokens. Access with `context.colors`.
///
/// Financial meaning is never conveyed by colour alone: every semantic
/// colour used for money is paired with a sign, icon, or label.
@immutable
class FinnColors extends ThemeExtension<FinnColors> {
  const FinnColors({
    required this.brightness,
    required this.background,
    required this.backdrop,
    required this.surface,
    required this.surfaceMuted,
    required this.surfaceSunken,
    required this.border,
    required this.borderStrong,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.primary,
    required this.onPrimary,
    required this.positive,
    required this.positiveSoft,
    required this.negative,
    required this.negativeSoft,
    required this.warning,
    required this.warningSoft,
    required this.attention,
    required this.attentionSoft,
    required this.info,
    required this.infoSoft,
    required this.focusRing,
    required this.scrim,
    required this.skeleton,
    required this.heroStart,
    required this.heroEnd,
    required this.accentTransactions,
    required this.accentBudgets,
    required this.accentGoals,
    required this.accentEmergency,
    required this.accentLoans,
    required this.accentSubscriptions,
    required this.accentPending,
    required this.accentAnalytics,
    required this.accentNetWorth,
    required this.agentStart,
    required this.agentMid,
    required this.agentEnd,
    required this.chartSeries,
  });

  final Brightness brightness;
  final Color background;

  /// Area behind the centred app column on tablets/desktop.
  final Color backdrop;
  final Color surface;
  final Color surfaceMuted;
  final Color surfaceSunken;
  final Color border;
  final Color borderStrong;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color primary;
  final Color onPrimary;

  /// Income, progress, healthy states.
  final Color positive;
  final Color positiveSoft;

  /// Outflows, breaches, critical states.
  final Color negative;
  final Color negativeSoft;

  /// Approaching limits.
  final Color warning;
  final Color warningSoft;

  /// Sunset orange: things that need the user's attention / key CTAs.
  final Color attention;
  final Color attentionSoft;
  final Color info;
  final Color infoSoft;
  final Color focusRing;
  final Color scrim;
  final Color skeleton;

  /// Hero (balance) card gradient.
  final Color heroStart;
  final Color heroEnd;

  final Color accentTransactions;
  final Color accentBudgets;
  final Color accentGoals;
  final Color accentEmergency;
  final Color accentLoans;
  final Color accentSubscriptions;
  final Color accentPending;
  final Color accentAnalytics;
  final Color accentNetWorth;

  /// FiNN agent brand gradient (orb, review panel accents).
  final Color agentStart;
  final Color agentMid;
  final Color agentEnd;

  /// Ordered categorical palette for charts.
  final List<Color> chartSeries;

  bool get isDark => brightness == Brightness.dark;

  /// Gradient of the FiNN agent mark.
  LinearGradient get agentGradient =>
      LinearGradient(colors: [agentStart, agentMid, agentEnd], begin: Alignment.topLeft, end: Alignment.bottomRight);

  LinearGradient get heroGradient =>
      LinearGradient(colors: [heroStart, heroEnd], begin: Alignment.topLeft, end: Alignment.bottomRight);

  static const light = FinnColors(
    brightness: Brightness.light,
    background: Color(0xFFF7F8FA),
    backdrop: Color(0xFFEDEFF3),
    surface: Palette.white,
    surfaceMuted: Palette.slate100,
    surfaceSunken: Color(0xFFEEF1F5),
    border: Palette.slate200,
    borderStrong: Palette.slate300,
    textPrimary: Palette.navy850,
    textSecondary: Palette.slate500,
    textTertiary: Color(0xFF8A97AB),
    primary: Palette.navy850,
    onPrimary: Palette.slate50,
    positive: Palette.emerald600,
    positiveSoft: Color(0xFFE7F8F1),
    negative: Palette.rose600,
    negativeSoft: Color(0xFFFFEEF1),
    warning: Palette.amber600,
    warningSoft: Color(0xFFFFF7E6),
    attention: Palette.orange600,
    attentionSoft: Color(0xFFFFF1E7),
    info: Palette.blue600,
    infoSoft: Color(0xFFEDF4FF),
    focusRing: Palette.blue500,
    scrim: Color(0x99020817),
    skeleton: Color(0xFFE6EAF0),
    heroStart: Palette.navy850,
    heroEnd: Color(0xFF1C2B4A),
    accentTransactions: Palette.navy700,
    accentBudgets: Palette.orange600,
    accentGoals: Palette.indigo600,
    accentEmergency: Palette.emerald600,
    accentLoans: Palette.amber600,
    accentSubscriptions: Palette.pink600,
    accentPending: Palette.violet600,
    accentAnalytics: Palette.emerald600,
    accentNetWorth: Palette.blue600,
    agentStart: Palette.emerald500,
    agentMid: Palette.cyan500,
    agentEnd: Palette.indigo600,
    chartSeries: [
      Palette.navy700,
      Palette.emerald500,
      Palette.orange500,
      Palette.indigo500,
      Palette.pink500,
      Palette.sky500,
      Palette.amber500,
      Palette.violet500,
    ],
  );

  static const dark = FinnColors(
    brightness: Brightness.dark,
    background: Palette.navy950,
    backdrop: Color(0xFF01050F),
    surface: Palette.navy900,
    surfaceMuted: Palette.navy800,
    surfaceSunken: Palette.navy925,
    border: Palette.navy700,
    borderStrong: Palette.navy600,
    textPrimary: Palette.slate50,
    textSecondary: Palette.slate400,
    textTertiary: Color(0xFF6B7A93),
    primary: Palette.slate50,
    onPrimary: Palette.navy850,
    positive: Palette.emerald400,
    positiveSoft: Color(0xFF0B2A23),
    negative: Palette.rose400,
    negativeSoft: Color(0xFF2E0F1A),
    warning: Palette.amber400,
    warningSoft: Color(0xFF2B1F08),
    attention: Palette.orange400,
    attentionSoft: Color(0xFF2E1709),
    info: Palette.blue400,
    infoSoft: Color(0xFF0E1D3A),
    focusRing: Palette.blue400,
    scrim: Color(0xB3000000),
    skeleton: Palette.navy800,
    heroStart: Color(0xFF13203A),
    heroEnd: Color(0xFF0A1222),
    accentTransactions: Palette.slate400,
    accentBudgets: Palette.orange500,
    accentGoals: Palette.indigo500,
    accentEmergency: Palette.emerald500,
    accentLoans: Palette.amber500,
    accentSubscriptions: Palette.pink500,
    accentPending: Palette.violet500,
    accentAnalytics: Palette.emerald500,
    accentNetWorth: Palette.blue500,
    agentStart: Palette.emerald400,
    agentMid: Palette.cyan500,
    agentEnd: Palette.indigo500,
    chartSeries: [
      Palette.slate300,
      Palette.emerald400,
      Palette.orange400,
      Palette.indigo400,
      Palette.pink400,
      Palette.sky500,
      Palette.amber400,
      Palette.violet400,
    ],
  );

  @override
  FinnColors copyWith() => this;

  @override
  FinnColors lerp(ThemeExtension<FinnColors>? other, double t) {
    if (other is! FinnColors) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return FinnColors(
      brightness: t < 0.5 ? brightness : other.brightness,
      background: l(background, other.background),
      backdrop: l(backdrop, other.backdrop),
      surface: l(surface, other.surface),
      surfaceMuted: l(surfaceMuted, other.surfaceMuted),
      surfaceSunken: l(surfaceSunken, other.surfaceSunken),
      border: l(border, other.border),
      borderStrong: l(borderStrong, other.borderStrong),
      textPrimary: l(textPrimary, other.textPrimary),
      textSecondary: l(textSecondary, other.textSecondary),
      textTertiary: l(textTertiary, other.textTertiary),
      primary: l(primary, other.primary),
      onPrimary: l(onPrimary, other.onPrimary),
      positive: l(positive, other.positive),
      positiveSoft: l(positiveSoft, other.positiveSoft),
      negative: l(negative, other.negative),
      negativeSoft: l(negativeSoft, other.negativeSoft),
      warning: l(warning, other.warning),
      warningSoft: l(warningSoft, other.warningSoft),
      attention: l(attention, other.attention),
      attentionSoft: l(attentionSoft, other.attentionSoft),
      info: l(info, other.info),
      infoSoft: l(infoSoft, other.infoSoft),
      focusRing: l(focusRing, other.focusRing),
      scrim: l(scrim, other.scrim),
      skeleton: l(skeleton, other.skeleton),
      heroStart: l(heroStart, other.heroStart),
      heroEnd: l(heroEnd, other.heroEnd),
      accentTransactions: l(accentTransactions, other.accentTransactions),
      accentBudgets: l(accentBudgets, other.accentBudgets),
      accentGoals: l(accentGoals, other.accentGoals),
      accentEmergency: l(accentEmergency, other.accentEmergency),
      accentLoans: l(accentLoans, other.accentLoans),
      accentSubscriptions: l(accentSubscriptions, other.accentSubscriptions),
      accentPending: l(accentPending, other.accentPending),
      accentAnalytics: l(accentAnalytics, other.accentAnalytics),
      accentNetWorth: l(accentNetWorth, other.accentNetWorth),
      agentStart: l(agentStart, other.agentStart),
      agentMid: l(agentMid, other.agentMid),
      agentEnd: l(agentEnd, other.agentEnd),
      chartSeries: t < 0.5 ? chartSeries : other.chartSeries,
    );
  }
}
