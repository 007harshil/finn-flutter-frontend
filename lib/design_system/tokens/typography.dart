import 'package:flutter/material.dart';

import 'finn_colors.dart';

/// Type scale. Uses the platform system font (Roboto / SF Pro) per the
/// FiNN design reference. Money uses tabular figures so columns align.
@immutable
class FinnTypography extends ThemeExtension<FinnTypography> {
  const FinnTypography({
    required this.display,
    required this.pageTitle,
    required this.title,
    required this.sectionTitle,
    required this.body,
    required this.bodyStrong,
    required this.caption,
    required this.label,
    required this.eyebrow,
    required this.micro,
    required this.amountHero,
    required this.amountLarge,
    required this.amountMedium,
    required this.amountSmall,
    required this.button,
  });

  factory FinnTypography.from(FinnColors c) {
    const tabular = [FontFeature.tabularFigures(), FontFeature.liningFigures()];
    TextStyle s(double size, FontWeight w, {double? ls, double? h, Color? color}) => TextStyle(
          fontSize: size,
          fontWeight: w,
          letterSpacing: ls,
          height: h,
          color: color ?? c.textPrimary,
        );
    return FinnTypography(
      display: s(30, FontWeight.w900, ls: -1.2, h: 1.1),
      pageTitle: s(24, FontWeight.w900, ls: -0.8, h: 1.15),
      title: s(18, FontWeight.w800, ls: -0.3, h: 1.25),
      sectionTitle: s(13, FontWeight.w900, ls: 0.4, h: 1.2),
      body: s(14, FontWeight.w500, h: 1.45),
      bodyStrong: s(14, FontWeight.w700, ls: -0.1, h: 1.35),
      caption: s(12, FontWeight.w500, h: 1.4, color: c.textSecondary),
      label: s(12, FontWeight.w700, ls: 0.2, h: 1.3, color: c.textSecondary),
      eyebrow: s(10.5, FontWeight.w900, ls: 1.2, h: 1.2, color: c.textSecondary),
      micro: s(10, FontWeight.w700, ls: 0.3, h: 1.2, color: c.textTertiary),
      amountHero: s(34, FontWeight.w900, ls: -1.4, h: 1.05).copyWith(fontFeatures: tabular),
      amountLarge: s(24, FontWeight.w900, ls: -0.9, h: 1.1).copyWith(fontFeatures: tabular),
      amountMedium: s(16, FontWeight.w800, ls: -0.4, h: 1.15).copyWith(fontFeatures: tabular),
      amountSmall: s(13, FontWeight.w700, ls: -0.2, h: 1.2).copyWith(fontFeatures: tabular),
      button: s(14, FontWeight.w800, ls: 0.3, h: 1.2),
    );
  }

  /// Hero-level heading (onboarding, empty dashboards).
  final TextStyle display;

  /// Top-of-screen titles.
  final TextStyle pageTitle;

  /// Card and sheet titles.
  final TextStyle title;

  /// Uppercase section headers.
  final TextStyle sectionTitle;
  final TextStyle body;
  final TextStyle bodyStrong;

  /// Supporting information.
  final TextStyle caption;

  /// Form labels and metadata keys.
  final TextStyle label;

  /// Small uppercase overline labels ("LIQUID CASH").
  final TextStyle eyebrow;

  /// Secondary metadata (timestamps, badges).
  final TextStyle micro;

  final TextStyle amountHero;
  final TextStyle amountLarge;
  final TextStyle amountMedium;
  final TextStyle amountSmall;
  final TextStyle button;

  @override
  FinnTypography copyWith() => this;

  @override
  FinnTypography lerp(ThemeExtension<FinnTypography>? other, double t) {
    if (other is! FinnTypography) return this;
    TextStyle l(TextStyle a, TextStyle b) => TextStyle.lerp(a, b, t)!;
    return FinnTypography(
      display: l(display, other.display),
      pageTitle: l(pageTitle, other.pageTitle),
      title: l(title, other.title),
      sectionTitle: l(sectionTitle, other.sectionTitle),
      body: l(body, other.body),
      bodyStrong: l(bodyStrong, other.bodyStrong),
      caption: l(caption, other.caption),
      label: l(label, other.label),
      eyebrow: l(eyebrow, other.eyebrow),
      micro: l(micro, other.micro),
      amountHero: l(amountHero, other.amountHero),
      amountLarge: l(amountLarge, other.amountLarge),
      amountMedium: l(amountMedium, other.amountMedium),
      amountSmall: l(amountSmall, other.amountSmall),
      button: l(button, other.button),
    );
  }
}
