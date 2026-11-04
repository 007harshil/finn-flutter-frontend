import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../agent/agent.dart' show AgentModePanel, AgentOrb, agentModeProvider, voiceInputProvider, VoicePhase;
import '../../design_system/design_system.dart';
import '../../features/accounts/presentation/transfer_form_sheet.dart';
import '../../features/more/presentation/more_drawer.dart';
import '../../kit/kit.dart' show FinnMenuItem, LedgerContext, Rad, showFinnActionMenu;
import '../di/core_providers.dart';
import '../di/data_providers.dart';
import '../router/routes.dart';
import 'app_drawer.dart';

class _Tab {
  const _Tab(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// Tabs, by shell branch index. Branch 4 (`/more`: profile, loans,
/// settings…) has no tab: it opens from the side drawer.
const _tabs = [
  _Tab('Home', LucideIcons.house),
  _Tab('Activity', LucideIcons.receiptText),
  _Tab('Budgets', LucideIcons.chartPie),
  _Tab('Goals', LucideIcons.target),
];

/// The bar has five equal slots: Home, Activity, Add, Budgets, Goals.
const _slotCount = 5;
const _addSlot = 2;

/// Tab (branch) shown in bar slot [s]; the add button takes the centre.
int _tabOf(int s) => s < _addSlot ? s : s - 1;

/// Application shell: a solid bottom navigation bar on phones (with "add"
/// at its centre, always one thumb-tap away), a navigation rail on wide
/// screens, the side drawer (menu) and the full-screen agent experience
/// above everything. The agent opens from the FiNN mark in each tab's
/// header (and from the rail).
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  final _scaffold = GlobalKey<ScaffoldState>();

  bool get _haptics => ref.read(settingsProvider).hapticsEnabled;

  void _openDrawer() {
    if (ref.read(agentModeProvider)) return;
    if (_haptics) HapticFeedback.selectionClick();
    FocusManager.instance.primaryFocus?.unfocus();
    _scaffold.currentState?.openDrawer();
  }

  void _select(int index) {
    if (ref.read(agentModeProvider)) return;
    if (_haptics) HapticFeedback.selectionClick();
    widget.shell.goBranch(index, initialLocation: index == widget.shell.currentIndex);
  }

  void _toggleAgent() {
    if (_haptics) HapticFeedback.mediumImpact();
    FocusManager.instance.primaryFocus?.unfocus();
    ref.read(agentModeProvider.notifier).toggle();
  }

  void _add() {
    if (ref.read(agentModeProvider)) return;
    context.push(AppRoutes.newTransaction());
  }

  Future<void> _addMenu() async {
    if (ref.read(agentModeProvider)) return;
    final pick = await showFinnActionMenu<String>(
      context,
      title: 'Add',
      items: const [
        FinnMenuItem(value: 'transaction', label: 'Add transaction', icon: LucideIcons.plus),
        FinnMenuItem(value: 'transfer', label: 'Transfer', icon: LucideIcons.arrowLeftRight),
        FinnMenuItem(value: 'agent', label: 'Ask FiNN', icon: LucideIcons.sparkles),
      ],
    );
    if (!mounted) return;
    switch (pick) {
      case 'transaction':
        _add();
      case 'transfer':
        showTransferSheet(context);
      case 'agent':
        _toggleAgent();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final index = widget.shell.currentIndex;
    final wide = MediaQuery.sizeOf(context).width >= 840;
    final agentMode = ref.watch(agentModeProvider);
    final listening = ref.watch(voiceInputProvider.select((v) => v.phase == VoicePhase.listening));
    final unread = ref.watch(unreadAlertCountProvider);

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
        openAgent: _toggleAgent,
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
                floatingActionButton: wide ? _RailAddButton(onTap: _add, onLongPress: _addMenu) : null,
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
                            indicatorColor: context.ink.brandSoft,
                            selectedIconTheme: IconThemeData(color: c.primary),
                            unselectedIconTheme: IconThemeData(color: c.textSecondary),
                            selectedLabelTextStyle: context.type.small.copyWith(
                              color: c.primary,
                              fontWeight: FontWeight.w700,
                            ),
                            unselectedLabelTextStyle: context.type.small,
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
                          Expanded(child: ResponsiveCenter(child: widget.shell)),
                        ],
                      )
                    : widget.shell,
                bottomNavigationBar: wide
                    ? null
                    : _BottomBar(
                        index: index,
                        unread: unread,
                        onSelect: _select,
                        onAdd: _add,
                        onAddLongPress: _addMenu,
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

/// Solid bottom navigation with five equal slots: Home, Activity, a teal
/// "add" button at the true centre, Budgets and Goals. Labels are always
/// shown and the bar never hides, so it is always where people expect it.
class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.index,
    required this.unread,
    required this.onSelect,
    required this.onAdd,
    required this.onAddLongPress,
  });

  /// Current shell branch; beyond the tabs (drawer pages) no tab is active.
  final int index;
  final int unread;
  final ValueChanged<int> onSelect;
  final VoidCallback onAdd;
  final VoidCallback onAddLongPress;

  static const height = 68.0;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final inset = MediaQuery.paddingOf(context).bottom;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.line)),
      ),
      child: Padding(
        padding: EdgeInsets.only(bottom: inset),
        child: SizedBox(
          height: height,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Row(
                children: [
                  for (var s = 0; s < _slotCount; s++)
                    Expanded(
                      child: s == _addSlot
                          ? _AddButton(onTap: onAdd, onLongPress: onAddLongPress)
                          : _NavTab(
                              tab: _tabs[_tabOf(s)],
                              selected: _tabOf(s) == index,
                              badge: s == 0 ? unread : 0,
                              onTap: () => onSelect(_tabOf(s)),
                            ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One tab: icon in a soft teal pill when selected, label underneath.
class _NavTab extends StatelessWidget {
  const _NavTab({required this.tab, required this.selected, required this.onTap, this.badge = 0});

  final _Tab tab;
  final bool selected;
  final VoidCallback onTap;
  final int badge;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final t = context.type;
    final motion = context.motion;
    final color = selected ? c.brand : c.inkSoft;
    Widget icon = Icon(tab.icon, size: 22, color: color);
    if (badge > 0) icon = CountBadge(count: badge, child: icon);
    return Semantics(
      selected: selected,
      button: true,
      label: badge > 0 ? '${tab.label}, $badge alerts' : tab.label,
      excludeSemantics: true,
      child: InkResponse(
        onTap: onTap,
        containedInkWell: true,
        highlightShape: BoxShape.rectangle,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: motion.normal,
              curve: motion.standard,
              width: selected ? 56 : 40,
              height: 30,
              decoration: BoxDecoration(
                color: selected ? c.brandSoft : Colors.transparent,
                borderRadius: Rad.pill,
              ),
              alignment: Alignment.center,
              child: icon,
            ),
            const SizedBox(height: 4),
            Text(
              tab.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.small.copyWith(
                fontSize: 12.5,
                color: selected ? c.ink : c.inkSoft,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                fontVariations: [FontVariation.weight(selected ? 720 : 540)],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The centre "add" button: tap records a transaction, long-press offers
/// a transfer or asking FiNN.
class _AddButton extends ConsumerWidget {
  const _AddButton({required this.onTap, required this.onLongPress});

  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.ink;
    return Center(
      child: Tooltip(
        message: 'Add transaction',
        child: Semantics(
          button: true,
          label: 'Add transaction',
          excludeSemantics: true,
          child: PressableScale(
            haptic: ref.watch(settingsProvider.select((s) => s.hapticsEnabled)),
            onTap: onTap,
            onLongPress: onLongPress,
            child: Container(
              width: 56,
              height: 44,
              decoration: BoxDecoration(
                color: c.brand,
                borderRadius: Rad.rMd,
                boxShadow: c.isDark
                    ? null
                    : [BoxShadow(color: c.brand.withValues(alpha: 0.28), blurRadius: 10, offset: const Offset(0, 3))],
              ),
              child: Icon(LucideIcons.plus, color: c.onBrand, size: 26),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Add" on wide screens, where the rail replaces the bottom bar.
class _RailAddButton extends StatelessWidget {
  const _RailAddButton({required this.onTap, required this.onLongPress});

  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    return Tooltip(
      message: 'Add transaction',
      child: Semantics(
        button: true,
        label: 'Add transaction',
        child: PressableScale(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Container(
            width: Dimens.fabSize,
            height: Dimens.fabSize,
            decoration: BoxDecoration(color: c.brand, borderRadius: Rad.rLg, boxShadow: Elevation.md),
            child: Icon(LucideIcons.plus, color: c.onBrand, size: 26),
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

/// The animated agent orb button at the top of the rail (wide screens).
class _AgentNavButton extends StatelessWidget {
  const _AgentNavButton({
    required this.active,
    required this.listening,
    required this.size,
    required this.onTap,
  });

  final bool active;
  final bool listening;
  final double size;
  final VoidCallback onTap;

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
          child: AgentOrb(size: size, active: active, listening: listening),
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
