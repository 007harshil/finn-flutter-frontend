import 'package:flutter/material.dart';

import '../../design_system/design_system.dart';

/// A go_router page that presents its child as a modal bottom sheet, so
/// forms keep sheet ergonomics while remaining addressable by URL.
class SheetPage<T> extends Page<T> {
  const SheetPage({required this.child, super.key, super.name, super.arguments, super.restorationId});

  final Widget child;

  @override
  Route<T> createRoute(BuildContext context) {
    final c = context.colors;
    return ModalBottomSheetRoute<T>(
      settings: this,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: false,
      backgroundColor: c.surface,
      modalBarrierColor: c.scrim,
      constraints: const BoxConstraints(maxWidth: Space.maxContentWidth),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.xxxl)),
      ),
      clipBehavior: Clip.antiAlias,
      builder: (_) => child,
    );
  }
}

/// Subtle fade + scale transition for full-screen pages.
class FadeScalePage<T> extends CustomTransitionPage<T> {
  FadeScalePage({required super.child, super.key, super.name})
      : super(
          transitionDuration: const Duration(milliseconds: 300),
          reverseTransitionDuration: const Duration(milliseconds: 240),
          transitionsBuilder: (context, animation, secondary, child) {
            if (context.reduceMotion) return child;
            final curved = CurvedAnimation(parent: animation, curve: Curves2.emphasized, reverseCurve: Curves2.exit);
            return FadeTransition(
              opacity: curved,
              child: ScaleTransition(scale: Tween(begin: 0.96, end: 1.0).animate(curved), child: child),
            );
          },
        );
}

/// Minimal copy of go_router's CustomTransitionPage contract so this file
/// has no go_router import (keeps the page reusable).
class CustomTransitionPage<T> extends Page<T> {
  const CustomTransitionPage({
    required this.child,
    required this.transitionsBuilder,
    this.transitionDuration = const Duration(milliseconds: 300),
    this.reverseTransitionDuration = const Duration(milliseconds: 300),
    super.key,
    super.name,
  });

  final Widget child;
  final Duration transitionDuration;
  final Duration reverseTransitionDuration;
  final Widget Function(BuildContext, Animation<double>, Animation<double>, Widget) transitionsBuilder;

  @override
  Route<T> createRoute(BuildContext context) => PageRouteBuilder<T>(
        settings: this,
        transitionDuration: transitionDuration,
        reverseTransitionDuration: reverseTransitionDuration,
        pageBuilder: (_, _, _) => child,
        transitionsBuilder: transitionsBuilder,
      );
}
