import 'dart:math' as math;
import 'dart:ui' show ImageFilter, lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../agent/agent.dart' show AgentModePanel, AgentOrb, agentModeProvider, voiceInputProvider, VoicePhase;
import '../../design_system/design_system.dart';
import '../../features/more/presentation/more_drawer.dart';
import '../di/core_providers.dart';
import '../di/data_providers.dart';
import '../router/routes.dart';
import 'app_drawer.dart';

class _Tab {
  const _Tab(this.label, this.icon, this.activeIcon);
  final String label;
  final IconData icon;
  final IconData activeIcon;
}

/// Tabs, by shell branch index. Branch 4 (`/more`: profile, loans,
/// settings…) has no tab: it opens from the side drawer.
const _tabs = [
  _Tab('Home', LucideIcons.layoutDashboard, LucideIcons.layoutDashboard),
  _Tab('Activity', LucideIcons.arrowLeftRight, LucideIcons.arrowLeftRight),
  _Tab('Budgets', LucideIcons.chartPie, LucideIcons.chartPie),
  _Tab('Goals', LucideIcons.target, LucideIcons.target),
];

/// The bar has five equal slots: Home, Activity, Agent, Budgets, Goals.
const _slotCount = 5;
const _agentSlot = 2;

/// Bar slot of tab (branch) [i]; the agent takes the centre slot.
int _slotOf(int i) => i < _agentSlot ? i : i + 1;

/// Application shell: floating bottom navigation on phones, a navigation rail on
/// wide screens, the side drawer (menu), the persistent "add transaction"
/// action and the full-screen agent experience above everything.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  final _chromeVisible = ValueNotifier<bool>(true);
  final _scaffold = GlobalKey<ScaffoldState>();

  void _openDrawer() {
    if (ref.read(agentModeProvider)) return;
    if (ref.read(settingsProvider).hapticsEnabled) HapticFeedback.selectionClick();
    FocusManager.instance.primaryFocus?.unfocus();
    _scaffold.currentState?.openDrawer();
  }

  @override
  void dispose() {
    _chromeVisible.dispose();
    super.dispose();
  }

  void _select(int index) {
    if (ref.read(agentModeProvider)) return;
    if (ref.read(settingsProvider).hapticsEnabled) HapticFeedback.selectionClick();
    _chromeVisible.value = true;
    widget.shell.goBranch(index, initialLocation: index == widget.shell.currentIndex);
  }

  void _toggleAgent() {
    if (ref.read(settingsProvider).hapticsEnabled) HapticFeedback.mediumImpact();
    _chromeVisible.value = true;
    FocusManager.instance.primaryFocus?.unfocus();
    ref.read(agentModeProvider.notifier).toggle();
  }

  /// Scroll distance travelled in the current direction (+ down, - up).
  double _scrollRun = 0;

  /// Distance in one direction that toggles the bar; small enough to feel
  /// instant, large enough to ignore jitter.
  static const _toggleDistance = 8.0;

  bool _onScroll(ScrollUpdateNotification n) {
    final m = n.metrics;
    if (n.depth != 0 || m.axis != Axis.vertical) return false;
    if (m.pixels <= m.minScrollExtent) {
      _scrollRun = 0;
      _chromeVisible.value = true;
      return false;
    }
    // Ignore bottom overscroll bounce, which reports upward deltas.
    if (m.pixels >= m.maxScrollExtent) return false;
    final delta = n.scrollDelta ?? 0;
    if (delta == 0) return false;
    if (delta.sign != _scrollRun.sign) _scrollRun = 0;
    _scrollRun += delta;
    if (_scrollRun > _toggleDistance) {
      _chromeVisible.value = false;
    } else if (_scrollRun < -_toggleDistance) {
      _chromeVisible.value = true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final index = widget.shell.currentIndex;
    final wide = MediaQuery.sizeOf(context).width >= 840;
    final agentMode = ref.watch(agentModeProvider);
    final listening = ref.watch(voiceInputProvider.select((v) => v.phase == VoicePhase.listening));
    final showFab = (index == 0 || index == 1) && !agentMode;
    final unread = ref.watch(unreadAlertCountProvider);

    final body = NotificationListener<ScrollUpdateNotification>(onNotification: _onScroll, child: widget.shell);

    final fab = showFab
        ? ValueListenableBuilder<bool>(
            valueListenable: _chromeVisible,
            builder: (context, visible, _) => AnimatedSlide(
              offset: visible ? Offset.zero : const Offset(0, 2),
              duration: context.motion.normal,
              curve: Curves2.standard,
              child: AnimatedOpacity(
                opacity: visible ? 1 : 0,
                duration: context.motion.fast,
                child: _AddFab(enabled: visible),
              ),
            ),
          )
        : null;

    return PopScope(
      canPop: index == 0 && !agentMode,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (agentMode) {
          ref.read(agentModeProvider.notifier).close();
        } else if (index != 0) {
          _select(0);
        }
      },
      child: AppDrawerScope(
        open: _openDrawer,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _AgentLock(
              locked: agentMode,
              child: Scaffold(
                key: _scaffold,
                backgroundColor: c.background,
                drawer: const MoreDrawer(),
                drawerEnableOpenDragGesture: !agentMode,
                drawerScrimColor: c.scrim,
                floatingActionButton: fab,
                body: wide
                    ? Row(
                        children: [
                          NavigationRail(
                            leading: Padding(
                              padding: const EdgeInsets.symmetric(vertical: Space.x3),
                              child: _AgentNavButton(
                                active: agentMode,
                                listening: listening,
                                size: 48,
                                onTap: _toggleAgent,
                              ),
                            ),
                            selectedIndex: index < _tabs.length ? index : null,
                            onDestinationSelected: _select,
                            trailing: Padding(
                              padding: const EdgeInsets.only(top: Space.x3),
                              child: FinnIconButton(
                                icon: LucideIcons.panelLeft,
                                tooltip: 'Menu',
                                onPressed: _openDrawer,
                              ),
                            ),
                            labelType: NavigationRailLabelType.all,
                            backgroundColor: c.surface,
                            indicatorColor: c.surfaceMuted,
                            selectedIconTheme: IconThemeData(color: c.primary),
                            unselectedIconTheme: IconThemeData(color: c.textSecondary),
                            selectedLabelTextStyle: context.text.micro.copyWith(
                              color: c.primary,
                              fontWeight: FontWeight.w800,
                            ),
                            unselectedLabelTextStyle: context.text.micro.copyWith(color: c.textSecondary),
                            destinations: [
                              for (var i = 0; i < _tabs.length; i++)
                                NavigationRailDestination(
                                  icon: _badged(Icon(_tabs[i].icon), i == 0 ? unread : 0),
                                  label: Text(_tabs[i].label),
                                  disabled: agentMode,
                                ),
                            ],
                          ),
                          VerticalDivider(width: 1, color: c.border),
                          Expanded(child: ResponsiveCenter(child: body)),
                        ],
                      )
                    : body,
                // Content scrolls behind the floating, translucent bar.
                extendBody: !wide,
                bottomNavigationBar: wide
                    ? null
                    : ValueListenableBuilder<bool>(
                        valueListenable: _chromeVisible,
                        builder: (context, visible, _) => _FloatingNavBar(
                          index: index,
                          onSelect: _select,
                          unread: unread,
                          collapsed: !visible && !agentMode,
                          onExpand: () => _chromeVisible.value = true,
                          agentMode: agentMode,
                          listening: listening,
                          onAgent: _toggleAgent,
                        ),
                      ),
              ),
            ),
            _AgentOverlay(active: agentMode),
          ],
        ),
      ),
    );
  }

  Widget _badged(Widget icon, int count) => count == 0 ? icon : CountBadge(count: count, child: icon);
}

/// Geometry of the floating bar at a given collapse progress
/// (0 = expanded, 1 = compact). The active tab sits in a raised bubble
/// that the bar's outline flows around with smooth fillets.
class _NavMetrics {
  _NavMetrics(double t)
    : barTop = lerpDouble(20, 12, t)!,
      barHeight = lerpDouble(64, 48, t)!,
      bubble = lerpDouble(50, 38, t)!,
      ring = lerpDouble(6, 4, t)!,
      fillet = lerpDouble(10, 8, t)!;

  /// Distance from the top of the raised bump to the top of the bar body.
  final double barTop;
  final double barHeight;
  final double bubble;

  /// Gap between the bubble and the bump outline around it.
  final double ring;
  final double fillet;

  static final expanded = _NavMetrics(0);

  double get height => barTop + barHeight;
  double get bumpRadius => bubble / 2 + ring;

  /// Pill-shaped bar unioned with a bump of radius r (top at y = 0) for
  /// each `(cx, r)` in [bumps], joined by concave fillets so the outline
  /// reads as one continuous surface.
  Path shape(double width, List<(double, double)> bumps) {
    var path = Path()..addRRect(RRect.fromLTRBR(0, barTop, width, height, Radius.circular(barHeight / 2)));
    for (final (cx, r) in bumps) {
      path = Path.combine(PathOperation.union, path, _bump(cx, r));
    }
    return path;
  }

  Path _bump(double cx, double r) {
    final cy = r;
    final f = fillet;
    final dy = cy - (barTop - f);
    final dx = math.sqrt(math.pow(r + f, 2) - dy * dy);
    final k = r / (r + f);
    final left = Offset(cx - dx * k, cy - dy * k);
    final right = Offset(cx + dx * k, cy - dy * k);
    final bump = Path()
      ..moveTo(cx - dx, barTop)
      ..arcToPoint(left, radius: Radius.circular(f), clockwise: false)
      ..arcToPoint(right, radius: Radius.circular(r))
      ..arcToPoint(Offset(cx + dx, barTop), radius: Radius.circular(f), clockwise: false)
      ..lineTo(cx + dx, barTop + barHeight / 2)
      ..lineTo(cx - dx, barTop + barHeight / 2)
      ..close();
    return bump;
  }
}

/// Floating, frosted bottom navigation with five equal slots: Home,
/// Activity, the agent orb at the true centre, Budgets and Goals. While
/// content scrolls down it shrinks into a compact pill (labels hidden) so
/// it stays out of the way; scrolling up or tapping it restores the bar.
class _FloatingNavBar extends StatelessWidget {
  const _FloatingNavBar({
    required this.index,
    required this.onSelect,
    required this.unread,
    required this.collapsed,
    required this.onExpand,
    required this.agentMode,
    required this.listening,
    required this.onAgent,
  });

  /// Current shell branch; beyond the tabs (drawer pages) no tab is active.
  final int index;
  final ValueChanged<int> onSelect;
  final int unread;
  final bool collapsed;
  final VoidCallback onExpand;
  final bool agentMode;
  final bool listening;
  final VoidCallback onAgent;

  static const _maxWidth = 520.0;
  static const _compactWidthFactor = 0.72;
  static const _bottomGap = Space.x3;

  /// Height reserved at the bottom of the screen for the bar.
  static double slotHeight(double bottomInset) => _NavMetrics.expanded.height + _bottomGap + bottomInset;

  bool get _hasActiveTab => index < _tabs.length;

  @override
  Widget build(BuildContext context) {
    final motion = context.motion;
    final inset = MediaQuery.paddingOf(context).bottom;
    // Fixed slot height keeps the body's bottom padding stable while the
    // bar animates, so scrolling content never relayouts mid-animation.
    return SizedBox(
      height: slotHeight(inset),
      child: Padding(
        padding: EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, _bottomGap + inset),
        child: LayoutBuilder(
          builder: (context, box) {
            final full = math.min(box.maxWidth, _maxWidth);
            return TweenAnimationBuilder<double>(
              tween: Tween(end: collapsed ? 1 : 0),
              // Quick so the bar tracks the scroll direction immediately.
              duration: motion.reduced ? Duration.zero : const Duration(milliseconds: 200),
              curve: Curves2.standard,
              builder: (context, t, _) => TweenAnimationBuilder<double>(
                // With no active tab the bubble slides under the orb and fades.
                tween: Tween(end: (_hasActiveTab ? _slotOf(index) : _agentSlot).toDouble()),
                duration: motion.slow,
                curve: Curves2.emphasized,
                builder: (context, pos, _) => TweenAnimationBuilder<double>(
                  tween: Tween(end: _hasActiveTab ? 1 : 0),
                  duration: motion.normal,
                  curve: Curves2.standard,
                  builder: (context, presence, _) => Align(
                    alignment: Alignment.bottomCenter,
                    child: _bar(context, t, pos, presence, lerpDouble(full, full * _compactWidthFactor, t)!),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _bar(BuildContext context, double t, double pos, double presence, double width) {
    final c = context.colors;
    final m = _NavMetrics(t);
    final slot = width / _slotCount;
    final cx = slot * (pos + 0.5);
    final orbCx = slot * (_agentSlot + 0.5);
    // The orb and the active bubble are the same size, in equal slots.
    final shape = m.shape(width, [(cx, m.bumpRadius), (orbCx, m.bumpRadius)]);
    final active = _hasActiveTab ? _tabs[index] : null;
    return GestureDetector(
      behavior: collapsed ? HitTestBehavior.opaque : HitTestBehavior.deferToChild,
      onTap: collapsed ? onExpand : null,
      child: IgnorePointer(
        ignoring: collapsed,
        child: SizedBox(
          width: width,
          height: m.height,
          child: CustomPaint(
            painter: _NavShadowPainter(shape, dark: c.isDark),
            foregroundPainter: _NavOutlinePainter(shape, c.border),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: ClipPath(
                    clipper: _PathClipper(shape),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                      child: ColoredBox(color: c.surface.withValues(alpha: c.isDark ? 0.7 : 0.76)),
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: m.barTop,
                  height: m.barHeight,
                  child: Row(
                    children: [
                      for (var s = 0; s < _slotCount; s++)
                        SizedBox(
                          width: slot,
                          child: s == _agentSlot
                              ? _AgentNavLabel(collapse: t, active: agentMode)
                              : _item(s < _agentSlot ? s : s - 1, t),
                        ),
                    ],
                  ),
                ),
                if (active != null || presence > 0)
                  Positioned(
                    left: cx - m.bubble / 2,
                    top: m.ring,
                    width: m.bubble,
                    height: m.bubble,
                    child: IgnorePointer(
                      ignoring: active == null,
                      child: Opacity(
                        opacity: presence.clamp(0.0, 1.0),
                        child: _ActiveBubble(
                          tab: active ?? _tabs.first,
                          badge: index == 0 ? unread : 0,
                          iconSize: lerpDouble(22, 18, t)!,
                          onTap: () => onSelect(index),
                        ),
                      ),
                    ),
                  ),
                // The agent orb, raised at the true centre.
                Positioned(
                  left: orbCx - m.bubble / 2,
                  top: m.ring,
                  width: m.bubble,
                  height: m.bubble,
                  child: _AgentNavButton(
                    active: agentMode,
                    listening: listening,
                    size: m.bubble,
                    onTap: onAgent,
                    attentionKey: index,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _item(int i, double t) =>
      _NavItem(tab: _tabs[i], selected: i == index, badge: i == 0 ? unread : 0, collapse: t, onTap: () => onSelect(i));
}

/// The "Agent" caption under the raised orb, laid out exactly like a tab
/// label so all five slots line up.
class _AgentNavLabel extends StatelessWidget {
  const _AgentNavLabel({required this.collapse, required this.active});

  final double collapse;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final labelVisibility = 1 - collapse;
    return IgnorePointer(
      child: ExcludeSemantics(
        child: Padding(
          padding: EdgeInsets.only(top: Space.x1 * labelVisibility),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(height: lerpDouble(22, 20, collapse)),
              ClipRect(
                child: Align(
                  alignment: Alignment.topCenter,
                  heightFactor: labelVisibility,
                  child: Opacity(
                    opacity: labelVisibility,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        active ? 'Close' : 'Agent',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.micro.copyWith(color: c.agentEnd, fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pauses the app while agent mode is on: it ignores input, focus and
/// semantics behind the agent experience.
class _AgentLock extends StatelessWidget {
  const _AgentLock({required this.locked, required this.child});
  final bool locked;
  final Widget child;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    ignoring: locked,
    child: ExcludeFocus(
      excluding: locked,
      child: ExcludeSemantics(excluding: locked, child: child),
    ),
  );
}

/// The animated agent orb button (navigation bar centre / rail).
class _AgentNavButton extends StatelessWidget {
  const _AgentNavButton({
    required this.active,
    required this.listening,
    required this.size,
    required this.onTap,
    this.attentionKey,
  });

  final bool active;
  final bool listening;
  final double size;
  final VoidCallback onTap;

  /// Replays the orb's attention burst when it changes (the current tab).
  final Object? attentionKey;

  @override
  Widget build(BuildContext context) {
    final label = active ? 'Exit agent mode' : 'FiNN Agent';
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        toggled: active,
        label: label,
        excludeSemantics: true,
        child: PressableScale(
          onTap: onTap,
          scale: 0.9,
          child: AgentOrb(size: size, active: active, listening: listening, attentionKey: attentionKey),
        ),
      ),
    );
  }
}

/// Full-screen agent experience over the whole app (navigation included):
/// an opaque paper surface that fades in on open and out on close. The app
/// underneath is paused and receives no touches.
class _AgentOverlay extends StatefulWidget {
  const _AgentOverlay({required this.active});
  final bool active;

  @override
  State<_AgentOverlay> createState() => _AgentOverlayState();
}

class _AgentOverlayState extends State<_AgentOverlay> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
    reverseDuration: const Duration(milliseconds: 180),
    value: widget.active ? 1 : 0,
  );
  late final CurvedAnimation _curve = CurvedAnimation(
    parent: _c,
    curve: Curves2.standard,
  );

  @override
  void didUpdateWidget(_AgentOverlay old) {
    super.didUpdateWidget(old);
    if (widget.active == old.active) return;
    if (context.reduceMotion) {
      _c.value = widget.active ? 1 : 0;
    } else {
      widget.active ? _c.forward() : _c.reverse();
    }
  }

  @override
  void dispose() {
    _curve.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _curve,
      builder: (context, child) {
        final v = _curve.value.clamp(0.0, 1.0);
        if (v == 0 && !widget.active) return const SizedBox.shrink();
        return Stack(
          fit: StackFit.expand,
          children: [
            // Absorbs every touch: the app behind is paused.
            const AbsorbPointer(child: SizedBox.expand()),
            Opacity(opacity: v, child: child),
          ],
        );
      },
      child: const AgentModePanel(key: ValueKey('agent-panel')),
    );
  }
}

class _ActiveBubble extends StatelessWidget {
  const _ActiveBubble({required this.tab, required this.badge, required this.iconSize, required this.onTap});

  final _Tab tab;
  final int badge;
  final double iconSize;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget icon = Icon(tab.activeIcon, size: iconSize, color: c.primary);
    if (badge > 0) icon = CountBadge(count: badge, child: icon);
    return PressableScale(
      onTap: onTap,
      scale: 0.92,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: c.surface,
          shape: BoxShape.circle,
          border: Border.all(color: c.border),
          boxShadow: c.isDark ? Elevation.sm : Elevation.md,
        ),
        child: Center(
          child: AnimatedSwitcher(
            duration: context.motion.fast,
            transitionBuilder: (child, a) => ScaleTransition(
              scale: Tween(begin: 0.6, end: 1.0).animate(a),
              child: FadeTransition(opacity: a, child: child),
            ),
            child: KeyedSubtree(key: ValueKey(tab.label), child: icon),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.tab,
    required this.selected,
    required this.onTap,
    required this.collapse,
    this.badge = 0,
  });

  final _Tab tab;
  final bool selected;
  final VoidCallback onTap;
  final int badge;

  /// Collapse progress of the bar: labels fade and fold away as it nears 1.
  final double collapse;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = selected ? c.primary : c.textSecondary;
    final labelVisibility = 1 - collapse;
    Widget icon = Icon(tab.icon, size: lerpDouble(22, 20, collapse), color: color);
    if (badge > 0) icon = CountBadge(count: badge, child: icon);
    return Semantics(
      selected: selected,
      button: true,
      label: badge > 0 ? '${tab.label}, $badge alerts' : tab.label,
      excludeSemantics: true,
      child: PressableScale(
        onTap: onTap,
        scale: 0.94,
        child: Padding(
          padding: EdgeInsets.only(top: Space.x1 * labelVisibility),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // The active icon lives in the raised bubble instead.
              AnimatedOpacity(opacity: selected ? 0 : 1, duration: context.motion.fast, child: icon),
              ClipRect(
                child: Align(
                  alignment: Alignment.topCenter,
                  heightFactor: labelVisibility,
                  child: Opacity(
                    opacity: labelVisibility,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        tab.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.micro.copyWith(
                          color: color,
                          fontWeight: selected ? FontWeight.w900 : FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PathClipper extends CustomClipper<Path> {
  const _PathClipper(this.path);
  final Path path;

  @override
  Path getClip(Size size) => path;

  @override
  bool shouldReclip(_PathClipper oldClipper) => oldClipper.path != path;
}

/// Soft drop shadow outside the bar only, so it never muddies the
/// translucent glass.
class _NavShadowPainter extends CustomPainter {
  const _NavShadowPainter(this.path, {required this.dark});
  final Path path;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final outside = Path.combine(PathOperation.difference, Path()..addRect((Offset.zero & size).inflate(64)), path);
    canvas
      ..save()
      ..clipPath(outside)
      ..drawShadow(path, dark ? const Color(0xFF000000) : const Color(0x660F172A), dark ? 6 : 12, false)
      ..restore();
  }

  @override
  bool shouldRepaint(_NavShadowPainter old) => old.path != path || old.dark != dark;
}

class _NavOutlinePainter extends CustomPainter {
  const _NavOutlinePainter(this.path, this.color);
  final Path path;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = color.withValues(alpha: 0.8),
    );
  }

  @override
  bool shouldRepaint(_NavOutlinePainter old) => old.path != path || old.color != color;
}

class _AddFab extends ConsumerWidget {
  const _AddFab({required this.enabled});
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    return Tooltip(
      message: 'Add transaction',
      child: Semantics(
        button: true,
        label: 'Add transaction',
        child: PressableScale(
          enabled: enabled,
          haptic: ref.watch(settingsProvider.select((s) => s.hapticsEnabled)),
          onTap: () => context.push(AppRoutes.newTransaction()),
          child: Container(
            width: Dimens.fabSize,
            height: Dimens.fabSize,
            decoration: BoxDecoration(
              color: c.primary,
              shape: BoxShape.circle,
              boxShadow: c.isDark ? Elevation.md : Elevation.xl,
            ),
            child: Icon(LucideIcons.plus, color: c.onPrimary, size: 26),
          ),
        ),
      ),
    );
  }
}
