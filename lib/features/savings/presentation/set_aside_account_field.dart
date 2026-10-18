import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/data_providers.dart';
import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../kit/kit.dart';
import '../../accounts/domain/money_account.dart';
import '../../accounts/presentation/widgets/account_picker_field.dart';

/// Accounts a contribution can be set aside on (credit cards cannot hold
/// savings), in display order.
List<AccountBalance> setAsideCandidates(Iterable<AccountBalance> balances) => [
  for (final b in balances)
    if (!b.account.isArchived && !b.isLiability) b,
];

/// The account preselected when adding: the default account, else the first
/// that can hold savings.
String? defaultSetAsideAccount(
  Iterable<AccountBalance> balances,
  String? defaultAccountId,
) {
  final list = setAsideCandidates(balances);
  if (list.any((b) => b.account.id == defaultAccountId)) {
    return defaultAccountId;
  }
  return list.firstOrNull?.account.id;
}

/// The account holding the most of a bucket (preselected when releasing).
String? largestHolding(Map<String?, Money> held) {
  String? best;
  var most = Money.zero;
  for (final e in held.entries) {
    if (e.key != null && e.value > most) {
      best = e.key;
      most = e.value;
    }
  }
  return best;
}

/// Picks the account savings are set aside on ("Free to spend ₹X" per row)
/// or, with [held], released from ("Where it is held", amount held per row).
class SetAsideAccountField extends ConsumerWidget {
  const SetAsideAccountField({
    super.key,
    required this.value,
    required this.onChanged,
    this.held,
    this.errorText,
    this.enabled = true,
  });

  final String? value;
  final ValueChanged<String?> onChanged;

  /// What the bucket holds per account; set when releasing.
  final Map<String?, Money>? held;
  final String? errorText;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balances = ref.watch(accountBalancesProvider).value;
    final releasing = held != null;
    final label = releasing ? 'Where it is held' : 'Set aside on';
    if (balances == null) {
      return LedgerField(
        label: label,
        errorText: errorText,
        child: const LedgerSkeleton(height: 52),
      );
    }
    final rows = releasing
        ? [
            for (final b in balances)
              if ((held![b.account.id] ?? Money.zero).isPositive) b,
          ]
        : setAsideCandidates(balances);
    return LedgerPickerField<String>(
      label: label,
      pickerTitle: label,
      hint: 'Choose an account',
      errorText: errorText,
      enabled: enabled && rows.isNotEmpty,
      value: rows.any((b) => b.account.id == value) ? value : null,
      options: [
        for (final b in rows)
          LedgerOption(
            b.account.id,
            b.account.name,
            key: ValueKey('setaside-${b.account.id}'),
            icon: accountKindIcon(b.account.kind),
            subtitle: releasing
                ? 'Set aside ${held![b.account.id]!.format()}'
                : (b.available.isPositive
                      ? 'Free to spend ${b.available.format()}'
                      : 'Nothing free to set aside'),
          ),
      ],
      onChanged: onChanged,
    );
  }
}
