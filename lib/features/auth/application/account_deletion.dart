import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../settings/application/data_reset.dart';
import '../domain/auth_session.dart';
import 'auth_controller.dart';

/// Permanent account deletion, confirmed with an emailed code. The server
/// erases the account and all of its data; then this device signs out and
/// forgets everything it kept, returning to sign-in and first-run setup.
class AccountDeletion {
  AccountDeletion(this._ref);
  final Ref _ref;

  /// Emails the confirmation code. Throws [AuthFailure].
  Future<void> sendCode() => _ref.read(authServiceProvider).sendAccountDeletionCode();

  /// Deletes the account with [code]. Throws [AuthFailure] (nothing is
  /// deleted then). [onDeleted] runs once the server has deleted the
  /// account, before signing out redirects to the login screen (close
  /// sheets and show feedback there).
  Future<void> confirm(String code, {void Function()? onDeleted}) async {
    await _ref.read(authServiceProvider).deleteAccount(code.trim());
    onDeleted?.call();
    // Signed-out state first, so the sync engine closes before the
    // settings reset (no preference push for a deleted account).
    try {
      await _ref.read(authControllerProvider.notifier).signOut();
    } catch (_) {
      // Signed out locally regardless; the server sessions are already gone.
    }
    await _ref.read(dataResetServiceProvider).wipeDevice();
  }
}

final accountDeletionProvider = Provider<AccountDeletion>((ref) => AccountDeletion(ref));
