import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/di/core_providers.dart';
import '../../../app/di/data_providers.dart';
import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../design_system/design_system.dart';
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
    if (_errors.containsKey(field)) setState(() => _errors = {..._errors}..remove(field));
  }

  bool get _changesBalances {
    final e = _existing;
    if (e == null) return false;
    final d = _openingDate;
    return (_openingValue != null && _openingValue != e.openingBalance) ||
        (d != null && (d.year != e.openingDate.year || d.month != e.openingDate.month || d.day != e.openingDate.day));
  }

  Future<void> _submit() async {
    final opening = _opening.text.trim().isEmpty ? Money.zero : AmountField.parse(_opening.text);
    final income = _income.text.trim().isEmpty ? null : AmountField.parse(_income.text);
    final local = <String, String>{
      if (_name.text.trim().isEmpty) 'displayName': 'Enter a name.',
      if (opening == null) 'openingBalance': 'Enter a valid amount, e.g. 25,000.',
      if (_income.text.trim().isNotEmpty && income == null) 'monthlyIncomeEstimate': 'Enter a valid amount.',
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
        monthlyIncomeEstimate: income != null && income.isPositive ? income : null,
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
      description: 'Your name and where your tracking starts. Balances are worked out from these.',
      footer: FinnButton(
        label: 'Save profile',
        icon: LucideIcons.check,
        expand: true,
        size: FinnButtonSize.lg,
        loading: _submitting,
        onPressed: _submitting || !ready ? null : _submit,
      ),
      child: !ready
          ? (value.hasError
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: Space.x6),
                  child: ErrorState(title: 'Could not load your profile', message: 'Please close and try again.'),
                )
              : const SkeletonPulse(child: ListSkeleton(count: 4, padding: EdgeInsets.zero)))
          : _form(context),
    );
  }

  Widget _form(BuildContext context) {
    final t = context.text;
    final today = ref.watch(todayProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FinnTextField(
          controller: _name,
          label: 'What should we call you?',
          hint: 'e.g. Priya',
          prefixIcon: LucideIcons.user,
          errorText: _errors['displayName'],
          maxLength: 40,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          onChanged: (_) => _clearError('displayName'),
        ),
        const SizedBox(height: Space.x3),
        AmountField(
          controller: _opening,
          label: 'Opening balance',
          hint: 'Bank + wallet when you started',
          errorText: _errors['openingBalance'],
          textInputAction: TextInputAction.next,
          onChanged: (m) => setState(() {
            _openingValue = m;
            _errors = {..._errors}..remove('openingBalance');
          }),
        ),
        const SizedBox(height: Space.x5),
        DateField(
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
        const SizedBox(height: Space.x1_5),
        Text('Transactions before this date are not counted in your cash balance.', style: t.caption),
        if (_changesBalances) ...[
          const SizedBox(height: Space.x3),
          const InfoBanner(
            tone: FinnTone.warning,
            title: 'This recalculates every balance',
            message: 'You\'ll see the before and after cash balance to review before anything changes.',
          ),
        ],
        const SizedBox(height: Space.x5),
        AmountField(
          controller: _income,
          label: 'Typical monthly income (optional)',
          hint: 'Used for guidance until we see your income',
          errorText: _errors['monthlyIncomeEstimate'],
          onChanged: (_) => _clearError('monthlyIncomeEstimate'),
        ),
      ],
    );
  }
}
