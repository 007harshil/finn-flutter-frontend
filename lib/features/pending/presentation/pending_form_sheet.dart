import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/di/core_providers.dart';
import '../../../app/di/data_providers.dart';
import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/presentation/action_runner.dart';
import '../application/pending_actions.dart';
import '../domain/pending_payment.dart';
import 'pending_ui.dart';

/// Distinct counterparty names already used, most recent first.
final _pendingNamesProvider = Provider<List<String>>((ref) {
  final views = ref.watch(pendingViewsProvider).value ?? const <PendingView>[];
  final sorted = List.of(views)..sort((a, b) => b.payment.updatedAt.compareTo(a.payment.updatedAt));
  final seen = <String>{};
  return [
    for (final v in sorted)
      if (seen.add(v.payment.counterparty.trim().toLowerCase())) v.payment.counterparty.trim(),
  ];
});

/// Add or edit a pending obligation. Never changes the cash balance.
class PendingFormSheet extends ConsumerStatefulWidget {
  const PendingFormSheet({super.key, this.pendingId, this.owedToMe = false});

  final String? pendingId;
  final bool owedToMe;

  @override
  ConsumerState<PendingFormSheet> createState() => _PendingFormSheetState();
}

class _PendingFormSheetState extends ConsumerState<PendingFormSheet> {
  final _key = newIdempotencyKey();
  final _name = TextEditingController();
  final _amount = TextEditingController();
  final _purpose = TextEditingController();
  final _notes = TextEditingController();

  late PendingDirection _direction = widget.owedToMe ? PendingDirection.owedToMe : PendingDirection.iOwe;
  PendingKind _kind = PendingKind.other;
  DateTime? _created;
  DateTime? _due;
  Map<String, String> _errors = const {};
  bool _busy = false;
  bool _loaded = false;
  PendingView? _existing;

  bool get _editing => widget.pendingId != null;

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _purpose.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _load(PendingView v) {
    final p = v.payment;
    _existing = v;
    _direction = p.direction;
    _kind = p.kind;
    _name.text = p.counterparty;
    _amount.text = MoneyFormatter.editable(p.originalAmount);
    _purpose.text = p.purpose;
    _notes.text = p.notes ?? '';
    _created = p.createdDate;
    _due = p.dueDate;
    _loaded = true;
  }

  Future<void> _submit() async {
    final today = ref.read(todayProvider);
    final amount = AmountField.parse(_amount.text);
    if (amount == null) {
      setState(() => _errors = {'amount': 'Enter an amount greater than zero.'});
      return;
    }
    final notes = _notes.text.trim();
    final input = PendingInput(
      counterparty: _name.text.trim(),
      direction: _direction,
      kind: _kind,
      amount: amount,
      purpose: _purpose.text.trim(),
      createdDate: _created ?? today,
      dueDate: _due,
      notes: notes.isEmpty ? null : notes,
    );
    setState(() {
      _busy = true;
      _errors = const {};
    });
    void onErrors(Map<String, String> e) => setState(() => _errors = e);
    final existing = _existing;
    final Object? result = existing == null
        ? await runAction(context, ref,
            action: const CreatePendingAction(), input: input, idempotencyKey: _key, onFieldErrors: onErrors)
        : await runAction(context, ref,
            action: const UpdatePendingAction(),
            input: UpdatePendingInput(id: existing.payment.id, expectedVersion: existing.payment.version, data: input),
            idempotencyKey: _key,
            onFieldErrors: onErrors);
    if (!mounted) return;
    setState(() => _busy = false);
    if (result != null) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final today = ref.watch(todayProvider);
    if (_editing && !_loaded) {
      final v = ref.watch(pendingViewProvider(widget.pendingId!)).value;
      if (v != null) _load(v);
    }
    final c = context.colors;
    final t = context.text;
    final existing = _existing;
    if (_editing && existing == null) {
      return const FinnSheetScaffold(
        title: 'Edit money owed',
        child: SkeletonPulse(child: Column(children: [CardSkeleton(height: 60), SizedBox(height: Space.x4), CardSkeleton(height: 240)])),
      );
    }
    final names = ref.watch(_pendingNamesProvider);
    final typed = _name.text.trim().toLowerCase();
    final suggestions = names
        .where((n) => n.toLowerCase() != typed && (typed.isEmpty || n.toLowerCase().contains(typed)))
        .take(6)
        .toList();
    final settled = existing?.settled ?? Money.zero;

    return FinnSheetScaffold(
      title: _editing ? 'Edit money owed' : 'Add money owed',
      description: _editing ? existing!.payment.purpose : 'Track what you owe or are owed. Your balance does not change.',
      footer: FinnButton(
        label: _editing ? 'Save changes' : 'Add',
        icon: _editing ? LucideIcons.check : LucideIcons.plus,
        expand: true,
        loading: _busy,
        onPressed: _busy ? null : _submit,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const PendingFieldLabel('Direction'),
          if (_editing)
            FinnCard(
              variant: FinnCardVariant.muted,
              padding: const EdgeInsets.all(Space.x3),
              child: Row(
                children: [
                  Icon(_direction.icon, size: 18, color: _direction.color(c)),
                  const SizedBox(width: Space.x2),
                  Expanded(child: Text(_direction.label, style: t.bodyStrong)),
                  Icon(LucideIcons.lock, size: 14, color: c.textTertiary),
                  const SizedBox(width: Space.x1),
                  Text('Locked', style: t.micro),
                ],
              ),
            )
          else
            SegmentedTabs<PendingDirection>(
              items: const [
                SegmentItem(PendingDirection.iOwe, 'I owe'),
                SegmentItem(PendingDirection.owedToMe, 'I will receive'),
              ],
              selected: _direction,
              onChanged: (d) => setState(() => _direction = d),
            ),
          const SizedBox(height: Space.x1_5),
          Text(
            _editing
                ? 'Direction cannot change after creation. Delete and re-add if it was wrong.'
                : (_direction.isOwe ? 'You have to pay this person.' : 'This person has to pay you.'),
            style: t.micro,
          ),
          const SizedBox(height: Space.x5),
          FinnTextField(
            label: _direction.isOwe ? 'Who do you owe?' : 'Who owes you?',
            hint: 'Name',
            controller: _name,
            prefixIcon: LucideIcons.user,
            errorText: _errors['counterparty'],
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            onChanged: (_) => setState(() {}),
          ),
          if (suggestions.isNotEmpty) ...[
            const SizedBox(height: Space.x2),
            Wrap(
              spacing: Space.x2,
              runSpacing: Space.x1,
              children: [
                for (final n in suggestions)
                  ActionChip(
                    avatar: const Icon(LucideIcons.user, size: 14),
                    label: Text(n),
                    onPressed: () => setState(() => _name.text = n),
                  ),
              ],
            ),
          ],
          const SizedBox(height: Space.x5),
          const PendingFieldLabel('Reason'),
          FilterChipBar<PendingKind>(
            padding: EdgeInsets.zero,
            multiSelect: false,
            items: [for (final k in PendingKind.values) FilterChipItem(k, k.label)],
            selected: {_kind},
            onChanged: (s) => setState(() => _kind = s.first),
          ),
          const SizedBox(height: Space.x5),
          AmountField(
            label: _editing ? 'Original amount' : 'Amount',
            controller: _amount,
            errorText: _errors['amount'],
            textInputAction: TextInputAction.next,
          ),
          if (settled.isPositive) ...[
            const SizedBox(height: Space.x1_5),
            Text('${settled.format()} is already settled, so the amount cannot be lower than that.', style: t.micro),
          ],
          const SizedBox(height: Space.x5),
          FinnTextField(
            label: 'What is it for?',
            hint: 'e.g. Goa trip hotel share',
            controller: _purpose,
            errorText: _errors['purpose'],
            maxLength: 80,
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: Space.x3),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: DateField(
                  label: 'Since',
                  value: _created ?? today,
                  firstDate: DateTime(today.year - 10),
                  lastDate: today,
                  errorText: _errors['createdDate'],
                  onChanged: (d) => setState(() => _created = d),
                ),
              ),
              const SizedBox(width: Space.x3),
              Expanded(
                child: DateField(
                  label: 'Due (optional)',
                  hint: 'No due date',
                  value: _due,
                  firstDate: _created ?? DateTime(today.year - 10),
                  lastDate: DateTime(today.year + 10),
                  errorText: _errors['dueDate'],
                  onChanged: (d) => setState(() => _due = d),
                ),
              ),
            ],
          ),
          if (_due != null)
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton.icon(
                onPressed: () => setState(() => _due = null),
                icon: const Icon(LucideIcons.x, size: 14),
                label: const Text('Clear due date'),
              ),
            ),
          const SizedBox(height: Space.x3),
          FinnTextField(
            label: 'Notes (optional)',
            hint: 'Anything to remember',
            controller: _notes,
            errorText: _errors['notes'],
            maxLines: 3,
            minLines: 2,
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: Space.x4),
          const InfoBanner(
            message: 'Adding this does not change your balance. When money changes hands, settle it to record the cash movement once.',
          ),
        ],
      ),
    );
  }
}
