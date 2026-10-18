import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/result/result.dart';
import '../../../core/time/dates.dart';
import '../../../finance/finance_snapshot.dart';
import '../../accounts/domain/money_account.dart';
import '../../goals/domain/goal.dart';

// Shared by goals.* and emergencyFund.*: setting money aside happens ON an
// account and never changes its balance. Mirrors
// finn-backend/server/modules/savings/allocation.ts (see
// docs/SAVINGS_ACCOUNTS.md).

/// The account a contribution sets money aside on.
class SetAsideTarget {
  const SetAsideTarget({required this.account, required this.available});
  final MoneyAccount account;

  /// Balance minus set aside on the account right now.
  final Money available;
}

/// The account a contribution sets money aside on (the default account when
/// [accountId] is omitted), or the failure explaining why it cannot be used.
/// Credit cards hold debt, not money.
({SetAsideTarget? target, AppFailure? failure}) resolveSetAside(
  FinanceSnapshot s,
  String? accountId, {
  String field = 'accountId',
}) {
  AppFailure fail(String message, String fieldText) =>
      AppFailure.validation(message, fields: {field: fieldText});
  final id = accountId ?? s.defaultAccountId;
  final row = s.balance.accounts.where((a) => a.account.id == id).firstOrNull;
  if (row == null) {
    if (s.accounts.isEmpty && accountId == null) {
      return (
        target: null,
        failure: fail('Add an account first.', 'No account available.'),
      );
    }
    return (
      target: null,
      failure: fail(
        'Choose one of your accounts.',
        'This account does not exist.',
      ),
    );
  }
  final account = row.account;
  if (account.isArchived) {
    return (
      target: null,
      failure: fail(
        'That account is archived. Choose another.',
        'This account is archived.',
      ),
    );
  }
  if (account.isLiability) {
    return (
      target: null,
      failure: fail(
        'Choose an account that holds money.',
        'A credit card cannot hold savings.',
      ),
    );
  }
  return (
    target: SetAsideTarget(account: account, available: row.available),
    failure: null,
  );
}

/// Message when an account has too little unreserved money.
String notEnoughOn(MoneyAccount account, Money available) =>
    available.isPositive
    ? 'Only ${available.format()} in ${account.name} is free to set aside.'
    : 'There is no free money in ${account.name} to set aside.';

/// What one bucket holds on each account (null key = old allocations on no
/// account), counting movements dated up to today.
Map<String?, Money> holdingsOf(
  Iterable<SavingsMovement> movements,
  SavingsBucketType type,
  String bucketId,
  DateTime today,
) {
  final held = <String?, int>{};
  final to = today.dateOnly;
  for (final m in movements) {
    if (m.bucketType != type || m.bucketId != bucketId || m.date.isAfter(to)) {
      continue;
    }
    held[m.accountId] = (held[m.accountId] ?? 0) + m.signedAmount.paise;
  }
  return {for (final e in held.entries) e.key: Money.fromPaise(e.value)};
}

class Release {
  const Release(this.accountId, this.amount);
  final String? accountId;
  final Money amount;
}

/// Where a withdrawal comes from. With [accountId] it must come from that
/// account; without, from the accounts holding the most first. [error] is set
/// when the bucket does not hold enough there.
({List<Release> releases, String? error}) planRelease(
  Map<String?, Money> held,
  Money amount,
  String? accountId,
  Map<String, String> names,
) {
  if (accountId != null) {
    final here = held[accountId] ?? Money.zero;
    if (amount > here) {
      final name = names[accountId] ?? 'this account';
      return (
        releases: const <Release>[],
        error: here.isPositive
            ? 'Only ${here.format()} is set aside on $name.'
            : 'Nothing is set aside on $name.',
      );
    }
    return (releases: [Release(accountId, amount)], error: null);
  }
  final order = held.entries.where((e) => e.value.isPositive).toList()
    ..sort((a, b) {
      final c = b.value.compareTo(a.value);
      return c != 0 ? c : '${a.key}'.compareTo('${b.key}');
    });
  final releases = <Release>[];
  var left = amount;
  for (final e in order) {
    if (!left.isPositive) break;
    final take = Money.min(e.value, left);
    releases.add(Release(e.key, take));
    left = left - take;
  }
  if (left.isPositive) {
    return (
      releases: const <Release>[],
      error: 'That is more than is set aside.',
    );
  }
  return (releases: releases, error: null);
}

/// A bucket's account plan: the movements to write and the preview lines.
class AccountPlan {
  const AccountPlan(this.releases, this.lines);
  final List<Release> releases;
  final List<PreviewLineSpec> lines;
}

/// (label, value) of a preview line, kept free of the action layer.
typedef PreviewLineSpec = (String, String);

/// Which account(s) the amount lands on or leaves, with preview lines;
/// problems go into [errors] (and [failure] for a direct account failure).
({AccountPlan plan, AppFailure? failure}) planAccounts({
  required FinanceSnapshot s,
  required bool isContribution,
  required Money amount,
  required String? accountId,
  required Money saved,
  required SavingsBucketType type,
  required String bucketId,
  required String savedMessage,
  required Map<String, String> errors,
}) {
  const empty = AccountPlan([], []);
  if (isContribution) {
    final r = resolveSetAside(s, accountId);
    if (r.failure != null) return (plan: empty, failure: r.failure);
    final here = r.target!;
    if (amount > here.available) {
      errors['amount'] = notEnoughOn(here.account, here.available);
    }
    return (
      plan: AccountPlan(
        [Release(here.account.id, amount)],
        [
          ('Set aside on', here.account.name),
          (
            'Free to spend in ${here.account.name}',
            '${here.available.format()} → ${(here.available - amount).format()}',
          ),
        ],
      ),
      failure: null,
    );
  }
  if (amount > saved) errors['amount'] = savedMessage;
  final names = {
    for (final a in s.balance.accounts) a.account.id: a.account.name,
  };
  if (accountId != null && !names.containsKey(accountId)) {
    errors['accountId'] = 'This account does not exist.';
  }
  final held = holdingsOf(s.savingsMovements, type, bucketId, s.today);
  final out = planRelease(held, amount, accountId, names);
  if (out.error != null) {
    errors.putIfAbsent('amount', () => out.error!);
    return (plan: empty, failure: null);
  }
  return (
    plan: AccountPlan(out.releases, [
      for (final r in out.releases)
        (
          'Released on ${r.accountId == null ? 'no account' : (names[r.accountId] ?? 'account')}',
          r.amount.format(),
        ),
    ]),
    failure: null,
  );
}
