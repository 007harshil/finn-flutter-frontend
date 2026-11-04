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

  /// Marigold: things that need the user's attention / highlights.
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
    background: Hue.shore,
    backdrop: Hue.shoreBackdrop,
    surface: Hue.panel,
    surfaceMuted: Hue.mist,
    surfaceSunken: Hue.mist,
    border: Hue.hair,
    borderStrong: Hue.hairStrong,
    textPrimary: Hue.ink,
    textSecondary: Hue.inkSoft,
    textTertiary: Hue.inkFaint,
    primary: Hue.current,
    onPrimary: Hue.panel,
    positive: Hue.moneyIn,
    positiveSoft: Hue.moneyInSoft,
    negative: Hue.over,
    negativeSoft: Hue.overSoft,
    warning: Hue.near,
    warningSoft: Hue.nearSoft,
    attention: Hue.marigoldInk,
    attentionSoft: Hue.marigoldSoft,
    info: Hue.info,
    infoSoft: Hue.infoSoft,
    focusRing: Hue.current,
    scrim: Color(0x66191B3F),
    skeleton: Hue.mist,
    heroStart: Hue.deep,
    heroEnd: Hue.deepEnd,
    accentTransactions: Hue.ink,
    accentBudgets: Hue.saffron,
    accentGoals: Hue.lilac,
    accentEmergency: Hue.jade,
    accentLoans: Hue.near,
    accentSubscriptions: Hue.rose,
    accentPending: Hue.marigoldInk,
    accentAnalytics: Hue.rain,
    accentNetWorth: Hue.current,
    agentStart: Hue.marigold,
    agentMid: Hue.current,
    agentEnd: Hue.deep,
    chartSeries: Hue.chartLight,
  );

  static const dark = FinnColors(
    brightness: Brightness.dark,
    background: Hue.night,
    backdrop: Hue.nightBackdrop,
    surface: Hue.nightPanel,
    surfaceMuted: Hue.nightRaised,
    surfaceSunken: Hue.nightRaised,
    border: Hue.nightHair,
    borderStrong: Hue.nightHairStrong,
    textPrimary: Hue.nightInk,
    textSecondary: Hue.nightInkSoft,
    textTertiary: Hue.nightInkFaint,
    primary: Hue.nightCurrent,
    onPrimary: Hue.nightOnCurrent,
    positive: Hue.nightIn,
    positiveSoft: Hue.nightInSoft,
    negative: Hue.nightOver,
    negativeSoft: Hue.nightOverSoft,
    warning: Hue.nightNear,
    warningSoft: Hue.nightNearSoft,
    attention: Hue.nightMarigoldInk,
    attentionSoft: Hue.nightMarigoldSoft,
    info: Hue.nightInfo,
    infoSoft: Hue.nightInfoSoft,
    focusRing: Hue.nightCurrent,
    scrim: Color(0x99000000),
    skeleton: Hue.nightRaised,
    heroStart: Hue.nightDeep,
    heroEnd: Hue.nightDeepEnd,
    accentTransactions: Hue.nightInkSoft,
    accentBudgets: Hue.nightSaffron,
    accentGoals: Hue.nightLilac,
    accentEmergency: Hue.nightJade,
    accentLoans: Hue.nightNear,
    accentSubscriptions: Hue.nightRose,
    accentPending: Hue.nightMarigoldInk,
    accentAnalytics: Hue.nightRain,
    accentNetWorth: Hue.nightCurrent,
    agentStart: Hue.nightMarigold,
    agentMid: Color(0xFFA3A9FF),
    agentEnd: Hue.nightDeep,
    chartSeries: Hue.chartDark,
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
