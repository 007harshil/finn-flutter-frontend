import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../app/di/data_providers.dart';
import '../../../../core/money/money_format.dart';
import '../../../../kit/kit.dart';
import '../../domain/money_account.dart';

/// Icon for an account kind (kit rows and picker options).
IconData accountKindIcon(MoneyAccountKind kind) => switch (kind) {
  MoneyAccountKind.cash => LucideIcons.banknote,
  MoneyAccountKind.bank => LucideIcons.landmark,
  MoneyAccountKind.promoCard => LucideIcons.gift,
  MoneyAccountKind.debitCard ||
  MoneyAccountKind.creditCard ||
  MoneyAccountKind.otherCard => LucideIcons.creditCard,
};

/// Picker value used for the "no account" row of an optional picker.
const String _none = '';

/// Picks one of the user's accounts. Opens a sheet listing active accounts
/// as "kind · ····last4" with the current balance (or amount owed).
///
/// The caller owns the selection: pass the default account id for new
/// records. [exclude] hides one account (the other side of a transfer).
/// With [optional] the sheet gains a "None" row and [onChanged] receives
/// null for it. An archived account that is the current [value] stays
/// listed so editing an old record does not lose it.
class AccountPickerField extends ConsumerWidget {
  const AccountPickerField({
    super.key,
    required this.value,
    required this.onChanged,
    this.label = 'Account',
    this.hint = 'Choose an account',
    this.helper,
    this.errorText,
    this.exclude,
    this.optional = false,
    this.noneLabel = 'None',
    this.enabled = true,
  });

  final String? value;
  final ValueChanged<String?> onChanged;
  final String? label;
  final String hint;
  final String? helper;
  final String? errorText;
  final String? exclude;
  final bool optional;
  final String noneLabel;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balances = ref.watch(accountBalancesProvider).value;
    if (balances == null) {
      return LedgerField(
        label: label,
        errorText: errorText,
        child: const LedgerSkeleton(height: 52),
      );
    }
    final options = <LedgerOption<String>>[
      if (optional)
        LedgerOption(
          _none,
          noneLabel,
          key: const ValueKey('account-none'),
          icon: LucideIcons.minus,
        ),
      for (final b in balances)
        if (b.account.id != exclude &&
            (!b.account.isArchived || b.account.id == value))
          LedgerOption(
            b.account.id,
            b.account.isArchived
                ? '${b.account.name} (archived)'
                : b.account.name,
            key: ValueKey('account-${b.account.id}'),
            icon: accountKindIcon(b.account.kind),
            subtitle: accountBalanceSubtitle(b),
          ),
    ];
    return LedgerPickerField<String>(
      label: label,
      pickerTitle: label ?? 'Account',
      hint: hint,
      helper: helper,
      errorText: errorText,
      enabled: enabled,
      options: options,
      value: value ?? (optional ? _none : null),
      onChanged: (id) => onChanged(id == _none ? null : id),
    );
  }
}

/// "Bank account · ····1234 · ₹12,000" or "Credit card · ····9 · owed ₹4,000".
String accountBalanceSubtitle(AccountBalance b) {
  final amount = b.isLiability
      ? 'owed ${b.balance.format()}'
      : b.balance.format();
  return '${b.account.subtitle} · $amount';
}
