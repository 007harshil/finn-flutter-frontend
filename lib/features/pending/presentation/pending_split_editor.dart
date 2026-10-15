import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../kit/kit.dart';
import '../domain/pending_payment.dart';
import 'pending_ui.dart';

/// One line of the split: the user or another person, with the field for
/// their value.
@immutable
class SplitSlot {
  const SplitSlot({
    required this.key,
    required this.name,
    required this.controller,
    this.isMe = false,
  });

  /// Stable id for keys: `me` or the person's slot id.
  final String key;
  final String name;
  final TextEditingController controller;
  final bool isMe;
}

/// Parses what was typed for one person into split units (see
/// [PendingSplit.part]). Empty counts as zero; null when it is not a number.
int? parseSplitValue(String text, SplitMethod method) {
  final s = text.trim().replaceAll(RegExp(r'[₹,%\s]'), '').replaceAll('−', '-');
  if (s.isEmpty || s == '-') return 0;
  if (method == SplitMethod.shares) return int.tryParse(s);
  final n = num.tryParse(s);
  return n == null ? null : (n * 100).round();
}

/// Starting values when the method or the people change, so the split
/// already adds up: equal percentages, one share each, equal amounts.
List<String> defaultSplitValues(SplitMethod method, int count, Money? total) {
  if (count == 0) return const [];
  switch (method) {
    case SplitMethod.equally:
    case SplitMethod.adjustment:
      return List.filled(count, '');
    case SplitMethod.shares:
      return List.filled(count, '1');
    case SplitMethod.percent:
      return [
        for (final bps in SplitCalculator.compute(
          const Money.fromPaise(10000),
          SplitMethod.equally,
          List.filled(count, 0),
        ).shares)
          formatSplitPercent(bps.paise).replaceAll('%', ''),
      ];
    case SplitMethod.exact:
      if (total == null || !total.isPositive) return List.filled(count, '');
      return [
        for (final m in SplitCalculator.compute(
          total,
          SplitMethod.equally,
          List.filled(count, 0),
        ).shares)
          MoneyFormatter.editable(m),
      ];
  }
}

/// How the bill is divided: method chips, "include me", one line per person
/// with their value and resulting share, and whether it adds up.
class PendingSplitEditor extends StatelessWidget {
  const PendingSplitEditor({
    super.key,
    required this.direction,
    required this.total,
    required this.method,
    required this.onMethod,
    required this.includeMe,
    required this.onIncludeMe,
    required this.slots,
    required this.onValueChanged,
    this.errorText,
  });

  final PendingDirection direction;

  /// Parsed total; null while the amount field is empty or invalid.
  final Money? total;
  final SplitMethod method;
  final ValueChanged<SplitMethod> onMethod;
  final bool includeMe;

  /// Null when the user cannot be part of the bill (they owe the money).
  final ValueChanged<bool>? onIncludeMe;
  final List<SplitSlot> slots;
  final VoidCallback onValueChanged;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final values = [
      for (final s in slots) parseSplitValue(s.controller.text, method),
    ];
    final SplitOutcome? outcome = total == null
        ? null
        : (values.contains(null)
              ? const SplitOutcome.invalid('Some values are not numbers.')
              : SplitCalculator.compute(total!, method, values.cast<int>()));
    final shares = outcome != null && outcome.isValid ? outcome.shares : null;
    final hasMe = slots.isNotEmpty && slots.first.isMe;
    final others = shares == null
        ? null
        : Money.sum(hasMe ? shares.skip(1) : shares);
    final error =
        errorText ?? (outcome?.isValid == false ? outcome!.error : null);

    return Column(
      key: const ValueKey('pending-split-editor'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LedgerField(
          label: 'Split',
          helper: method.hint,
          child: LedgerChoiceChips<SplitMethod>(
            options: [
              for (final m in SplitMethod.values)
                LedgerOption(
                  m,
                  m.label,
                  key: ValueKey('split-method:${m.name}'),
                ),
            ],
            selected: method,
            onChanged: onMethod,
          ),
        ),
        if (onIncludeMe != null) ...[
          const SizedBox(height: Sp.md),
          LedgerSwitchRow(
            key: const ValueKey('split-include-me'),
            title: 'Include me',
            subtitle: includeMe
                ? 'You had a part too. Only the others owe you.'
                : 'You only paid. The bill is split between the others.',
            value: includeMe,
            onChanged: onIncludeMe!,
          ),
        ],
        const SizedBox(height: Sp.md),
        DecoratedBox(
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: Rad.rLg,
            border: Border.all(color: error != null ? c.red : c.line),
          ),
          child: Column(
            children: [
              for (var i = 0; i < slots.length; i++) ...[
                if (i > 0) const LedgerDivider(indent: Sp.lg),
                _SlotRow(
                  slot: slots[i],
                  method: method,
                  share: shares?[i],
                  onChanged: onValueChanged,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: Sp.sm),
        _Summary(
          key: const ValueKey('split-summary'),
          error: error,
          line: shares == null
              ? (total == null ? 'Enter the total to see each share.' : null)
              : _summary(shares, values.cast<int>()),
          others: others,
          count: slots.length - (hasMe ? 1 : 0),
          direction: direction,
        ),
      ],
    );
  }

  String _summary(List<Money> shares, List<int> values) => switch (method) {
    SplitMethod.equally =>
      shares.toSet().length == 1
          ? '${shares.first.format()} each'
          : 'About ${shares.last.format()} each (paise rounded)',
    SplitMethod.exact => 'Adds up to ${total!.format()}',
    SplitMethod.percent => 'Adds up to 100%',
    SplitMethod.shares => () {
      final n = values.fold<int>(0, (a, b) => a + b);
      return '$n ${n == 1 ? 'share' : 'shares'} · '
          '${Money.fromPaise((total!.paise / n).round()).format()} per share';
    }(),
    SplitMethod.adjustment =>
      'Equal part, then each adjustment added or taken off',
  };
}

class _SlotRow extends StatelessWidget {
  const _SlotRow({
    required this.slot,
    required this.method,
    required this.share,
    required this.onChanged,
  });

  final SplitSlot slot;
  final SplitMethod method;
  final Money? share;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final t = context.type;
    final (prefix, suffix, hint) = switch (method) {
      SplitMethod.exact => ('₹', null, '0'),
      SplitMethod.adjustment => ('±₹', null, '0'),
      SplitMethod.percent => (null, '%', '0'),
      SplitMethod.shares => (null, 'x', '1'),
      SplitMethod.equally => (null, null, ''),
    };
    final allowed = switch (method) {
      SplitMethod.shares => RegExp(r'[0-9]'),
      SplitMethod.adjustment => RegExp(r'[0-9.\-−]'),
      _ => RegExp(r'[0-9.]'),
    };
    OutlineInputBorder edge(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: Rad.rMd,
          borderSide: BorderSide(color: color, width: width),
        );
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Sp.lg, vertical: Sp.sm),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    slot.isMe ? 'You' : slot.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.bodyStrong,
                  ),
                  if (slot.isMe) Text('Your share, not owed', style: t.small),
                ],
              ),
            ),
            if (method.takesValues) ...[
              const SizedBox(width: Sp.sm),
              SizedBox(
                width: 92,
                child: TextField(
                  key: ValueKey('split-value:${slot.key}'),
                  controller: slot.controller,
                  onChanged: (_) => onChanged(),
                  keyboardType: TextInputType.numberWithOptions(
                    decimal: method != SplitMethod.shares,
                    signed: method == SplitMethod.adjustment,
                  ),
                  inputFormatters: [FilteringTextInputFormatter.allow(allowed)],
                  textAlign: TextAlign.end,
                  cursorColor: c.ink,
                  style: t.bodyStrong,
                  decoration: InputDecoration(
                    isDense: true,
                    filled: true,
                    fillColor: c.paper,
                    hintText: hint,
                    hintStyle: t.body.copyWith(color: c.inkSoft),
                    prefixText: prefix,
                    suffixText: suffix,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: Sp.sm + 2,
                      vertical: Sp.md,
                    ),
                    border: edge(c.line),
                    enabledBorder: edge(c.line),
                    focusedBorder: edge(c.ink, 1.5),
                  ),
                ),
              ),
            ],
            const SizedBox(width: Sp.md),
            SizedBox(
              width: 84,
              child: Align(
                alignment: Alignment.centerRight,
                child: share == null
                    ? Text('—', style: t.bodyStrong.copyWith(color: c.inkFaint))
                    : FittedBox(
                        fit: BoxFit.scaleDown,
                        child: AmountText(
                          share!,
                          key: ValueKey('split-share:${slot.key}'),
                          style: t.figureSmall.copyWith(
                            color: slot.isMe ? c.inkSoft : c.ink,
                          ),
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({
    super.key,
    required this.error,
    required this.line,
    required this.others,
    required this.count,
    required this.direction,
  });

  final String? error;
  final String? line;
  final Money? others;
  final int count;
  final PendingDirection direction;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final t = context.type;
    if (error != null) {
      return Semantics(
        liveRegion: true,
        child: Text(error!, style: t.small.copyWith(color: c.red)),
      );
    }
    return Text.rich(
      TextSpan(
        children: [
          if (line != null) TextSpan(text: line),
          if (others != null)
            TextSpan(
              text: direction.isOwe
                  ? ' · You owe ${others!.format()} to $count people'
                  : ' · $count people owe you ${others!.format()}',
              style: t.small.copyWith(
                color: c.ink,
                fontWeight: FontWeight.w700,
              ),
            ),
        ],
      ),
      style: t.small,
    );
  }
}
