import 'package:flutter/material.dart';

/// FiNN colour tokens (new UI kit). Quiet, mostly monochrome surfaces;
/// colour is kept for meaning only: money in, money out, urgency, purpose.
///
/// Read through [UiColors.of] (or `context.ui`), never raw hex in widgets.
@immutable
class UiColors {
  const UiColors._({
    required this.dark,
    required this.page,
    required this.surface,
    required this.muted,
    required this.ink,
    required this.inkSoft,
    required this.inkFaint,
    required this.hairline,
    required this.positive,
    required this.negative,
    required this.warning,
    required this.info,
    required this.goals,
    required this.emergency,
  });

  static const light = UiColors._(
    dark: false,
    page: Color(0xFFF6F6F3),
    surface: Color(0xFFFFFFFF),
    muted: Color(0xFFEDEDE8),
    ink: Color(0xFF111316),
    inkSoft: Color(0xFF585E69),
    inkFaint: Color(0xFF9096A0),
    hairline: Color(0xFFE3E3DE),
    positive: Color(0xFF0B7A4B),
    negative: Color(0xFFB42318),
    warning: Color(0xFF9A5B06),
    info: Color(0xFF2F5BBF),
    goals: Color(0xFF3B5BDB),
    emergency: Color(0xFF0E7C7B),
  );

  static const darkMode = UiColors._(
    dark: true,
    page: Color(0xFF0C0D0F),
    surface: Color(0xFF17191C),
    muted: Color(0xFF222529),
    ink: Color(0xFFF3F4F6),
    inkSoft: Color(0xFFA3A9B3),
    inkFaint: Color(0xFF6C727C),
    hairline: Color(0xFF272A2F),
    positive: Color(0xFF3DD68C),
    negative: Color(0xFFFF7B70),
    warning: Color(0xFFF2B54C),
    info: Color(0xFF8AB4FF),
    goals: Color(0xFF93A6FF),
    emergency: Color(0xFF4FD1C5),
  );

  static UiColors of(BuildContext context) => Theme.of(context).brightness == Brightness.dark ? darkMode : light;

  final bool dark;

  /// Page background (never pure white, so surfaces lift off it).
  final Color page;
  final Color surface;

  /// Pressed / placeholder fills and bar tracks.
  final Color muted;

  /// Primary text and icons.
  final Color ink;

  /// Secondary text (≥ 4.5:1 on [page] and [surface]).
  final Color inkSoft;

  /// Decorative only (chevrons, bar segments); never text.
  final Color inkFaint;
  final Color hairline;
  final Color positive;
  final Color negative;
  final Color warning;
  final Color info;
  final Color goals;
  final Color emergency;
}
