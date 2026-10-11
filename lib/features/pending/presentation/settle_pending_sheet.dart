import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/di/core_providers.dart';
import '../../../app/di/data_providers.dart';
import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/time/dates.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/presentation/action_runner.dart';
import '../../transactions/domain/transaction.dart';
import '../application/pending_actions.dart';
import '../domain/pending_payment.dart';
import 'pending_ui.dart';

/// Other active items with the same person (never picked automatically).
final _siblingsProvider = Provider.family<List<PendingView>, String>((ref, id) {
  final all = ref.watch(pendingViewsProvider).value ?? const <PendingView>[];
  final self = all.where((v) => v.payment.id == id).firstOrNull;
  if (self == null) return const [];
  final name = self.payment.counterparty.trim().toLowerCase();
  return all
      .where((v) => v.payment.id != id && v.status.isActive && v.payment.counterparty.trim().toLowerCase() == name)
      .toList();
});

/// Records a full or partial settlement of one pending item.
class SettlePendingSheet extends ConsumerStatefulWidget {
  const SettlePendingSheet({super.key, required this.pendingId});

  final String pendingId;

  @override
  ConsumerState<SettlePendingSheet> createState() => _SettlePendingSheetState();
}

class _SettlePendingSheetState extends ConsumerState<SettlePendingSheet> {
  final _key = newIdempotencyKey();
  final _amount = TextEditingController();
  final _note = TextEditingController();
  bool _full = true;
  DateTime? _date;
  PaymentMethod _method = PaymentMethod.upi;
  bool _recordCash = true;
  bool _busy = false;
  bool _prefilled = false;
  Map<String, String> _errors = const {};

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  void _setFull(PendingView v) => setState(() {
        _full = true;
        _amount.text = MoneyFormatter.editable(v.outstanding);
        _errors = const {};
      });

  Future<void> _submit(PendingView v) async {
    final amount = AmountField.parse(_amount.text);
    if (amount == null || !amount.isPositive) {
      setState(() => _errors = {'amount': 'Enter an amount greater than zero.'});
      return;
    }
    final note = _note.text.trim();
    setState(() {
      _busy = true;
      _errors = const {};
    });
    final result = await runAction(
      context,
      ref,
      action: const SettlePendingAction(),
      input: SettlePendingInput(
        pendingId: v.payment.id,
        amount: amount,
        date: _date ?? ref.read(todayProvider),
        method: _method,
        recordCashMovement: _recordCash,
        note: note.isEmpty ? null : note,
      ),
      idempotencyKey: _key,
      celebrate: true,
      successTitle: amount >= v.outstanding ? 'Settled in full' : 'Partial settlement recorded',
      onFieldErrors: (e) => setState(() => _errors = e),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (result != null) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final v = ref.watch(pendingViewProvider(widget.pendingId)).value;
    if (v == null) {
      return const FinnSheetScaffold(
        title: 'Settle',
        child: SkeletonPulse(child: Column(children: [CardSkeleton(height: 120), SizedBox(height: Space.x4), CardSkeleton(height: 200)])),
      );
    }
    if (!_prefilled) {
      _prefilled = true;
      _amount.text = MoneyFormatter.editable(v.outstanding);
    }
    if (!v.status.isActive) return _Closed(view: v);

    final today = ref.watch(todayProvider);
    final c = context.colors;
    final t = context.text;
    final p = v.payment;
    final owe = p.direction.isOwe;
    final siblings = ref.watch(_siblingsProvider(p.id));
    final entered = AmountField.parse(_amount.text) ?? Money.zero;
    final leaves = v.outstanding - entered;

    return FinnSheetScaffold(
      title: owe ? 'Settle · I paid' : 'Settle · I received',
      description: '${p.direction.sentence(p.counterparty)} · ${p.purpose}',
      footer: FinnButton(
        label: owe ? 'Record payment to ${p.counterparty}' : 'Record money from ${p.counterparty}',
        icon: LucideIcons.circleCheck,
        expand: true,
        loading: _busy,
        onPressed: _busy ? null : () => _submit(v),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FinnCard(
            variant: FinnCardVariant.muted,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PendingDirectionLabel(direction: p.direction),
                const SizedBox(height: Space.x2),
                Text('OUTSTANDING', style: t.eyebrow),
                const SizedBox(height: Space.x0_5),
                AmountText(v.outstanding, style: t.amountLarge.copyWith(color: p.direction.color(c)), fit: true),
                const SizedBox(height: Space.x1),
                Text(
                  v.settled.isPositive
                      ? 'of ${p.originalAmount.format()} · ${v.settled.format()} already settled'
                      : 'Original amount ${p.originalAmount.format()}',
                  style: t.caption,
                ),
              ],
            ),
          ),
          if (siblings.isNotEmpty) ...[
            const SizedBox(height: Space.x3),
            InfoBanner(
              title: 'Other open items with ${p.counterparty}',
              message: [
                for (final s in siblings)
                  '• ${s.payment.purpose}: ${s.outstanding.format()} (${s.payment.direction.label.toLowerCase()})',
                'This settlement applies only to "${p.purpose}". Settle the others separately.',
              ].join('\n'),
            ),
          ],
          const SizedBox(height: Space.x5),
          SegmentedTabs<bool>(
            items: const [SegmentItem(true, 'Full'), SegmentItem(false, 'Partial')],
            selected: _full,
            onChanged: (full) {
              if (full) {
                _setFull(v);
              } else {
                setState(() => _full = false);
              }
            },
          ),
          const SizedBox(height: Space.x4),
          AmountField(
            label: owe ? 'Amount paid' : 'Amount received',
            controller: _amount,
            errorText: _errors['amount'],
            onChanged: (m) => setState(() => _full = m != null && m == v.outstanding),
          ),
          const SizedBox(height: Space.x1_5),
          Text(
            entered > v.outstanding
                ? 'More than the ${v.outstanding.format()} outstanding.'
                : (entered.isPositive && leaves.isPositive
                    ? '${leaves.format()} will remain outstanding.'
                    : 'This settles the item in full.'),
            style: t.micro.copyWith(color: entered > v.outstanding ? c.negative : null),
          ),
          const SizedBox(height: Space.x5),
          DateField(
            label: owe ? 'Paid on' : 'Received on',
            value: _date ?? today,
            firstDate: p.createdDate,
            lastDate: today,
            errorText: _errors['date'],
            onChanged: (d) => setState(() => _date = d),
          ),
          const SizedBox(height: Space.x5),
          const PendingFieldLabel('Method'),
          PendingMethodChips(selected: _method, onChanged: (m) => setState(() => _method = m)),
          const SizedBox(height: Space.x4),
          _CashSwitch(
            value: _recordCash,
            owe: owe,
            onChanged: (b) => setState(() => _recordCash = b),
          ),
          const SizedBox(height: Space.x4),
          FinnTextField(
            label: 'Note (optional)',
            hint: 'e.g. UPI ref 4821',
            controller: _note,
            maxLength: 120,
            errorText: _errors['note'],
          ),
        ],
      ),
    );
  }
}

class _CashSwitch extends StatelessWidget {
  const _CashSwitch({required this.value, required this.owe, required this.onChanged});

  final bool value;
  final bool owe;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.text;
    return FinnCard(
      variant: FinnCardVariant.outlined,
      padding: const EdgeInsets.fromLTRB(Space.x4, Space.x2, Space.x2, Space.x2),
      child: MergeSemantics(
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Record as cash movement', style: t.bodyStrong),
                  const SizedBox(height: 2),
                  Text(
                    value
                        ? (owe ? 'Adds an expense and lowers your balance once.' : 'Adds income and raises your balance once.')
                        : 'Off: settled outside your FiNN-tracked cash (e.g. adjusted against something else). Balance stays the same.',
                    style: t.caption,
                  ),
                ],
              ),
            ),
            Switch(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}

class _Closed extends StatelessWidget {
  const _Closed({required this.view});

  final PendingView view;

  @override
  Widget build(BuildContext context) {
    final settled = view.status == PendingStatus.settled;
    return FinnSheetScaffold(
      title: settled ? 'Fully settled' : 'Written off',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.x6),
        child: EmptyState(
          icon: settled ? LucideIcons.circleCheck : LucideIcons.ban,
          title: settled ? 'Nothing left to settle' : 'This item was written off',
          message: settled && view.settledOn != null
              ? 'Settled on ${DateFormats.dayMonthYear.format(view.settledOn!)}.'
              : 'No further settlements can be recorded.',
          actionLabel: 'Close',
          onAction: () => Navigator.of(context).maybePop(),
        ),
      ),
    );
  }
}
