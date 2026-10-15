/// Form controls for sheets ("calm ledger").
///
/// How to build a form sheet (see `features/goals/presentation/goal_form_sheet.dart`):
///
/// ```dart
/// FinnSheetScaffold(
///   title: 'New goal',                       // no description unless it adds a fact
///   footer: LedgerButton(label: 'Create goal', expand: true, loading: busy, onPressed: submit),
///   child: Column(
///     crossAxisAlignment: CrossAxisAlignment.stretch,
///     children: [
///       LedgerAmountField(hero: true, label: 'Target', controller: target, errorText: errors['target']),
///       const SizedBox(height: LedgerForm.gap),
///       LedgerTextField(label: 'Name', controller: name, errorText: errors['name']),
///       const SizedBox(height: LedgerForm.gap),
///       LedgerField(label: 'Type', child: LedgerChoiceChips(options: ..., selected: v, onChanged: set)),
///       const SizedBox(height: LedgerForm.gap),
///       LedgerDateField(label: 'Date', value: d, firstDate: a, lastDate: b, onChanged: setD),
///     ],
///   ),
/// )
/// ```
///
/// Rules:
/// - The one amount that matters goes first as `LedgerAmountField(hero: true)`;
///   other amounts use the regular boxed field.
/// - `LedgerForm.gap` between fields, `LedgerForm.groupGap` before a new group.
/// - Labels name the field ("Name", not "Goal name" inside a goal sheet).
///   Mark optional fields with "(optional)"; put explanations in `helper`,
///   only when they say something the label does not.
/// - Errors go in `errorText` (field) or `LedgerField.errorText` (custom
///   pickers), never as loose red `Text`.
/// - Picking: `LedgerSegmented` for 2–3 mutually exclusive modes,
///   `LedgerChoiceChips` for up to ~8 short options (frequency, method),
///   `LedgerPickerField` (opens [showLedgerPicker]) for long lists
///   (categories, accounts). On/off settings use `LedgerSwitchRow`.
/// - `FinnTextField`, `AmountField` and `DateField` from `design_system/`
///   are subclasses of [LedgerTextField], [LedgerAmountField] and
///   [LedgerDateField]: they already render this look. Migrated files use
///   the `Ledger*` names; test helpers match either with `w is Ledger...`.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/money/money.dart';
import '../../core/money/money_format.dart';
import '../../core/time/dates.dart';
import '../tokens.dart';
import 'controls.dart';
import 'data.dart';
import 'sheets.dart';
import 'surfaces.dart';

/// Spacing between form fields.
abstract final class LedgerForm {
  /// Between two fields.
  static const double gap = 20;

  /// Before a new group of fields.
  static const double groupGap = Sp.xxl;
}

/// Label shown above a field.
class LedgerFieldLabel extends StatelessWidget {
  const LedgerFieldLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: Sp.sm),
    child: Text(text, style: context.type.label.copyWith(color: context.ink.ink)),
  );
}

/// Label, custom control, then a helper or error line. Use it around
/// pickers, chips and segmented controls so they line up with text fields.
class LedgerField extends StatelessWidget {
  const LedgerField({super.key, this.label, required this.child, this.helper, this.errorText});

  final String? label;
  final Widget child;

  /// Short supporting line under the control.
  final String? helper;

  /// Replaces [helper] in red.
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final l = label;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (l != null) LedgerFieldLabel(l),
        child,
        _FieldNote(helper: helper, error: errorText),
      ],
    );
  }
}

class _FieldNote extends StatelessWidget {
  const _FieldNote({this.helper, this.error});

  final String? helper;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final t = context.type;
    final e = error;
    final h = helper;
    if (e == null && h == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: Sp.xs + 2),
      child: e != null
          ? Semantics(
              liveRegion: true,
              child: Text(e, style: t.small.copyWith(color: c.red)),
            )
          : Text(h!, style: t.small),
    );
  }
}

/// Visible label above the field; the same label is announced on the
/// field itself. (`MergeSemantics` is not used: merging a text field with a
/// suffix widget trips the framework's `isMergedIntoParent` assertion.)
Widget _labelled(String? label, Widget field) {
  if (label == null) return field;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      ExcludeSemantics(child: LedgerFieldLabel(label)),
      Semantics(label: label, child: field),
    ],
  );
}

/// The boxed field decoration shared by text, amount, date and picker
/// fields: paper fill, hairline edge, ink edge on focus, red on error.
InputDecoration _boxDecoration(
  BuildContext context, {
  String? hint,
  TextStyle? hintStyle,
  String? errorText,
  String? helper,
  Widget? prefix,
  Widget? suffix,
  bool enabled = true,
}) {
  final c = context.ink;
  final t = context.type;
  OutlineInputBorder edge(Color color, [double width = 1]) => OutlineInputBorder(
    borderRadius: Rad.rMd,
    borderSide: BorderSide(color: color, width: width),
  );
  return InputDecoration(
    enabled: enabled,
    hintText: hint,
    hintStyle: hintStyle ?? t.body.copyWith(color: c.inkSoft),
    errorText: errorText,
    errorStyle: t.small.copyWith(color: c.red),
    errorMaxLines: 3,
    helperText: helper,
    helperStyle: t.small,
    helperMaxLines: 3,
    counterStyle: t.small,
    filled: true,
    fillColor: enabled ? c.paper : c.sunken,
    isDense: false,
    contentPadding: const EdgeInsets.symmetric(horizontal: Sp.lg - 2, vertical: Sp.md + 2),
    prefixIcon: prefix,
    prefixIconColor: c.inkSoft,
    prefixIconConstraints: const BoxConstraints(minWidth: 44, minHeight: 48),
    suffixIcon: suffix,
    suffixIconColor: c.inkSoft,
    border: edge(c.line),
    enabledBorder: edge(c.line),
    disabledBorder: edge(c.line),
    focusedBorder: edge(c.ink, 1.5),
    errorBorder: edge(c.red),
    focusedErrorBorder: edge(c.red, 1.5),
  );
}

/// Counter only once the text gets close to [maxLength].
Widget? _quietCounter(
  BuildContext context, {
  required int currentLength,
  required bool isFocused,
  required int? maxLength,
}) {
  final max = maxLength;
  if (max == null || currentLength < max * 0.8) return null;
  return Text('$currentLength / $max', style: context.type.small);
}

/// Text input with its label above.
class LedgerTextField extends StatelessWidget {
  const LedgerTextField({
    super.key,
    this.label,
    this.hint,
    this.helper,
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

  /// Supporting line under the field; hidden while [errorText] shows.
  final String? helper;
  final TextEditingController? controller;
  final String? errorText;

  /// Use only when the icon tells the field apart (search, %, phone).
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
    final c = context.ink;
    final t = context.type;
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
        buildCounter: _quietCounter,
        textInputAction: textInputAction,
        textCapitalization: textCapitalization,
        inputFormatters: inputFormatters,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        enabled: enabled,
        autofocus: autofocus,
        obscureText: obscureText,
        cursorColor: c.ink,
        style: t.body.copyWith(color: enabled ? c.ink : c.inkSoft),
        decoration: _boxDecoration(
          context,
          hint: hint,
          errorText: errorText,
          helper: helper,
          enabled: enabled,
          prefix: icon == null ? null : Icon(icon, size: 18),
          suffix: suffix,
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
    return TextEditingValue(
      text: stripped,
      selection: TextSelection.collapsed(offset: offset),
    );
  }
}

/// Rupee amount input with a ₹ prefix and strict formatting.
///
/// [hero] is for the one amount a sheet is about: a large tabular figure on
/// a hairline, no box. Other amounts use the regular boxed field.
class LedgerAmountField extends StatelessWidget {
  const LedgerAmountField({
    super.key,
    this.controller,
    this.label,
    this.hint = '0',
    this.helper,
    this.errorText,
    this.onChanged,
    this.onSubmitted,
    this.focusNode,
    this.autofocus = false,
    this.enabled = true,
    this.textInputAction,
    this.hero = false,
  });

  final TextEditingController? controller;
  final String? label;
  final String hint;
  final String? helper;
  final String? errorText;

  /// Parsed value on every edit (null when empty or invalid).
  final ValueChanged<Money?>? onChanged;
  final ValueChanged<Money?>? onSubmitted;
  final FocusNode? focusNode;
  final bool autofocus;
  final bool enabled;
  final TextInputAction? textInputAction;
  final bool hero;

  /// Parses field text into [Money]; null when empty or invalid.
  static Money? parse(String text) => Money.tryParse(text);

  static final RegExp _numeric = RegExp(r'^[\d.,\s]*$');

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final t = context.type;
    final change = onChanged;
    final submit = onSubmitted;
    final figure = hero ? t.figureXL : t.figure.copyWith(fontSize: 20, height: 1.2);
    final color = enabled ? c.ink : c.inkSoft;
    final hintStyle = _numeric.hasMatch(hint)
        ? figure.copyWith(color: hero ? c.inkFaint : c.inkSoft)
        : t.body.copyWith(color: c.inkSoft);
    final symbol = ExcludeSemantics(
      // Same size as the figure so the symbol shares its baseline; lighter so
      // the number leads.
      child: Text(
        MoneyFormatter.symbol,
        style: figure.copyWith(
          color: c.inkSoft,
          fontWeight: FontWeight.w400,
          fontVariations: const [FontVariation.weight(400)],
        ),
      ),
    );
    InputDecoration decoration;
    if (hero) {
      UnderlineInputBorder line(Color color, [double width = 1]) => UnderlineInputBorder(
        borderSide: BorderSide(color: color, width: width),
      );
      decoration = InputDecoration(
        enabled: enabled,
        hintText: hint,
        hintStyle: hintStyle,
        errorText: errorText,
        errorStyle: t.small.copyWith(color: c.red),
        errorMaxLines: 3,
        helperText: helper,
        helperStyle: t.small,
        helperMaxLines: 3,
        filled: false,
        contentPadding: const EdgeInsets.only(bottom: Sp.sm, top: Sp.xs),
        prefixIcon: Padding(
          padding: const EdgeInsets.only(right: Sp.sm),
          child: symbol,
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
        border: line(c.line),
        enabledBorder: line(c.lineStrong),
        disabledBorder: line(c.line),
        focusedBorder: line(c.ink, 1.5),
        errorBorder: line(c.red),
        focusedErrorBorder: line(c.red, 1.5),
      );
    } else {
      decoration = _boxDecoration(
        context,
        hint: hint,
        hintStyle: hintStyle,
        errorText: errorText,
        helper: helper,
        enabled: enabled,
        prefix: Padding(
          padding: const EdgeInsets.only(left: Sp.lg - 2, right: Sp.sm),
          child: symbol,
        ),
      ).copyWith(prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0));
    }
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
        cursorColor: c.ink,
        style: figure.copyWith(color: color),
        onChanged: change == null ? null : (s) => change(parse(s)),
        onSubmitted: submit == null ? null : (s) => submit(parse(s)),
        decoration: decoration,
      ),
    );
  }
}

/// Read-only field that opens a date picker; shows `d MMM yyyy`. With
/// [onClear], a set date gets a clear button (optional dates).
class LedgerDateField extends StatelessWidget {
  const LedgerDateField({
    super.key,
    required this.value,
    required this.onChanged,
    required this.firstDate,
    required this.lastDate,
    this.label,
    this.hint = 'Pick a date',
    this.helper,
    this.errorText,
    this.enabled = true,
    this.onClear,
  });

  final DateTime? value;
  final ValueChanged<DateTime> onChanged;
  final DateTime firstDate;
  final DateTime lastDate;
  final String? label;
  final String hint;
  final String? helper;
  final String? errorText;
  final bool enabled;
  final VoidCallback? onClear;

  Future<void> _pick(BuildContext context) async {
    final current = value ?? DateTime.now();
    final initial = current.isBefore(firstDate) ? firstDate : (current.isAfter(lastDate) ? lastDate : current);
    final picked = await showLedgerDatePicker(context, initial: initial, first: firstDate, last: lastDate);
    if (picked != null) onChanged(picked.dateOnly);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final t = context.type;
    final v = value;
    final display = v == null ? null : DateFormats.dayMonthYear.format(v);
    final clear = onClear;
    return _labelled(
      label,
      Semantics(
        button: true,
        enabled: enabled,
        value: display ?? hint,
        child: InkWell(
          borderRadius: Rad.rMd,
          onTap: enabled ? () => _pick(context) : null,
          child: InputDecorator(
            isEmpty: v == null,
            decoration: _boxDecoration(
              context,
              hint: hint,
              errorText: errorText,
              helper: helper,
              enabled: enabled,
              prefix: const Icon(LucideIcons.calendar, size: 18),
              suffix: v != null && clear != null && enabled
                  ? IconButton(
                      tooltip: 'Clear date',
                      icon: Icon(LucideIcons.x, size: 18, color: c.inkSoft),
                      onPressed: clear,
                    )
                  : Icon(LucideIcons.chevronDown, size: 18, color: c.inkSoft),
            ),
            child: Text(
              display ?? '',
              style: t.body.copyWith(color: enabled ? c.ink : c.inkSoft),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
    );
  }
}

/// Material date picker in ledger colours.
Future<DateTime?> showLedgerDatePicker(
  BuildContext context, {
  required DateTime initial,
  required DateTime first,
  required DateTime last,
}) {
  final c = context.ink;
  return showDatePicker(
    context: context,
    initialDate: initial,
    firstDate: first,
    lastDate: last,
    barrierColor: c.scrim,
    builder: (ctx, child) {
      final theme = Theme.of(ctx);
      return Theme(
        data: theme.copyWith(
          colorScheme: theme.colorScheme.copyWith(
            primary: c.ink,
            onPrimary: c.onInk,
            surface: c.surface,
            onSurface: c.ink,
            surfaceTint: Colors.transparent,
          ),
          datePickerTheme: theme.datePickerTheme.copyWith(
            backgroundColor: c.surface,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: Rad.rLg,
              side: BorderSide(color: c.line),
            ),
          ),
        ),
        child: child!,
      );
    },
  );
}

/// One choice for [LedgerChoiceChips], [LedgerPickerField] and
/// [showLedgerPicker].
@immutable
class LedgerOption<T> {
  const LedgerOption(this.value, this.label, {this.icon, this.leading, this.subtitle, this.key});

  final T value;
  final String label;

  /// Small icon (chips) or icon well (rows). Ignored when [leading] is set.
  final IconData? icon;

  /// Custom leading widget in rows (e.g. a `CategoryMark`).
  final Widget? leading;
  final String? subtitle;
  final Key? key;
}

/// Single-choice chips that wrap onto new lines; for a handful of short
/// options (frequency, payment method, goal type).
class LedgerChoiceChips<T> extends StatelessWidget {
  const LedgerChoiceChips({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.enabled = true,
    this.onCleared,
  });

  final List<LedgerOption<T>> options;
  final T? selected;
  final ValueChanged<T> onChanged;
  final bool enabled;

  /// When set, tapping the selected chip clears the choice.
  final VoidCallback? onCleared;

  @override
  Widget build(BuildContext context) {
    final chips = Wrap(
      spacing: Sp.sm,
      runSpacing: Sp.sm,
      children: [
        for (final o in options)
          LedgerChip(
            key: o.key,
            label: o.label,
            icon: o.icon,
            selected: o.value == selected,
            onTap: () {
              if (o.value != selected) {
                onChanged(o.value);
              } else {
                onCleared?.call();
              }
            },
          ),
      ],
    );
    if (enabled) return chips;
    return IgnorePointer(child: Opacity(opacity: 0.5, child: chips));
  }
}

/// A selectable row: radio-style choice in a list. Selected shows a check.
class LedgerOptionRow extends StatelessWidget {
  const LedgerOptionRow({
    super.key,
    required this.title,
    required this.selected,
    required this.onTap,
    this.subtitle,
    this.leading,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final t = context.type;
    final lead = leading;
    final sub = subtitle;
    return Semantics(
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Sp.lg, vertical: Sp.sm + 2),
            child: Row(
              children: [
                if (lead != null) ...[lead, const SizedBox(width: Sp.md + 2)],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(title, style: selected ? t.bodyStrong : t.body),
                      if (sub != null) ...[const SizedBox(height: 2), Text(sub, style: t.label)],
                    ],
                  ),
                ),
                const SizedBox(width: Sp.md),
                SizedBox.square(
                  dimension: 20,
                  child: selected ? Icon(LucideIcons.check, size: 20, color: c.ink) : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Widget? _optionLeading<T>(LedgerOption<T> o, {double size = 36}) =>
    o.leading ?? (o.icon == null ? null : IconWell(icon: o.icon!, size: size));

/// Opens a sheet listing [options]; resolves with the chosen value, or
/// null when dismissed. Long lists (over 8) get a search box.
Future<T?> showLedgerPicker<T>(
  BuildContext context, {
  required String title,
  required List<LedgerOption<T>> options,
  T? selected,
  String searchHint = 'Search',
}) {
  return showFinnSheet<T>(
    context,
    builder: (ctx) => _PickerSheet<T>(title: title, options: options, selected: selected, searchHint: searchHint),
  );
}

class _PickerSheet<T> extends StatefulWidget {
  const _PickerSheet({required this.title, required this.options, required this.selected, required this.searchHint});

  final String title;
  final List<LedgerOption<T>> options;
  final T? selected;
  final String searchHint;

  @override
  State<_PickerSheet<T>> createState() => _PickerSheetState<T>();
}

class _PickerSheetState<T> extends State<_PickerSheet<T>> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    final q = _query.trim().toLowerCase();
    final visible = q.isEmpty
        ? widget.options
        : widget.options
              .where((o) => o.label.toLowerCase().contains(q) || (o.subtitle?.toLowerCase().contains(q) ?? false))
              .toList();
    return FinnSheetScaffold(
      title: widget.title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.options.length > 8) ...[
            LedgerSearchField(hint: widget.searchHint, onChanged: (v) => setState(() => _query = v)),
            const SizedBox(height: Sp.md),
          ],
          if (visible.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Sp.xl),
              child: Text('Nothing matches', style: t.label, textAlign: TextAlign.center),
            )
          else
            LedgerPanel(
              dividerIndent: Sp.lg,
              children: [
                for (final o in visible)
                  LedgerOptionRow(
                    key: o.key,
                    title: o.label,
                    subtitle: o.subtitle,
                    leading: _optionLeading(o),
                    selected: o.value == widget.selected,
                    onTap: () => Navigator.of(context).pop(o.value),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Field that shows the current choice and opens [showLedgerPicker]; for
/// long lists such as categories or accounts.
class LedgerPickerField<T> extends StatelessWidget {
  const LedgerPickerField({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.label,
    this.pickerTitle,
    this.hint = 'Choose',
    this.helper,
    this.errorText,
    this.enabled = true,
    this.searchHint = 'Search',
  });

  final List<LedgerOption<T>> options;
  final T? value;
  final ValueChanged<T> onChanged;
  final String? label;

  /// Sheet title; defaults to [label].
  final String? pickerTitle;
  final String hint;
  final String? helper;
  final String? errorText;
  final bool enabled;
  final String searchHint;

  Future<void> _open(BuildContext context) async {
    final picked = await showLedgerPicker<T>(
      context,
      title: pickerTitle ?? label ?? hint,
      options: options,
      selected: value,
      searchHint: searchHint,
    );
    if (picked != null && picked != value) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final t = context.type;
    LedgerOption<T>? current;
    for (final o in options) {
      if (o.value == value) current = o;
    }
    final cur = current;
    final lead = cur == null
        ? null
        : (cur.leading ?? (cur.icon == null ? null : Icon(cur.icon, size: 18, color: c.ink)));
    return _labelled(
      label,
      Semantics(
        button: true,
        enabled: enabled,
        value: cur?.label ?? hint,
        child: InkWell(
          borderRadius: Rad.rMd,
          onTap: enabled ? () => _open(context) : null,
          child: InputDecorator(
            isEmpty: cur == null,
            decoration: _boxDecoration(
              context,
              hint: hint,
              errorText: errorText,
              helper: helper,
              enabled: enabled,
              suffix: Icon(LucideIcons.chevronDown, size: 18, color: c.inkSoft),
            ),
            child: cur == null
                ? const SizedBox(height: 22)
                : Row(
                    children: [
                      if (lead != null) ...[
                        SizedBox(height: 22, child: FittedBox(child: lead)),
                        const SizedBox(width: Sp.sm + 2),
                      ],
                      Expanded(
                        child: Text(
                          cur.label,
                          style: t.body.copyWith(color: enabled ? c.ink : c.inkSoft),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/// Title, optional explanation and a switch; the whole row toggles.
class LedgerSwitchRow extends StatelessWidget {
  const LedgerSwitchRow({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.enabled = true,
  });

  final String title;

  /// Say what the current setting does, in one line.
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final t = context.type;
    final sub = subtitle;
    return MergeSemantics(
      child: InkWell(
        borderRadius: Rad.rMd,
        onTap: enabled ? () => onChanged(!value) : null,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: Sp.sm),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(title, style: t.bodyStrong),
                      if (sub != null) ...[const SizedBox(height: 2), Text(sub, style: t.label)],
                    ],
                  ),
                ),
                const SizedBox(width: Sp.md),
                Switch(
                  value: value,
                  onChanged: enabled ? onChanged : null,
                  thumbColor: WidgetStateProperty.resolveWith(
                    (s) => s.contains(WidgetState.selected) ? c.onInk : c.inkSoft,
                  ),
                  trackColor: WidgetStateProperty.resolveWith(
                    (s) => s.contains(WidgetState.selected) ? c.ink : c.sunken,
                  ),
                  trackOutlineColor: WidgetStateProperty.resolveWith(
                    (s) => s.contains(WidgetState.selected) ? Colors.transparent : c.lineStrong,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
