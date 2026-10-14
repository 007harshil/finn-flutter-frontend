import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../motion/motion.dart';
import 'luxe_motion.dart';
import 'luxe_tokens.dart';
import 'luxe_widgets.dart';

/// Opens a Luxe bottom sheet: paper surface, deep rounded top, a slow
/// "arrive" rise and a quicker exit. Pair with [LuxeSheet].
Future<T?> showLuxeSheet<T>(BuildContext context, {required WidgetBuilder builder, bool dismissible = true}) {
  final p = context.luxe;
  final reduced = context.reduceMotion;
  return showModalBottomSheet<T>(
    context: context,
    builder: builder,
    isScrollControlled: true,
    useSafeArea: true,
    useRootNavigator: true,
    isDismissible: dismissible,
    backgroundColor: p.paper,
    barrierColor: p.scrim,
    elevation: 0,
    clipBehavior: Clip.antiAlias,
    constraints: const BoxConstraints(maxWidth: 640),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
    sheetAnimationStyle: AnimationStyle(
      duration: reduced ? Duration.zero : const Duration(milliseconds: 520),
      reverseDuration: reduced ? Duration.zero : const Duration(milliseconds: 280),
      curve: LuxeCurves.arrive,
      reverseCurve: LuxeCurves.leave,
    ),
  );
}

/// Sheet layout: handle, eyebrow + serif title, close, scrolling body and a
/// footer pinned above the keyboard.
class LuxeSheet extends StatelessWidget {
  const LuxeSheet({
    super.key,
    required this.child,
    this.title,
    this.eyebrow,
    this.description,
    this.footer,
    this.bodyPadding = const EdgeInsets.fromLTRB(24, 8, 24, 24),
  });

  final Widget child;
  final String? title;
  final String? eyebrow;
  final String? description;
  final Widget? footer;
  final EdgeInsetsGeometry bodyPadding;

  @override
  Widget build(BuildContext context) {
    final p = context.luxe;
    final t = context.lt;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final screen = MediaQuery.sizeOf(context).height;
    final maxHeight = (screen * 0.9 - keyboard).clamp(180.0, screen);
    final foot = footer;
    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 10),
            Center(
              child: ExcludeSemantics(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(color: p.lineStrong, borderRadius: BorderRadius.circular(2)),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 14, 12, 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (eyebrow != null) ...[
                            Text(eyebrow!.toUpperCase(), style: t.eyebrow),
                            const SizedBox(height: 6),
                          ],
                          if (title != null)
                            Semantics(header: true, child: Text(title!, style: t.title.copyWith(fontSize: 26))),
                          if (description != null) ...[
                            const SizedBox(height: 6),
                            Text(description!, style: t.bodySoft),
                          ],
                        ],
                      ),
                    ),
                  ),
                  LuxeIconButton(
                    icon: LucideIcons.x,
                    tooltip: 'Close',
                    style: LuxeIconStyle.ghost,
                    size: 40,
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: bodyPadding,
                child: foot == null ? SafeArea(top: false, child: child) : child,
              ),
            ),
            if (foot != null)
              DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: p.line)),
                ),
                child: SafeArea(
                  top: false,
                  minimum: const EdgeInsets.only(bottom: 14),
                  child: Padding(padding: const EdgeInsets.fromLTRB(24, 14, 24, 0), child: foot),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// One choice of [showLuxeMenu].
class LuxeMenuItem<T> {
  const LuxeMenuItem({
    required this.value,
    required this.label,
    required this.icon,
    this.hint,
    this.destructive = false,
  });
  final T value;
  final String label;
  final IconData icon;
  final String? hint;
  final bool destructive;
}

/// Contextual actions (long-press menus) as a sheet of large, staggered rows.
Future<T?> showLuxeMenu<T>(
  BuildContext context, {
  required String title,
  String? eyebrow,
  required List<LuxeMenuItem<T>> items,
}) {
  return showLuxeSheet<T>(
    context,
    builder: (context) {
      final p = context.luxe;
      final t = context.lt;
      return LuxeSheet(
        title: title,
        eyebrow: eyebrow,
        bodyPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < items.length; i++)
              Reveal(
                index: i,
                offset: 10,
                blur: 0,
                duration: LuxeDurations.base,
                child: Squish(
                  key: ValueKey('luxe-menu:${items[i].value}'),
                  onTap: () => Navigator.of(context).pop(items[i].value),
                  scale: 0.98,
                  semanticLabel: items[i].label,
                  excludeSemantics: true,
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 60),
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(color: p.canvas, borderRadius: BorderRadius.circular(18)),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: items[i].destructive ? p.tint(p.negative) : p.paper,
                            shape: BoxShape.circle,
                            border: Border.all(color: p.line),
                          ),
                          child: Icon(items[i].icon, size: 18, color: items[i].destructive ? p.negative : p.ink),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(items[i].label, style: t.heading.c(items[i].destructive ? p.negative : p.ink)),
                              if (items[i].hint != null) Text(items[i].hint!, style: t.caption),
                            ],
                          ),
                        ),
                        Icon(LucideIcons.chevronRight, size: 16, color: p.inkMute),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
}
