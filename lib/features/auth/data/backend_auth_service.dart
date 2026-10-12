import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/time/clock.dart';
import '../../../data/remote/api_client.dart';
import '../../../data/remote/api_config.dart';
import '../domain/auth_session.dart';

/// The FiNN API session: a short-lived bearer token plus a rotating refresh
/// token, and the account it belongs to.
@immutable
class BackendSession {
  const BackendSession({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    required this.userId,
    required this.email,
  });

  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;
  final String userId;
  final String email;

  /// Parses the API's `Session` payload. [now] backs up a missing
  /// `expiresAt` with `expiresIn`.
  factory BackendSession.fromApi(Object? data, {required DateTime now}) {
    if (data is! Map) throw const FormatException('Session payload is not an object');
    final user = data['user'];
    final access = data['accessToken'];
    final refresh = data['refreshToken'];
    if (access is! String || access.isEmpty || refresh is! String || refresh.isEmpty || user is! Map) {
      throw const FormatException('Session payload is incomplete');
    }
    final id = user['id'];
    if (id is! String || id.isEmpty) throw const FormatException('Session has no user id');
    final rawExpiry = data['expiresAt'];
    final parsed = rawExpiry is String ? DateTime.tryParse(rawExpiry) : null;
    final expiresIn = data['expiresIn'];
    final expiresAt = parsed ?? now.add(Duration(seconds: expiresIn is num ? expiresIn.toInt() : 900));
    return BackendSession(
      accessToken: access,
      refreshToken: refresh,
      expiresAt: expiresAt,
      userId: id,
      email: user['email'] is String ? user['email'] as String : '',
    );
  }

  Map<String, Object?> toJson() => {
    'accessToken': accessToken,
    'refreshToken': refreshToken,
    'expiresAt': expiresAt.toUtc().toIso8601String(),
    'userId': userId,
    'email': email,
  };

  factory BackendSession.fromJson(Map<String, Object?> j) => BackendSession(
    accessToken: j['accessToken']! as String,
    refreshToken: j['refreshToken']! as String,
    expiresAt: DateTime.parse(j['expiresAt']! as String),
    userId: j['userId']! as String,
    email: (j['email'] as String?) ?? '',
  );
}

/// An error response from one of the public `/auth/*` endpoints.
class BackendAuthException implements Exception {
  const BackendAuthException(this.status, this.code, this.message, {this.retryAfterSeconds});

  final int status;

  /// The envelope's `error.code`, or null when the body had no envelope.
  final String? code;
  final String message;
  final int? retryAfterSeconds;

  bool get isUnauthenticated => code == 'unauthenticated' || (code == null && status == 401);

  @override
  String toString() => 'BackendAuthException($status, $code): $message';
}

/// Holds the FiNN API session, persists it in SharedPreferences and
/// supplies its access token to [ApiClient].
///
/// Refresh tokens rotate: every refresh stores the new one, and refreshes
/// are serialised (one in flight at a time) because presenting an already
/// used refresh token revokes the whole session.
class BackendApiAuth implements ProactiveApiAuth {
  BackendApiAuth({
    required this.config,
    required this.prefs,
    http.Client? httpClient,
    this.clock = const SystemClock(),
    this.refreshMargin = const Duration(seconds: 60),
  }) : _http = httpClient ?? http.Client() {
    _session = _load();
  }

  /// SharedPreferences key of the stored session.
  static const storageKey = 'finn.auth.session.v1';

  final ApiConfig config;
  final SharedPreferences prefs;
  final Clock clock;

  /// How long before expiry the access token is renewed ahead of a request.
  final Duration refreshMargin;
  final http.Client _http;

  BackendSession? _session;
  Future<bool>? _refreshing;

  /// Signs the user out of the app when the session cannot be recovered.
  /// Set by the remote session scope.
  Future<void> Function()? onExpired;

  BackendSession? get session => _session;

  /// FiNN user id of the signed-in account.
  String? get userId => _session?.userId;

  String? get email => _session?.email;

  @override
  String? get accessToken => _session?.accessToken;

  BackendSession? _load() {
    final raw = prefs.getString(storageKey);
    if (raw == null) return null;
    try {
      return BackendSession.fromJson(Map<String, Object?>.from(jsonDecode(raw) as Map));
    } catch (e) {
      debugPrint('Discarding unreadable auth session: $e');
      unawaited(prefs.remove(storageKey));
      return null;
    }
  }

  /// Adopts [session] and persists it.
  Future<void> save(BackendSession session) async {
    _session = session;
    await prefs.setString(storageKey, jsonEncode(session.toJson()));
  }

  /// Forgets the session on this device.
  Future<void> clear() async {
    _session = null;
    await prefs.remove(storageKey);
  }

  /// POSTs [body] to a public `/auth` endpoint (no Authorization header)
  /// and returns the `data` payload. Throws [BackendAuthException] for an
  /// error response; network errors and timeouts propagate as-is.
  Future<Object?> postPublic(String path, Map<String, Object?> body) async {
    final response = await _http
        .post(
          Uri.parse('${config.baseUrl}$path'),
          headers: const {'accept': 'application/json', 'content-type': 'application/json; charset=utf-8'},
          body: jsonEncode(body),
        )
        .timeout(config.timeout);
    Object? decoded;
    if (response.bodyBytes.isNotEmpty) {
      try {
        decoded = jsonDecode(utf8.decode(response.bodyBytes));
      } catch (_) {
        decoded = null;
      }
    }
    final status = response.statusCode;
    if (status >= 200 && status < 300) {
      return decoded is Map && decoded.containsKey('data') ? decoded['data'] : decoded;
    }
    final error = decoded is Map ? decoded['error'] : null;
    if (error is Map) {
      final details = error['details'];
      final retryAfter = details is Map ? details['retryAfterSeconds'] : null;
      throw BackendAuthException(
        status,
        error['code'] is String ? error['code'] as String : null,
        error['message'] is String ? error['message'] as String : '',
        retryAfterSeconds: retryAfter is num ? retryAfter.toInt() : null,
      );
    }
    throw BackendAuthException(status, null, '');
  }

  @override
  Future<bool> refresh() => _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);

  Future<bool> _doRefresh() async {
    final current = _session;
    if (current == null) return false;
    final Object? data;
    try {
      data = await postPublic('/auth/refresh', {'refreshToken': current.refreshToken});
    } on BackendAuthException catch (e) {
      if (e.isUnauthenticated) {
        // Invalid, expired or revoked: the session is gone for good.
        if (identical(_session, current)) await clear();
        return false;
      }
      rethrow;
    }
    // Signed out (or signed in again) while the refresh was in flight.
    if (!identical(_session, current)) return _session != null;
    await save(BackendSession.fromApi(data, now: clock.now()));
    return true;
  }

  /// Renews the access token when it expires within [refreshMargin]. Never
  /// throws: on failure the current token is sent and the API's
  /// `unauthenticated` response drives the usual refresh-or-sign-out path.
  @override
  Future<void> ensureFresh() async {
    final current = _session;
    if (current == null) return;
    if (current.expiresAt.difference(clock.now()) > refreshMargin) return;
    try {
      await refresh();
    } catch (e) {
      debugPrint('Proactive session refresh failed: $e');
    }
  }

  @override
  Future<void> expire() async {
    final handler = onExpired;
    if (handler != null) {
      await handler();
    } else {
      await clear();
    }
  }
}

/// Passwordless email sign-in with the FiNN API's email OTP
/// (`/auth/otp`, `/auth/verify`, `/auth/logout`).
class BackendAuthService implements AuthService {
  BackendAuthService({required this.auth, required this.clock});

  final BackendApiAuth auth;
  final Clock clock;

  @override
  String? get demoHint => null;

  @override
  Future<void> sendCode(String email) async {
    if (!isValidEmail(email)) throw const AuthFailure('Invalid email address.');
    try {
      await auth.postPublic('/auth/otp', {'email': normaliseEmail(email)});
    } on BackendAuthException catch (e) {
      throw AuthFailure(_message(e, invalidInput: 'Invalid email address.'));
    } catch (e) {
      debugPrint('Sending the sign-in code failed: $e');
      throw const AuthFailure(_offline);
    }
  }

  @override
  Future<AuthSession> verifyCode(String email, String code) async {
    if (!isWellFormedOtp(code)) throw const AuthFailure('Please enter the 6-digit code.');
    final BackendSession session;
    try {
      final data = await auth.postPublic('/auth/verify', {'email': normaliseEmail(email), 'code': code});
      session = BackendSession.fromApi(data, now: clock.now());
    } on BackendAuthException catch (e) {
      throw AuthFailure(_message(e, invalidInput: _invalidCode));
    } on FormatException catch (e) {
      debugPrint('Unexpected session payload: $e');
      throw const AuthFailure(_invalidCode);
    } catch (e) {
      debugPrint('Verifying the sign-in code failed: $e');
      throw const AuthFailure(_offline);
    }
    await auth.save(session);
    return AuthSession(email: session.email.isEmpty ? normaliseEmail(email) : session.email, signedInAt: clock.now());
  }

  @override
  Future<void> signOut() async {
    final session = auth.session;
    try {
      if (session != null) await auth.postPublic('/auth/logout', {'refreshToken': session.refreshToken});
    } catch (e) {
      // The local session is cleared regardless; the server token expires.
      debugPrint('FiNN sign-out failed: $e');
    } finally {
      await auth.clear();
    }
  }

  static const _offline = 'Could not reach FiNN. Check your connection and try again.';
  static const _invalidCode = 'The code was invalid or has expired.';
  static const _rateLimited = 'Too many attempts. Please wait a minute and try again.';

  static String _message(BackendAuthException e, {required String invalidInput}) {
    if (e.isUnauthenticated || e.status == 403) return _invalidCode;
    if (e.status == 429 || (e.code == 'unavailable' && e.retryAfterSeconds != null)) {
      return e.message.isEmpty ? _rateLimited : e.message;
    }
    if (e.code == 'validation' || (e.code == null && (e.status == 400 || e.status == 422))) {
      return invalidInput;
    }
    if (e.code == null && e.status >= 500) return _offline;
    if (e.code == 'unavailable' && e.message.isEmpty) return _offline;
    return e.message.isEmpty ? 'Sign-in failed. Please try again.' : e.message;
  }
}
