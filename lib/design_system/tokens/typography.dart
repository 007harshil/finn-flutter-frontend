import 'package:flutter/material.dart';

import 'finn_colors.dart';

/// Type scale in Anek Latin, the app font (see `LedgerType`): condensed
/// for money, wide for display headings. Money uses tabular figures so
/// columns align.
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
    TextStyle s(double size, FontWeight w, {double? ls, double? h, Color? color, double width = 100}) => TextStyle(
          fontFamily: 'AnekLatin',
          fontFamilyFallback: const ['AnekDevanagari', 'Manrope'],
          fontSize: size,
          fontWeight: w,
          fontVariations: [FontVariation.weight(w.value.toDouble()), FontVariation.width(width)],
          letterSpacing: ls,
          height: h,
          color: color ?? c.textPrimary,
        );
    return FinnTypography(
      display: s(32, FontWeight.w700, ls: -0.3, h: 1.05, width: 112),
      pageTitle: s(26, FontWeight.w700, ls: -0.2, h: 1.1, width: 112),
      title: s(19, FontWeight.w600, ls: -0.1, h: 1.2, width: 106),
      sectionTitle: s(13, FontWeight.w700, ls: 0.6, h: 1.2, width: 110),
      body: s(15, FontWeight.w400, h: 1.4),
      bodyStrong: s(15, FontWeight.w600, h: 1.3),
      caption: s(13, FontWeight.w500, h: 1.35, color: c.textSecondary),
      label: s(13, FontWeight.w600, ls: 0.1, h: 1.3, color: c.textSecondary),
      eyebrow: s(11.5, FontWeight.w700, ls: 1.0, h: 1.2, color: c.textSecondary, width: 110),
      micro: s(11, FontWeight.w600, ls: 0.2, h: 1.2, color: c.textTertiary),
      amountHero: s(46, FontWeight.w700, ls: -0.4, h: 1.0, width: 78).copyWith(fontFeatures: tabular),
      amountLarge: s(30, FontWeight.w700, ls: -0.3, h: 1.05, width: 82).copyWith(fontFeatures: tabular),
      amountMedium: s(18, FontWeight.w600, h: 1.15, width: 90).copyWith(fontFeatures: tabular),
      amountSmall: s(14, FontWeight.w600, h: 1.2, width: 95).copyWith(fontFeatures: tabular),
      button: s(15, FontWeight.w600, h: 1.2, width: 104),
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
