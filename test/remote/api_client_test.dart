import 'dart:convert';

import 'package:finn/core/result/result.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'remote_fakes.dart';

Future<AppFailure> failureOf(Future<Object?> call) async {
  try {
    await call;
  } on AppFailure catch (f) {
    return f;
  }
  fail('Expected an AppFailure');
}

void main() {
  test('unwraps the data envelope and sends the bearer token and headers', () async {
    late http.Request seen;
    final api = apiWith(MockClient((req) async {
      seen = req;
      return ok({'hello': 'world'});
    }));
    final data = await api.post('/actions/x', body: {'a': 1}, headers: {'Idempotency-Key': 'key_12345678'});
    expect(data, {'hello': 'world'});
    expect(seen.url.toString(), 'https://api.test/api/v1/actions/x');
    expect(seen.headers['authorization'], 'Bearer token-1');
    expect(seen.headers['Idempotency-Key'], 'key_12345678');
    expect(jsonDecode(seen.body), {'a': 1});
  });

  test('maps error envelopes onto FailureCode with field errors', () async {
    final api = apiWith(MockClient((_) async =>
        errorResponse(422, 'validation', 'Enter an amount.', fields: {'amount': 'Enter an amount.'})));
    final f = await failureOf(api.get('/x'));
    expect(f.code, FailureCode.validation);
    expect(f.message, 'Enter an amount.');
    expect(f.fieldErrors, {'amount': 'Enter an amount.'});
    expect(f.retryable, isFalse);
  });

  test('keeps every FailureCode name and maps unknown codes to unknown', () async {
    for (final code in FailureCode.values) {
      final api = apiWith(MockClient((_) async => errorResponse(409, code.name, 'msg')));
      expect((await failureOf(api.get('/x'))).code, code);
    }
    final api = apiWith(MockClient((_) async => errorResponse(400, 'somethingNew', 'msg')));
    expect((await failureOf(api.get('/x'))).code, FailureCode.unknown);
  });

  test('5xx without an envelope, network errors and timeouts are unavailable and retryable', () async {
    final gateway = apiWith(MockClient((_) async => http.Response('<html>Bad gateway</html>', 502)));
    final f1 = await failureOf(gateway.get('/x'));
    expect(f1.code, FailureCode.unavailable);
    expect(f1.retryable, isTrue);

    final offline = apiWith(MockClient((_) async => throw http.ClientException('Failed host lookup')));
    final f2 = await failureOf(offline.get('/x'));
    expect(f2.code, FailureCode.unavailable);
    expect(f2.retryable, isTrue);

    final slow = apiWith(MockClient((_) async {
      await Future<void>.delayed(const Duration(seconds: 1));
      return ok(null);
    }));
    final f3 = await failureOf(slow.get('/x'));
    expect(f3.code, FailureCode.unavailable);
    expect(f3.retryable, isTrue);
  });

  test('unauthenticated refreshes the session once and retries', () async {
    final auth = FakeApiAuth(refreshTo: 'token-2');
    final tokens = <String?>[];
    final api = apiWith(MockClient((req) async {
      tokens.add(req.headers['authorization']);
      return req.headers['authorization'] == 'Bearer token-2'
          ? ok({'ok': true})
          : errorResponse(401, 'unauthenticated', 'Your session has expired.');
    }), auth: auth);
    expect(await api.get('/x'), {'ok': true});
    expect(tokens, ['Bearer token-1', 'Bearer token-2']);
    expect(auth.refreshCalls, 1);
    expect(auth.expireCalls, 0);
  });

  test('signs out and reports notPermitted when the refreshed session is rejected too', () async {
    final auth = FakeApiAuth(refreshTo: 'token-2');
    var calls = 0;
    final api = apiWith(MockClient((_) async {
      calls++;
      return errorResponse(401, 'unauthenticated', 'Your session has expired.');
    }), auth: auth);
    final f = await failureOf(api.get('/x'));
    expect(f.code, FailureCode.notPermitted);
    expect(calls, 2);
    expect(auth.refreshCalls, 1);
    expect(auth.expireCalls, 1);
  });

  test('signs out when the refresh itself fails', () async {
    final auth = FakeApiAuth();
    final api = apiWith(MockClient((_) async => http.Response('', 401)), auth: auth);
    final f = await failureOf(api.get('/x'));
    expect(f.code, FailureCode.notPermitted);
    expect(auth.expireCalls, 1);
  });
}
