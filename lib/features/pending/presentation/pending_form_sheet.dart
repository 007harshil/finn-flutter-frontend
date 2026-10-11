import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'pending_person_field.dart';
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
  Map<String, String> _errors = const {};
  bool _busy = false;
  bool _loaded = false;
  PendingView? _existing;
  FinnUser? _linked;

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
    final link = p.link;
    _linked = link == null
        ? null
        : (ref.read(userDirectoryProvider).known(link.userId) ??
            FinnUser(id: link.userId, name: p.counterparty, handle: link.handle));
    _amount.text = MoneyFormatter.editable(p.originalAmount);
    _purpose.text = p.purpose;
    _notes.text = p.notes ?? '';
    _created = p.createdDate;
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
      notes: notes.isEmpty ? null : notes,
      linkedUserId: _linked?.id,
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
            Row(
              children: [
                for (final d in PendingDirection.values) ...[
                  if (d != PendingDirection.values.first) const SizedBox(width: Space.x2),
                  Expanded(
                    child: _DirectionTile(
                      direction: d,
                      selected: _direction == d,
                      onTap: () => setState(() => _direction = d),
                    ),
                  ),
                ],
              ],
            ),
          const SizedBox(height: Space.x1_5),
          Text(
            _editing
                ? 'Direction cannot change after creation. Delete and re-add if it was wrong.'
                : (_direction.isOwe ? 'You have to pay this person.' : 'This person has to pay you.'),
            style: t.micro,
          ),
          const SizedBox(height: Space.x4),
          PendingPersonField(
            controller: _name,
            label: _direction.isOwe ? 'Who do you owe?' : 'Who owes you?',
            direction: _direction,
            linked: _linked,
            locked: existing?.payment.isShared ?? false,
            recentNames: suggestions,
            errorText: _errors['counterparty'] ?? _errors['linkedUserId'],
            onLinked: (u) => setState(() => _linked = u),
          ),
          const SizedBox(height: Space.x4),
          const PendingFieldLabel('Reason'),
          FilterChipBar<PendingKind>(
            padding: EdgeInsets.zero,
            multiSelect: false,
            items: [for (final k in PendingKind.values) FilterChipItem(k, k.label)],
            selected: {_kind},
            onChanged: (s) => setState(() => _kind = s.first),
          ),
          const SizedBox(height: Space.x4),
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
          const SizedBox(height: Space.x4),
          FinnTextField(
            label: 'What is it for?',
            hint: 'e.g. Goa trip hotel share',
            controller: _purpose,
            errorText: _errors['purpose'],
            maxLength: 80,
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: Space.x3),
          DateField(
            label: 'Since',
            value: _created ?? today,
            firstDate: DateTime(today.year - 10),
            lastDate: today,
            errorText: _errors['createdDate'],
            onChanged: (d) => setState(() => _created = d),
          ),
          const SizedBox(height: Space.x1_5),
          Text('No deadline needed. FiNN shows how many days have passed since this date.', style: t.micro),
          const SizedBox(height: Space.x4),
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

/// Who pays whom, as two tiles with an arrow showing which way money moves.
class _DirectionTile extends StatelessWidget {
  const _DirectionTile({required this.direction, required this.selected, required this.onTap});

  final PendingDirection direction;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final color = direction.color(c);
    return Semantics(
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      label: direction.label,
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: Radii.rLg,
          onTap: () {
            if (selected) return;
            HapticFeedback.selectionClick();
            onTap();
          },
          child: AnimatedContainer(
            duration: context.motion.normal,
            curve: Curves2.emphasized,
            padding: const EdgeInsets.symmetric(horizontal: Space.x3, vertical: Space.x2_5),
            decoration: BoxDecoration(
              color: selected ? direction.soft(c) : c.surface,
              borderRadius: Radii.rLg,
              border: Border.all(color: selected ? color : c.border, width: selected ? 1.5 : 1),
            ),
            child: Row(
              children: [
                AnimatedScale(
                  scale: selected ? 1 : 0.85,
                  duration: context.motion.normal,
                  curve: Curves.easeOutBack,
                  child: IconTile(
                    icon: direction.icon,
                    background: selected ? color : c.surfaceMuted,
                    foreground: selected ? c.onSolid : c.textSecondary,
                    size: 30,
                    iconSize: 16,
                  ),
                ),
                const SizedBox(width: Space.x2),
                Expanded(
                  child: Text(
                    direction.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.label.copyWith(
                      color: selected ? c.textPrimary : c.textSecondary,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    ),
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
