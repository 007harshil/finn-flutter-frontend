import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/money/money.dart';
import '../../core/money/money_format.dart';
import '../../core/time/dates.dart';
import '../theme/finn_theme.dart';
import '../tokens/tokens.dart';

/// Field label rendered above inputs.
class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: Space.x1_5),
        child: Text(text, style: context.text.label),
      );
}

Widget _labelled(String? label, Widget field) {
  if (label == null) return field;
  // The visible label is announced on the field itself. MergeSemantics is not
  // used: merging a text field with a suffix widget trips the framework's
  // `isMergedIntoParent` assertion while editing.
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      ExcludeSemantics(child: _FieldLabel(label)),
      Semantics(label: label, child: field),
    ],
  );
}

/// Text input with the label above the field.
class FinnTextField extends StatelessWidget {
  const FinnTextField({
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
  Widget build(BuildContext context) {
    final icon = prefixIcon;
    return _labelled(
      label,
      TextField(
        controller: controller,
        focusNode: focusNode,
        keyboardType: keyboardType,
        maxLines: obscureText ? 1 : maxLines,
        minLines: minLines,
        maxLength: maxLength,
        textInputAction: textInputAction,
        textCapitalization: textCapitalization,
        inputFormatters: inputFormatters,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        enabled: enabled,
        autofocus: autofocus,
        obscureText: obscureText,
        style: context.text.body.copyWith(fontSize: 15, fontWeight: FontWeight.w600),
        decoration: InputDecoration(
          hintText: hint,
          errorText: errorText,
          errorMaxLines: 3,
          prefixIcon: icon == null ? null : Icon(icon, size: 18),
          suffixIcon: suffix,
        ),
      ),
    );
  }
}

/// Restricts input to a non-negative rupee amount: max 12 integer digits
/// and 2 decimals.
class AmountInputFormatter extends TextInputFormatter {
  const AmountInputFormatter();

  static final RegExp _pattern = RegExp(r'^\d{0,12}(\.\d{0,2})?$');
  static final RegExp _leadingZeros = RegExp(r'^0+(?=\d)');

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final text = newValue.text;
    if (text.isEmpty) return newValue;
    if (text == '.') {
      return const TextEditingValue(text: '0.', selection: TextSelection.collapsed(offset: 2));
    }
    if (!_pattern.hasMatch(text)) return oldValue;
    final stripped = text.replaceFirst(_leadingZeros, '');
    if (stripped == text) return newValue;
    final removed = text.length - stripped.length;
    final offset = (newValue.selection.extentOffset - removed).clamp(0, stripped.length);
    return TextEditingValue(text: stripped, selection: TextSelection.collapsed(offset: offset));
  }
}

/// Large rupee amount input with a ₹ prefix and strict formatting.
class AmountField extends StatelessWidget {
  const AmountField({
    super.key,
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
  });

  final TextEditingController? controller;
  final String? label;
  final String hint;
  final String? errorText;

  /// Parsed value on every edit (null when empty or invalid).
  final ValueChanged<Money?>? onChanged;
  final ValueChanged<Money?>? onSubmitted;
  final FocusNode? focusNode;
  final bool autofocus;
  final bool enabled;
  final TextInputAction? textInputAction;

  /// Parses field text into [Money]; null when empty or invalid.
  static Money? parse(String text) => Money.tryParse(text);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final style = context.text.amountLarge.copyWith(fontSize: 28, fontWeight: FontWeight.w900);
    final change = onChanged;
    final submit = onSubmitted;
    return _labelled(
      label,
      TextField(
        controller: controller,
        focusNode: focusNode,
        autofocus: autofocus,
        enabled: enabled,
        textInputAction: textInputAction,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: const [AmountInputFormatter()],
        style: style,
        onChanged: change == null ? null : (s) => change(parse(s)),
        onSubmitted: submit == null ? null : (s) => submit(parse(s)),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: style.copyWith(color: c.textTertiary),
          errorText: errorText,
          errorMaxLines: 3,
          contentPadding: const EdgeInsets.symmetric(horizontal: Space.x4, vertical: Space.x3),
          prefixIcon: Padding(
            padding: const EdgeInsets.only(left: Space.x4, right: Space.x1_5),
            child: ExcludeSemantics(
              child: Text(
                MoneyFormatter.symbol,
                style: style.copyWith(color: c.textSecondary),
              ),
            ),
          ),
          prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
        ),
      ),
    );
  }
}

/// Pill search field with debounced [onChanged] and a clear button.
class FinnSearchField extends StatefulWidget {
  const FinnSearchField({
    super.key,
    required this.onChanged,
    this.controller,
    this.hint = 'Search',
    this.debounce = const Duration(milliseconds: 300),
    this.onSubmitted,
    this.focusNode,
    this.autofocus = false,
  });

  final ValueChanged<String> onChanged;
  final TextEditingController? controller;
  final String hint;
  final Duration debounce;
  final ValueChanged<String>? onSubmitted;
  final FocusNode? focusNode;
  final bool autofocus;

  @override
  State<FinnSearchField> createState() => _FinnSearchFieldState();
}

class _FinnSearchFieldState extends State<FinnSearchField> {
  TextEditingController? _owned;
  Timer? _timer;

  TextEditingController get _controller => widget.controller ?? (_owned ??= TextEditingController());

  void _changed(String value) {
    _timer?.cancel();
    if (widget.debounce == Duration.zero) {
      widget.onChanged(value);
      return;
    }
    _timer = Timer(widget.debounce, () => widget.onChanged(value));
  }

  void _clear() {
    _timer?.cancel();
    _controller.clear();
    widget.onChanged('');
  }

  @override
  void dispose() {
    _timer?.cancel();
    _owned?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    const pill = OutlineInputBorder(borderRadius: Radii.rFull, borderSide: BorderSide.none);
    return TextField(
      controller: _controller,
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      onChanged: _changed,
      onSubmitted: widget.onSubmitted,
      textInputAction: TextInputAction.search,
      style: context.text.body.copyWith(fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        hintText: widget.hint,
        filled: true,
        fillColor: c.surfaceMuted,
        border: pill,
        enabledBorder: pill,
        focusedBorder: OutlineInputBorder(
          borderRadius: Radii.rFull,
          borderSide: BorderSide(color: c.focusRing, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: Space.x4, vertical: Space.x3),
        prefixIcon: const Icon(LucideIcons.search, size: 18),
        suffixIcon: ValueListenableBuilder<TextEditingValue>(
          valueListenable: _controller,
          builder: (context, value, _) => value.text.isEmpty
              ? const SizedBox.shrink()
              : IconButton(
                  tooltip: 'Clear search',
                  onPressed: _clear,
                  icon: Icon(LucideIcons.x, size: 18, color: c.textSecondary),
                ),
        ),
      ),
    );
  }
}

/// Read-only field that opens a date picker; shows `d MMM yyyy`.
class DateField extends StatelessWidget {
  const DateField({
    super.key,
    required this.value,
    required this.onChanged,
    required this.firstDate,
    required this.lastDate,
    this.label,
    this.hint = 'Pick a date',
    this.errorText,
    this.enabled = true,
  });

  final DateTime? value;
  final ValueChanged<DateTime> onChanged;
  final DateTime firstDate;
  final DateTime lastDate;
  final String? label;
  final String hint;
  final String? errorText;
  final bool enabled;

  Future<void> _pick(BuildContext context) async {
    final current = value ?? DateTime.now();
    final initial = current.isBefore(firstDate)
        ? firstDate
        : (current.isAfter(lastDate) ? lastDate : current);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: firstDate,
      lastDate: lastDate,
    );
    if (picked != null) onChanged(picked.dateOnly);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final v = value;
    final display = v == null ? null : DateFormats.dayMonthYear.format(v);
    return _labelled(
      label,
      Semantics(
        button: true,
        enabled: enabled,
        value: display ?? hint,
        child: InkWell(
          borderRadius: Radii.rLg,
          onTap: enabled ? () => _pick(context) : null,
          child: InputDecorator(
            isEmpty: v == null,
            decoration: InputDecoration(
              enabled: enabled,
              errorText: errorText,
              hintText: hint,
              prefixIcon: const Icon(LucideIcons.calendar, size: 18),
              suffixIcon: Icon(LucideIcons.chevronDown, size: 18, color: c.textTertiary),
            ),
            child: Text(
              display ?? '',
              style: context.text.body.copyWith(fontSize: 15, fontWeight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
    );
  }
}
