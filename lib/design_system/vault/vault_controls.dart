import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/money/money.dart';
import '../../core/money/money_format.dart';
import '../../core/time/dates.dart';
import '../motion/motion.dart';
import 'vault_motion.dart';
import 'vault_tokens.dart';

// ---------------------------------------------------------------------------
// Buttons
// ---------------------------------------------------------------------------

/// Visual weight of a [VaultButton].
enum VaultButtonTone { ink, positive, negative, accent, quiet, outline, ghost }

/// Pill button. One `ink` (or tone) button per surface; it carries a light
/// sheen that sweeps once when the surface lands and loops while busy.
class VaultButton extends StatelessWidget {
  const VaultButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.tone = VaultButtonTone.ink,
    this.height = 56,
    this.expand = false,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final VaultButtonTone tone;
  final double height;
  final bool expand;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final p = context.vault;
    final t = context.vt;
    final enabled = onPressed != null && !loading;
    final (Color? bg, Gradient? gradient, Color fg, Color? border) = switch (tone) {
      VaultButtonTone.ink => (null, p.inkGradient, p.onInk, null),
      VaultButtonTone.positive => (null, p.toneGradient(p.positive), p.surface, null),
      VaultButtonTone.negative => (null, p.toneGradient(p.negative), p.surface, null),
      VaultButtonTone.accent => (null, p.champagne, const Color(0xFF17130C), null),
      VaultButtonTone.quiet => (p.well, null, p.ink, null),
      VaultButtonTone.outline => (Colors.transparent, null, p.ink, p.hairlineStrong),
      VaultButtonTone.ghost => (Colors.transparent, null, p.inkSoft, null),
    };
    final solid = gradient != null;
    final small = height < 48;
    final textStyle = (small ? t.label.copyWith(fontSize: 13.5) : t.button).vw(small ? 680 : 700).vc(fg);
    final iconSize = small ? 16.0 : 18.0;

    final text = Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: textStyle);
    final content = Stack(
      alignment: Alignment.center,
      children: [
        AnimatedOpacity(
          opacity: loading ? 0 : 1,
          duration: VaultMotion.quick,
          child: Row(
            mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[Icon(icon, size: iconSize, color: fg), const SizedBox(width: 9)],
              Flexible(child: text),
            ],
          ),
        ),
        if (loading) VaultDots(color: fg),
      ],
    );

    Widget body = AnimatedContainer(
      duration: VaultMotion.state,
      curve: VaultMotion.settle,
      height: height,
      padding: EdgeInsets.symmetric(horizontal: small ? 16 : 24),
      decoration: BoxDecoration(
        color: bg,
        gradient: gradient,
        borderRadius: BorderRadius.circular(height / 2),
        border: border == null ? null : Border.all(color: border),
        boxShadow: solid && enabled
            ? [
                BoxShadow(
                  color: (tone == VaultButtonTone.ink ? const Color(0xFF000000) : (gradient.colors.last)).withValues(
                    alpha: p.isDark ? 0.35 : 0.22,
                  ),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                  spreadRadius: -8,
                ),
              ]
            : null,
      ),
      child: content,
    );
    if (solid) {
      body = VaultSheen(
        loop: loading,
        trigger: enabled,
        radius: height / 2,
        color: p.isDark && tone == VaultButtonTone.ink ? p.accent.withValues(alpha: 0.35) : const Color(0x38FFFFFF),
        child: body,
      );
    }
    if (expand) body = SizedBox(width: double.infinity, child: body);

    return AnimatedOpacity(
      opacity: enabled || loading ? 1 : 0.38,
      duration: VaultMotion.quick,
      child: Semantics(
        label: loading ? '$label, loading' : null,
        child: VaultPress(
          onTap: enabled ? onPressed : null,
          semanticLabel: label,
          scale: 0.97,
          child: ConstrainedBox(constraints: const BoxConstraints(minHeight: 44, minWidth: 44), child: body),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Fields
// ---------------------------------------------------------------------------

InputDecoration _bare({String? hint, TextStyle? hintStyle}) => InputDecoration(
  isCollapsed: true,
  filled: false,
  hintText: hint,
  hintStyle: hintStyle,
  counterText: '',
  contentPadding: EdgeInsets.zero,
  border: InputBorder.none,
  enabledBorder: InputBorder.none,
  focusedBorder: InputBorder.none,
  disabledBorder: InputBorder.none,
  errorBorder: InputBorder.none,
  focusedErrorBorder: InputBorder.none,
);

/// Inline error under a field: icon + reason, sliding in and out.
class VaultFieldError extends StatelessWidget {
  const VaultFieldError(this.text, {super.key, this.center = false});

  final String? text;
  final bool center;

  @override
  Widget build(BuildContext context) {
    final p = context.vault;
    final t = context.vt;
    final e = text;
    final child = e == null
        ? const SizedBox(width: double.infinity, key: ValueKey('none'))
        : Padding(
            key: ValueKey(e),
            padding: EdgeInsets.only(top: 8, left: center ? 0 : 6),
            child: Row(
              mainAxisAlignment: center ? MainAxisAlignment.center : MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1.5),
                  child: Icon(LucideIcons.circleAlert, size: 13, color: p.negative),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      e,
                      textAlign: center ? TextAlign.center : TextAlign.start,
                      style: t.caption.vc(p.negative).vw(620),
                    ),
                  ),
                ),
              ],
            ),
          );
    return AnimatedSize(
      duration: context.reduceMotion ? Duration.zero : VaultMotion.state,
      curve: VaultMotion.settle,
      alignment: Alignment.topCenter,
      child: VaultSwap(alignment: center ? Alignment.topCenter : Alignment.topLeft, child: child),
    );
  }
}

/// Focus-tracking well shared by Vault fields: label inside, champagne
/// edge and soft glow on focus, red edge on error.
class _Well extends StatelessWidget {
  const _Well({
    required this.focused,
    required this.error,
    required this.enabled,
    required this.child,
    required this.onTap,
  });

  static const padding = EdgeInsets.fromLTRB(16, 11, 12, 12);

  final bool focused;
  final bool error;
  final bool enabled;
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.vault;
    final edge = error ? p.negative.withValues(alpha: focused ? 1 : 0.75) : (focused ? p.accent : p.well);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      excludeFromSemantics: true,
      onTap: enabled ? onTap : null,
      child: AnimatedOpacity(
        opacity: enabled ? 1 : 0.55,
        duration: VaultMotion.quick,
        child: AnimatedContainer(
          duration: context.reduceMotion ? Duration.zero : VaultMotion.state,
          curve: VaultMotion.settle,
          constraints: const BoxConstraints(minHeight: 60),
          padding: padding,
          decoration: BoxDecoration(
            color: focused ? p.wellFocus : p.well,
            borderRadius: BorderRadius.circular(VaultShape.well),
            border: Border.all(color: edge, width: focused || error ? 1.3 : 1),
            boxShadow: focused ? p.focusGlow(error ? p.negative : p.accent) : const [],
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Vault text input: label inside the well, optional leading glyph.
class VaultTextField extends StatefulWidget {
  const VaultTextField({
    super.key,
    this.label,
    this.hint,
    this.controller,
    this.errorText,
    this.prefixIcon,
    this.suffix,
    this.keyboardType,
    this.maxLines = 1,
    this.minLines,
    this.maxLength,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
    this.inputFormatters,
    this.onChanged,
    this.onSubmitted,
    this.enabled = true,
    this.autofocus = false,
    this.obscureText = false,
    this.focusNode,
  });

  final String? label;
  final String? hint;
  final TextEditingController? controller;
  final String? errorText;
  final IconData? prefixIcon;
  final Widget? suffix;
  final TextInputType? keyboardType;
  final int? maxLines;
  final int? minLines;
  final int? maxLength;
  final TextInputAction? textInputAction;
  final TextCapitalization textCapitalization;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool enabled;
  final bool autofocus;
  final bool obscureText;
  final FocusNode? focusNode;

  @override
  State<VaultTextField> createState() => _VaultTextFieldState();
}

class _VaultTextFieldState extends State<VaultTextField> {
  FocusNode? _own;
  FocusNode get _focus => widget.focusNode ?? (_own ??= FocusNode());

  @override
  void initState() {
    super.initState();
    _focus.addListener(_changed);
  }

  @override
  void didUpdateWidget(VaultTextField old) {
    super.didUpdateWidget(old);
    if (old.focusNode != widget.focusNode) {
      (old.focusNode ?? _own)?.removeListener(_changed);
      _focus.addListener(_changed);
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _focus.removeListener(_changed);
    _own?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.vault;
    final t = context.vt;
    final focused = _focus.hasFocus;
    final label = widget.label;
    final icon = widget.prefixIcon;
    final error = widget.errorText;
    final field = TextField(
      controller: widget.controller,
      focusNode: _focus,
      keyboardType: widget.keyboardType,
      maxLines: widget.obscureText ? 1 : widget.maxLines,
      minLines: widget.minLines,
      maxLength: widget.maxLength,
      textInputAction: widget.textInputAction,
      textCapitalization: widget.textCapitalization,
      inputFormatters: widget.inputFormatters,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      enabled: widget.enabled,
      autofocus: widget.autofocus,
      obscureText: widget.obscureText,
      style: t.input,
      decoration: _bare(hint: widget.hint, hintStyle: t.input.vw(500).vc(p.inkFaint)),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _Well(
          focused: focused,
          error: error != null,
          enabled: widget.enabled,
          onTap: _focus.requestFocus,
          child: Row(
            crossAxisAlignment: (widget.maxLines ?? 2) > 1 ? CrossAxisAlignment.start : CrossAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: AnimatedSwitcher(
                    duration: VaultMotion.quick,
                    child: Icon(icon, key: ValueKey(focused), size: 18, color: focused ? p.accentInk : p.inkMute),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (label != null) ...[
                      ExcludeSemantics(
                        child: AnimatedDefaultTextStyle(
                          duration: VaultMotion.quick,
                          style: t.label.copyWith(fontSize: 11.5, color: focused ? p.accentInk : p.inkMute),
                          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                      ),
                      const SizedBox(height: 5),
                    ],
                    Semantics(label: label, child: field),
                  ],
                ),
              ),
              if (widget.suffix != null) ...[const SizedBox(width: 8), widget.suffix!],
              if (!widget.enabled) ...[
                const SizedBox(width: 8),
                Icon(LucideIcons.lock, size: 14, color: p.inkMute),
              ],
            ],
          ),
        ),
        VaultFieldError(error),
      ],
    );
  }
}

/// Rupee amount input. [prominent] sets it as the hero of the sheet: a large
/// centred serif figure that resizes as it grows, with a formatted reading
/// underneath; otherwise it is a well like the other fields.
class VaultAmountField extends StatefulWidget {
  const VaultAmountField({
    super.key,
    required this.formatters,
    this.controller,
    this.label,
    this.hint = '0',
    this.errorText,
    this.onChanged,
    this.onSubmitted,
    this.focusNode,
    this.autofocus = false,
    this.enabled = true,
    this.textInputAction,
    this.prominent = false,
    this.tone,
  });

  final List<TextInputFormatter> formatters;
  final TextEditingController? controller;
  final String? label;
  final String hint;
  final String? errorText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final FocusNode? focusNode;
  final bool autofocus;
  final bool enabled;
  final TextInputAction? textInputAction;
  final bool prominent;

  /// Colour of the figure (e.g. positive for money coming in).
  final Color? tone;

  @override
  State<VaultAmountField> createState() => _VaultAmountFieldState();
}

class _VaultAmountFieldState extends State<VaultAmountField> {
  FocusNode? _ownFocus;
  TextEditingController? _ownText;
  FocusNode get _focus => widget.focusNode ?? (_ownFocus ??= FocusNode());
  TextEditingController get _text => widget.controller ?? (_ownText ??= TextEditingController());

  @override
  void initState() {
    super.initState();
    _focus.addListener(_changed);
    _text.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _focus.removeListener(_changed);
    _text.removeListener(_changed);
    _ownFocus?.dispose();
    _ownText?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.prominent ? _hero(context) : _compact(context);

  TextField _field(TextStyle style, TextStyle hintStyle, {TextAlign align = TextAlign.start, String? hint}) => TextField(
    controller: _text,
    focusNode: _focus,
    autofocus: widget.autofocus,
    enabled: widget.enabled,
    textInputAction: widget.textInputAction,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    inputFormatters: widget.formatters,
    textAlign: align,
    style: style,
    onChanged: widget.onChanged,
    onSubmitted: widget.onSubmitted,
    decoration: _bare(hint: hint ?? widget.hint, hintStyle: hintStyle),
  );

  Widget _compact(BuildContext context) {
    final p = context.vault;
    final t = context.vt;
    final focused = _focus.hasFocus;
    final style = t.figure.vc(widget.tone ?? p.ink);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _Well(
          focused: focused,
          error: widget.errorText != null,
          enabled: widget.enabled,
          onTap: _focus.requestFocus,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.label != null) ...[
                ExcludeSemantics(
                  child: Text(
                    widget.label!,
                    style: t.label.copyWith(fontSize: 11.5, color: focused ? p.accentInk : p.inkMute),
                  ),
                ),
                const SizedBox(height: 4),
              ],
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  ExcludeSemantics(
                    child: Text(MoneyFormatter.symbol, style: style.copyWith(fontSize: 22, color: p.inkMute)),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Semantics(label: widget.label, child: _field(style, style.copyWith(color: p.inkFaint))),
                  ),
                  if (!widget.enabled) Icon(LucideIcons.lock, size: 14, color: p.inkMute),
                ],
              ),
            ],
          ),
        ),
        VaultFieldError(widget.errorText),
      ],
    );
  }

  Widget _hero(BuildContext context) {
    final p = context.vault;
    final t = context.vt;
    final focused = _focus.hasFocus;
    final len = _text.text.length;
    final size = len <= 6 ? 60.0 : (len <= 9 ? 48.0 : 38.0);
    final color = widget.tone ?? p.ink;
    final style = t.hero.copyWith(fontSize: size, color: color);
    final parsed = Money.tryParse(_text.text);
    final reading = parsed == null || parsed.isZero ? null : parsed.format();
    final error = widget.errorText;
    // A descriptive hint reads as guidance under the figure, not inside it.
    final longHint = widget.hint.length > 6;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.label != null)
          ExcludeSemantics(
            child: Center(child: VaultLabelPill(text: widget.label!, active: focused)),
          ),
        const SizedBox(height: 10),
        VaultShake(
          trigger: error,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            excludeFromSemantics: true,
            onTap: widget.enabled ? _focus.requestFocus : null,
            child: SizedBox(
              height: 76,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  ExcludeSemantics(
                    child: AnimatedDefaultTextStyle(
                      duration: VaultMotion.state,
                      curve: VaultMotion.settle,
                      style: style.copyWith(fontSize: size * 0.55, color: len == 0 ? p.inkFaint : p.inkMute),
                      child: const Text(MoneyFormatter.symbol),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 36),
                      child: IntrinsicWidth(
                        child: Semantics(
                          label: widget.label,
                          child: AnimatedDefaultTextStyle(
                            duration: VaultMotion.state,
                            curve: VaultMotion.settle,
                            style: style,
                            child: _field(
                              style,
                              style.copyWith(color: p.inkFaint),
                              align: TextAlign.center,
                              hint: longHint ? '0' : widget.hint,
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
        ),
        // Focus line: grows from the centre while editing.
        Center(
          child: AnimatedContainer(
            duration: context.reduceMotion ? Duration.zero : const Duration(milliseconds: 520),
            curve: VaultMotion.spring,
            width: focused ? 132 : 44,
            height: 2,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(1),
              gradient: error != null
                  ? LinearGradient(colors: [p.negative, p.negative])
                  : (focused ? p.champagne : LinearGradient(colors: [p.hairlineStrong, p.hairlineStrong])),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Center(
          child: VaultSwap(
            alignment: Alignment.topCenter,
            child: error != null
                ? VaultFieldError(error, key: const ValueKey('err'), center: true)
                : Text(
                    reading ?? (longHint ? widget.hint : 'Tap to enter an amount'),
                    key: ValueKey(reading == null),
                    style: t.caption.vc(reading == null ? p.inkMute : p.inkSoft).copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

/// Small capsule label (centred above hero figures).
class VaultLabelPill extends StatelessWidget {
  const VaultLabelPill({super.key, required this.text, this.active = false, this.color});

  final String text;
  final bool active;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final p = context.vault;
    final t = context.vt;
    final c = color ?? (active ? p.accentInk : p.inkMute);
    return AnimatedContainer(
      duration: VaultMotion.state,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: active ? p.tint(p.accent, 0.12) : p.well,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(text.toUpperCase(), style: t.eyebrow.copyWith(color: c, letterSpacing: 1.4)),
    );
  }
}

/// Read-only well that opens the (Vault-themed) date picker. Shows the
/// date and how far it is from today.
class VaultDateField extends StatelessWidget {
  const VaultDateField({
    super.key,
    required this.value,
    required this.onPick,
    this.label,
    this.hint = 'Pick a date',
    this.errorText,
    this.enabled = true,
  });

  final DateTime? value;
  final VoidCallback onPick;
  final String? label;
  final String hint;
  final String? errorText;
  final bool enabled;

  static String? relative(DateTime? d) {
    if (d == null) return null;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final diff = DateTime(d.year, d.month, d.day).difference(today).inDays;
    return switch (diff) {
      0 => 'Today',
      -1 => 'Yesterday',
      1 => 'Tomorrow',
      < 0 && > -31 => '${-diff} days ago',
      > 0 && < 31 => 'In $diff days',
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final p = context.vault;
    final t = context.vt;
    final v = value;
    final display = v == null ? null : DateFormats.dayMonthYear.format(v);
    final rel = relative(v);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          button: true,
          enabled: enabled,
          label: label,
          value: display ?? hint,
          excludeSemantics: true,
          onTap: enabled ? onPick : null,
          child: VaultPress(
            onTap: enabled ? onPick : null,
            scale: 0.985,
            excludeSemantics: false,
            child: _Well(
              focused: false,
              error: errorText != null,
              enabled: enabled,
              onTap: null,
              child: LayoutBuilder(
                builder: (context, box) {
                  // Narrow (side-by-side) wells drop the ornaments first.
                  final roomy = box.maxWidth > 220;
                  return Row(
                    children: [
                      if (roomy) ...[
                        Icon(LucideIcons.calendarDays, size: 18, color: p.inkMute),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (label != null) ...[
                              Text(
                                label!,
                                style: t.label.copyWith(fontSize: 11.5, color: p.inkMute),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 5),
                            ],
                            Text(
                              display ?? hint,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: display == null ? t.input.vw(500).vc(p.inkFaint) : t.input,
                            ),
                          ],
                        ),
                      ),
                      if (rel != null && roomy) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(999)),
                          child: Text(rel, style: t.caption.copyWith(fontSize: 11.5).vw(650)),
                        ),
                      ],
                      const SizedBox(width: 4),
                      Icon(enabled ? LucideIcons.chevronDown : LucideIcons.lock, size: 16, color: p.inkMute),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
        VaultFieldError(errorText),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Selection
// ---------------------------------------------------------------------------

/// Segmented control: a raised capsule glides (on a spring) to the chosen
/// option inside a sunken track.
class VaultSegmented<T> extends StatelessWidget {
  const VaultSegmented({
    super.key,
    required this.values,
    required this.labels,
    required this.selected,
    required this.onChanged,
    this.counts,
    this.capsuleColor,
    this.selectedTextColor,
    this.enabled = true,
  });

  final List<T> values;
  final List<String> labels;
  final List<int?>? counts;
  final T selected;
  final ValueChanged<T> onChanged;

  /// Overrides the capsule (e.g. a tone for income / expense).
  final Color? capsuleColor;
  final Color? selectedTextColor;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final p = context.vault;
    final t = context.vt;
    final n = values.length;
    final index = values.indexOf(selected);
    final x = n <= 1 || index < 0 ? -1.0 : -1 + 2 * index / (n - 1);
    final capsule = capsuleColor ?? (p.isDark ? const Color(0xFF2C2C32) : p.surfaceRaised);
    final onCapsule = selectedTextColor ?? p.ink;
    final reduced = context.reduceMotion;
    return AnimatedOpacity(
      opacity: enabled ? 1 : 0.55,
      duration: VaultMotion.quick,
      child: Container(
        height: 50,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: p.well, borderRadius: BorderRadius.circular(999)),
        child: Stack(
          children: [
            if (index >= 0)
              Positioned.fill(
                child: AnimatedAlign(
                  alignment: Alignment(x, 0),
                  duration: reduced ? Duration.zero : const Duration(milliseconds: 560),
                  curve: VaultMotion.spring,
                  child: FractionallySizedBox(
                    widthFactor: 1 / n,
                    heightFactor: 1,
                    child: AnimatedContainer(
                      duration: VaultMotion.state,
                      decoration: BoxDecoration(
                        color: capsule,
                        borderRadius: BorderRadius.circular(999),
                        boxShadow: p.isDark && capsuleColor == null
                            ? null
                            : [
                                BoxShadow(
                                  color: (capsuleColor ?? const Color(0xFF1E160A)).withValues(alpha: 0.16),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                  spreadRadius: -2,
                                ),
                              ],
                      ),
                    ),
                  ),
                ),
              ),
            Row(
              children: [
                for (var i = 0; i < n; i++)
                  Expanded(
                    child: Semantics(
                      button: true,
                      selected: i == index,
                      inMutuallyExclusiveGroup: true,
                      label: counts?[i] == null ? labels[i] : '${labels[i]}, ${counts![i]}',
                      excludeSemantics: true,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: !enabled || i == index
                            ? null
                            : () {
                                HapticFeedback.selectionClick();
                                onChanged(values[i]);
                              },
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: AnimatedDefaultTextStyle(
                                    duration: VaultMotion.quick,
                                    style: t.chip
                                        .vw(i == index ? 720 : 600)
                                        .vc(i == index ? onCapsule : p.inkSoft),
                                    child: Text(labels[i], maxLines: 1, overflow: TextOverflow.ellipsis),
                                  ),
                                ),
                                if (counts?[i] != null) ...[
                                  const SizedBox(width: 6),
                                  Text(
                                    '${counts![i]}',
                                    style: t.caption.copyWith(fontSize: 11).vw(760).vc(p.inkMute),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
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

/// One chip in [VaultChips].
@immutable
class VaultChipItem<T> {
  const VaultChipItem(this.value, this.label, {this.icon});

  final T value;
  final String label;
  final IconData? icon;
}

/// Wrapping chip set (single or multi select). Chips never shrink their
/// labels; the set reflows instead.
class VaultChips<T> extends StatelessWidget {
  const VaultChips({
    super.key,
    required this.items,
    required this.selected,
    required this.onChanged,
    this.multiSelect = true,
    this.enabled = true,
  });

  final List<VaultChipItem<T>> items;
  final Set<T> selected;
  final ValueChanged<Set<T>> onChanged;
  final bool multiSelect;
  final bool enabled;

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
    return AnimatedOpacity(
      opacity: enabled ? 1 : 0.55,
      duration: VaultMotion.quick,
      child: IgnorePointer(
        ignoring: !enabled,
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final item in items)
              VaultChip(
                label: item.label,
                icon: item.icon,
                selected: selected.contains(item.value),
                onTap: () => _toggle(item.value),
              ),
          ],
        ),
      ),
    );
  }
}

/// A single selectable chip.
class VaultChip extends StatelessWidget {
  const VaultChip({super.key, required this.label, required this.selected, required this.onTap, this.icon});

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final p = context.vault;
    final t = context.vt;
    final fg = selected ? p.onInk : p.ink;
    final glyph = selected ? LucideIcons.check : icon;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: VaultPress(
        onTap: onTap,
        haptic: false,
        scale: 0.94,
        excludeSemantics: false,
        child: AnimatedContainer(
          duration: context.reduceMotion ? Duration.zero : VaultMotion.state,
          curve: VaultMotion.settle,
          constraints: const BoxConstraints(minHeight: 44),
          padding: EdgeInsets.fromLTRB(glyph == null ? 16 : 12, 10, 16, 10),
          decoration: BoxDecoration(
            color: selected ? null : p.well,
            gradient: selected ? p.inkGradient : null,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (glyph != null) ...[
                AnimatedSwitcher(
                  duration: VaultMotion.state,
                  switchInCurve: VaultMotion.pop,
                  transitionBuilder: (c, a) => ScaleTransition(scale: a, child: FadeTransition(opacity: a, child: c)),
                  child: Icon(glyph, key: ValueKey(selected), size: 15, color: selected ? p.onInk : p.inkSoft),
                ),
                const SizedBox(width: 7),
              ],
              AnimatedDefaultTextStyle(
                duration: VaultMotion.quick,
                style: t.chip.vw(selected ? 700 : 600).vc(fg),
                child: Text(label),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Grouping & feedback
// ---------------------------------------------------------------------------

/// Numbered section header: a serif ordinal, a title and one line of help.
/// Splits a long form into a few calm chapters.
class VaultSection extends StatelessWidget {
  const VaultSection({super.key, required this.title, this.index, this.hint, this.trailing, this.top = 30});

  final String title;
  final int? index;
  final String? hint;
  final Widget? trailing;
  final double top;

  @override
  Widget build(BuildContext context) {
    final p = context.vault;
    final t = context.vt;
    return Padding(
      padding: EdgeInsets.only(top: top, bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (index != null) ...[
            ExcludeSemantics(
              child: Text(
                index!.toString().padLeft(2, '0'),
                style: t.figure.copyWith(fontSize: 22, color: p.accentInk, height: 1),
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Semantics(header: true, child: Text(title.toUpperCase(), style: t.eyebrow.vc(p.inkSoft))),
                if (hint != null) ...[
                  const SizedBox(height: 4),
                  Text(hint!, style: t.caption.vc(p.inkMute)),
                ],
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// A rounded group of rows separated by inset hairlines (settings-style).
class VaultGroup extends StatelessWidget {
  const VaultGroup({super.key, required this.children, this.padding = EdgeInsets.zero});

  final List<Widget> children;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final p = context.vault;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: p.well,
        borderRadius: BorderRadius.circular(VaultShape.group),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Container(height: 1, color: p.hairline)),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// A quiet note with a tone emblem; used for locks, warnings and tips.
class VaultNote extends StatelessWidget {
  const VaultNote({
    super.key,
    required this.message,
    required this.color,
    required this.icon,
    this.title,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final Color color;
  final IconData icon;
  final String? title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final p = context.vault;
    final t = context.vt;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 16, 14),
      decoration: BoxDecoration(
        color: p.tint(color, 0.07),
        borderRadius: BorderRadius.circular(VaultShape.well),
        border: Border.all(color: p.tint(color, 0.14)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(shape: BoxShape.circle, color: p.tint(color, 0.14)),
            child: Icon(icon, size: 15, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null) ...[
                  Text(title!, style: t.heading.copyWith(fontSize: 14.5)),
                  const SizedBox(height: 3),
                ] else
                  const SizedBox(height: 5),
                Text(message, style: t.caption.vc(title == null ? p.ink : p.inkSoft).copyWith(fontSize: 13)),
                if (actionLabel != null && onAction != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: TextButton(
                      onPressed: onAction,
                      style: TextButton.styleFrom(
                        foregroundColor: color,
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(48, 36),
                      ),
                      child: Text(actionLabel!),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Toggle row: title, explanation that changes with the state, switch.
class VaultSwitchRow extends StatelessWidget {
  const VaultSwitchRow({super.key, required this.title, required this.value, required this.onChanged, this.message, this.icon});

  final String title;
  final String? message;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final p = context.vault;
    final t = context.vt;
    return MergeSemantics(
      child: VaultPress(
        onTap: onChanged == null ? null : () => onChanged!(!value),
        scale: 0.985,
        excludeSemantics: false,
        child: AnimatedContainer(
          duration: VaultMotion.state,
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          decoration: BoxDecoration(
            color: value ? p.tint(p.accent, 0.08) : p.well,
            borderRadius: BorderRadius.circular(VaultShape.well),
            border: Border.all(color: value ? p.tint(p.accent, 0.3) : p.well),
          ),
          child: Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: value ? p.accentInk : p.inkMute),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: t.heading.copyWith(fontSize: 14.5)),
                    if (message != null) ...[
                      const SizedBox(height: 3),
                      VaultSwap(child: Text(message!, key: ValueKey(message), style: t.caption)),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Switch(value: value, onChanged: onChanged),
            ],
          ),
        ),
      ),
    );
  }
}

/// A label/value line for summaries and receipts.
class VaultFact extends StatelessWidget {
  const VaultFact({super.key, required this.label, this.value, this.valueWidget, this.emphasis = false, this.color});

  final String label;
  final String? value;
  final Widget? valueWidget;
  final bool emphasis;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final p = context.vault;
    final t = context.vt;
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(child: Text(label, style: t.bodySoft)),
            const SizedBox(width: 12),
            Flexible(
              flex: 2,
              child: Align(
                alignment: AlignmentDirectional.centerEnd,
                child: valueWidget ??
                    Text(
                      value ?? '',
                      textAlign: TextAlign.end,
                      style: emphasis ? t.figure.copyWith(fontSize: 24, color: color ?? p.ink) : t.number.vc(color ?? p.ink),
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
