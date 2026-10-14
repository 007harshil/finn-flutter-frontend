import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../components/safe_insets.dart';
import '../motion/motion.dart';
import 'vault_theme.dart';
import 'vault_tokens.dart';

/// Opens [builder] in a floating Vault sheet. Pair with `VaultSheet`.
Future<T?> showVaultSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool dismissible = true,
  bool enableDrag = true,
  bool useRootNavigator = true,
}) {
  final navigator = Navigator.of(context, rootNavigator: useRootNavigator);
  return navigator.push<T>(
    VaultSheetRoute<T>(
      builder: builder,
      dismissible: dismissible,
      enableDrag: enableDrag,
      capturedThemes: InheritedTheme.capture(from: context, to: navigator.context),
    ),
  );
}

/// Opens [builder] as a centred Vault dialog card.
Future<T?> showVaultDialog<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool dismissible = true,
  bool useRootNavigator = true,
}) {
  final navigator = Navigator.of(context, rootNavigator: useRootNavigator);
  return navigator.push<T>(
    VaultDialogRoute<T>(
      builder: builder,
      dismissible: dismissible,
      capturedThemes: InheritedTheme.capture(from: context, to: navigator.context),
    ),
  );
}

/// Dimmed, progressively blurred world behind a Vault surface. The blur
/// and the dim both follow the route animation, so the page recedes as the
/// sheet rises and returns as it leaves.
class _VaultBarrier extends StatelessWidget {
  const _VaultBarrier({required this.animation, required this.dismissible, required this.onDismiss});

  final Animation<double> animation;
  final bool dismissible;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final p = context.vault;
    final reduced = context.reduceMotion;
    return Semantics(
      label: dismissible ? MaterialLocalizations.of(context).modalBarrierDismissLabel : null,
      onTap: dismissible ? onDismiss : null,
      container: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        onTap: dismissible ? onDismiss : null,
        child: AnimatedBuilder(
          animation: animation,
          builder: (context, _) {
            final v = Curves.easeOut.transform(animation.value.clamp(0.0, 1.0));
            final sigma = reduced ? 0.0 : 9 * v;
            final dim = ColoredBox(color: p.scrim.withValues(alpha: p.scrim.a * v));
            if (sigma < 0.4) return dim;
            return BackdropFilter(filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma), child: dim);
          },
        ),
      ),
    );
  }
}

/// Lets a sheet's header and body drive the sheet's drag-to-dismiss.
class VaultSheetDrag extends InheritedWidget {
  const VaultSheetDrag({super.key, required this.update, required this.end, required super.child});

  /// Moves the sheet by a vertical pixel delta (positive = down).
  final ValueChanged<double> update;

  /// Releases the sheet with a vertical velocity in px/s.
  final ValueChanged<double> end;

  static VaultSheetDrag? maybeOf(BuildContext context) => context.getInheritedWidgetOfExactType<VaultSheetDrag>();

  @override
  bool updateShouldNotify(VaultSheetDrag oldWidget) => false;
}

/// Route for a floating Vault sheet.
///
/// The sheet is a detached card: it floats [VaultShape.float] in from the
/// screen edges and above the gesture bar (from [SafeInsetsX.safeInsets]),
/// rises on a spring, and can be pulled down to dismiss from its header or
/// by over-scrolling its body. The keyboard lifts it rather than covering
/// it. Underneath, the page dims and blurs.
class VaultSheetRoute<T> extends PopupRoute<T> {
  VaultSheetRoute({
    required this.builder,
    this.dismissible = true,
    this.enableDrag = true,
    this.capturedThemes,
    super.settings,
  });

  final WidgetBuilder builder;
  final bool dismissible;
  final bool enableDrag;
  final CapturedThemes? capturedThemes;

  /// Linear (finger-tracking) while dragging or settling after a drag.
  final ValueNotifier<bool> _tracking = ValueNotifier(false);
  double _height = 1;

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => false; // handled by the custom barrier

  @override
  String? get barrierLabel => null;

  @override
  Duration get transitionDuration => VaultMotion.sheetIn;

  @override
  Duration get reverseTransitionDuration => VaultMotion.sheetOut;

  @override
  Widget buildModalBarrier() => _VaultBarrier(
    animation: animation!,
    dismissible: dismissible,
    onDismiss: () => navigator?.maybePop(),
  );

  void _dragUpdate(double dy) {
    if (!enableDrag || !isActive) return;
    final c = controller;
    if (c == null || c.isAnimating && !_tracking.value) return;
    _tracking.value = true;
    c.value = (c.value - dy / _height).clamp(0.0, 1.0);
  }

  void _dragEnd(double velocity) {
    final c = controller;
    if (c == null || !_tracking.value) return;
    final flung = velocity > 700;
    if (dismissible && (flung || c.value < 0.72)) {
      // A PopScope may refuse (e.g. unsaved changes); then settle back.
      navigator?.maybePop().then((_) {
        if (isActive && c.status != AnimationStatus.reverse && c.value < 1) _settle(c);
      });
      return;
    }
    _settle(c);
  }

  void _settle(AnimationController c) {
    c.animateTo(1, duration: const Duration(milliseconds: 260), curve: Curves.easeOutCubic).whenCompleteOrCancel(
      () => _tracking.value = false,
    );
  }

  @override
  void dispose() {
    _tracking.dispose();
    super.dispose();
  }

  @override
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation) {
    final content = Builder(builder: builder);
    final themed = capturedThemes?.wrap(content) ?? content;
    return _VaultSheetFrame(route: this, child: themed);
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => child;
}

class _VaultSheetFrame extends StatelessWidget {
  const _VaultSheetFrame({required this.route, required this.child});

  final VaultSheetRoute<dynamic> route;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final safe = context.safeInsets;
    final keyboard = mq.viewInsets.bottom;
    final size = mq.size;
    final wide = size.width >= 600;
    final side = wide ? 24.0 : VaultShape.float;
    final bottom = keyboard > 0 ? keyboard + 8 : math.max(safe.bottom, VaultShape.float) + (safe.bottom > 0 ? 4 : 0);
    final top = safe.top + 12;
    final maxHeight = math.max(200.0, size.height - top - bottom);
    final reduced = context.reduceMotion;
    final palette = Theme.of(context).brightness == Brightness.dark ? VaultPalette.dark : VaultPalette.light;

    final surface = VaultSurface(
      radius: VaultShape.sheet,
      palette: palette,
      child: child,
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(side + safe.left, top, side + safe.right, bottom),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: VaultShape.maxWidth, maxHeight: maxHeight),
          child: LayoutBuilder(
            builder: (context, box) {
              return ValueListenableBuilder<bool>(
                valueListenable: route._tracking,
                builder: (context, tracking, child) => AnimatedBuilder(
                  animation: route.animation!,
                  child: child,
                  builder: (context, child) {
                    final raw = route.animation!.value;
                    final forward = route.animation!.status != AnimationStatus.reverse;
                    final v = reduced
                        ? 1.0
                        : tracking
                        ? raw
                        : (forward ? VaultMotion.spring : Curves.easeInCubic).transform(raw);
                    return _MeasureHeight(
                      onHeight: (h) => route._height = h + bottom,
                      child: FractionalTranslation(
                        translation: Offset(0, (1 - v) * 1.08),
                        child: Transform.scale(
                          scale: reduced || tracking ? 1 : 0.94 + 0.06 * v.clamp(0.0, 1.06),
                          alignment: Alignment.bottomCenter,
                          child: Opacity(opacity: reduced ? raw : (raw * 3).clamp(0.0, 1.0), child: child),
                        ),
                      ),
                    );
                  },
                ),
                child: VaultSheetDrag(
                  update: route._dragUpdate,
                  end: route._dragEnd,
                  child: Semantics(
                    scopesRoute: true,
                    namesRoute: true,
                    explicitChildNodes: true,
                    label: MaterialLocalizations.of(context).bottomSheetLabel,
                    child: MediaQuery.removePadding(
                      context: context,
                      removeTop: true,
                      removeBottom: true,
                      removeLeft: true,
                      removeRight: true,
                      child: MediaQuery.removeViewInsets(context: context, removeBottom: true, child: surface),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Reports its child's laid-out height after layout.
class _MeasureHeight extends SingleChildRenderObjectWidget {
  const _MeasureHeight({required this.onHeight, super.child});

  final ValueChanged<double> onHeight;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderMeasure(onHeight);

  @override
  void updateRenderObject(BuildContext context, _RenderMeasure renderObject) => renderObject.onHeight = onHeight;
}

class _RenderMeasure extends RenderProxyBox {
  _RenderMeasure(this.onHeight);

  ValueChanged<double> onHeight;

  @override
  void performLayout() {
    super.performLayout();
    onHeight(size.height);
  }
}

/// The floating card itself: Vault surface, lit top edge, deep soft shadow,
/// and the Vault theme for everything inside.
class VaultSurface extends StatelessWidget {
  const VaultSurface({super.key, required this.child, required this.radius, required this.palette});

  final Widget child;
  final double radius;
  final VaultPalette palette;

  @override
  Widget build(BuildContext context) {
    final br = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: br, boxShadow: palette.float),
      child: ClipRRect(
        borderRadius: br,
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            borderRadius: br,
            border: Border.all(color: palette.isDark ? palette.hairline : palette.hairline.withValues(alpha: 0.7)),
          ),
          child: Material(
            color: palette.surface,
            child: Stack(
              children: [
                VaultScope(
                  palette: palette,
                  child: Theme(data: VaultTheme.of(palette), child: child),
                ),
                // Light falling on the top edge.
                Positioned(
                  left: radius,
                  right: radius,
                  top: 0,
                  height: 1,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            palette.highlight.withValues(alpha: 0),
                            palette.highlight,
                            palette.highlight.withValues(alpha: 0),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Route for a centred Vault dialog: rises a little and lands on a spring
/// while the page blurs behind it.
class VaultDialogRoute<T> extends PopupRoute<T> {
  VaultDialogRoute({required this.builder, this.dismissible = true, this.capturedThemes, super.settings});

  final WidgetBuilder builder;
  final bool dismissible;
  final CapturedThemes? capturedThemes;

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => false;

  @override
  String? get barrierLabel => null;

  @override
  Duration get transitionDuration => VaultMotion.dialogIn;

  @override
  Duration get reverseTransitionDuration => VaultMotion.dialogOut;

  @override
  Widget buildModalBarrier() => _VaultBarrier(
    animation: animation!,
    dismissible: dismissible,
    onDismiss: () => navigator?.maybePop(),
  );

  @override
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation) {
    final content = Builder(builder: builder);
    final themed = capturedThemes?.wrap(content) ?? content;
    final palette = Theme.of(context).brightness == Brightness.dark ? VaultPalette.dark : VaultPalette.light;
    final safe = context.safeInsets;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20 + safe.left, safe.top + 20, 20 + safe.right, math.max(safe.bottom, keyboard) + 20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Semantics(
            scopesRoute: true,
            namesRoute: true,
            explicitChildNodes: true,
            label: MaterialLocalizations.of(context).dialogLabel,
            child: MediaQuery.removePadding(
              context: context,
              removeTop: true,
              removeBottom: true,
              child: VaultSurface(radius: VaultShape.dialog, palette: palette, child: themed),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (context.reduceMotion) return FadeTransition(opacity: animation, child: child);
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        final forward = animation.status != AnimationStatus.reverse;
        final raw = animation.value;
        final v = (forward ? VaultMotion.spring : VaultMotion.exit).transform(raw);
        return Opacity(
          opacity: (raw * (forward ? 2.4 : 1.4)).clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, 28 * (1 - v)),
            child: Transform.scale(scale: forward ? 0.9 + 0.1 * v : 0.96 + 0.04 * v, child: child),
          ),
        );
      },
    );
  }
}

/// Fires a light haptic; centralised so Vault feedback stays consistent.
void vaultHaptic([bool strong = false]) => strong ? HapticFeedback.mediumImpact() : HapticFeedback.selectionClick();
