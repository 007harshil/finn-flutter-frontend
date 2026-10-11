import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../design_system/design_system.dart';
import '../domain/pending_payment.dart';
import 'pending_ui.dart';

/// One line of the split: the user or another person, with the field for
/// their value.
@immutable
class SplitSlot {
  const SplitSlot({required this.key, required this.name, required this.controller, this.isMe = false});

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
        for (final bps in SplitCalculator.compute(const Money.fromPaise(10000), SplitMethod.equally, List.filled(count, 0)).shares)
          formatSplitPercent(bps.paise).replaceAll('%', ''),
      ];
    case SplitMethod.exact:
      if (total == null || !total.isPositive) return List.filled(count, '');
      return [
        for (final m in SplitCalculator.compute(total, SplitMethod.equally, List.filled(count, 0)).shares)
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
    final c = context.colors;
    final t = context.text;
    final values = [for (final s in slots) parseSplitValue(s.controller.text, method)];
    final SplitOutcome? outcome = total == null
        ? null
        : (values.contains(null)
            ? const SplitOutcome.invalid('Some values are not numbers.')
            : SplitCalculator.compute(total!, method, values.cast<int>()));
    final shares = outcome != null && outcome.isValid ? outcome.shares : null;
    final hasMe = slots.isNotEmpty && slots.first.isMe;
    final others = shares == null ? null : Money.sum(hasMe ? shares.skip(1) : shares);
    final error = errorText ?? (outcome?.isValid == false ? outcome!.error : null);

    return Column(
      key: const ValueKey('pending-split-editor'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PendingFieldLabel('Split'),
        Wrap(
          spacing: Space.x2,
          runSpacing: Space.x2,
          children: [
            for (final m in SplitMethod.values)
              FinnTapChip(
                key: ValueKey('split-method:${m.name}'),
                label: m.label,
                selected: m == method,
                color: m == method ? c.accentPending : null,
                height: 34,
                semantics: 'Split ${m.label.toLowerCase()}',
                onTap: () {
                  if (m == method) return;
                  HapticFeedback.selectionClick();
                  onMethod(m);
                },
              ),
          ],
        ),
        const SizedBox(height: Space.x1_5),
        Text(method.hint, style: t.micro),
        if (onIncludeMe != null) ...[
          const SizedBox(height: Space.x3),
          MergeSemantics(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Include me', style: t.bodyStrong),
                      Text(
                        includeMe
                            ? 'You had a part too. Your share stays with you; only the others owe you.'
                            : 'You only paid. The whole bill is split between the others.',
                        style: t.caption,
                      ),
                    ],
                  ),
                ),
                Switch(key: const ValueKey('split-include-me'), value: includeMe, onChanged: onIncludeMe),
              ],
            ),
          ),
        ],
        const SizedBox(height: Space.x3),
        DecoratedBox(
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: Radii.rLg,
            border: Border.all(color: error != null ? c.warning : c.border),
          ),
          child: Column(
            children: [
              for (var i = 0; i < slots.length; i++) ...[
                if (i > 0) const FinnDivider(indent: Space.x3 + 32 + Space.x3),
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
        const SizedBox(height: Space.x2),
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
        SplitMethod.equally => shares.toSet().length == 1
            ? '${shares.first.format()} each'
            : 'About ${shares.last.format()} each (paise rounded)',
        SplitMethod.exact => 'Adds up to ${total!.format()}',
        SplitMethod.percent => 'Adds up to 100%',
        SplitMethod.shares => () {
            final n = values.fold<int>(0, (a, b) => a + b);
            return '$n ${n == 1 ? 'share' : 'shares'} · '
                '${Money.fromPaise((total!.paise / n).round()).format()} per share';
          }(),
        SplitMethod.adjustment => 'Equal part, then each adjustment added or taken off',
      };
}

class _SlotRow extends StatelessWidget {
  const _SlotRow({required this.slot, required this.method, required this.share, required this.onChanged});

  final SplitSlot slot;
  final SplitMethod method;
  final Money? share;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.x3, vertical: Space.x2),
      child: Row(
        children: [
          PendingAvatar(name: slot.isMe ? 'Me' : slot.name, color: slot.isMe ? c.textSecondary : c.accentPending, size: 32),
          const SizedBox(width: Space.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  slot.isMe ? 'You' : slot.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.body.copyWith(fontWeight: FontWeight.w700),
                ),
                Text(slot.isMe ? 'Your share · not owed' : 'Share', style: t.micro),
              ],
            ),
          ),
          if (method.takesValues) ...[
            const SizedBox(width: Space.x2),
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
                style: t.bodyStrong,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: hint,
                  prefixText: prefix,
                  suffixText: suffix,
                  contentPadding: const EdgeInsets.symmetric(horizontal: Space.x2, vertical: Space.x2),
                  border: OutlineInputBorder(borderRadius: Radii.rMd, borderSide: BorderSide(color: c.border)),
                ),
              ),
            ),
          ],
          const SizedBox(width: Space.x3),
          SizedBox(
            width: 84,
            child: Align(
              alignment: Alignment.centerRight,
              child: share == null
                  ? Text('—', style: t.bodyStrong.copyWith(color: c.textTertiary))
                  : FittedBox(
                      fit: BoxFit.scaleDown,
                      child: AmountText(
                        share!,
                        key: ValueKey('split-share:${slot.key}'),
                        style: t.amountSmall.copyWith(color: slot.isMe ? c.textSecondary : c.textPrimary),
                      ),
                    ),
            ),
          ),
        ],
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
    final c = context.colors;
    final t = context.text;
    if (error != null) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(LucideIcons.triangleAlert, size: 14, color: c.warning),
          const SizedBox(width: Space.x1_5),
          Expanded(
            child: Text(error!, style: t.caption.copyWith(color: c.warning, fontWeight: FontWeight.w700)),
          ),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(others == null ? LucideIcons.info : LucideIcons.circleCheck,
            size: 14, color: others == null ? c.textTertiary : c.positive),
        const SizedBox(width: Space.x1_5),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                if (line != null) TextSpan(text: line),
                if (others != null)
                  TextSpan(
                    text: direction.isOwe
                        ? ' · You owe ${others!.format()} to $count people'
                        : ' · $count people owe you ${others!.format()}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
              ],
            ),
            style: t.caption,
          ),
        ),
      ],
    );
  }
}
