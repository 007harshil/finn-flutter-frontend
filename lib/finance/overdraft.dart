import '../core/money/money.dart';
import '../core/money/money_format.dart';
import '../core/time/dates.dart';
import '../core/result/result.dart';
import '../features/accounts/domain/money_account.dart';
import '../features/accounts/domain/transfer.dart';
import '../features/settings/domain/financial_profile.dart';
import '../features/transactions/domain/transaction.dart';
import 'finance_snapshot.dart';

/// Rule: a cash, bank or debit account never goes below zero.
///
/// Recomputes every account balance as it would be after a change (the new
/// list of transactions, transfers or accounts) and refuses the change when
/// it pushes an asset account below zero. An account that is already below
/// zero (old data) may still receive money or unrelated edits, but can never
/// drop further. Credit cards hold an amount owed and are not checked.
///
/// Returns null when the change is allowed.
AppFailure? overdraftFailure(
  FinanceSnapshot s, {
  List<Transaction>? transactions,
  List<Transfer>? transfers,
  List<MoneyAccount>? accounts,
  FinancialProfile? profile,
  Map<String, DateTime> movedOn = const {},
  String field = 'amount',
  bool canSplit = false,
}) {
  // A movement dated before an account's tracking start moves that start
  // back (extendTrackingStart), so it counts. Mirror that here.
  var accountList = accounts ?? s.accounts;
  profile ??= s.profile;
  if (movedOn.isNotEmpty) {
    accountList = [
      for (final a in accountList)
        if (movedOn[a.id] case final d? when d.dateOnly.isBefore(a.openingDate.dateOnly))
          a.copyWith(openingDate: d.dateOnly)
        else
          a,
    ];
    final earliest = movedOn.values.reduce((a, b) => a.isBefore(b) ? a : b).dateOnly;
    if (profile != null && earliest.isBefore(profile.openingDate.dateOnly)) {
      profile = profile.copyWith(openingDate: earliest);
    }
  }
  final after = FinanceSnapshot.ledgerCalc.balance(
    profile: profile,
    accounts: accountList,
    transfers: transfers ?? s.transfers,
    transactions: transactions ?? s.transactions,
    movements: s.savingsMovements,
    asOf: s.today,
  );
  final before = {for (final b in s.balance.accounts) b.account.id: b.balance};
  var spare = Money.zero;
  AccountBalance? short;
  Money shortBy = Money.zero;
  for (final b in after.accounts) {
    if (b.isLiability) continue;
    final was = before[b.account.id] ?? Money.zero;
    if (b.balance.isNegative && b.balance < was) {
      if (short == null) {
        short = b;
        shortBy = was - b.balance;
      }
    } else if (b.balance.isPositive && !b.account.isArchived) {
      spare += b.balance;
    }
  }
  if (short == null) return null;
  final has = before[short.account.id] ?? Money.zero;
  final hint = canSplit && spare >= -short.balance ? ' Split the payment across accounts.' : '';
  final message = has.isPositive
      ? 'Not enough money in ${short.account.name}. It has ${has.format()}, this needs ${shortBy.format()}.$hint'
      : 'Not enough money in ${short.account.name}. It has ${has.format()}.$hint';
  return AppFailure(FailureCode.insufficientFunds, message, fieldErrors: {field: message});
}

/// [overdraftFailure] for adding [add] and removing the transactions with
/// ids in [remove].
AppFailure? transactionOverdraft(
  FinanceSnapshot s, {
  Iterable<Transaction> add = const [],
  Set<String> remove = const {},
  String field = 'amount',
  bool canSplit = false,
}) =>
    overdraftFailure(
      s,
      transactions: [
        for (final t in s.transactions)
          if (!remove.contains(t.id)) t,
        ...add,
      ],
      movedOn: _earliestPerAccount([
        for (final t in add)
          for (final l in t.legs) (l.accountId, t.date),
      ]),
      field: field,
      canSplit: canSplit,
    );

Map<String, DateTime> _earliestPerAccount(Iterable<(String, DateTime)> moves) {
  final out = <String, DateTime>{};
  for (final (id, d) in moves) {
    final cur = out[id];
    if (cur == null || d.isBefore(cur)) out[id] = d;
  }
  return out;
}

/// [overdraftFailure] for adding [add] and removing the transfers with ids
/// in [remove].
AppFailure? transferOverdraft(
  FinanceSnapshot s, {
  Iterable<Transfer> add = const [],
  Set<String> remove = const {},
  String field = 'amount',
}) =>
    overdraftFailure(
      s,
      transfers: [
        for (final t in s.transfers)
          if (!remove.contains(t.id)) t,
        ...add,
      ],
      movedOn: _earliestPerAccount([
        for (final t in add) ...[(t.fromAccountId, t.date), (t.toAccountId, t.date)],
      ]),
      field: field,
    );

/// A throwaway transaction used only to test balances before writing.
Transaction draftTransaction({
  required TransactionType type,
  required Money amount,
  required DateTime date,
  required String accountId,
  List<AccountLeg> splits = const [],
}) =>
    Transaction(
      id: '_draft',
      type: type,
      amount: amount,
      categoryId: '_draft',
      date: date,
      accountId: splits.length > 1 ? splits.first.accountId : accountId,
      splits: splits.length > 1 ? splits : const [],
      createdAt: date,
      updatedAt: date,
    );
