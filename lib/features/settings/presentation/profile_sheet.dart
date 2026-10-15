import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/di/core_providers.dart';
import '../../../app/di/data_providers.dart';
import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../kit/kit.dart';
import '../../../shared/presentation/action_runner.dart';
import '../application/profile_actions.dart';
import '../domain/financial_profile.dart';

/// Edit the user's name and financial starting point.
class ProfileSheet extends ConsumerStatefulWidget {
  const ProfileSheet({super.key});

  @override
  ConsumerState<ProfileSheet> createState() => _ProfileSheetState();
}

class _ProfileSheetState extends ConsumerState<ProfileSheet> {
  final _key = newIdempotencyKey();
  final _name = TextEditingController();
  final _opening = TextEditingController();
  final _income = TextEditingController();
  DateTime? _openingDate;
  Money? _openingValue;
  Map<String, String> _errors = const {};
  bool _submitting = false;
  bool _loaded = false;
  FinancialProfile? _existing;

  @override
  void dispose() {
    _name.dispose();
    _opening.dispose();
    _income.dispose();
    super.dispose();
  }

  void _load(FinancialProfile? p) {
    if (_loaded) return;
    _loaded = true;
    if (p == null) return;
    _existing = p;
    _name.text = p.displayName;
    _opening.text = MoneyFormatter.editable(p.openingBalance);
    _openingValue = p.openingBalance;
    _openingDate = p.openingDate;
    final income = p.monthlyIncomeEstimate;
    if (income != null) _income.text = MoneyFormatter.editable(income);
  }

  void _clearError(String field) {
    if (_errors.containsKey(field)) {
      setState(() => _errors = {..._errors}..remove(field));
    }
  }

  bool get _changesBalances {
    final e = _existing;
    if (e == null) return false;
    final d = _openingDate;
    return (_openingValue != null && _openingValue != e.openingBalance) ||
        (d != null &&
            (d.year != e.openingDate.year ||
                d.month != e.openingDate.month ||
                d.day != e.openingDate.day));
  }

  Future<void> _submit() async {
    final opening = _opening.text.trim().isEmpty
        ? Money.zero
        : LedgerAmountField.parse(_opening.text);
    final income = _income.text.trim().isEmpty
        ? null
        : LedgerAmountField.parse(_income.text);
    final local = <String, String>{
      if (_name.text.trim().isEmpty) 'displayName': 'Enter a name.',
      if (opening == null)
        'openingBalance': 'Enter a valid amount, e.g. 25,000.',
      if (_income.text.trim().isNotEmpty && income == null)
        'monthlyIncomeEstimate': 'Enter a valid amount.',
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
    final result = await runAction(
      context,
      ref,
      action: const UpdateProfileAction(),
      input: UpdateProfileInput(
        displayName: _name.text.trim(),
        openingBalance: opening!,
        openingDate: _openingDate ?? ref.read(todayProvider),
        monthlyIncomeEstimate: income != null && income.isPositive
            ? income
            : null,
      ),
      idempotencyKey: _key,
      successTitle: 'Profile saved',
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
    final value = ref.watch(profileStreamProvider);
    final ready = value.hasValue || _loaded;
    if (value.hasValue) _load(value.value);
    return FinnSheetScaffold(
      title: 'Your profile',
      footer: LedgerButton(
        label: 'Save profile',
        expand: true,
        loading: _submitting,
        onPressed: _submitting || !ready ? null : _submit,
      ),
      child: !ready
          ? (value.hasError
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: Sp.xl),
                    child: LedgerEmpty(
                      title: 'Could not load your profile',
                      message: 'Please close and try again.',
                    ),
                  )
                : const _FormSkeleton())
          : _form(context),
    );
  }

  Widget _form(BuildContext context) {
    final today = ref.watch(todayProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LedgerTextField(
          controller: _name,
          label: 'Name',
          hint: 'e.g. Priya',
          errorText: _errors['displayName'],
          maxLength: 40,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          onChanged: (_) => _clearError('displayName'),
        ),
        const SizedBox(height: LedgerForm.gap),
        LedgerAmountField(
          hero: true,
          controller: _opening,
          label: 'Opening balance',
          helper: 'Bank and wallet when you started. Balances are worked out from this.',
          errorText: _errors['openingBalance'],
          textInputAction: TextInputAction.next,
          onChanged: (m) => setState(() {
            _openingValue = m;
            _errors = {..._errors}..remove('openingBalance');
          }),
        ),
        const SizedBox(height: LedgerForm.gap),
        LedgerDateField(
          label: 'Tracking since',
          value: _openingDate ?? today,
          firstDate: DateTime(today.year - 30),
          lastDate: today,
          errorText: _errors['openingDate'],
          onChanged: (d) => setState(() {
            _openingDate = d;
            _errors = {..._errors}..remove('openingDate');
          }),
        ),
        const SizedBox(height: Sp.sm),
        Text(
          'Transactions before this date are not counted in your cash balance.',
          style: context.type.label,
        ),
        if (_changesBalances) ...[
          const SizedBox(height: Sp.md),
          const LedgerNote(
            icon: LucideIcons.triangleAlert,
            tone: NoteTone.caution,
            text: "This recalculates every balance. You'll review the before and after before anything changes.",
          ),
        ],
        const SizedBox(height: LedgerForm.gap),
        LedgerAmountField(
          controller: _income,
          label: 'Monthly income (optional)',
          helper: 'Used for guidance until we see your income.',
          errorText: _errors['monthlyIncomeEstimate'],
          onChanged: (_) => _clearError('monthlyIncomeEstimate'),
        ),
      ],
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
            LedgerSkeleton(height: 52),
            SizedBox(height: LedgerForm.gap),
            LedgerSkeleton(width: 200, height: 44),
            SizedBox(height: LedgerForm.gap),
            LedgerSkeleton(height: 52),
            SizedBox(height: LedgerForm.gap),
            LedgerSkeleton(height: 52),
          ],
        ),
      ),
    );
  }
}
