import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/shell/app_drawer.dart';
import '../../design_system/design_system.dart';
import '../../design_system/luxe/luxe.dart';

/// Frame shared by the Luxe money screens: lit canvas with scroll parallax,
/// one scroll view, and a frosted compact title that fades in once the big
/// title has scrolled away (so the user always knows where they are).
class LuxePage extends StatefulWidget {
  const LuxePage({
    super.key,
    required this.storageKey,
    required this.compactTitle,
    required this.slivers,
    this.onNotification,
  });

  final String storageKey;
  final String compactTitle;
  final List<Widget> slivers;
  final bool Function(ScrollNotification n)? onNotification;

  @override
  State<LuxePage> createState() => _LuxePageState();
}

class _LuxePageState extends State<LuxePage> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.luxe;
    final view = CustomScrollView(
      key: PageStorageKey<String>(widget.storageKey),
      controller: _scroll,
      slivers: [
        ...widget.slivers,
        SliverToBoxAdapter(child: SizedBox(height: context.bottomClearance + 12)),
      ],
    );
    final on = widget.onNotification;
    return Scaffold(
      backgroundColor: p.canvas,
      body: Stack(
        fit: StackFit.expand,
        children: [
          LuxeBackdrop(scroll: _scroll),
          SafeArea(
            bottom: false,
            child: on == null ? view : NotificationListener<ScrollNotification>(onNotification: on, child: view),
          ),
          _CompactTitle(scroll: _scroll, title: widget.compactTitle),
        ],
      ),
    );
  }
}

class _CompactTitle extends StatelessWidget {
  const _CompactTitle({required this.scroll, required this.title});

  final ScrollController scroll;
  final String title;

  @override
  Widget build(BuildContext context) {
    final p = context.luxe;
    final top = MediaQuery.paddingOf(context).top;
    return Positioned(
      left: 0,
      right: 0,
      top: 0,
      child: IgnorePointer(
        child: ExcludeSemantics(
          child: AnimatedBuilder(
            animation: scroll,
            builder: (context, _) {
              final offset = scroll.hasClients && scroll.positions.length == 1 ? scroll.offset : 0.0;
              final t = ((offset - 90) / 50).clamp(0.0, 1.0);
              if (t == 0) return const SizedBox.shrink();
              return ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 18 * t, sigmaY: 18 * t),
                  child: Container(
                    height: top + 48,
                    padding: EdgeInsets.only(top: top),
                    decoration: BoxDecoration(
                      color: p.canvas.withValues(alpha: 0.78 * t),
                      border: Border(
                        bottom: BorderSide(color: p.line.withValues(alpha: t)),
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Opacity(
                      opacity: t,
                      child: Transform.translate(
                        offset: Offset(0, 6 * (1 - t)),
                        child: Text(title, style: context.lt.heading.copyWith(fontSize: 15)),
                      ),
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

/// A full-width box sliver, centred and padded like the rest of the page.
Widget luxeBox(Widget child, {double top = 0, double bottom = 0, double side = LuxeSpace.gutter}) => SliverToBoxAdapter(
  child: ResponsiveCenter(padding: EdgeInsets.fromLTRB(side, top, side, bottom), child: child),
);

/// Opens the side drawer (profile, loans, settings…). Hidden when the
/// screen is shown outside the shell.
class LuxeMenuButton extends StatelessWidget {
  const LuxeMenuButton({super.key});

  @override
  Widget build(BuildContext context) {
    final open = AppDrawerScope.maybeOf(context);
    if (open == null) return const SizedBox.shrink();
    return LuxeIconButton(key: const ValueKey('app-menu'), icon: LucideIcons.menu, tooltip: 'Menu', onPressed: open);
  }
}

/// Header row shared by the tabs: menu on the left, actions on the right.
class LuxeTopBar extends StatelessWidget {
  const LuxeTopBar({super.key, this.actions = const []});

  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: Row(
        children: [
          const LuxeMenuButton(),
          const Spacer(),
          for (var i = 0; i < actions.length; i++) ...[if (i > 0) const SizedBox(width: 4), actions[i]],
        ],
      ),
    );
  }
}
