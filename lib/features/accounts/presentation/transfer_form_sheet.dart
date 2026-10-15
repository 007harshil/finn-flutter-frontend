import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/di/core_providers.dart';
import '../../../app/di/data_providers.dart';
import '../../../core/money/money_format.dart';
import '../../../kit/kit.dart';
import '../../../shared/presentation/action_runner.dart';
import '../application/account_support.dart';
import '../application/transfer_actions.dart';
import '../domain/transfer.dart';
import 'widgets/account_picker_field.dart';
import 'widgets/channel_field.dart';

/// Opens the transfer form: move money between two of your own accounts.
/// Pass [existing] to edit (or delete) a transfer; [fromAccountId] /
/// [toAccountId] preselect accounts for a new one.
Future<void> showTransferSheet(
  BuildContext context, {
  String? fromAccountId,
  String? toAccountId,
  Transfer? existing,
}) {
  return showFinnSheet<void>(
    context,
    builder: (_) => TransferFormSheet(
      fromAccountId: fromAccountId,
      toAccountId: toAccountId,
      existing: existing,
    ),
  );
}

class TransferFormSheet extends ConsumerStatefulWidget {
  const TransferFormSheet({
    super.key,
    this.fromAccountId,
    this.toAccountId,
    this.existing,
  });

  final String? fromAccountId;
  final String? toAccountId;
  final Transfer? existing;

  @override
  ConsumerState<TransferFormSheet> createState() => _TransferFormSheetState();
}

class _TransferFormSheetState extends ConsumerState<TransferFormSheet> {
  final _key = newIdempotencyKey();
  final _deleteKey = newIdempotencyKey();
  final _amount = TextEditingController();
  final _note = TextEditingController();
  String? _from;
  String? _to;
  late DateTime _date;
  String? _channel;
  Map<String, String> _errors = const {};
  bool _submitting = false;
  bool _deleting = false;

  bool get _editing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _date = ref.read(todayProvider);
    if (e != null) {
      _from = e.fromAccountId;
      _to = e.toAccountId;
      _date = e.date;
      _channel = e.channel;
      _amount.text = MoneyFormatter.editable(e.amount);
      _note.text = e.note ?? '';
    } else {
      _from =
          widget.fromAccountId ?? ref.read(defaultAccountProvider).value?.id;
      _to = widget.toAccountId == _from ? null : widget.toAccountId;
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  void _clearError(String field) {
    if (_errors.containsKey(field))
      setState(() => _errors = Map.of(_errors)..remove(field));
  }

  Future<void> _submit() async {
    if (_submitting || _deleting) return;
    FocusScope.of(context).unfocus();
    final amount = LedgerAmountField.parse(_amount.text);
    final note = _note.text.trim();
    final local = <String, String>{
      if (_from == null)
        'fromAccountId': 'Choose the account the money leaves.',
      if (_to == null) 'toAccountId': 'Choose the account the money goes to.',
      if (_from != null && _from == _to)
        'toAccountId': 'Choose two different accounts.',
      if (amount == null || !amount.isPositive)
        'amount': 'Enter an amount greater than zero.',
      if (channelError(_channel) != null) 'channel': channelError(_channel)!,
    };
    if (local.isNotEmpty) {
      setState(() => _errors = local);
      return;
    }
    setState(() {
      _errors = const {};
      _submitting = true;
    });
    final data = TransferInput(
      fromAccountId: _from!,
      toAccountId: _to!,
      amount: amount!,
      date: _date,
      channel: cleanChannel(_channel),
      note: note.isEmpty ? null : note,
    );
    void onErrors(Map<String, String> e) {
      if (mounted) setState(() => _errors = e);
    }

    final existing = widget.existing;
    final Transfer? saved;
    if (existing == null) {
      saved = await runAction(
        context,
        ref,
        action: const CreateTransferAction(),
        input: data,
        idempotencyKey: _key,
        successTitle: 'Transfer recorded',
        successSubtitle: amount.format(),
        onFieldErrors: onErrors,
      );
    } else {
      saved = await runAction(
        context,
        ref,
        action: const UpdateTransferAction(),
        input: UpdateTransferInput(
          id: existing.id,
          version: existing.version,
          data: data,
        ),
        idempotencyKey: _key,
        successTitle: 'Changes saved',
        successSubtitle: amount.format(),
        onFieldErrors: onErrors,
      );
    }
    if (!mounted) return;
    if (saved == null) {
      setState(() => _submitting = false);
      return;
    }
    await Navigator.of(context).maybePop();
  }

  Future<void> _delete() async {
    final existing = widget.existing;
    if (existing == null || _deleting || _submitting) return;
    final ok = await showFinnConfirm(
      context,
      title: 'Delete transfer?',
      message: 'Both account balances will update. This cannot be undone.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() => _deleting = true);
    final deleted = await runAction(
      context,
      ref,
      action: const DeleteTransferAction(),
      input: DeleteTransferInput(id: existing.id),
      idempotencyKey: _deleteKey,
      successTitle: 'Transfer deleted',
      successSubtitle: 'Your balances have been updated.',
    );
    if (!mounted) return;
    if (deleted == null) {
      setState(() => _deleting = false);
      return;
    }
    await Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final today = ref.watch(todayProvider);
    final c = context.ink;
    return FinnSheetScaffold(
      title: _editing ? 'Edit transfer' : 'Transfer',
      footer: LedgerButton(
        label: _editing ? 'Save changes' : 'Record transfer',
        expand: true,
        loading: _submitting,
        onPressed: _submitting || _deleting ? null : _submit,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LedgerAmountField(
            hero: true,
            label: 'Amount',
            controller: _amount,
            autofocus: !_editing,
            errorText: _errors['amount'],
            textInputAction: TextInputAction.next,
            onChanged: (_) => _clearError('amount'),
          ),
          const SizedBox(height: LedgerForm.gap),
          AccountPickerField(
            label: 'From',
            value: _from,
            errorText: _errors['fromAccountId'],
            onChanged: (id) => setState(() {
              _from = id;
              if (_to == id) _to = null;
              _errors = Map.of(_errors)
                ..remove('fromAccountId')
                ..remove('toAccountId');
            }),
          ),
          const SizedBox(height: LedgerForm.gap),
          AccountPickerField(
            label: 'To',
            value: _to,
            exclude: _from,
            errorText: _errors['toAccountId'],
            onChanged: (id) => setState(() {
              _to = id;
              _errors = Map.of(_errors)..remove('toAccountId');
            }),
          ),
          const SizedBox(height: LedgerForm.gap),
          LedgerDateField(
            label: 'Date',
            value: _date,
            firstDate: DateTime(2000),
            lastDate: today,
            errorText: _errors['date'],
            onChanged: (d) => setState(() {
              _date = d;
              _errors = Map.of(_errors)..remove('date');
            }),
          ),
          const SizedBox(height: LedgerForm.gap),
          ChannelField(
            value: _channel,
            errorText: _errors['channel'],
            onChanged: (v) {
              _channel = v;
              _clearError('channel');
            },
          ),
          const SizedBox(height: LedgerForm.gap),
          LedgerTextField(
            label: 'Note (optional)',
            controller: _note,
            minLines: 2,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            errorText: _errors['note'],
            onChanged: (_) => _clearError('note'),
          ),
          if (_editing) ...[
            const SizedBox(height: LedgerForm.groupGap),
            LedgerButton(
              label: 'Delete transfer',
              icon: LucideIcons.trash2,
              variant: LedgerButtonVariant.quiet,
              color: c.red,
              expand: true,
              loading: _deleting,
              onPressed: _submitting ? null : _delete,
            ),
          ],
        ],
      ),
    );
  }
}
