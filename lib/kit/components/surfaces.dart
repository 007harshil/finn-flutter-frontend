import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../design_system/components/layout.dart' show BottomClearanceX;
import '../tokens.dart';
import 'controls.dart';

/// A tab or detail page: paper background, one scroll view, content kept
/// in a centred column with the page gutter. Bottom padding clears the
/// navigation bar.
class LedgerPage extends StatelessWidget {
  const LedgerPage({super.key, required this.slivers, this.storageKey, this.controller, this.appBar});

  final List<Widget> slivers;

  /// Restores scroll position when switching tabs.
  final String? storageKey;
  final ScrollController? controller;

  /// For pushed detail pages; tabs put a [PageHeader] in [slivers] instead.
  final PreferredSizeWidget? appBar;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final key = storageKey;
    return Scaffold(
      backgroundColor: c.paper,
      appBar: appBar,
      body: SafeArea(
        top: appBar == null,
        bottom: false,
        child: CustomScrollView(
          key: key == null ? null : PageStorageKey<String>(key),
          controller: controller,
          slivers: [
            ...slivers,
            SliverToBoxAdapter(child: SizedBox(height: context.bottomClearance)),
          ],
        ),
      ),
    );
  }
}

/// Top bar for pushed detail pages: back arrow, title, actions. Flat, on
/// paper, no elevation.
class LedgerAppBar extends StatelessWidget implements PreferredSizeWidget {
  const LedgerAppBar({super.key, required this.title, this.actions = const []});

  final String title;
  final List<Widget> actions;

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final t = context.type;
    return AppBar(
      backgroundColor: c.paper,
      surfaceTintColor: Colors.transparent,
      foregroundColor: c.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleSpacing: 0,
      leading: (ModalRoute.of(context)?.canPop ?? false)
          ? IconButton(
              tooltip: 'Back',
              icon: const Icon(LucideIcons.arrowLeft, size: 22),
              onPressed: () => Navigator.of(context).maybePop(),
            )
          : null,
      title: Text(title, style: t.bodyStrong.copyWith(fontSize: 17), maxLines: 1, overflow: TextOverflow.ellipsis),
      actions: [...actions, const SizedBox(width: Sp.sm)],
    );
  }
}

/// Wraps a box widget as a sliver inside the page column.
class PageBlock extends StatelessWidget {
  const PageBlock({super.key, required this.child, this.top = 0, this.bottom = 0});

  final Widget child;
  final double top;
  final double bottom;

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(child: PageColumn(top: top, bottom: bottom, child: child));
  }
}

/// The centred, gutter-padded content column (box version of [PageBlock]).
class PageColumn extends StatelessWidget {
  const PageColumn({super.key, required this.child, this.top = 0, this.bottom = 0});

  final Widget child;
  final double top;
  final double bottom;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: Sp.maxWidth),
        child: Padding(
          padding: EdgeInsets.fromLTRB(Sp.gutter, top, Sp.gutter, bottom),
          child: child,
        ),
      ),
    );
  }
}

/// Tab header: menu, page title, then up to two actions on the right.
class PageHeader extends StatelessWidget {
  const PageHeader({super.key, required this.title, this.actions = const [], this.subtitle});

  final String title;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    final sub = subtitle;
    return Padding(
      padding: const EdgeInsets.only(top: Sp.sm),
      child: Row(
        children: [
          // Optically align the menu glyph with the page gutter.
          Transform.translate(offset: const Offset(-10, 0), child: const LedgerMenuButton()),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (sub != null) Text(sub, style: t.label),
                Semantics(
                  header: true,
                  child: Text(title, style: t.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
          for (final a in actions) ...[const SizedBox(width: Sp.xs), a],
        ],
      ),
    );
  }
}

/// A titled section. The title is the only label; no overlines.
class LedgerSection extends StatelessWidget {
  const LedgerSection({
    super.key,
    required this.title,
    required this.child,
    this.count,
    this.actionLabel,
    this.onAction,
    this.trailing,
  });

  final String title;
  final Widget child;

  /// Shown next to the title in a lighter tone.
  final int? count;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Free-form widget on the right instead of an action.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final t = context.type;
    final label = actionLabel;
    final n = count;
    final tr = trailing;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Semantics(
                header: true,
                child: Text.rich(
                  TextSpan(
                    text: title,
                    children: [
                      if (n != null) TextSpan(text: '  $n', style: t.heading.copyWith(color: c.inkSoft, fontWeight: FontWeight.w500)),
                    ],
                  ),
                  style: t.heading,
                ),
              ),
            ),
            ?tr,
            if (label != null)
              LedgerButton(label: label, onPressed: onAction, variant: LedgerButtonVariant.quiet, small: true),
          ],
        ),
        const SizedBox(height: Sp.md),
        child,
      ],
    );
  }
}

/// White panel with a hairline edge. Holds rows; never nested.
class LedgerPanel extends StatelessWidget {
  const LedgerPanel({super.key, required this.children, this.dividerIndent = Sp.lg, this.padding});

  final List<Widget> children;

  /// Left inset of the hairline between rows (align it with row text).
  final double dividerIndent;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: Rad.rLg,
        border: Border.all(color: c.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) LedgerDivider(indent: dividerIndent),
            children[i],
          ],
        ],
      ),
    );
  }
}

class LedgerDivider extends StatelessWidget {
  const LedgerDivider({super.key, this.indent = 0});

  final double indent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsetsDirectional.only(start: indent),
      child: Container(height: 1, color: context.ink.line),
    );
  }
}

enum NoteTone { neutral, caution, alert }

/// One-line explanation on a tinted fill ("Past months are read-only").
class LedgerNote extends StatelessWidget {
  const LedgerNote({super.key, required this.text, this.icon = LucideIcons.info, this.tone = NoteTone.neutral});

  final String text;
  final IconData icon;
  final NoteTone tone;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final t = context.type;
    final (bg, fg) = switch (tone) {
      NoteTone.neutral => (c.sunken, c.inkSoft),
      NoteTone.caution => (c.amberSoft, c.amber),
      NoteTone.alert => (c.redSoft, c.red),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Sp.md + 2, vertical: Sp.md),
      decoration: BoxDecoration(color: bg, borderRadius: Rad.rMd),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(padding: const EdgeInsets.only(top: 1), child: Icon(icon, size: 18, color: fg)),
          const SizedBox(width: Sp.md),
          Expanded(child: Text(text, style: t.label.copyWith(color: c.ink))),
        ],
      ),
    );
  }
}

/// Empty or "nothing matches" state: what is missing and the next step.
class LedgerEmpty extends StatelessWidget {
  const LedgerEmpty({
    super.key,
    required this.title,
    required this.message,
    this.icon,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String message;
  final IconData? icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final t = context.type;
    final ic = icon;
    final label = actionLabel;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Sp.xl, horizontal: Sp.sm),
      child: Column(
        children: [
          if (ic != null) ...[
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(color: c.sunken, shape: BoxShape.circle),
              child: Icon(ic, size: 24, color: c.inkSoft),
            ),
            const SizedBox(height: Sp.lg),
          ],
          Text(title, style: t.heading, textAlign: TextAlign.center),
          const SizedBox(height: Sp.xs + 2),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Text(message, style: t.label, textAlign: TextAlign.center),
          ),
          if (label != null) ...[
            const SizedBox(height: Sp.lg),
            LedgerButton(label: label, onPressed: onAction, variant: LedgerButtonVariant.secondary),
          ],
        ],
      ),
    );
  }
}

/// Placeholder block with the shape of the content it stands in for.
class LedgerSkeleton extends StatelessWidget {
  const LedgerSkeleton({super.key, this.width, required this.height, this.radius = Rad.md});

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: context.ink.sunken,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// Generic page skeleton: title line, hero figure, a panel of rows.
class LedgerPageSkeleton extends StatelessWidget {
  const LedgerPageSkeleton({super.key, this.rows = 5});

  final int rows;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading',
      child: ExcludeSemantics(
        child: PageColumn(
          top: Sp.lg,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const LedgerSkeleton(width: 140, height: 28),
              const SizedBox(height: Sp.xxl),
              const LedgerSkeleton(width: 110, height: 14),
              const SizedBox(height: Sp.sm),
              const LedgerSkeleton(width: 210, height: 40),
              const SizedBox(height: Sp.lg),
              const LedgerSkeleton(height: 6, radius: 3),
              const SizedBox(height: Sp.section),
              for (var i = 0; i < rows; i++) ...[
                const LedgerSkeleton(height: 56),
                const SizedBox(height: Sp.sm),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
