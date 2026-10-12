import '../../../actions/action.dart';
import '../../../core/time/dates.dart';

/// Moves the profile's tracking start back to [date] when a transaction is
/// recorded before it, so the entry counts towards cash (the ledger skips
/// anything dated before the opening date). The opening balance is kept.
/// No-op without a profile or when [date] is not earlier.
///
/// Mirrors the server's `extendTrackingStart`; call it after every
/// transaction write (local mode only — remote actions run on the server).
Future<void> extendTrackingStart(ActionEnvironment env, DateTime date) async {
  final profile = env.repos.profile.current;
  final day = date.dateOnly;
  if (profile == null || !day.isBefore(profile.openingDate.dateOnly)) return;
  await env.repos.profile.set(profile.copyWith(openingDate: day));
}
