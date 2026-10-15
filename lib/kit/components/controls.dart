import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/shell/app_drawer.dart';
import '../../core/time/dates.dart';
import '../../design_system/motion/motion.dart';
import '../tokens.dart';

enum LedgerButtonVariant {
  /// Ink fill. One per view: the main thing to do.
  primary,

  /// Outlined. Everything else that is a button.
  secondary,

  /// Text only, for low-weight actions in rows and headers.
  quiet,
}

/// The one button of the kit.
class LedgerButton extends StatelessWidget {
  const LedgerButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.variant = LedgerButtonVariant.primary,
    this.small = false,
    this.expand = false,
    this.loading = false,
    this.color,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final LedgerButtonVariant variant;
  final bool small;
  final bool expand;
  final bool loading;

  /// Overrides the fill (primary), text and outline (secondary) or text
  /// colour (quiet). Use sparingly: `c.red` on a secondary button is the
  /// destructive action.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final t = context.type;
    final enabled = onPressed != null && !loading;
    final (Color bg, Color fg, BorderSide side) = switch (variant) {
      LedgerButtonVariant.primary => (color ?? c.ink, c.onInk, BorderSide.none),
      LedgerButtonVariant.secondary => (
          c.surface,
          color ?? c.ink,
          BorderSide(color: color?.withValues(alpha: 0.55) ?? c.lineStrong),
        ),
      LedgerButtonVariant.quiet => (Colors.transparent, color ?? c.ink, BorderSide.none),
    };
    final height = small ? 36.0 : 48.0;
    final pad = variant == LedgerButtonVariant.quiet ? Sp.sm : (small ? Sp.md : Sp.lg + Sp.xs);
    final ic = icon;
    final content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (loading)
          SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2, color: fg))
        else if (ic != null)
          Icon(ic, size: small ? 16 : 18, color: fg),
        if (loading || ic != null) const SizedBox(width: Sp.sm),
        Flexible(
          child: Text(
            label,
            style: (small ? t.button.copyWith(fontSize: 14) : t.button).copyWith(color: fg),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
    return Semantics(
      button: true,
      enabled: enabled,
      child: Opacity(
        opacity: enabled || loading ? 1 : 0.4,
        child: Material(
          color: bg,
          shape: RoundedRectangleBorder(borderRadius: Rad.rMd, side: side),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: enabled
                ? () {
                    HapticFeedback.selectionClick();
                    onPressed!();
                  }
                : null,
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: height, minWidth: small ? 0 : 48),
              child: Padding(padding: EdgeInsets.symmetric(horizontal: pad), child: content),
            ),
          ),
        ),
      ),
    );
  }
}

/// 44pt round icon button. [selected] fills it with ink (an active toggle
/// or a filter that is on); [badge] shows a count in the corner.
class LedgerIconButton extends StatelessWidget {
  const LedgerIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.selected = false,
    this.badge = 0,
    this.badgeLabel,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool selected;
  final int badge;

  /// Spoken text for the badge ("2 filters on").
  final String? badgeLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final t = context.type;
    final button = Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        selected: selected,
        child: Material(
          color: selected ? c.ink : Colors.transparent,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: SizedBox.square(
              dimension: 44,
              child: Icon(icon, size: 21, color: selected ? c.onInk : c.ink),
            ),
          ),
        ),
      ),
    );
    if (badge <= 0) return button;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        button,
        Positioned(
          top: 2,
          right: 0,
          child: IgnorePointer(
            child: Semantics(
              label: badgeLabel,
              excludeSemantics: badgeLabel == null,
              child: Container(
                constraints: const BoxConstraints(minWidth: 18),
                height: 18,
                padding: const EdgeInsets.symmetric(horizontal: 5),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: c.red,
                  borderRadius: Rad.pill,
                  border: Border.all(color: c.paper, width: 2),
                ),
                child: Text(
                  badge > 9 ? '9+' : '$badge',
                  style: t.small.copyWith(color: Colors.white, fontSize: 11, height: 1, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Opens the side drawer. Renders nothing outside the app shell.
class LedgerMenuButton extends StatelessWidget {
  const LedgerMenuButton({super.key});

  @override
  Widget build(BuildContext context) {
    final open = AppDrawerScope.maybeOf(context);
    if (open == null) return const SizedBox.shrink();
    return LedgerIconButton(
      key: const ValueKey('app-menu'),
      icon: LucideIcons.menu,
      tooltip: 'Menu',
      onPressed: open,
    );
  }
}

/// Pill used for filters and quick choices. Selected = ink fill.
class LedgerChip extends StatelessWidget {
  const LedgerChip({
    super.key,
    required this.label,
    required this.onTap,
    this.selected = false,
    this.count,
    this.dot,
    this.icon,
    this.removable = false,
    this.semanticLabel,
  });

  final String label;
  final VoidCallback? onTap;
  final bool selected;

  /// Shown after the label in a lighter tone.
  final int? count;

  /// Small colour key in front of the label (status, category share).
  final Color? dot;
  final IconData? icon;

  /// Adds an "x": tapping removes this filter.
  final bool removable;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final t = context.type;
    final fg = selected ? c.onInk : c.ink;
    final soft = selected ? c.onInk.withValues(alpha: 0.72) : c.inkSoft;
    final d = dot;
    final ic = icon;
    final n = count;
    return Semantics(
      button: true,
      selected: selected,
      label: semanticLabel,
      excludeSemantics: semanticLabel != null,
      child: Material(
        color: selected ? c.ink : c.surface,
        shape: StadiumBorder(side: BorderSide(color: selected ? c.ink : c.line)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap == null
              ? null
              : () {
                  HapticFeedback.selectionClick();
                  onTap!();
                },
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 36),
            child: Padding(
              padding: EdgeInsets.only(left: Sp.md + 2, right: removable ? Sp.sm + 2 : Sp.md + 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (d != null) ...[
                    Container(width: 8, height: 8, decoration: BoxDecoration(color: d, shape: BoxShape.circle)),
                    const SizedBox(width: Sp.sm),
                  ],
                  if (ic != null) ...[Icon(ic, size: 16, color: fg), const SizedBox(width: 6)],
                  Flexible(
                    child: Text(
                      label,
                      style: t.labelStrong.copyWith(color: fg),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (n != null) ...[
                    const SizedBox(width: 6),
                    Text('$n', style: t.label.copyWith(color: soft, fontFeatures: const [FontFeature.tabularFigures()])),
                  ],
                  if (removable) ...[const SizedBox(width: 6), Icon(LucideIcons.x, size: 15, color: soft)],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One option of a [LedgerSegmented].
class LedgerSegment<T> {
  const LedgerSegment(this.value, this.label, {this.count, this.key});

  final T value;
  final String label;
  final int? count;
  final Key? key;
}

/// Mutually exclusive tabs inside one sunken track.
class LedgerSegmented<T> extends StatelessWidget {
  const LedgerSegmented({super.key, required this.segments, required this.selected, required this.onChanged});

  final List<LedgerSegment<T>> segments;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final t = context.type;
    final motion = context.motion;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: c.sunken, borderRadius: Rad.rMd),
      child: Row(
        children: [
          for (final s in segments)
            Expanded(
              child: Semantics(
                key: s.key,
                button: true,
                selected: s.value == selected,
                inMutuallyExclusiveGroup: true,
                label: s.count == null ? s.label : '${s.label}, ${s.count}',
                excludeSemantics: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    if (s.value == selected) return;
                    HapticFeedback.selectionClick();
                    onChanged(s.value);
                  },
                  child: AnimatedContainer(
                    duration: motion.fast,
                    curve: motion.standard,
                    height: 38,
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: Sp.xs),
                    decoration: BoxDecoration(
                      color: s.value == selected ? c.surface : Colors.transparent,
                      borderRadius: const BorderRadius.all(Radius.circular(Rad.md - 3)),
                      border: s.value == selected ? Border.all(color: c.line) : null,
                    ),
                    child: Text.rich(
                      TextSpan(
                        text: s.label,
                        children: [
                          if (s.count != null)
                            TextSpan(text: '  ${s.count}', style: TextStyle(color: c.inkSoft, fontWeight: FontWeight.w500)),
                        ],
                      ),
                      style: t.labelStrong.copyWith(color: s.value == selected ? c.ink : c.inkSoft),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// "‹ October 2026 ›" with swipe support. Arrows disable at the bounds.
class MonthStepper extends StatelessWidget {
  const MonthStepper({
    super.key,
    required this.month,
    required this.onChanged,
    this.min,
    this.max,
    this.trailing,
  });

  final MonthKey month;
  final ValueChanged<MonthKey> onChanged;
  final MonthKey? min;
  final MonthKey? max;

  /// Shown under the month ("17 days left").
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    final lo = min;
    final hi = max;
    final canBack = lo == null || month > lo;
    final canNext = hi == null || month < hi;
    void go(MonthKey m) {
      HapticFeedback.selectionClick();
      onChanged(m);
    }

    final sub = trailing;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragEnd: (d) {
        final v = d.primaryVelocity ?? 0;
        if (v > 200 && canBack) go(month.previous);
        if (v < -200 && canNext) go(month.next);
      },
      child: Row(
        children: [
          _Arrow(icon: LucideIcons.chevronLeft, tooltip: 'Previous month', onTap: canBack ? () => go(month.previous) : null),
          Expanded(
            child: Semantics(
              liveRegion: true,
              child: Column(
                children: [
                  Text(DateFormats.monthYear.format(month.start), style: t.bodyStrong, textAlign: TextAlign.center),
                  if (sub != null) Text(sub, style: t.small, textAlign: TextAlign.center),
                ],
              ),
            ),
          ),
          _Arrow(icon: LucideIcons.chevronRight, tooltip: 'Next month', onTap: canNext ? () => go(month.next) : null),
        ],
      ),
    );
  }
}

class _Arrow extends StatelessWidget {
  const _Arrow({required this.icon, required this.tooltip, required this.onTap});

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        enabled: onTap != null,
        child: InkResponse(
          onTap: onTap,
          radius: 22,
          child: SizedBox.square(
            dimension: 44,
            child: Icon(icon, size: 20, color: onTap == null ? c.inkFaint.withValues(alpha: 0.5) : c.ink),
          ),
        ),
      ),
    );
  }
}

/// Rounded search box on a sunken fill.
class LedgerSearchField extends StatefulWidget {
  const LedgerSearchField({super.key, required this.hint, required this.onChanged, this.controller});

  final String hint;
  final ValueChanged<String> onChanged;
  final TextEditingController? controller;

  @override
  State<LedgerSearchField> createState() => _LedgerSearchFieldState();
}

class _LedgerSearchFieldState extends State<LedgerSearchField> {
  late final TextEditingController _own = TextEditingController();
  TextEditingController get _c => widget.controller ?? _own;

  @override
  void dispose() {
    _own.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final t = context.type;
    return Container(
      height: 44,
      decoration: BoxDecoration(color: c.sunken, borderRadius: Rad.rMd),
      child: Row(
        children: [
          const SizedBox(width: Sp.md),
          Icon(LucideIcons.search, size: 18, color: c.inkSoft),
          const SizedBox(width: Sp.sm),
          Expanded(
            child: TextField(
              controller: _c,
              onChanged: (v) {
                setState(() {});
                widget.onChanged(v);
              },
              style: t.body,
              cursorColor: c.ink,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: widget.hint,
                hintStyle: t.body.copyWith(color: c.inkSoft),
                isCollapsed: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          if (_c.text.isNotEmpty)
            IconButton(
              tooltip: 'Clear search',
              icon: Icon(LucideIcons.x, size: 18, color: c.inkSoft),
              onPressed: () {
                _c.clear();
                setState(() {});
                widget.onChanged('');
              },
            )
          else
            const SizedBox(width: Sp.md),
        ],
      ),
    );
  }
}
