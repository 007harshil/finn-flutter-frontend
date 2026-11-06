import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../app/di/data_providers.dart';
import '../../../../core/money/money.dart';
import '../../../../core/money/money_format.dart';
import '../../../../kit/kit.dart';
import '../../../transactions/domain/transaction.dart';
import '../../domain/money_account.dart';
import 'account_picker_field.dart';

/// "Paid from" for a payment: one account, or the same payment split
/// across several accounts (one transaction, several parts).
///
/// Single mode is a normal [AccountPickerField]. When [total] is more than
/// the chosen account holds, a short line says so next to the split button.
/// Split mode lists every active account with an amount box and a "Max"
/// chip (fills what is left, capped at what the account holds), then a
/// running "assigned of total" line.
///
/// The caller owns the values: [accountId] for single mode, and gets the
/// parts through [onSplitChanged] (null when split is turned off).
class PaidFromField extends ConsumerStatefulWidget {
  const PaidFromField({
    super.key,
    required this.accountId,
    required this.onAccountChanged,
    required this.total,
    required this.onSplitChanged,
    this.initialSplits = const [],
    this.room = const {},
    this.label = 'Paid from',
    this.errorText,
    this.splitErrorText,
    this.enabled = true,
  });

  final String? accountId;
  final ValueChanged<String?> onAccountChanged;

  /// The payment amount typed so far (null while empty or invalid).
  final Money? total;
  final ValueChanged<List<AccountLeg>?> onSplitChanged;

  /// Parts of the record being edited; non-empty opens split mode.
  final List<AccountLeg> initialSplits;

  /// Money the record being edited already took from each account; it
  /// comes back before the new payment, so it counts as room.
  final Map<String, Money> room;
  final String label;
  final String? errorText;
  final String? splitErrorText;
  final bool enabled;

  @override
  ConsumerState<PaidFromField> createState() => _PaidFromFieldState();
}

class _PaidFromFieldState extends ConsumerState<PaidFromField> {
  final Map<String, TextEditingController> _parts = {};
  late bool _split = widget.initialSplits.length > 1;

  @override
  void initState() {
    super.initState();
    for (final l in widget.initialSplits) {
      _controller(l.accountId).text = MoneyFormatter.editable(l.amount);
    }
  }

  @override
  void dispose() {
    for (final c in _parts.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _controller(String id) => _parts.putIfAbsent(id, TextEditingController.new);

  Money _partOf(String id) {
    final v = LedgerAmountField.parse(_parts[id]?.text ?? '');
    return v == null || v.isNegative ? Money.zero : v;
  }

  List<AccountLeg> _legs(List<AccountBalance> balances) => [
        for (final b in balances)
          if (_partOf(b.account.id).isPositive) AccountLeg(b.account.id, _partOf(b.account.id)),
      ];

  /// What [b] can pay: its balance (plus [PaidFromField.room]) for money
  /// accounts; for a credit card the limit left, or no cap.
  Money? _capOf(AccountBalance b) {
    final room = widget.room[b.account.id] ?? Money.zero;
    if (b.isLiability) {
      final left = b.limitLeft;
      return left == null ? null : left + room;
    }
    final cap = b.balance + room;
    return cap.isNegative ? Money.zero : cap;
  }

  void _emit(List<AccountBalance> balances) => widget.onSplitChanged(_split ? _legs(balances) : null);

  void _turnOn(List<AccountBalance> balances) {
    final total = widget.total;
    final first = balances.where((b) => b.account.id == widget.accountId).firstOrNull;
    for (final c in _parts.values) {
      c.clear();
    }
    if (first != null && total != null) {
      final cap = _capOf(first);
      final take = cap == null || cap > total ? total : cap;
      if (take.isPositive) _controller(first.account.id).text = MoneyFormatter.editable(take);
    }
    setState(() => _split = true);
    _emit(balances);
  }

  void _turnOff(List<AccountBalance> balances) {
    setState(() => _split = false);
    widget.onSplitChanged(null);
  }

  void _fill(AccountBalance b, List<AccountBalance> balances) {
    final total = widget.total;
    if (total == null) return;
    final others = Money.sum([
      for (final x in balances)
        if (x.account.id != b.account.id) _partOf(x.account.id),
    ]);
    var take = total - others;
    final cap = _capOf(b);
    if (cap != null && take > cap) take = cap;
    if (take.isNegative) take = Money.zero;
    _controller(b.account.id).text = take.isZero ? '' : MoneyFormatter.editable(take);
    setState(() {});
    _emit(balances);
  }

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(accountBalancesProvider).value;
    if (all == null) {
      return LedgerField(label: widget.label, child: const LedgerSkeleton(height: 52));
    }
    final active = [for (final b in all) if (!b.account.isArchived || _partOf(b.account.id).isPositive) b];
    final canSplit = active.length > 1;
    if (_split && canSplit) return _splitView(active);
    return _singleView(active, canSplit);
  }

  Widget _singleView(List<AccountBalance> active, bool canSplit) {
    final c = context.ink;
    final t = context.type;
    final chosen = active.where((b) => b.account.id == widget.accountId).firstOrNull;
    final total = widget.total;
    final cap = chosen == null ? null : _capOf(chosen);
    final short = total != null && cap != null && total > cap;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AccountPickerField(
          label: widget.label,
          value: widget.accountId,
          errorText: widget.errorText,
          enabled: widget.enabled,
          onChanged: widget.onAccountChanged,
        ),
        if (canSplit)
          Padding(
            padding: const EdgeInsets.only(top: Sp.xs),
            child: Row(
              children: [
                if (short)
                  Expanded(
                    child: Text(
                      '${chosen!.account.name} has only ${maskedMoney(context, cap)}',
                      key: const ValueKey('pay-short'),
                      style: t.small.copyWith(color: c.red),
                    ),
                  )
                else
                  const Spacer(),
                LedgerButton(
                  key: const ValueKey('pay-split'),
                  label: 'Split across accounts',
                  icon: LucideIcons.split,
                  variant: short ? LedgerButtonVariant.secondary : LedgerButtonVariant.quiet,
                  small: true,
                  onPressed: widget.enabled ? () => _turnOn(active) : null,
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _splitView(List<AccountBalance> active) {
    final c = context.ink;
    final t = context.type;
    final total = widget.total;
    final assigned = Money.sum([for (final b in active) _partOf(b.account.id)]);
    final left = total == null ? null : total - assigned;
    final status = left == null
        ? 'Enter the amount first'
        : left.isZero
            ? 'All ${maskedMoney(context, total!)} assigned'
            : left.isPositive
                ? '${maskedMoney(context, left)} left to assign'
                : '${maskedMoney(context, -left)} more than the amount';
    final statusColor = left == null || left.isZero ? c.green : (left.isNegative ? c.red : c.amber);
    return LedgerField(
      label: '${widget.label} · split',
      errorText: widget.splitErrorText,
      child: Container(
        decoration: BoxDecoration(
          color: c.surface,
          border: Border.all(color: c.line),
          borderRadius: Rad.rTile,
        ),
        padding: const EdgeInsets.fromLTRB(Sp.md, Sp.sm, Sp.md, Sp.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final b in active) _partRow(b, active),
            const SizedBox(height: Sp.sm),
            if (total != null && total.isPositive)
              LedgerBar(
                value: (assigned.paise / total.paise).clamp(0.0, 1.0),
                color: statusColor,
                height: 6,
                semanticLabel: status,
              ),
            const SizedBox(height: Sp.xs),
            Row(
              children: [
                Expanded(
                  child: Text(
                    status,
                    key: const ValueKey('pay-split-status'),
                    style: t.small.copyWith(color: statusColor, fontWeight: FontWeight.w600),
                  ),
                ),
                LedgerButton(
                  key: const ValueKey('pay-split-off'),
                  label: 'One account',
                  variant: LedgerButtonVariant.quiet,
                  small: true,
                  onPressed: widget.enabled ? () => _turnOff(active) : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _partRow(AccountBalance b, List<AccountBalance> active) {
    final c = context.ink;
    final t = context.type;
    final cap = _capOf(b);
    final over = cap != null && _partOf(b.account.id) > cap;
    return Padding(
      key: ValueKey('pay-part:${b.account.id}'),
      padding: const EdgeInsets.symmetric(vertical: Sp.xs),
      child: Row(
        children: [
          Icon(accountKindIcon(b.account.kind), size: 18, color: c.inkSoft),
          const SizedBox(width: Sp.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(b.account.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.labelStrong),
                Text(
                  b.isLiability
                      ? (b.limitLeft == null ? 'Credit card' : '${maskedMoney(context, b.limitLeft!)} limit left')
                      : 'Has ${maskedMoney(context, cap ?? b.balance)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.small.copyWith(color: over ? c.red : c.inkSoft),
                ),
              ],
            ),
          ),
          const SizedBox(width: Sp.sm),
          SizedBox(
            width: 112,
            child: LedgerAmountField(
              key: ValueKey('pay-amount:${b.account.id}'),
              controller: _controller(b.account.id),
              enabled: widget.enabled,
              onChanged: (_) {
                setState(() {});
                _emit(active);
              },
            ),
          ),
          const SizedBox(width: Sp.xs),
          LedgerChip(
            key: ValueKey('pay-max:${b.account.id}'),
            label: 'Max',
            onTap: widget.enabled && widget.total != null ? () => _fill(b, active) : null,
          ),
        ],
      ),
    );
  }
}

/// Amount for inline copy; masked when balances are hidden.
String maskedMoney(BuildContext context, Money amount) =>
    AmountVisibility.hiddenOf(context) ? MoneyFormatter.masked : AmountText.formatted(amount);
