import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/di/core_providers.dart';
import '../../../app/di/data_providers.dart';
import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/time/dates.dart';
import '../../../kit/kit.dart';
import '../../../shared/presentation/action_runner.dart';
import '../../accounts/presentation/widgets/account_picker_field.dart';
import '../../accounts/presentation/widgets/channel_field.dart';
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
      .where(
        (v) =>
            v.payment.id != id &&
            v.status.isActive &&
            v.payment.counterparty.trim().toLowerCase() == name,
      )
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
  // Null until picked: the form shows the default account and sends it.
  String? _accountId;
  String? _channel;
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
    final amount = LedgerAmountField.parse(_amount.text);
    if (amount == null || !amount.isPositive) {
      setState(
        () => _errors = {'amount': 'Enter an amount greater than zero.'},
      );
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
        accountId: _recordCash ? (_accountId ?? ref.read(defaultAccountProvider).value?.id) : null,
        channel: _recordCash ? _channel : null,
        recordCashMovement: _recordCash,
        note: note.isEmpty ? null : note,
      ),
      idempotencyKey: _key,
      celebrate: true,
      successTitle: amount >= v.outstanding
          ? 'Settled in full'
          : 'Partial settlement recorded',
      onFieldErrors: (e) => setState(() => _errors = e),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (result != null) Navigator.of(context).maybePop(amount >= v.outstanding);
  }

  @override
  Widget build(BuildContext context) {
    final v = ref.watch(pendingViewProvider(widget.pendingId)).value;
    if (v == null) {
      return const FinnSheetScaffold(title: 'Settle', child: _FormSkeleton());
    }
    if (!_prefilled) {
      _prefilled = true;
      _amount.text = MoneyFormatter.editable(v.outstanding);
    }
    if (!v.status.isActive) return _Closed(view: v);

    final today = ref.watch(todayProvider);
    final p = v.payment;
    final owe = p.direction.isOwe;
    final siblings = ref.watch(_siblingsProvider(p.id));
    final entered = LedgerAmountField.parse(_amount.text) ?? Money.zero;
    final leaves = v.outstanding - entered;
    final tooMuch = entered > v.outstanding;

    return FinnSheetScaffold(
      title: 'Settle',
      description: '${p.direction.sentence(p.counterparty)} · ${p.purpose}',
      footer: LedgerButton(
        label: owe ? 'Record payment' : 'Record receipt',
        expand: true,
        loading: _busy,
        onPressed: _busy ? null : () => _submit(v),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LedgerAmountField(
            hero: true,
            label: owe ? 'Amount paid' : 'Amount received',
            controller: _amount,
            helper: entered.isPositive && leaves.isPositive
                ? '${leaves.format()} will remain outstanding.'
                : (_full
                      ? 'This settles the item in full.'
                      : 'Enter the amount that changed hands.'),
            errorText:
                _errors['amount'] ??
                (tooMuch
                    ? 'More than the ${v.outstanding.format()} outstanding.'
                    : null),
            onChanged: (m) =>
                setState(() => _full = m != null && m == v.outstanding),
          ),
          const SizedBox(height: Sp.md),
          _QuickAmounts(
            outstanding: v.outstanding,
            entered: entered,
            onPick: (m) {
              if (m == v.outstanding) {
                _setFull(v);
              } else {
                setState(() {
                  _full = false;
                  _amount.text = MoneyFormatter.editable(m);
                  _errors = const {};
                });
              }
            },
          ),
          const SizedBox(height: LedgerForm.gap),
          _SettlePreview(view: v, entered: entered),
          if (siblings.isNotEmpty) ...[
            const SizedBox(height: Sp.md),
            LedgerNote(
              text: [
                'Other open items with ${p.counterparty}',
                for (final s in siblings)
                  '• ${s.payment.purpose}: ${s.outstanding.format()} (${s.payment.direction.label.toLowerCase()})',
                'This settlement applies only to "${p.purpose}". Settle the others separately.',
              ].join('\n'),
            ),
          ],
          const SizedBox(height: LedgerForm.groupGap),
          LedgerDateField(
            label: owe ? 'Paid on' : 'Received on',
            value: _date ?? today,
            firstDate: p.createdDate,
            lastDate: today,
            errorText: _errors['date'],
            onChanged: (d) => setState(() => _date = d),
          ),
          const SizedBox(height: LedgerForm.gap),
          LedgerSwitchRow(
            title: 'Record as cash movement',
            subtitle: _recordCash
                ? (owe
                      ? 'Adds an expense and lowers your balance.'
                      : 'Adds income and raises your balance.')
                : 'Off: settled outside FiNN. Balance unchanged.',
            value: _recordCash,
            onChanged: (b) => setState(() => _recordCash = b),
          ),
          if (_recordCash) ...[
            const SizedBox(height: LedgerForm.gap),
            AccountPickerField(
              label: owe ? 'Paid from' : 'Received in',
              value: _accountId ?? ref.watch(defaultAccountProvider).value?.id,
              errorText: _errors['accountId'],
              onChanged: (id) => setState(() {
                _accountId = id;
                _errors = Map.of(_errors)..remove('accountId');
              }),
            ),
            const SizedBox(height: LedgerForm.gap),
            ChannelField(
              value: _channel,
              errorText: _errors['channel'],
              onChanged: (v) => _channel = v,
            ),
          ],
          const SizedBox(height: LedgerForm.gap),
          LedgerTextField(
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

class _FormSkeleton extends StatelessWidget {
  const _FormSkeleton();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading',
      child: const ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LedgerSkeleton(width: 200, height: 44),
            SizedBox(height: LedgerForm.gap),
            LedgerSkeleton(height: 104),
            SizedBox(height: LedgerForm.gap),
            LedgerSkeleton(height: 52),
          ],
        ),
      ),
    );
  }
}

/// What is outstanding and what this settlement does to it: the bar shows
/// what was settled before and this payment, and follows the amount as it
/// is typed.
class _SettlePreview extends StatelessWidget {
  const _SettlePreview({required this.view, required this.entered});

  final PendingView view;
  final Money entered;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final t = context.type;
    final v = view;
    final p = v.payment;
    final whole = p.originalAmount.paise;
    double frac(Money m) => whole <= 0 ? 0 : (m.paise / whole).clamp(0.0, 1.0);
    final now = Money.min(Money.max(entered, Money.zero), v.outstanding);
    return LedgerPanel(
      children: [
        LedgerFact(
          label: 'Outstanding',
          value: AmountText(v.outstanding, style: t.bodyStrong),
        ),
        LedgerFact(
          label: 'Original',
          value: AmountText(
            p.originalAmount,
            style: t.body.copyWith(color: c.inkSoft),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Sp.lg,
            vertical: Sp.md + 2,
          ),
          child: LedgerStackBar(
            semanticLabel: 'Settled before, this settlement and what is left',
            parts: [
              BarPart(frac(v.settled), c.lineStrong),
              BarPart(frac(now), c.green),
              BarPart(1 - frac(v.settled) - frac(now), c.sunken),
            ],
          ),
        ),
      ],
    );
  }
}

/// One-tap amounts: the full outstanding, half, or a quarter.
class _QuickAmounts extends StatelessWidget {
  const _QuickAmounts({
    required this.outstanding,
    required this.entered,
    required this.onPick,
  });

  final Money outstanding;
  final Money entered;
  final ValueChanged<Money> onPick;

  @override
  Widget build(BuildContext context) {
    final hidden = AmountVisibility.hiddenOf(context);
    Money part(int d) => Money.fromPaise(outstanding.paise ~/ d).roundToRupee();
    final options = <(String, Money)>[
      ('Full', outstanding),
      if (outstanding >= const Money.rupees(2)) ('Half', part(2)),
      if (outstanding >= const Money.rupees(4)) ('Quarter', part(4)),
    ];
    int? selected;
    for (var i = 0; i < options.length; i++) {
      if (options[i].$2 == entered) {
        selected = i;
        break;
      }
    }
    return LedgerChoiceChips<int>(
      options: [
        for (var i = 0; i < options.length; i++)
          LedgerOption(
            i,
            hidden
                ? options[i].$1
                : '${options[i].$1} · ${AmountText.formatted(options[i].$2, compact: true)}',
          ),
      ],
      selected: selected,
      onChanged: (i) => onPick(options[i].$2),
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
      child: LedgerEmpty(
        icon: settled ? LucideIcons.circleCheck : LucideIcons.ban,
        title: settled ? 'Nothing left to settle' : 'This item was written off',
        message: settled && view.settledOn != null
            ? 'Settled on ${DateFormats.dayMonthYear.format(view.settledOn!)}.'
            : 'No further settlements can be recorded.',
        actionLabel: 'Close',
        onAction: () => Navigator.of(context).maybePop(),
      ),
    );
  }
}
