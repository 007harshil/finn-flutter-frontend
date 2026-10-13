import '../../../core/time/clock.dart';
import '../domain/auth_session.dart';

/// On-device stand-in for an email OTP provider. Any well-formed code is
/// accepted except [rejectedCode], which exercises the failure path.
class MockAuthService implements AuthService {
  MockAuthService({required this.clock, this.latency = const Duration(milliseconds: 700)});

  final Clock clock;
  final Duration latency;

  static const rejectedCode = '000000';

  Future<void> _wait() => latency == Duration.zero ? Future<void>.value() : Future<void>.delayed(latency);

  @override
  String? get demoHint => 'Demo mode: no email is sent. Enter any 6 digits except $rejectedCode.';

  @override
  Future<void> sendCode(String email) async {
    await _wait();
    if (!isValidEmail(email)) throw const AuthFailure('Invalid email address.');
  }

  @override
  Future<AuthSession> verifyCode(String email, String code) async {
    await _wait();
    if (!isWellFormedOtp(code)) throw const AuthFailure('Please enter the 6-digit code.');
    if (code == rejectedCode) throw const AuthFailure('The code was invalid or has expired.');
    return AuthSession(email: normaliseEmail(email), signedInAt: clock.now());
  }

  @override
  Future<void> signOut() => _wait();

  @override
  Future<void> sendAccountDeletionCode() => _wait();

  @override
  Future<void> deleteAccount(String code) async {
    await _wait();
    if (!isWellFormedOtp(code)) throw const AuthFailure('Please enter the 6-digit code.');
    if (code == rejectedCode) throw const AuthFailure('The code was invalid or has expired.');
  }
}
