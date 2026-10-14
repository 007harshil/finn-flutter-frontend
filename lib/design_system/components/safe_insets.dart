import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The device's safe insets (status bar, display cutout, navigation /
/// gesture bar), captured once at the app root before any widget consumes
/// them.
///
/// `MediaQuery.padding` is rewritten as it travels down the tree: a
/// `SafeArea`, a `Scaffold` or a modal route may zero it. Anything that has
/// to clear the real system bars — floating sheets, docks, toasts, fixed
/// footers — reads [SafeInsetsX.safeInsets] instead, so no screen hard-codes
/// a status-bar or home-indicator height.
class SafeInsetsScope extends InheritedWidget {
  const SafeInsetsScope({super.key, required this.insets, required super.child});

  /// Wraps [child] with the insets of the nearest [MediaQuery].
  factory SafeInsetsScope.fromMediaQuery(BuildContext context, {required Widget child}) =>
      SafeInsetsScope(insets: MediaQuery.viewPaddingOf(context), child: child);

  final EdgeInsets insets;

  static EdgeInsets of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SafeInsetsScope>()?.insets ?? MediaQuery.viewPaddingOf(context);

  @override
  bool updateShouldNotify(SafeInsetsScope oldWidget) => oldWidget.insets != insets;
}

extension SafeInsetsX on BuildContext {
  /// Raw device safe insets (never consumed by intermediate widgets).
  EdgeInsets get safeInsets => SafeInsetsScope.of(this);

  double get safeTop => safeInsets.top;
  double get safeBottom => safeInsets.bottom;

  /// Space to leave under content that rests on the bottom edge: the
  /// gesture / navigation bar, but never less than [min].
  double safeBottomAtLeast(double min) => math.max(safeBottom, min);

  /// [base] padding grown so content never sits under the system bars on
  /// the given edges.
  EdgeInsets safePadding(EdgeInsets base, {bool top = false, bool bottom = true, bool sides = true}) {
    final s = safeInsets;
    return EdgeInsets.fromLTRB(
      base.left + (sides ? s.left : 0),
      base.top + (top ? s.top : 0),
      base.right + (sides ? s.right : 0),
      base.bottom + (bottom ? s.bottom : 0),
    );
  }
}

/// Transparent, edge-to-edge system bars whose icons follow the theme, so
/// the app draws behind them and every screen pads itself from
/// [SafeInsetsX.safeInsets].
abstract final class SystemBars {
  static SystemUiOverlayStyle styleFor(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    return SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
      statusBarBrightness: dark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarIconBrightness: dark ? Brightness.light : Brightness.dark,
      systemNavigationBarContrastEnforced: false,
      systemStatusBarContrastEnforced: false,
    );
  }

  /// Opts into edge-to-edge drawing (Android draws under the bars; iOS
  /// already does).
  static Future<void> enableEdgeToEdge() => SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
}

/// App-root frame: captures the safe insets, applies transparent system
/// bars, and keeps landscape content clear of side cutouts.
class SafeFrame extends StatelessWidget {
  const SafeFrame({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemBars.styleFor(brightness),
      child: SafeInsetsScope.fromMediaQuery(context, child: child),
    );
  }
}

/// Route-level guard for full-screen pages: keeps content clear of side
/// cutouts (landscape notches) while leaving top and bottom to the page,
/// which paints behind the bars and pads its own scroll content.
class SafeSides extends StatelessWidget {
  const SafeSides({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => SafeArea(top: false, bottom: false, child: child);
}
