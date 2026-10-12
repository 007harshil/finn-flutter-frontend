import 'dart:convert';

import 'package:finn/data/remote/api_client.dart';
import 'package:finn/data/remote/api_config.dart';
import 'package:http/http.dart' as http;

/// Token source with a controllable refresh outcome.
class FakeApiAuth implements ApiAuth {
  FakeApiAuth({this.token = 'token-1', this.refreshTo});

  String? token;

  /// Token adopted on refresh; null makes the refresh fail.
  String? refreshTo;
  int refreshCalls = 0;
  int expireCalls = 0;

  @override
  String? get accessToken => token;

  @override
  Future<bool> refresh() async {
    refreshCalls++;
    if (refreshTo == null) return false;
    token = refreshTo;
    return true;
  }

  @override
  Future<void> expire() async {
    expireCalls++;
    token = null;
  }
}

const testConfig = ApiConfig(apiUrl: 'https://api.test/', timeout: Duration(milliseconds: 200));

ApiClient apiWith(http.Client client, {FakeApiAuth? auth}) =>
    ApiClient(config: testConfig, auth: auth ?? FakeApiAuth(), httpClient: client);

http.Response ok(Object? data, {int status = 200}) =>
    http.Response(jsonEncode({'data': data}), status, headers: {'content-type': 'application/json'});

http.Response errorResponse(int status, String code, String message, {Map<String, String>? fields, bool retryable = false}) =>
    http.Response(
      jsonEncode({
        'error': {'code': code, 'message': message, 'fieldErrors': ?fields, 'retryable': retryable},
      }),
      status,
      headers: {'content-type': 'application/json'},
    );

Map<String, Object?> txJson(String id, {int paise = 12500, int version = 1}) => {
      'id': id,
      'type': 'expense',
      'amountPaise': paise,
      'categoryId': 'cat_food',
      'date': '2026-10-10',
      'paymentMethod': 'upi',
      'counterparty': null,
      'note': null,
      'origin': 'manual',
      'originRefId': null,
      'createdAt': '2026-10-10T09:00:00.000Z',
      'updatedAt': '2026-10-10T09:00:00.000Z',
      'version': version,
    };

Map<String, Object?> pendingJson(String id, {Map<String, Object?>? link}) => {
      'id': id,
      'counterparty': 'Ramesh Kumar',
      'direction': 'owedToMe',
      'kind': 'other',
      'originalPaise': 50000,
      'purpose': 'Dinner',
      'createdDate': '2026-10-01',
      'notes': null,
      'isCancelled': false,
      'createdAt': '2026-10-01T09:00:00.000Z',
      'updatedAt': '2026-10-01T09:00:00.000Z',
      'version': 1,
      'link': link,
      'split': null,
    };

/// A sync page payload.
Map<String, Object?> page({
  required String cursor,
  bool hasMore = false,
  Map<String, Object?> collections = const {},
  Map<String, Object?> values = const {},
}) =>
    {'cursor': cursor, 'hasMore': hasMore, 'collections': collections, 'values': values};
