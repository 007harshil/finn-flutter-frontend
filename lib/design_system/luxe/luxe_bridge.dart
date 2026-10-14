import 'package:flutter/material.dart';

import '../theme/finn_theme.dart';
import '../tokens/finn_colors.dart';
import '../tokens/typography.dart';
import '../vault/vault_tokens.dart';
import 'luxe_tokens.dart';

/// Re-skins a subtree in Luxe: every legacy component below it (cards,
/// fields, chips, pills, sheets, charts) reads `context.colors` /
/// `context.text`, so mapping those tokens onto the Luxe palette and type
/// makes forms and charts sit in the same warm, quiet world as the Luxe
/// screens without forking their logic.
class LuxeScope extends StatelessWidget {
  const LuxeScope({super.key, required this.child, this.paint = false});

  final Widget child;

  /// Paints the Luxe paper behind [child] (for sheets whose route surface
  /// still uses the app theme).
  final bool paint;

  static final _cache = <bool, ThemeData>{};

  static ThemeData themeFor(Brightness b) => _cache.putIfAbsent(b == Brightness.dark, () {
    final p = b == Brightness.dark ? LuxePalette.dark : LuxePalette.light;
    final c = luxeFinnColors(p);
    return FinnTheme.fromTokens(c, type: luxeFinnType(p));
  });

  @override
  Widget build(BuildContext context) {
    // Modal surfaces carry their own (Vault) theme and paint.
    if (VaultScope.isActive(context)) return child;
    final theme = themeFor(Theme.of(context).brightness);
    final body = Theme(data: theme, child: child);
    if (!paint) return body;
    // A Material (not a ColoredBox) so ink from list tiles and buttons
    // inside the sheet still shows.
    return Material(color: context.luxe.paper, child: body);
  }
}

/// FinnColors expressed in the Luxe palette.
FinnColors luxeFinnColors(LuxePalette p) => FinnColors(
  brightness: p.isDark ? Brightness.dark : Brightness.light,
  background: p.canvas,
  backdrop: p.canvasDeep,
  surface: p.paper,
  surfaceMuted: p.sunk,
  surfaceSunken: p.sunk,
  border: p.line,
  borderStrong: p.lineStrong,
  textPrimary: p.ink,
  textSecondary: p.inkSoft,
  textTertiary: p.inkMute,
  primary: p.ink,
  onPrimary: p.canvas,
  positive: p.positive,
  positiveSoft: p.tint(p.positive, 0.1),
  negative: p.negative,
  negativeSoft: p.tint(p.negative, 0.1),
  warning: p.warning,
  warningSoft: p.tint(p.warning, 0.1),
  attention: p.goldInk,
  attentionSoft: p.goldSoft,
  info: p.info,
  infoSoft: p.tint(p.info, 0.1),
  focusRing: p.gold,
  scrim: p.scrim,
  skeleton: p.sunk,
  heroStart: p.isDark ? const Color(0xFF221F1B) : const Color(0xFF2A2621),
  heroEnd: const Color(0xFF0F0E0C),
  accentTransactions: p.ink,
  accentBudgets: p.goldInk,
  accentGoals: p.info,
  accentEmergency: p.positive,
  accentLoans: p.goldInk,
  accentSubscriptions: p.mute(const Color(0xFFB0567A)),
  accentPending: p.mute(const Color(0xFF7A62B0)),
  accentAnalytics: p.goldInk,
  accentNetWorth: p.info,
  agentStart: p.gold,
  agentMid: p.goldInk,
  agentEnd: p.ink,
  chartSeries: luxeSeries(p),
);

/// Categorical chart colours: quiet, warm and distinguishable.
List<Color> luxeSeries(LuxePalette p) => p.isDark
    ? const [
        Color(0xFFD7B67A),
        Color(0xFF7DC5A1),
        Color(0xFF94B3E2),
        Color(0xFFEA8C82),
        Color(0xFFC3A3E0),
        Color(0xFF8FD0D3),
        Color(0xFFE5B45E),
        Color(0xFFB7B1A7),
      ]
    : const [
        Color(0xFFB8925A),
        Color(0xFF2E6A4D),
        Color(0xFF3A5884),
        Color(0xFFA23A33),
        Color(0xFF6C5594),
        Color(0xFF2F7A7E),
        Color(0xFF9A6210),
        Color(0xFF575045),
      ];

/// FinnTypography expressed in Luxe type: serif for big figures and
/// titles, Manrope for the rest.
FinnTypography luxeFinnType(LuxePalette p) {
  final t = p.isDark ? LuxeType.dark : LuxeType.light;
  return FinnTypography(
    display: t.headline,
    pageTitle: t.headline.copyWith(fontSize: 30),
    title: t.title.copyWith(fontSize: 22),
    sectionTitle: t.heading,
    body: t.body,
    bodyStrong: t.body.w(650),
    caption: t.caption,
    label: t.label.c(p.inkSoft),
    eyebrow: t.eyebrow,
    micro: t.micro,
    amountHero: t.display.copyWith(fontSize: 42),
    amountLarge: t.figure,
    amountMedium: t.number.copyWith(fontSize: 16),
    amountSmall: t.numberSmall,
    button: t.button,
  );
}
