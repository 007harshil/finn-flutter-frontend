import '../../../actions/action.dart';
import '../../../core/time/dates.dart';
import '../../accounts/application/account_support.dart';

/// Moves the tracking start back to [date] when a movement is recorded
/// before it, so the entry counts towards cash (the ledger skips anything
/// dated before an account's opening date). Each account in [accountIds]
/// gets its own `openingDate` moved back, and so does the profile's
/// tracking start. Opening balances are kept. No-op for accounts/profile
/// whose date is not later than [date].
///
/// Mirrors the server's `extendTrackingStart`; call it after every
/// transaction or transfer write (local mode only — remote actions run on
/// the server).
Future<void> extendTrackingStart(
  ActionEnvironment env,
  DateTime date, {
  Iterable<String> accountIds = const [],
}) async {
  final day = date.dateOnly;
  await extendAccountOpeningDates(env, accountIds, day);
  final profile = env.repos.profile.current;
  if (profile == null || !day.isBefore(profile.openingDate.dateOnly)) return;
  await env.repos.profile.set(profile.copyWith(openingDate: day));
}
