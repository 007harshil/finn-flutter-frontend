import 'package:flutter/foundation.dart';

/// Number of digits in an email sign-in code.
const otpLength = 6;

final _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');

/// [raw] trimmed and lower-cased, the form every email is stored in.
String normaliseEmail(String raw) => raw.trim().toLowerCase();

bool isValidEmail(String raw) {
  final email = normaliseEmail(raw);
  return email.length <= 254 && _emailPattern.hasMatch(email);
}

/// Whether [code] is exactly [otpLength] digits.
bool isWellFormedOtp(String code) => code.length == otpLength && RegExp(r'^\d+$').hasMatch(code);

/// The signed-in account. Holds identity only, never financial data.
@immutable
class AuthSession {
  const AuthSession({required this.email, required this.signedInAt});

  final String email;
  final DateTime signedInAt;

  Map<String, Object?> toJson() => {
        'email': email,
        'signedInAt': signedInAt.toIso8601String(),
      };

  factory AuthSession.fromJson(Map<String, Object?> j) => AuthSession(
        email: j['email']! as String,
        signedInAt: DateTime.parse(j['signedInAt']! as String),
      );

  @override
  bool operator ==(Object other) => other is AuthSession && other.email == email && other.signedInAt == signedInAt;

  @override
  int get hashCode => Object.hash(email, signedInAt);
}

/// A sign-in step the auth provider refused. [message] is shown to the user
/// as-is.
class AuthFailure implements Exception {
  const AuthFailure(this.message);
  final String message;

  @override
  String toString() => 'AuthFailure: $message';
}

/// Passwordless email sign-in. Replace [MockAuthService] with a real
/// provider (e.g. Supabase email OTP); nothing else needs to change.
abstract interface class AuthService {
  /// Emails a one-time code to [email]. Signs up unknown addresses.
  Future<void> sendCode(String email);

  /// Exchanges [code] for a session. Throws [AuthFailure] if it is wrong
  /// or expired. Does not sign in on its own; see `AuthController.signIn`.
  Future<AuthSession> verifyCode(String email, String code);

  /// Ends the session on the server.
  Future<void> signOut();

  /// Guidance shown on the code screen in demo builds; null for a real
  /// backend.
  String? get demoHint;
}
