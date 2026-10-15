import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/money/money.dart';
import '../../kit/components/forms.dart';
import '../theme/finn_theme.dart';
import '../tokens/tokens.dart';

export '../../kit/components/forms.dart' show AmountInputFormatter;

/// Legacy names for the kit form fields. Each is a subclass of its kit
/// counterpart (same look, same parameters) so unmigrated sheets and test
/// finders keep working. New code uses the `Ledger*` names from the kit.

/// Text input with the label above the field. See [LedgerTextField].
class FinnTextField extends LedgerTextField {
  const FinnTextField({
    super.key,
    super.label,
    super.hint,
    super.helper,
    super.controller,
    super.errorText,
    super.prefixIcon,
    super.suffix,
    super.keyboardType,
    super.maxLines,
    super.minLines,
    super.maxLength,
    super.textInputAction,
    super.textCapitalization,
    super.inputFormatters,
    super.onChanged,
    super.onSubmitted,
    super.enabled,
    super.autofocus,
    super.obscureText,
    super.focusNode,
  });
}

/// Rupee amount input with a ₹ prefix. See [LedgerAmountField].
class AmountField extends LedgerAmountField {
  const AmountField({
    super.key,
    super.controller,
    super.label,
    super.hint,
    super.helper,
    super.errorText,
    super.onChanged,
    super.onSubmitted,
    super.focusNode,
    super.autofocus,
    super.enabled,
    super.textInputAction,
    super.hero,
  });

  /// Parses field text into [Money]; null when empty or invalid.
  static Money? parse(String text) => LedgerAmountField.parse(text);
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

/// Read-only field that opens a date picker. See [LedgerDateField].
class DateField extends LedgerDateField {
  const DateField({
    super.key,
    required super.value,
    required super.onChanged,
    required super.firstDate,
    required super.lastDate,
    super.label,
    super.hint,
    super.helper,
    super.errorText,
    super.enabled,
    super.onClear,
  });
}
