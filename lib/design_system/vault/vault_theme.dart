import 'package:flutter/material.dart';

import '../theme/finn_theme.dart';
import '../tokens/finn_colors.dart';
import '../tokens/typography.dart';
import 'vault_tokens.dart';

/// Material theme for everything rendered inside a Vault surface. Legacy
/// components read `context.colors` / `context.text`, so those tokens are
/// re-expressed in the Vault palette; Material widgets (date picker,
/// switches, text buttons, sliders) get Vault-shaped themes.
abstract final class VaultTheme {
  static final _cache = <bool, ThemeData>{};

  static ThemeData of(VaultPalette p) => _cache.putIfAbsent(p.isDark, () => _build(p));

  static ThemeData _build(VaultPalette p) {
    final t = p.isDark ? VaultType.dark : VaultType.light;
    final c = vaultFinnColors(p);
    final base = FinnTheme.fromTokens(c, type: vaultFinnType(p));
    final well = OutlineInputBorder(
      borderRadius: BorderRadius.circular(VaultShape.well),
      borderSide: BorderSide.none,
    );
    return base.copyWith(
      canvasColor: p.surface,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.well,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        border: well,
        enabledBorder: well,
        disabledBorder: well,
        focusedBorder: well.copyWith(borderSide: BorderSide(color: p.accent, width: 1.4)),
        errorBorder: well.copyWith(borderSide: BorderSide(color: p.negative.withValues(alpha: 0.7))),
        focusedErrorBorder: well.copyWith(borderSide: BorderSide(color: p.negative, width: 1.4)),
        hintStyle: t.input.vw(500).vc(p.inkFaint),
        labelStyle: t.label,
        errorStyle: t.caption.vc(p.negative).vw(600),
        prefixIconColor: p.inkMute,
        suffixIconColor: p.inkMute,
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: p.accent,
        selectionColor: p.accent.withValues(alpha: 0.28),
        selectionHandleColor: p.accent,
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: p.accentInk,
          textStyle: t.label.vw(700),
          minimumSize: const Size(48, 44),
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 12),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? p.onInk : (p.isDark ? p.inkMute : p.surfaceRaised),
        ),
        trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p.ink : p.hairlineStrong),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
        thumbIcon: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Icon(Icons.check_rounded, size: 14, color: p.ink) : null,
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: p.ink,
        inactiveTrackColor: p.well,
        thumbColor: p.ink,
        overlayColor: p.accent.withValues(alpha: 0.16),
        trackHeight: 4,
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p.ink : Colors.transparent),
        checkColor: WidgetStateProperty.all(p.onInk),
        side: BorderSide(color: p.hairlineStrong, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      dividerTheme: DividerThemeData(color: p.hairline, thickness: 1, space: 1),
      chipTheme: ChipThemeData(
        backgroundColor: p.well,
        selectedColor: p.ink,
        disabledColor: p.well,
        checkmarkColor: p.onInk,
        side: BorderSide.none,
        shape: const StadiumBorder(),
        labelStyle: t.chip.vw(620),
        secondaryLabelStyle: t.chip.vw(700).vc(p.onInk),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        labelPadding: const EdgeInsets.symmetric(horizontal: 4),
        showCheckmark: true,
        elevation: 0,
        pressElevation: 0,
        color: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p.ink : p.well),
      ),
      listTileTheme: ListTileThemeData(
        titleTextStyle: t.heading.copyWith(fontSize: 14.5),
        subtitleTextStyle: t.caption,
        iconColor: p.inkMute,
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shadowColor: Colors.transparent,
        headerBackgroundColor: p.surface,
        headerForegroundColor: p.ink,
        headerHeadlineStyle: t.title,
        headerHelpStyle: t.eyebrow,
        weekdayStyle: t.eyebrow.copyWith(letterSpacing: 0.6),
        dayStyle: t.chip,
        yearStyle: t.chip,
        dayForegroundColor: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.selected)) return p.onInk;
          if (s.contains(WidgetState.disabled)) return p.inkFaint;
          return p.ink;
        }),
        dayBackgroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p.ink : null),
        dayOverlayColor: WidgetStateProperty.all(p.accent.withValues(alpha: 0.12)),
        todayForegroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p.onInk : p.accentInk),
        todayBackgroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p.ink : null),
        todayBorder: BorderSide(color: p.accent),
        yearForegroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p.onInk : p.ink),
        yearBackgroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p.ink : null),
        dividerColor: p.hairline,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(VaultShape.dialog)),
        cancelButtonStyle: TextButton.styleFrom(foregroundColor: p.inkSoft, textStyle: t.label.vw(700)),
        confirmButtonStyle: TextButton.styleFrom(foregroundColor: p.ink, textStyle: t.label.vw(760)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(VaultShape.dialog)),
        titleTextStyle: t.dialogTitle,
        contentTextStyle: t.bodySoft,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: p.ink, linearTrackColor: p.well),
    );
  }
}

/// FinnColors expressed in the Vault palette.
FinnColors vaultFinnColors(VaultPalette p) => FinnColors(
  brightness: p.isDark ? Brightness.dark : Brightness.light,
  background: p.surface,
  backdrop: p.surface,
  surface: p.surface,
  surfaceMuted: p.well,
  surfaceSunken: p.well,
  border: p.hairline,
  borderStrong: p.hairlineStrong,
  textPrimary: p.ink,
  textSecondary: p.inkSoft,
  textTertiary: p.inkMute,
  primary: p.ink,
  onPrimary: p.onInk,
  positive: p.positive,
  positiveSoft: p.tint(p.positive),
  negative: p.negative,
  negativeSoft: p.tint(p.negative),
  warning: p.warning,
  warningSoft: p.tint(p.warning),
  attention: p.accentInk,
  attentionSoft: p.tint(p.accent, 0.14),
  info: p.info,
  infoSoft: p.tint(p.info),
  focusRing: p.accent,
  scrim: p.scrim,
  skeleton: p.well,
  heroStart: p.inkGradientColors.first,
  heroEnd: p.inkGradientColors.last,
  accentTransactions: p.ink,
  accentBudgets: p.accentInk,
  accentGoals: p.info,
  accentEmergency: p.positive,
  accentLoans: p.accentInk,
  accentSubscriptions: p.isDark ? const Color(0xFFE29BB8) : const Color(0xFF94456A),
  accentPending: p.isDark ? const Color(0xFFB9A6E8) : const Color(0xFF5F4C93),
  accentAnalytics: p.accentInk,
  accentNetWorth: p.info,
  agentStart: p.accent,
  agentMid: p.accentInk,
  agentEnd: p.ink,
  chartSeries: p.isDark
      ? const [
          Color(0xFFD9B97F),
          Color(0xFF7CCBA3),
          Color(0xFF98B6E5),
          Color(0xFFEE8F85),
          Color(0xFFC3A3E0),
          Color(0xFF8FD0D3),
        ]
      : const [
          Color(0xFFB98F4E),
          Color(0xFF22684A),
          Color(0xFF34548A),
          Color(0xFFA6362F),
          Color(0xFF6C5594),
          Color(0xFF2F7A7E),
        ],
);

/// FinnTypography expressed in Vault type.
FinnTypography vaultFinnType(VaultPalette p) {
  final t = p.isDark ? VaultType.dark : VaultType.light;
  return FinnTypography(
    display: t.title.copyWith(fontSize: 36),
    pageTitle: t.title,
    title: t.title.copyWith(fontSize: 24),
    sectionTitle: t.heading,
    body: t.body,
    bodyStrong: t.body.vw(660),
    caption: t.caption,
    label: t.label,
    eyebrow: t.eyebrow,
    micro: t.caption.copyWith(fontSize: 11.5, color: p.inkMute),
    amountHero: t.hero.copyWith(fontSize: 44),
    amountLarge: t.figure,
    amountMedium: t.number.copyWith(fontSize: 16),
    amountSmall: t.number.copyWith(fontSize: 13.5),
    button: t.button,
  );
}
