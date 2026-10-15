import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/data_providers.dart';
import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../kit/kit.dart';
import '../../../shared/presentation/action_runner.dart';
import '../application/account_actions.dart';
import '../domain/money_account.dart';

/// "Correct balance": enter what the account really shows (or what a credit
/// card really owes). The account's opening figures are adjusted so that
/// today's balance matches; transactions are kept.
class SetBalanceSheet extends ConsumerStatefulWidget {
  const SetBalanceSheet({super.key, required this.accountId});

  final String accountId;

  @override
  ConsumerState<SetBalanceSheet> createState() => _SetBalanceSheetState();
}

class _SetBalanceSheetState extends ConsumerState<SetBalanceSheet> {
  final _key = newIdempotencyKey();
  final _amount = TextEditingController();
  Money? _value;
  Map<String, String> _errors = const {};
  bool _submitting = false;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _submit(AccountBalance b) async {
    final value = LedgerAmountField.parse(_amount.text);
    if (value == null) {
      setState(() => _errors = {'balance': b.isLiability ? 'Enter the amount owed.' : 'Enter the actual balance.'});
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _errors = const {};
    });
    final result = await runAction(
      context,
      ref,
      action: const SetAccountBalanceAction(),
      input: SetAccountBalanceInput(id: b.account.id, balance: value),
      idempotencyKey: _key,
      successTitle: 'Balance corrected',
      successSubtitle: b.account.name,
      onFieldErrors: (e) {
        if (mounted) setState(() => _errors = e);
      },
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (result != null) await Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(accountBalanceProvider(widget.accountId));
    final b = value.value;
    final ready = value.hasValue;
    final missing = ready && b == null;
    return FinnSheetScaffold(
      title: b != null && b.isLiability ? 'Correct amount owed' : 'Correct balance',
      description: 'Your transactions are kept. Only the starting figure changes to match.',
      footer: LedgerButton(
        label: 'Save',
        expand: true,
        loading: _submitting,
        onPressed: _submitting || b == null ? null : () => _submit(b),
      ),
      child: !ready
          ? const LedgerSkeleton(height: 120)
          : missing
          ? const LedgerEmpty(title: 'Account not found', message: 'It may have been deleted.')
          : _form(context, b!),
    );
  }

  Widget _form(BuildContext context, AccountBalance b) {
    final c = context.ink;
    final t = context.type;
    final liability = b.isLiability;
    final next = _value;
    final changed = next != null && next != b.balance;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LedgerAmountField(
          hero: true,
          controller: _amount,
          label: liability ? 'Amount owed now' : 'Actual balance',
          helper: liability ? 'What your card statement says you owe.' : 'What the account really holds right now.',
          errorText: _errors['balance'],
          onChanged: (m) => setState(() {
            _value = m;
            _errors = {..._errors}..remove('balance');
          }),
        ),
        const SizedBox(height: LedgerForm.gap),
        LedgerPanel(
          padding: const EdgeInsets.symmetric(vertical: Sp.xs),
          children: [
            LedgerFact(
              label: liability ? 'Owed now' : 'Balance now',
              value: AmountText(b.balance, style: t.figure),
            ),
            LedgerFact(
              label: liability ? 'Will be owed' : 'Will be',
              value: next == null
                  ? Text('—', style: t.figure.copyWith(color: c.inkFaint))
                  : AmountText(next, style: t.figure),
            ),
            if (changed)
              LedgerFact(
                label: 'Difference',
                value: AmountText(next - b.balance, sign: SignDisplay.always, style: t.figureSmall.copyWith(color: c.ink)),
              ),
          ],
        ),
      ],
    );
  }
}
