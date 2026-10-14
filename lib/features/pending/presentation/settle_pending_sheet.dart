import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/di/core_providers.dart';
import '../../../app/di/data_providers.dart';
import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/time/dates.dart';
import '../../../design_system/design_system.dart';
import '../../../design_system/luxe/luxe.dart';
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
  Widget build(BuildContext context) => LuxeScope(paint: true, child: Builder(builder: _buildSheet));

  Widget _buildSheet(BuildContext context) {
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
          _SettlePreview(view: v, entered: entered),
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
          const SizedBox(height: Space.x4),
          AmountField(
            prominent: true,
            label: owe ? 'Amount paid' : 'Amount received',
            controller: _amount,
            errorText: _errors['amount'],
            onChanged: (m) => setState(() => _full = m != null && m == v.outstanding),
          ),
          const SizedBox(height: Space.x2),
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
          const SizedBox(height: Space.x1_5),
          Text(
            entered > v.outstanding
                ? 'More than the ${v.outstanding.format()} outstanding.'
                : (entered.isPositive && leaves.isPositive
                    ? '${leaves.format()} will remain outstanding.'
                    : (_full ? 'This settles the item in full.' : 'Enter the amount that changed hands.')),
            style: t.micro.copyWith(color: entered > v.outstanding ? c.negative : null),
          ),
          const SizedBox(height: Space.x4),
          DateField(
            label: owe ? 'Paid on' : 'Received on',
            value: _date ?? today,
            firstDate: p.createdDate,
            lastDate: today,
            errorText: _errors['date'],
            onChanged: (d) => setState(() => _date = d),
          ),
          const SizedBox(height: Space.x4),
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

/// What is outstanding and what this settlement does to it: the bar shows
/// already settled, this payment and what will be left, and follows the
/// amount as it is typed.
class _SettlePreview extends StatelessWidget {
  const _SettlePreview({required this.view, required this.entered});

  final PendingView view;
  final Money entered;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final v = view;
    final p = v.payment;
    final tone = p.direction.color(c);
    final whole = p.originalAmount.paise;
    double frac(Money m) => whole <= 0 ? 0 : (m.paise / whole).clamp(0.0, 1.0);
    final over = entered > v.outstanding;
    final now = Money.min(Money.max(entered, Money.zero), v.outstanding);
    return FinnCard(
      variant: FinnCardVariant.muted,
      padding: const EdgeInsets.all(Space.x3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              PendingAvatar(
                name: p.counterparty,
                color: tone,
                progress: v.settledBps / 10000,
                direction: p.direction,
              ),
              const SizedBox(width: Space.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('OUTSTANDING', style: t.eyebrow),
                    AmountText(v.outstanding, style: t.amountLarge.copyWith(color: tone), fit: true),
                  ],
                ),
              ),
              const SizedBox(width: Space.x2),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('ORIGINAL', style: t.eyebrow),
                  AmountText(p.originalAmount, style: t.amountSmall.copyWith(color: c.textSecondary)),
                ],
              ),
            ],
          ),
          const SizedBox(height: Space.x2_5),
          ExcludeSemantics(
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: frac(now)),
              duration: context.motion.normal,
              curve: Curves2.emphasized,
              builder: (context, n, _) => CustomPaint(
                size: const Size(double.infinity, 10),
                painter: _PreviewPainter(
                  settled: frac(v.settled),
                  now: n,
                  settledColor: tone.withValues(alpha: 0.38),
                  nowColor: tone,
                  track: c.surface,
                  outline: over ? c.negative : null,
                ),
              ),
            ),
          ),
          const SizedBox(height: Space.x1_5),
          Wrap(
            spacing: Space.x3,
            runSpacing: Space.x1,
            children: [
              if (v.settled.isPositive) _Legend(color: tone.withValues(alpha: 0.38), label: 'Settled before'),
              _Legend(color: tone, label: 'This settlement'),
              _Legend(color: c.surface, label: 'Left after', border: c.border),
            ],
          ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label, this.border});

  final Color color;
  final String label;
  final Color? border;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: border == null ? null : Border.all(color: border!),
            ),
          ),
          const SizedBox(width: Space.x1),
          Text(label, style: context.text.micro),
        ],
      );
}

class _PreviewPainter extends CustomPainter {
  const _PreviewPainter({
    required this.settled,
    required this.now,
    required this.settledColor,
    required this.nowColor,
    required this.track,
    this.outline,
  });

  final double settled;
  final double now;
  final Color settledColor;
  final Color nowColor;
  final Color track;
  final Color? outline;

  @override
  void paint(Canvas canvas, Size size) {
    final bar = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(size.height / 2));
    canvas.drawRRect(bar, Paint()..color = track);
    canvas.save();
    canvas.clipRRect(bar);
    final a = settled * size.width;
    final b = (settled + now).clamp(0.0, 1.0) * size.width;
    canvas.drawRect(Rect.fromLTRB(0, 0, a, size.height), Paint()..color = settledColor);
    canvas.drawRect(Rect.fromLTRB(a, 0, b, size.height), Paint()..color = nowColor);
    canvas.restore();
    if (outline != null) {
      canvas.drawRRect(
        bar.deflate(0.75),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = outline!,
      );
    }
  }

  @override
  bool shouldRepaint(_PreviewPainter old) =>
      old.settled != settled ||
      old.now != now ||
      old.settledColor != settledColor ||
      old.nowColor != nowColor ||
      old.track != track ||
      old.outline != outline;
}

/// One-tap amounts: the full outstanding, half, or a quarter.
class _QuickAmounts extends StatelessWidget {
  const _QuickAmounts({required this.outstanding, required this.entered, required this.onPick});

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
    return FilterChipBar<int>(
      padding: EdgeInsets.zero,
      multiSelect: false,
      items: [
        for (var i = 0; i < options.length; i++)
          FilterChipItem(
            i,
            hidden ? options[i].$1 : '${options[i].$1} · ${AmountText.formatted(options[i].$2, compact: true)}',
          ),
      ],
      selected: {
        for (var i = 0; i < options.length; i++)
          if (options[i].$2 == entered) i,
      },
      onChanged: (s) => onPick(options[s.first].$2),
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
