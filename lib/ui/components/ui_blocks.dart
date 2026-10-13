import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../foundation/ui_colors.dart';
import '../foundation/ui_motion.dart';
import '../foundation/ui_space.dart';
import '../foundation/ui_type.dart';
import 'ui_controls.dart';
import 'ui_surfaces.dart';

/// Screen top bar: back (when the route can be popped) or a [leading]
/// control, a title and up to three icon actions. Flat on the page
/// background.
class UiTopBar extends StatelessWidget {
  const UiTopBar({super.key, required this.title, this.actions = const [], this.leading});

  final String title;
  final List<Widget> actions;

  /// Replaces the back button (e.g. the app menu on a tab root).
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final t = UiType.of(context);
    final canPop = ModalRoute.of(context)?.impliesAppBarDismissal ?? false;
    return Padding(
      padding: const EdgeInsets.fromLTRB(UiSpace.gutter - UiSpace.md, UiSpace.xs, UiSpace.gutter - UiSpace.md, 0),
      child: SizedBox(
        height: 52,
        child: Row(
          children: [
            if (leading != null)
              leading!
            else if (canPop)
              UiIconButton(
                icon: LucideIcons.chevronLeft,
                tooltip: 'Back',
                onPressed: () => Navigator.of(context).maybePop(),
              )
            else
              const SizedBox(width: UiSpace.md),
            const SizedBox(width: UiSpace.xs),
            Expanded(
              child: Semantics(
                header: true,
                child: Text(title, style: t.section, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ),
            ...actions,
          ],
        ),
      ),
    );
  }
}

/// Page scaffold for the kit: page colour, safe top, a [UiTopBar] and a
/// scrolling body below it.
class UiPage extends StatelessWidget {
  const UiPage({super.key, required this.title, required this.body, this.actions = const [], this.leading});

  final String title;
  final List<Widget> actions;
  final Widget? leading;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: UiColors.of(context).page,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            UiTopBar(title: title, actions: actions, leading: leading),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }
}

/// The one figure a screen is about: a quiet label, the value, and an
/// optional caption and footer (progress, stats).
class UiHero extends StatelessWidget {
  const UiHero({
    super.key,
    required this.label,
    required this.value,
    this.labelTrailing,
    this.caption,
    this.captionColor,
    this.footer,
  });

  final String label;
  final Widget? labelTrailing;
  final Widget value;
  final String? caption;
  final Color? captionColor;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final t = UiType.of(context);
    final cap = caption;
    final end = labelTrailing;
    final foot = footer;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: UiSpace.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 28),
            child: Row(
              children: [
                Expanded(
                  child: Text(label, style: t.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                ?end,
              ],
            ),
          ),
          value,
          if (cap != null) ...[
            const SizedBox(height: UiSpace.xs),
            Text(cap, style: t.label.copyWith(color: captionColor)),
          ],
          if (foot != null) ...[const SizedBox(height: UiSpace.lg), foot],
        ],
      ),
    );
  }
}

/// A labelled figure. With [onTap] it becomes a toggle: [selected] tints
/// the label and adds a check.
class UiStat extends StatelessWidget {
  const UiStat({
    super.key,
    required this.label,
    required this.value,
    this.dot,
    this.end = false,
    this.onTap,
    this.selected = false,
    this.semanticLabel,
  });

  final String label;
  final Widget value;

  /// Small legend dot before the label.
  final Color? dot;
  final bool end;
  final VoidCallback? onTap;
  final bool selected;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = UiColors.of(context);
    final t = UiType.of(context);
    final d = dot;
    final body = Column(
      crossAxisAlignment: end ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected) ...[
              Icon(LucideIcons.check, size: 13, color: c.ink),
              const SizedBox(width: 4),
            ] else if (d != null) ...[
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: d, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                label,
                style: t.small.copyWith(color: selected ? c.ink : null, fontWeight: selected ? FontWeight.w600 : null),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        FittedBox(fit: BoxFit.scaleDown, alignment: end ? Alignment.centerRight : Alignment.centerLeft, child: value),
      ],
    );
    final tap = onTap;
    if (tap == null) return MergeSemantics(child: body);
    return Semantics(
      button: true,
      selected: selected,
      label: semanticLabel,
      excludeSemantics: semanticLabel != null,
      child: InkWell(
        borderRadius: UiRadius.chip,
        onTap: () {
          HapticFeedback.selectionClick();
          tap();
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: UiSpace.touch),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: UiSpace.xs),
            child: Align(alignment: end ? Alignment.centerRight : Alignment.centerLeft, widthFactor: 1, child: body),
          ),
        ),
      ),
    );
  }
}

/// Thin progress bar that settles to [value] (0..1) once.
class UiProgress extends StatelessWidget {
  const UiProgress({super.key, required this.value, this.color, this.height = 6, this.semanticsLabel});

  final double value;
  final Color? color;
  final double height;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final c = UiColors.of(context);
    final v = value.clamp(0.0, 1.0);
    return Semantics(
      label: semanticsLabel,
      value: '${(v * 100).round()}%',
      child: ExcludeSemantics(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: v),
          duration: UiMotion.of(context).settle,
          curve: UiMotion.ease,
          builder: (context, p, _) => ClipRRect(
            borderRadius: BorderRadius.circular(height / 2),
            child: SizedBox(
              height: height,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(color: c.muted),
                  FractionallySizedBox(
                    alignment: AlignmentDirectional.centerStart,
                    widthFactor: p,
                    child: ColoredBox(color: color ?? c.ink),
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

/// One option of a [UiSegmented].
@immutable
class UiSegment<T> {
  const UiSegment(this.value, this.label, {this.count, this.key});

  final T value;
  final String label;
  final int? count;

  /// Key for the tappable segment (finders, analytics).
  final Key? key;
}

/// Quiet segmented control: equal segments on a muted track; the chosen
/// one lifts onto the surface colour.
class UiSegmented<T> extends StatelessWidget {
  const UiSegmented({super.key, required this.segments, required this.selected, required this.onChanged});

  final List<UiSegment<T>> segments;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = UiColors.of(context);
    final t = UiType.of(context);
    final m = UiMotion.of(context);
    return Container(
      height: UiSpace.touch,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: c.muted, borderRadius: UiRadius.control),
      child: Row(
        children: [
          for (final s in segments)
            Expanded(
              child: Semantics(
                button: true,
                selected: s.value == selected,
                inMutuallyExclusiveGroup: true,
                label: s.count == null ? s.label : '${s.label}, ${s.count}',
                excludeSemantics: true,
                child: GestureDetector(
                  key: s.key,
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    if (s.value == selected) return;
                    HapticFeedback.selectionClick();
                    onChanged(s.value);
                  },
                  child: AnimatedContainer(
                    duration: m.quick,
                    curve: UiMotion.ease,
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: UiSpace.sm),
                    decoration: BoxDecoration(
                      color: s.value == selected
                          ? (c.dark ? Color.alphaBlend(c.ink.withValues(alpha: 0.10), c.muted) : c.surface)
                          : c.muted.withValues(alpha: 0),
                      borderRadius: const BorderRadius.all(Radius.circular(11)),
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        s.count == null ? s.label : '${s.label} ${s.count}',
                        maxLines: 1,
                        style: t.label.copyWith(
                          color: s.value == selected ? c.ink : c.inkSoft,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
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

/// Label and value on one line, for read-only facts inside a [UiPanel].
class UiDetailRow extends StatelessWidget {
  const UiDetailRow({super.key, required this.label, this.value, this.valueWidget, this.valueColor})
    : assert(value != null || valueWidget != null);

  final String label;
  final String? value;
  final Widget? valueWidget;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final t = UiType.of(context);
    return MergeSemantics(
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: UiSpace.lg, vertical: UiSpace.md),
          child: Row(
            children: [
              Expanded(child: Text(label, style: t.label)),
              const SizedBox(width: UiSpace.md),
              Flexible(
                child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child:
                      valueWidget ??
                      Text(
                        value!,
                        style: t.body.copyWith(color: valueColor),
                        textAlign: TextAlign.end,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
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

/// Free text (a note) inside a [UiPanel].
class UiNoteRow extends StatelessWidget {
  const UiNoteRow({super.key, required this.label, required this.text});

  final String label;
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = UiType.of(context);
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: UiSpace.lg, vertical: UiSpace.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(label, style: t.label),
            const SizedBox(height: UiSpace.xs),
            Text(text, style: t.body.copyWith(fontWeight: FontWeight.w400, height: 1.45)),
          ],
        ),
      ),
    );
  }
}

/// Nothing to show yet: a mark, one line of context and at most one action.
class UiEmpty extends StatelessWidget {
  const UiEmpty({super.key, required this.icon, required this.title, this.message, this.action, this.onAction});

  final IconData icon;
  final String title;
  final String? message;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final t = UiType.of(context);
    final msg = message;
    final act = action;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: UiSpace.xl, vertical: UiSpace.section),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          UiMark(icon: icon, size: 48),
          const SizedBox(height: UiSpace.lg),
          Semantics(
            header: true,
            child: Text(title, style: t.section, textAlign: TextAlign.center),
          ),
          if (msg != null) ...[
            const SizedBox(height: UiSpace.xs),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 300),
              child: Text(msg, style: t.label, textAlign: TextAlign.center),
            ),
          ],
          if (act != null && onAction != null) ...[
            const SizedBox(height: UiSpace.xl),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 260),
              child: UiPrimaryButton(label: act, onPressed: onAction!),
            ),
          ],
        ],
      ),
    );
  }
}

/// A single quiet line that flags something (icon + text, never colour
/// alone), with an optional text action.
class UiNotice extends StatelessWidget {
  const UiNotice({super.key, required this.icon, required this.text, this.color, this.action, this.onAction});

  final IconData icon;
  final String text;
  final Color? color;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final c = UiColors.of(context);
    final t = UiType.of(context);
    final fg = color ?? c.inkSoft;
    final act = action;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: UiSpace.touch),
      child: Padding(
        padding: const EdgeInsets.only(left: UiSpace.xs),
        child: Row(
          children: [
            ExcludeSemantics(child: Icon(icon, size: 16, color: fg)),
            const SizedBox(width: UiSpace.sm),
            Expanded(
              child: Text(text, style: t.label.copyWith(color: fg)),
            ),
            if (act != null && onAction != null) UiTextButton(label: act, onTap: onAction!),
          ],
        ),
      ),
    );
  }
}

/// Muted-fill button for the secondary action beside a [UiPrimaryButton].
/// A null [onPressed] disables it.
class UiSecondaryButton extends StatelessWidget {
  const UiSecondaryButton({super.key, required this.label, required this.onPressed, this.icon});

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = UiColors.of(context);
    final t = UiType.of(context);
    final ic = icon;
    final enabled = onPressed != null;
    final fg = enabled ? c.ink : c.inkFaint;
    return Semantics(
      button: true,
      enabled: enabled,
      child: Material(
        color: c.muted,
        borderRadius: UiRadius.control,
        child: InkWell(
          onTap: onPressed,
          borderRadius: UiRadius.control,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: UiSpace.lg),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (ic != null) ...[Icon(ic, size: 18, color: fg), const SizedBox(width: UiSpace.sm)],
                  Flexible(
                    child: Text(
                      label,
                      style: t.body.copyWith(color: fg, fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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

/// Compact pill action that sits inside a row (e.g. "Mark paid"). The pill
/// is 32 dp; its hit area is the full 44 dp.
class UiChipButton extends StatelessWidget {
  const UiChipButton({
    super.key,
    required this.label,
    required this.onTap,
    this.color,
    this.semanticLabel,
    this.trailingIcon,
    this.selected = false,
  });

  final String label;
  final VoidCallback onTap;

  /// Solid ink pill: the filter this chip stands for is on.
  final bool selected;

  /// Small icon after the label (e.g. a cross on a removable filter).
  final IconData? trailingIcon;

  /// Text colour; the pill is a faint wash of it. Defaults to ink on muted.
  final Color? color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = UiColors.of(context);
    final t = UiType.of(context);
    final fg = selected ? c.page : (color ?? c.ink);
    final bg = selected
        ? c.ink
        : (color == null ? c.muted : Color.alphaBlend(fg.withValues(alpha: c.dark ? 0.18 : 0.10), c.surface));
    return Semantics(
      button: true,
      selected: selected,
      label: semanticLabel,
      excludeSemantics: semanticLabel != null,
      child: InkResponse(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        radius: 28,
        child: SizedBox(
          height: UiSpace.touch,
          child: Center(
            widthFactor: 1,
            child: Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: UiSpace.md),
              decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      label,
                      style: t.small.copyWith(color: fg, fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (trailingIcon != null) ...[const SizedBox(width: 4), Icon(trailingIcon, size: 13, color: fg)],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Initials in a soft circle: the leading mark for a person.
class UiInitials extends StatelessWidget {
  const UiInitials({super.key, required this.name, this.color, this.size = 36});

  final String name;

  /// Text colour; the circle is a faint wash of it. Defaults to ink on muted.
  final Color? color;
  final double size;

  static String of(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    final first = parts.first.characters.first;
    if (parts.length == 1) return first.toUpperCase();
    return (first + parts.last.characters.first).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final c = UiColors.of(context);
    final t = UiType.of(context);
    final fg = color ?? c.ink;
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color == null ? c.muted : Color.alphaBlend(fg.withValues(alpha: c.dark ? 0.18 : 0.10), c.surface),
          shape: BoxShape.circle,
        ),
        child: Text(
          of(name),
          style: t.small.copyWith(color: fg, fontWeight: FontWeight.w700, fontSize: size * 0.34, height: 1),
        ),
      ),
    );
  }
}

/// Search box on a muted fill with a clear-and-close button. Reports text
/// after a short pause.
class UiSearchField extends StatefulWidget {
  const UiSearchField({
    super.key,
    required this.hint,
    required this.onChanged,
    required this.onClose,
    this.initialValue = '',
    this.autofocus = true,
    this.debounce = const Duration(milliseconds: 250),
  });

  final String hint;

  /// Text already searched for when the field opens.
  final String initialValue;
  final ValueChanged<String> onChanged;
  final VoidCallback onClose;
  final bool autofocus;
  final Duration debounce;

  @override
  State<UiSearchField> createState() => _UiSearchFieldState();
}

class _UiSearchFieldState extends State<UiSearchField> {
  Timer? _timer;
  late final TextEditingController _text = TextEditingController(text: widget.initialValue);

  @override
  void dispose() {
    _timer?.cancel();
    _text.dispose();
    super.dispose();
  }

  void _changed(String v) {
    _timer?.cancel();
    _timer = Timer(widget.debounce, () => widget.onChanged(v));
  }

  @override
  Widget build(BuildContext context) {
    final c = UiColors.of(context);
    final t = UiType.of(context);
    return Row(
      children: [
        Expanded(
          child: Container(
            height: UiSpace.touch,
            padding: const EdgeInsets.symmetric(horizontal: UiSpace.md),
            decoration: BoxDecoration(color: c.muted, borderRadius: UiRadius.control),
            child: Row(
              children: [
                ExcludeSemantics(child: Icon(LucideIcons.search, size: 16, color: c.inkSoft)),
                const SizedBox(width: UiSpace.sm),
                Expanded(
                  child: TextField(
                    controller: _text,
                    autofocus: widget.autofocus,
                    onChanged: _changed,
                    style: t.body,
                    cursorColor: c.ink,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration.collapsed(
                      hintText: widget.hint,
                      hintStyle: t.body.copyWith(color: c.inkSoft),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        UiIconButton(icon: LucideIcons.x, tooltip: 'Close search', onPressed: widget.onClose),
      ],
    );
  }
}

/// Small chevron step (previous / next). A null [onPressed] shows it
/// disabled but keeps its place.
class UiStepButton extends StatelessWidget {
  const UiStepButton({super.key, required this.icon, required this.tooltip, required this.onPressed});

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final c = UiColors.of(context);
    final tap = onPressed;
    if (tap == null) {
      return Semantics(
        button: true,
        enabled: false,
        label: tooltip,
        excludeSemantics: true,
        child: SizedBox.square(
          dimension: UiSpace.touch,
          child: Icon(icon, size: 18, color: c.hairline),
        ),
      );
    }
    return UiIconButton(icon: icon, tooltip: tooltip, size: 18, color: c.inkSoft, onPressed: tap);
  }
}

/// One slice of a panel built row by row in a sliver list: rounded on the
/// [first] and [last] slice, with an inset rule above every slice but the
/// first. Lets long lists stay lazy while reading as one [UiPanel].
class UiPanelSlice extends StatelessWidget {
  const UiPanelSlice({super.key, required this.first, required this.last, required this.child, this.ruleIndent = 64});

  final bool first;
  final bool last;
  final Widget child;
  final double ruleIndent;

  @override
  Widget build(BuildContext context) {
    const r = Radius.circular(20);
    final radius = BorderRadius.vertical(top: first ? r : Radius.zero, bottom: last ? r : Radius.zero);
    return DecoratedBox(
      decoration: BoxDecoration(color: UiColors.of(context).surface, borderRadius: radius),
      child: ClipRRect(
        borderRadius: radius,
        child: Material(
          type: MaterialType.transparency,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!first) UiRule(indent: ruleIndent),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

/// A [UiPanel] of rows with an inset rule between each.
class UiPanelList extends StatelessWidget {
  const UiPanelList({super.key, required this.children, this.ruleIndent = UiSpace.lg});

  final List<Widget> children;
  final double ruleIndent;

  @override
  Widget build(BuildContext context) {
    return UiPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[if (i > 0) UiRule(indent: ruleIndent), children[i]],
        ],
      ),
    );
  }
}

/// A [UiProgress] with a short caption at each end (e.g. "42% repaid" ·
/// "of ₹5,00,000").
class UiProgressFooter extends StatelessWidget {
  const UiProgressFooter({
    super.key,
    required this.value,
    required this.start,
    required this.end,
    this.color,
    this.semanticsLabel,
  });

  final double value;
  final String start;
  final String end;
  final Color? color;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final t = UiType.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        UiProgress(value: value, color: color, semanticsLabel: semanticsLabel),
        const SizedBox(height: UiSpace.sm),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(child: Text(start, style: t.small, maxLines: 1, overflow: TextOverflow.ellipsis)),
            const SizedBox(width: UiSpace.md),
            Flexible(
              child: Text(end, style: t.small, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.end),
            ),
          ],
        ),
      ],
    );
  }
}

/// "‹ October 2026 ›": steps through periods. A null [onPrevious] or
/// [onNext] keeps the arrow in place but disabled; [onLabel] makes the
/// label itself a button (e.g. to pick a custom range). [trailing] sits at
/// the far end (a calendar or clear button).
class UiPeriodStepper extends StatelessWidget {
  const UiPeriodStepper({
    super.key,
    required this.label,
    required this.onPrevious,
    required this.onNext,
    this.onLabel,
    this.labelHint,
    this.trailing,
  });

  final String label;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback? onLabel;
  final String? labelHint;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = UiType.of(context);
    final tap = onLabel;
    final text = Text(label, style: t.body.copyWith(fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis);
    final end = trailing;
    return SizedBox(
      height: UiSpace.touch,
      child: Row(
        children: [
          UiStepButton(icon: LucideIcons.chevronLeft, tooltip: 'Previous', onPressed: onPrevious),
          Flexible(
            child: tap == null
                ? Semantics(liveRegion: true, child: text)
                : Semantics(
                    button: true,
                    liveRegion: true,
                    hint: labelHint,
                    child: InkWell(
                      onTap: tap,
                      borderRadius: UiRadius.chip,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: UiSpace.xs, vertical: UiSpace.sm),
                        child: text,
                      ),
                    ),
                  ),
          ),
          UiStepButton(icon: LucideIcons.chevronRight, tooltip: 'Next', onPressed: onNext),
          const Spacer(),
          ?end,
        ],
      ),
    );
  }
}
