import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/core_providers.dart';
import '../../export/application/export_file_sink.dart';
import '../data/mock_auth_service.dart';
import '../domain/auth_session.dart';

/// The sign-in provider. Override to connect a real backend.
final authServiceProvider = Provider<AuthService>((ref) => MockAuthService(clock: ref.watch(clockProvider)));

/// The signed-in account, or null when signed out. Persisted in
/// SharedPreferences so the session survives restarts.
final authControllerProvider = NotifierProvider<AuthController, AuthSession?>(AuthController.new);

class AuthController extends Notifier<AuthSession?> {
  static const storageKey = 'finn.auth.v1';

  AuthService get _service => ref.read(authServiceProvider);

  @override
  AuthSession? build() {
    final raw = ref.watch(sharedPreferencesProvider).getString(storageKey);
    if (raw == null) return null;
    try {
      return AuthSession.fromJson(Map<String, Object?>.from(jsonDecode(raw) as Map));
    } catch (_) {
      return null;
    }
  }

  /// Emails a sign-in code. Throws [AuthFailure] on a provider error.
  Future<void> requestCode(String email) => _service.sendCode(normaliseEmail(email));

  /// Checks [code] without signing in, so the UI can confirm success before
  /// the router moves on. Pass the result to [signIn].
  Future<AuthSession> verifyCode(String email, String code) => _service.verifyCode(normaliseEmail(email), code);

  Future<void> signIn(AuthSession session) async {
    state = session;
    await ref.read(sharedPreferencesProvider).setString(storageKey, jsonEncode(session.toJson()));
  }

  /// Signs out locally even if the provider call fails. Records stay on
  /// this device; exported files do not.
  Future<void> signOut() async {
    try {
      await _service.signOut();
    } finally {
      state = null;
      await ref.read(sharedPreferencesProvider).remove(storageKey);
      unawaited(ShareExportFileSink.purge());
    }
  }
}
