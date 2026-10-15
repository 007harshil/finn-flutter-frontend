import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/core_providers.dart';
import '../../../app/di/data_providers.dart';
import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../kit/kit.dart';
import '../../../shared/presentation/action_runner.dart';
import '../application/account_actions.dart';
import '../domain/money_account.dart';
import 'widgets/account_ui.dart';

/// Create or edit a money account.
class AccountFormSheet extends ConsumerStatefulWidget {
  const AccountFormSheet({super.key, this.accountId});

  final String? accountId;

  @override
  ConsumerState<AccountFormSheet> createState() => _AccountFormSheetState();
}

class _AccountFormSheetState extends ConsumerState<AccountFormSheet> {
  final _key = newIdempotencyKey();
  final _name = TextEditingController();
  final _institution = TextEditingController();
  final _last4 = TextEditingController();
  final _opening = TextEditingController();
  final _limit = TextEditingController();
  final _note = TextEditingController();
  MoneyAccountKind _kind = MoneyAccountKind.bank;
  DateTime? _openingDate;
  bool _makeDefault = false;
  Map<String, String> _errors = const {};
  bool _submitting = false;
  bool _loaded = false;
  MoneyAccount? _existing;

  bool get _isEdit => widget.accountId != null;

  @override
  void dispose() {
    _name.dispose();
    _institution.dispose();
    _last4.dispose();
    _opening.dispose();
    _limit.dispose();
    _note.dispose();
    super.dispose();
  }

  void _load(MoneyAccount? a) {
    if (_loaded) return;
    _loaded = true;
    if (a == null) return;
    _existing = a;
    _name.text = a.name;
    _institution.text = a.institution ?? '';
    _last4.text = a.last4 ?? '';
    _opening.text = MoneyFormatter.editable(a.opening);
    final limit = a.creditLimit;
    if (limit != null) _limit.text = MoneyFormatter.editable(limit);
    _note.text = a.note ?? '';
    _kind = a.kind;
    _openingDate = a.openingDate;
  }

  void _clearError(String field) {
    if (_errors.containsKey(field)) setState(() => _errors = {..._errors}..remove(field));
  }

  String? _trimmed(TextEditingController c) {
    final t = c.text.trim();
    return t.isEmpty ? null : t;
  }

  Future<void> _submit() async {
    final today = ref.read(todayProvider);
    final opening = _opening.text.trim().isEmpty ? Money.zero : LedgerAmountField.parse(_opening.text);
    final limit = _limit.text.trim().isEmpty ? null : LedgerAmountField.parse(_limit.text);
    final last4 = _trimmed(_last4);
    final local = <String, String>{
      if (_name.text.trim().isEmpty) 'name': 'Enter a name.',
      if (opening == null) 'openingBalance': 'Enter a valid amount.',
      if (_kind.isCard && last4 != null && !RegExp(r'^\d{4}$').hasMatch(last4)) 'last4': 'Enter exactly 4 digits.',
      if (_kind.isLiability && _limit.text.trim().isNotEmpty && limit == null) 'creditLimit': 'Enter a valid amount.',
    };
    if (local.isNotEmpty) {
      setState(() => _errors = local);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _errors = const {};
    });
    void onErrors(Map<String, String> e) {
      if (mounted) setState(() => _errors = e);
    }

    final existing = _existing;
    final data = AccountInput(
      name: _name.text.trim(),
      kind: _kind,
      openingBalance: opening!,
      institution: _trimmed(_institution),
      last4: _kind.isCard ? last4 : null,
      openingDate: _openingDate ?? (existing == null ? today : null),
      creditLimit: _kind.isLiability ? limit : null,
      isDefault: existing == null ? _makeDefault : null,
      note: _trimmed(_note),
    );
    final MoneyAccount? result;
    if (existing == null) {
      result = await runAction(
        context,
        ref,
        action: const CreateAccountAction(),
        input: data,
        idempotencyKey: _key,
        successTitle: 'Account added',
        successSubtitle: data.name,
        onFieldErrors: onErrors,
      );
    } else {
      result = await runAction(
        context,
        ref,
        action: const UpdateAccountAction(),
        input: UpdateAccountInput(id: existing.id, version: existing.version, data: data),
        idempotencyKey: _key,
        successTitle: 'Account updated',
        onFieldErrors: onErrors,
      );
    }
    if (!mounted) return;
    setState(() => _submitting = false);
    if (result != null) await Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final value = _isEdit ? ref.watch(accountBalanceProvider(widget.accountId!)) : null;
    final ready = value == null || value.hasValue || _loaded;
    if (value != null && value.hasValue) _load(value.value?.account);
    final missing = _isEdit && ready && _existing == null;
    return FinnSheetScaffold(
      title: _isEdit ? 'Edit account' : 'New account',
      footer: LedgerButton(
        label: _isEdit ? 'Save changes' : 'Add account',
        expand: true,
        loading: _submitting,
        onPressed: _submitting || !ready || missing ? null : _submit,
      ),
      child: !ready
          ? const Column(
              children: [LedgerSkeleton(height: 52), SizedBox(height: LedgerForm.gap), LedgerSkeleton(height: 52)],
            )
          : missing
          ? const LedgerEmpty(title: 'Account not found', message: 'It may have been deleted.')
          : _form(context),
    );
  }

  Widget _form(BuildContext context) {
    final today = ref.watch(todayProvider);
    final liability = _kind.isLiability;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LedgerTextField(
          controller: _name,
          label: 'Name',
          hint: 'e.g. SBI savings',
          errorText: _errors['name'],
          maxLength: 40,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          onChanged: (_) => _clearError('name'),
        ),
        const SizedBox(height: LedgerForm.gap),
        LedgerField(
          label: 'Kind',
          errorText: _errors['kind'],
          child: LedgerChoiceChips<MoneyAccountKind>(
            options: [
              for (final k in MoneyAccountKind.values) LedgerOption(k, k.label, icon: accountIcon(k)),
            ],
            selected: _kind,
            onChanged: (v) => setState(() {
              _kind = v;
              _errors = {..._errors}
                ..remove('kind')
                ..remove('last4')
                ..remove('creditLimit');
            }),
          ),
        ),
        const SizedBox(height: LedgerForm.groupGap),
        LedgerTextField(
          controller: _institution,
          label: 'Institution (optional)',
          hint: 'e.g. HDFC Bank',
          errorText: _errors['institution'],
          maxLength: 40,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          onChanged: (_) => _clearError('institution'),
        ),
        if (_kind.isCard) ...[
          const SizedBox(height: LedgerForm.gap),
          LedgerTextField(
            controller: _last4,
            label: 'Last 4 digits (optional)',
            hint: '1234',
            errorText: _errors['last4'],
            maxLength: 4,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            textInputAction: TextInputAction.next,
            onChanged: (_) => _clearError('last4'),
          ),
        ],
        const SizedBox(height: LedgerForm.gap),
        LedgerAmountField(
          controller: _opening,
          label: liability ? 'Amount owed' : 'Opening balance',
          helper: liability ? 'What you owe on this card right now.' : 'Money in it on the date below.',
          errorText: _errors['openingBalance'],
          onChanged: (_) => _clearError('openingBalance'),
        ),
        const SizedBox(height: LedgerForm.gap),
        LedgerDateField(
          label: liability ? 'Owed as of' : 'Balance as of',
          value: _openingDate ?? today,
          firstDate: DateTime(2000),
          lastDate: today,
          errorText: _errors['openingDate'],
          onChanged: (d) => setState(() {
            _openingDate = d;
            _errors = {..._errors}..remove('openingDate');
          }),
        ),
        if (liability) ...[
          const SizedBox(height: LedgerForm.gap),
          LedgerAmountField(
            controller: _limit,
            label: 'Credit limit (optional)',
            errorText: _errors['creditLimit'],
            onChanged: (_) => _clearError('creditLimit'),
          ),
        ],
        const SizedBox(height: LedgerForm.gap),
        LedgerTextField(
          controller: _note,
          label: 'Note (optional)',
          errorText: _errors['note'],
          maxLength: 200,
          minLines: 1,
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
          onChanged: (_) => _clearError('note'),
        ),
        if (!_isEdit) ...[
          const SizedBox(height: LedgerForm.gap),
          LedgerSwitchRow(
            title: 'Set as default',
            subtitle: 'New transactions start on this account.',
            value: _makeDefault,
            onChanged: (v) => setState(() => _makeDefault = v),
          ),
        ],
      ],
    );
  }
}
