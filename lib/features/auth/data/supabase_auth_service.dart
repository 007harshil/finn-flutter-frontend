import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/time/clock.dart';
import '../../../data/remote/api_client.dart';
import '../domain/auth_session.dart';

/// Passwordless email sign-in with Supabase Auth (email OTP).
class SupabaseAuthService implements AuthService {
  SupabaseAuthService({required this.auth, required this.clock});

  final GoTrueClient auth;
  final Clock clock;

  @override
  String? get demoHint => null;

  @override
  Future<void> sendCode(String email) async {
    if (!isValidEmail(email)) throw const AuthFailure('Invalid email address.');
    try {
      await auth.signInWithOtp(email: normaliseEmail(email), shouldCreateUser: true);
    } on AuthException catch (e) {
      throw AuthFailure(_message(e));
    } catch (e) {
      debugPrint('signInWithOtp failed: $e');
      throw const AuthFailure(_offline);
    }
  }

  @override
  Future<AuthSession> verifyCode(String email, String code) async {
    if (!isWellFormedOtp(code)) throw const AuthFailure('Please enter the 6-digit code.');
    final AuthResponse response;
    try {
      response = await auth.verifyOTP(email: normaliseEmail(email), token: code, type: OtpType.email);
    } on AuthException catch (e) {
      throw AuthFailure(_message(e));
    } catch (e) {
      debugPrint('verifyOTP failed: $e');
      throw const AuthFailure(_offline);
    }
    if (response.session == null) throw const AuthFailure('The code was invalid or has expired.');
    return AuthSession(email: response.user?.email ?? normaliseEmail(email), signedInAt: clock.now());
  }

  @override
  Future<void> signOut() async {
    try {
      await auth.signOut();
    } catch (e) {
      // The local session is cleared regardless; the server token expires.
      debugPrint('Supabase sign-out failed: $e');
    }
  }

  static const _offline = 'Could not reach FiNN. Check your connection and try again.';

  static String _message(AuthException e) {
    if (e is AuthRetryableFetchException) return _offline;
    final code = e.code ?? '';
    if (code == 'otp_expired' || code == 'invalid_credentials' || e.statusCode == '403') {
      return 'The code was invalid or has expired.';
    }
    if (code.contains('rate_limit') || e.statusCode == '429') {
      return 'Too many attempts. Please wait a minute and try again.';
    }
    if (code == 'email_address_invalid') return 'Invalid email address.';
    return e.message.isEmpty ? 'Sign-in failed. Please try again.' : e.message;
  }
}

/// Supplies the Supabase access token to [ApiClient].
class SupabaseApiAuth implements ApiAuth {
  SupabaseApiAuth(this.auth);

  final GoTrueClient auth;

  /// Signs the user out of the app when the session cannot be recovered.
  /// Set by the remote session scope.
  Future<void> Function()? onExpired;

  /// Supabase user id of the signed-in account.
  String? get userId => auth.currentUser?.id;

  String? get email => auth.currentUser?.email;

  @override
  String? get accessToken => auth.currentSession?.accessToken;

  @override
  Future<bool> refresh() async {
    final response = await auth.refreshSession();
    return response.session != null;
  }

  @override
  Future<void> expire() async {
    final handler = onExpired;
    if (handler != null) {
      await handler();
    } else {
      await auth.signOut();
    }
  }
}
