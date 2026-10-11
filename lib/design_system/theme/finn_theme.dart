import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../tokens/finn_colors.dart';
import '../tokens/tokens.dart';
import '../tokens/typography.dart';

/// Builds Material themes from FiNN tokens.
abstract final class FinnTheme {
  static ThemeData light() => _build(FinnColors.light);
  static ThemeData dark() => _build(FinnColors.dark);

  static ThemeData _build(FinnColors c) {
    final type = FinnTypography.from(c);
    final scheme = ColorScheme(
      brightness: c.brightness,
      primary: c.primary,
      onPrimary: c.onPrimary,
      secondary: c.positive,
      onSecondary: Colors.white,
      tertiary: c.attention,
      onTertiary: Colors.white,
      error: c.negative,
      onError: Colors.white,
      surface: c.surface,
      onSurface: c.textPrimary,
      onSurfaceVariant: c.textSecondary,
      outline: c.border,
      outlineVariant: c.border,
      surfaceContainerHighest: c.surfaceMuted,
      surfaceContainerHigh: c.surfaceMuted,
      surfaceContainer: c.surface,
      surfaceContainerLow: c.surface,
      surfaceContainerLowest: c.surface,
      shadow: Colors.black,
      scrim: c.scrim,
    );
    final inputBorder = OutlineInputBorder(
      borderRadius: Radii.rLg,
      borderSide: BorderSide(color: c.border, width: 1.5),
    );
    return ThemeData(
      useMaterial3: true,
      brightness: c.brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: c.background,
      canvasColor: c.background,
      dividerColor: c.border,
      splashFactory: InkSparkle.splashFactory,
      extensions: [c, type],
      textTheme: TextTheme(
        displaySmall: type.display,
        headlineSmall: type.pageTitle,
        titleLarge: type.title,
        titleMedium: type.bodyStrong,
        titleSmall: type.label,
        bodyLarge: type.body.copyWith(fontSize: 16),
        bodyMedium: type.body,
        bodySmall: type.caption,
        labelLarge: type.button,
        labelMedium: type.label,
        labelSmall: type.micro,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: c.background,
        foregroundColor: c.textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: type.title,
        systemOverlayStyle: c.isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      ),
      dividerTheme: DividerThemeData(color: c.border, thickness: 1, space: 1),
      iconTheme: IconThemeData(color: c.textPrimary, size: 20),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: Space.x4, vertical: Space.x4),
        border: inputBorder,
        enabledBorder: inputBorder,
        focusedBorder: inputBorder.copyWith(borderSide: BorderSide(color: c.primary, width: 2)),
        errorBorder: inputBorder.copyWith(borderSide: BorderSide(color: c.negative, width: 1.5)),
        focusedErrorBorder: inputBorder.copyWith(borderSide: BorderSide(color: c.negative, width: 2)),
        hintStyle: type.body.copyWith(color: c.textTertiary),
        labelStyle: type.label,
        errorStyle: type.caption.copyWith(color: c.negative, fontWeight: FontWeight.w600),
        prefixIconColor: c.textSecondary,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        modalBarrierColor: c.scrim,
        showDragHandle: false,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.xxxl)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: Radii.rXxxl),
        titleTextStyle: type.title,
        contentTextStyle: type.body.copyWith(color: c.textSecondary),
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        headerBackgroundColor: c.primary,
        headerForegroundColor: c.onPrimary,
        shape: const RoundedRectangleBorder(borderRadius: Radii.rXxxl),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: c.primary,
        contentTextStyle: type.bodyStrong.copyWith(color: c.onPrimary),
        shape: const RoundedRectangleBorder(borderRadius: Radii.rXl),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Colors.white : c.textTertiary,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.positive : c.surfaceMuted,
        ),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.primary : Colors.transparent,
        ),
        checkColor: WidgetStateProperty.all(c.onPrimary),
        side: BorderSide(color: c.borderStrong, width: 1.5),
        shape: const RoundedRectangleBorder(borderRadius: Radii.rSm),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: c.primary),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(color: c.primary, borderRadius: Radii.rMd),
        textStyle: type.caption.copyWith(color: c.onPrimary),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
        },
      ),
    );
  }
}

extension FinnThemeX on BuildContext {
  FinnColors get colors => Theme.of(this).extension<FinnColors>()!;
  FinnTypography get text => Theme.of(this).extension<FinnTypography>()!;
}
