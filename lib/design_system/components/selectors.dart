import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../motion/motion.dart';
import '../theme/finn_theme.dart';
import '../tokens/tokens.dart';

/// One option in a [SegmentedTabs].
@immutable
class SegmentItem<T> {
  const SegmentItem(this.value, this.label, {this.count});

  final T value;
  final String label;

  /// Optional count shown next to the label.
  final int? count;
}

/// Pill-style segmented control with an animated sliding indicator.
class SegmentedTabs<T> extends StatelessWidget {
  const SegmentedTabs({
    super.key,
    required this.items,
    required this.selected,
    required this.onChanged,
    this.haptic = true,
  });

  final List<SegmentItem<T>> items;
  final T selected;
  final ValueChanged<T> onChanged;
  final bool haptic;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final n = items.length;
    final index = items.indexWhere((i) => i.value == selected);
    final x = n <= 1 || index < 0 ? -1.0 : -1 + 2 * index / (n - 1);
    return DecoratedBox(
      decoration: BoxDecoration(color: c.surfaceMuted, borderRadius: Radii.rFull),
      child: Padding(
        padding: const EdgeInsets.all(Space.x1),
        child: Stack(
          children: [
            if (index >= 0 && n > 0)
              Positioned.fill(
                child: AnimatedAlign(
                  alignment: Alignment(x, 0),
                  duration: context.motion.normal,
                  curve: Curves2.emphasized,
                  child: FractionallySizedBox(
                    widthFactor: 1 / n,
                    heightFactor: 1,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: c.isDark ? c.border : c.surface,
                        borderRadius: Radii.rFull,
                        boxShadow: c.isDark ? Elevation.none : Elevation.md,
                      ),
                    ),
                  ),
                ),
              ),
            Row(
              children: [
                for (final item in items)
                  Expanded(
                    child: _Segment<T>(
                      item: item,
                      selected: item.value == selected,
                      onTap: () {
                        if (item.value == selected) return;
                        if (haptic) HapticFeedback.selectionClick();
                        onChanged(item.value);
                      },
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Segment<T> extends StatelessWidget {
  const _Segment({required this.item, required this.selected, required this.onTap});

  final SegmentItem<T> item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fg = selected ? c.textPrimary : c.textSecondary;
    final count = item.count;
    return Semantics(
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      label: count == null ? item.label : '${item.label}, $count',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: Dimens.minTouch - Space.x2),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.x2, vertical: Space.x2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: AnimatedDefaultTextStyle(
                    duration: context.motion.fast,
                    style: context.text.eyebrow.copyWith(
                      color: fg,
                      fontSize: 11,
                      letterSpacing: 0.9,
                    ),
                    child: Text(
                      item.label.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
                if (count != null) ...[
                  const SizedBox(width: Space.x1_5),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: selected ? c.primary : c.border,
                      borderRadius: Radii.rFull,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: Space.x1_5, vertical: 1),
                      child: Text(
                        '$count',
                        style: context.text.micro.copyWith(
                          color: selected ? c.onPrimary : c.textSecondary,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One option in a [FilterChipBar].
@immutable
class FilterChipItem<T> {
  const FilterChipItem(this.value, this.label, {this.icon});

  final T value;
  final String label;
  final IconData? icon;
}

/// Horizontally scrolling selectable chips (single or multi select).
class FilterChipBar<T> extends StatelessWidget {
  const FilterChipBar({
    super.key,
    required this.items,
    required this.selected,
    required this.onChanged,
    this.multiSelect = true,
    this.padding = const EdgeInsets.symmetric(horizontal: Space.gutter),
  });

  final List<FilterChipItem<T>> items;
  final Set<T> selected;

  /// Receives the new selection set.
  final ValueChanged<Set<T>> onChanged;

  /// When false, tapping a chip selects only that chip.
  final bool multiSelect;
  final EdgeInsetsGeometry padding;

  void _toggle(T value) {
    HapticFeedback.selectionClick();
    if (!multiSelect) {
      onChanged({value});
      return;
    }
    final next = Set<T>.of(selected);
    if (!next.remove(value)) next.add(value);
    onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: padding,
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(width: Space.x2),
            _Chip<T>(
              item: items[i],
              selected: selected.contains(items[i].value),
              onTap: () => _toggle(items[i].value),
            ),
          ],
        ],
      ),
    );
  }
}

class _Chip<T> extends StatelessWidget {
  const _Chip({required this.item, required this.selected, required this.onTap});

  final FilterChipItem<T> item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fg = selected ? c.onPrimary : c.textPrimary;
    final icon = selected ? LucideIcons.check : item.icon;
    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.x1),
          child: AnimatedContainer(
            duration: context.motion.fast,
            constraints: const BoxConstraints(minHeight: 40),
            padding: const EdgeInsets.symmetric(horizontal: Space.x3,vertical: Space.x2),
            decoration: BoxDecoration(
              color: selected ? c.primary : c.surface,
              borderRadius: Radii.rFull,
              border: Border.all(color: selected ? c.primary : c.border, width: 1.5),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 14, color: fg),
                  const SizedBox(width: Space.x1_5),
                ],
                Text(
                  item.label,
                  style: context.text.label.copyWith(color: fg, fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
