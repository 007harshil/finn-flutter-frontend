import '../../../actions/action.dart';
import '../../../core/time/dates.dart';
import '../../../finance/finance_snapshot.dart';
import '../domain/money_account.dart';

/// Suggested channels (sub-types) offered in forms. Free text is allowed.
const List<String> channelSuggestions = [
  'UPI',
  'IMPS',
  'NEFT',
  'RTGS',
  'Net banking',
  'Cheque',
  'Tap / swipe',
  'ATM',
];

const int maxChannelLength = 30;

/// Trims [v]; empty becomes null.
String? cleanChannel(String? v) {
  final t = v?.trim();
  return t == null || t.isEmpty ? null : t;
}

/// Validation message for a channel, or null.
String? channelError(String? v) =>
    (v?.trim().length ?? 0) > maxChannelLength ? 'Keep the channel under $maxChannelLength characters.' : null;

/// The account id to use: [accountId] when given, else the user's default.
String resolveAccountId(FinanceSnapshot s, String? accountId) => accountId ?? s.defaultAccountId;

/// Why [accountId] cannot take a new write, or null when it can.
///
/// The account must exist and not be archived. When editing a record that
/// already sits on [keepAccountId] (possibly archived) leaving it unchanged
/// is allowed.
String? accountWriteError(FinanceSnapshot s, String accountId, {String? keepAccountId}) {
  final a = s.account(accountId);
  if (a == null) {
    // Without any accounts yet, the implicit Cash account stands in.
    if (s.accounts.isEmpty && accountId == cashAccountId) return null;
    return 'Choose an account.';
  }
  if (a.isArchived && accountId != keepAccountId) return '${a.name} is archived. Choose another account.';
  return null;
}

/// Moves the tracking start of each account in [accountIds] back to [date]
/// when a movement is recorded before it. Mirrors the server.
Future<void> extendAccountOpeningDates(ActionEnvironment env, Iterable<String> accountIds, DateTime date) async {
  final day = date.dateOnly;
  for (final id in accountIds.toSet()) {
    final account = await env.repos.moneyAccounts.getById(id);
    if (account == null || !day.isBefore(account.openingDate.dateOnly)) continue;
    await env.repos.moneyAccounts.save(account.copyWith(openingDate: day, updatedAt: env.clock.now()));
  }
}
