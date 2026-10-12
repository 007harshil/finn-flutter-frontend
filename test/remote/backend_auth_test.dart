import 'dart:async';
import 'dart:convert';

import 'package:finn/core/time/clock.dart';
import 'package:finn/data/remote/api_client.dart';
import 'package:finn/features/auth/data/backend_auth_service.dart';
import 'package:finn/features/auth/domain/auth_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'remote_fakes.dart';

final _now = DateTime.utc(2026, 10, 12, 9);

Map<String, Object?> sessionJson(String n, {Duration expiresIn = const Duration(minutes: 15)}) => {
  'accessToken': 'access-$n',
  'refreshToken': 'refresh-$n',
  'tokenType': 'Bearer',
  'expiresIn': expiresIn.inSeconds,
  'expiresAt': _now.add(expiresIn).toIso8601String(),
  'user': {'id': '9b2f1c3e-0000-4000-8000-000000000001', 'email': 'asha@example.com'},
};

http.Response unavailable(String message, {int? retryAfter}) => http.Response(
  jsonEncode({
    'error': {
      'code': 'unavailable',
      'message': message,
      'retryable': true,
      if (retryAfter != null) 'details': {'retryAfterSeconds': retryAfter},
    },
  }),
  503,
  headers: {'content-type': 'application/json'},
);

class AuthHarness {
  AuthHarness(this.prefs, this.handler) {
    auth = BackendApiAuth(config: testConfig, prefs: prefs, httpClient: MockClient(_handle), clock: clock);
    service = BackendAuthService(auth: auth, clock: clock);
  }

  final SharedPreferences prefs;
  Future<http.Response> Function(http.Request req) handler;
  final clock = FixedClock(DateTime.utc(2026, 10, 12, 9));
  final requests = <http.Request>[];
  late final BackendApiAuth auth;
  late final BackendAuthService service;

  Future<http.Response> _handle(http.Request req) {
    requests.add(req);
    return handler(req);
  }

  List<String> get paths => [for (final r in requests) r.url.path];
  Map<String, Object?> bodyOf(int i) => Map<String, Object?>.from(jsonDecode(requests[i].body) as Map);
}

Future<AuthHarness> harness(
  Future<http.Response> Function(http.Request req) handler, {
  Map<String, Object> stored = const {},
}) async {
  SharedPreferences.setMockInitialValues(stored);
  return AuthHarness(await SharedPreferences.getInstance(), handler);
}

Future<String> failureMessage(Future<Object?> call) async {
  try {
    await call;
  } on AuthFailure catch (f) {
    return f.message;
  }
  fail('Expected an AuthFailure');
}

Map<String, Object> storedSession(String n, {Duration expiresIn = const Duration(minutes: 15)}) => {
  BackendApiAuth.storageKey: jsonEncode(
    BackendSession.fromApi(sessionJson(n, expiresIn: expiresIn), now: _now).toJson(),
  ),
};

void main() {
  group('sendCode', () {
    test('posts the normalised email without an Authorization header', () async {
      final h = await harness((_) async => ok({'sent': true, 'expiresInSeconds': 600, 'resendAfterSeconds': 60}));
      await h.service.sendCode('  Asha@Example.com ');
      expect(h.requests.single.method, 'POST');
      expect(h.requests.single.url.toString(), 'https://api.test/api/v1/auth/otp');
      expect(h.requests.single.headers.containsKey('authorization'), isFalse);
      expect(h.bodyOf(0), {'email': 'asha@example.com'});
    });

    test('rejects a malformed email before calling the API', () async {
      final h = await harness((_) async => ok({}));
      expect(await failureMessage(h.service.sendCode('not-an-email')), 'Invalid email address.');
      expect(h.requests, isEmpty);
    });

    test('maps validation, rate limits, mail failures and network errors', () async {
      final h = await harness((_) async => errorResponse(422, 'validation', 'Enter a valid email.'));
      expect(await failureMessage(h.service.sendCode('a@b.co')), 'Invalid email address.');

      h.handler = (_) async => unavailable('Too many attempts. Try again in 5 minutes.', retryAfter: 300);
      expect(await failureMessage(h.service.sendCode('a@b.co')), 'Too many attempts. Try again in 5 minutes.');

      h.handler = (_) async => unavailable('', retryAfter: 60);
      expect(
        await failureMessage(h.service.sendCode('a@b.co')),
        'Too many attempts. Please wait a minute and try again.',
      );

      h.handler = (_) async => http.Response('', 429);
      expect(
        await failureMessage(h.service.sendCode('a@b.co')),
        'Too many attempts. Please wait a minute and try again.',
      );

      h.handler = (_) async => unavailable('We could not send the code. Please try again.');
      expect(await failureMessage(h.service.sendCode('a@b.co')), 'We could not send the code. Please try again.');

      h.handler = (_) async => http.Response('<html>Bad gateway</html>', 502);
      expect(
        await failureMessage(h.service.sendCode('a@b.co')),
        'Could not reach FiNN. Check your connection and try again.',
      );

      h.handler = (_) async => throw http.ClientException('Failed host lookup');
      expect(
        await failureMessage(h.service.sendCode('a@b.co')),
        'Could not reach FiNN. Check your connection and try again.',
      );
    });
  });

  group('verifyCode', () {
    test('stores the session and returns the account', () async {
      final h = await harness((_) async => ok(sessionJson('1')));
      final session = await h.service.verifyCode('Asha@example.com', '123456');

      expect(h.requests.single.url.path, '/api/v1/auth/verify');
      expect(h.requests.single.headers.containsKey('authorization'), isFalse);
      expect(h.bodyOf(0), {'email': 'asha@example.com', 'code': '123456'});
      expect(session.email, 'asha@example.com');
      expect(session.signedInAt, h.clock.now());
      expect(h.auth.accessToken, 'access-1');
      expect(h.auth.userId, '9b2f1c3e-0000-4000-8000-000000000001');

      // Survives a restart.
      final restored = BackendApiAuth(
        config: testConfig,
        prefs: h.prefs,
        httpClient: MockClient((_) async => ok(null)),
      );
      expect(restored.accessToken, 'access-1');
      expect(restored.session!.refreshToken, 'refresh-1');
      expect(restored.session!.expiresAt, _now.add(const Duration(minutes: 15)));
      expect(restored.email, 'asha@example.com');
    });

    test('rejects a malformed code before calling the API', () async {
      final h = await harness((_) async => ok(sessionJson('1')));
      expect(await failureMessage(h.service.verifyCode('a@b.co', '12a')), 'Please enter the 6-digit code.');
      expect(h.requests, isEmpty);
    });

    test('maps a wrong or expired code, rate limits and network errors', () async {
      final h = await harness(
        (_) async => errorResponse(401, 'unauthenticated', 'The code was invalid or has expired.'),
      );
      expect(await failureMessage(h.service.verifyCode('a@b.co', '123456')), 'The code was invalid or has expired.');
      expect(h.auth.session, isNull);

      h.handler = (_) async => unavailable('Too many attempts. Try again later.', retryAfter: 120);
      expect(await failureMessage(h.service.verifyCode('a@b.co', '123456')), 'Too many attempts. Try again later.');

      h.handler = (_) async => throw http.ClientException('offline');
      expect(
        await failureMessage(h.service.verifyCode('a@b.co', '123456')),
        'Could not reach FiNN. Check your connection and try again.',
      );
      expect(h.auth.session, isNull);
    });
  });

  group('refresh', () {
    test('rotates the refresh token and persists the new session', () async {
      final h = await harness((_) async => ok(sessionJson('2')), stored: storedSession('1'));
      expect(h.auth.accessToken, 'access-1');

      expect(await h.auth.refresh(), isTrue);
      expect(h.requests.single.url.path, '/api/v1/auth/refresh');
      expect(h.bodyOf(0), {'refreshToken': 'refresh-1'});
      expect(h.auth.accessToken, 'access-2');

      h.handler = (_) async => ok(sessionJson('3'));
      expect(await h.auth.refresh(), isTrue);
      expect(h.bodyOf(1), {'refreshToken': 'refresh-2'}, reason: 'the rotated token is used next');

      final stored = jsonDecode(h.prefs.getString(BackendApiAuth.storageKey)!) as Map;
      expect(stored['refreshToken'], 'refresh-3');
      expect(stored['accessToken'], 'access-3');
    });

    test('returns false and forgets the session on unauthenticated', () async {
      final h = await harness(
        (_) async => errorResponse(401, 'unauthenticated', 'Session revoked.'),
        stored: storedSession('1'),
      );
      expect(await h.auth.refresh(), isFalse);
      expect(h.auth.session, isNull);
      expect(h.prefs.getString(BackendApiAuth.storageKey), isNull);
    });

    test('returns false without a call when signed out', () async {
      final h = await harness((_) async => ok(sessionJson('2')));
      expect(await h.auth.refresh(), isFalse);
      expect(h.requests, isEmpty);
    });

    test('concurrent refreshes share one request', () async {
      final gate = Completer<http.Response>();
      final h = await harness((_) => gate.future, stored: storedSession('1'));
      final results = [h.auth.refresh(), h.auth.refresh(), h.auth.refresh()];
      await Future<void>.delayed(Duration.zero);
      gate.complete(ok(sessionJson('2')));
      expect(await Future.wait(results), [true, true, true]);
      expect(h.requests, hasLength(1));
      expect(h.auth.accessToken, 'access-2');

      // A later refresh starts a new request with the rotated token.
      h.handler = (_) async => ok(sessionJson('3'));
      expect(await h.auth.refresh(), isTrue);
      expect(h.requests, hasLength(2));
      expect(h.bodyOf(1), {'refreshToken': 'refresh-2'});
    });

    test('a refresh finishing after sign-out does not restore the session', () async {
      final gate = Completer<http.Response>();
      final h = await harness(
        (req) => req.url.path.endsWith('/refresh') ? gate.future : Future.value(ok({'signedOut': true})),
        stored: storedSession('1'),
      );
      final pending = h.auth.refresh();
      await Future<void>.delayed(Duration.zero);
      await h.service.signOut();
      gate.complete(ok(sessionJson('2')));
      expect(await pending, isFalse);
      expect(h.auth.session, isNull);
      expect(h.prefs.getString(BackendApiAuth.storageKey), isNull);
    });

    test('ApiClient renews a token about to expire before sending the request', () async {
      final h = await harness(
        (req) async => ok(sessionJson('2')),
        stored: storedSession('1', expiresIn: const Duration(seconds: 30)),
      );
      final seen = <String?>[];
      final api = ApiClient(
        config: testConfig,
        auth: h.auth,
        httpClient: MockClient((req) async {
          seen.add(req.headers['authorization']);
          return ok({'fine': true});
        }),
      );
      expect(await api.get('/sync'), {'fine': true});
      expect(h.paths, ['/api/v1/auth/refresh']);
      expect(seen, ['Bearer access-2']);

      // Fresh token: no further refresh.
      await api.get('/sync');
      expect(h.requests, hasLength(1));
      expect(seen.last, 'Bearer access-2');
    });

    test('a failed proactive refresh still sends the current token', () async {
      final h = await harness(
        (_) async => throw http.ClientException('offline'),
        stored: storedSession('1', expiresIn: const Duration(seconds: 30)),
      );
      final seen = <String?>[];
      final api = ApiClient(
        config: testConfig,
        auth: h.auth,
        httpClient: MockClient((req) async {
          seen.add(req.headers['authorization']);
          return ok(null);
        }),
      );
      await api.get('/sync');
      expect(seen, ['Bearer access-1']);
      expect(h.auth.accessToken, 'access-1');
    });
  });

  group('signOut and expiry', () {
    test('signOut calls logout with the refresh token and clears the session', () async {
      final h = await harness((_) async => ok({'signedOut': true}), stored: storedSession('1'));
      await h.service.signOut();
      expect(h.requests.single.url.path, '/api/v1/auth/logout');
      expect(h.bodyOf(0), {'refreshToken': 'refresh-1'});
      expect(h.auth.session, isNull);
      expect(h.prefs.getString(BackendApiAuth.storageKey), isNull);
    });

    test('signOut clears the session even when logout fails', () async {
      final h = await harness((_) async => throw http.ClientException('offline'), stored: storedSession('1'));
      await h.service.signOut();
      expect(h.auth.session, isNull);
      expect(h.prefs.getString(BackendApiAuth.storageKey), isNull);
    });

    test('expire runs the sign-out handler, or clears the session without one', () async {
      final h = await harness((_) async => ok(null), stored: storedSession('1'));
      var called = 0;
      h.auth.onExpired = () async => called++;
      await h.auth.expire();
      expect(called, 1);
      expect(h.auth.session, isNotNull);

      h.auth.onExpired = null;
      await h.auth.expire();
      expect(h.auth.session, isNull);
    });

    test('an unreadable stored session is discarded', () async {
      final h = await harness((_) async => ok(null), stored: {BackendApiAuth.storageKey: '{"broken": true}'});
      expect(h.auth.session, isNull);
      expect(h.prefs.getString(BackendApiAuth.storageKey), isNull);
    });
  });
}
