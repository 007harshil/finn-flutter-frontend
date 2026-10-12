import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../core/result/result.dart';
import 'api_config.dart';

/// Access to the signed-in user's credentials for API requests.
abstract interface class ApiAuth {
  /// The current bearer token, or null when signed out.
  String? get accessToken;

  /// Refreshes the session. Returns false when it cannot be refreshed.
  Future<bool> refresh();

  /// Called when the session is gone for good (refresh failed or the
  /// refreshed token was rejected too). Signs the user out.
  Future<void> expire();
}

/// An [ApiAuth] that can renew its token shortly before it expires, so a
/// request is not first sent with a token about to be rejected.
abstract interface class ProactiveApiAuth implements ApiAuth {
  /// Refreshes the session if the access token is about to expire. Never
  /// throws; a failed attempt falls back to the `unauthenticated` path.
  Future<void> ensureFresh();
}

/// Message used when the session cannot be recovered.
const sessionExpiredMessage = 'Your session has expired. Please sign in again.';

/// Thin JSON client for the FiNN API (`/api/v1`).
///
/// * Adds `Authorization: Bearer <token>` to every request.
/// * Unwraps the `{ "data": ... }` envelope.
/// * Maps `{ "error": { code, message, fieldErrors, retryable } }` onto
///   [AppFailure] with the same [FailureCode] names.
/// * On `unauthenticated` refreshes the session once and retries; if that
///   fails the user is signed out and [FailureCode.notPermitted] is thrown.
/// * Timeouts, 5xx without an error body and network errors become
///   [FailureCode.unavailable] (retryable).
class ApiClient {
  ApiClient({required this.config, required this.auth, http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  final ApiConfig config;
  final ApiAuth auth;
  final http.Client _http;

  Future<bool>? _refreshing;

  Future<Object?> get(String path, {Map<String, String>? query}) => send('GET', path, query: query);

  Future<Object?> post(String path, {Object? body, Map<String, String>? headers}) =>
      send('POST', path, body: body, headers: headers);

  Future<Object?> put(String path, {Object? body}) => send('PUT', path, body: body);

  Future<Object?> patch(String path, {Object? body}) => send('PATCH', path, body: body);

  /// Sends one request and returns the decoded `data` payload.
  Future<Object?> send(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
    Map<String, String>? headers,
  }) async {
    final first = await _attempt(method, path, query: query, body: body, headers: headers);
    if (first case _Unauthenticated()) {
      final refreshed = await _refreshOnce();
      if (refreshed) {
        final second = await _attempt(method, path, query: query, body: body, headers: headers);
        if (second case _Done(:final data)) return data;
      }
      await _expire();
      throw const AppFailure(FailureCode.notPermitted, sessionExpiredMessage);
    }
    return (first as _Done).data;
  }

  Future<bool> _refreshOnce() {
    return _refreshing ??= () async {
      try {
        return await auth.refresh();
      } catch (e) {
        debugPrint('Session refresh failed: $e');
        return false;
      } finally {
        _refreshing = null;
      }
    }();
  }

  Future<void> _expire() async {
    try {
      await auth.expire();
    } catch (e) {
      debugPrint('Sign-out after session expiry failed: $e');
    }
  }

  Uri _uri(String path, Map<String, String>? query) {
    final uri = Uri.parse('${config.baseUrl}${path.startsWith('/') ? path : '/$path'}');
    return query == null || query.isEmpty ? uri : uri.replace(queryParameters: {...uri.queryParameters, ...query});
  }

  Future<_Attempt> _attempt(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
    Map<String, String>? headers,
  }) async {
    if (auth case final ProactiveApiAuth proactive) await proactive.ensureFresh();
    final token = auth.accessToken;
    if (token == null || token.isEmpty) return const _Unauthenticated();

    final request = http.Request(method, _uri(path, query))
      ..headers.addAll({
        'accept': 'application/json',
        'authorization': 'Bearer $token',
        ...?headers,
      });
    if (body != null) {
      request.headers['content-type'] = 'application/json; charset=utf-8';
      request.body = jsonEncode(body);
    }

    final http.Response response;
    try {
      final streamed = await _http.send(request).timeout(config.timeout);
      response = await http.Response.fromStream(streamed).timeout(config.timeout);
    } on TimeoutException {
      throw const AppFailure(FailureCode.unavailable,
          'FiNN is taking too long to respond. Please try again.', retryable: true);
    } catch (e) {
      throw AppFailure(FailureCode.unavailable, 'Could not reach FiNN. Check your connection and try again.',
          retryable: true, cause: e);
    }

    final decoded = _decodeBody(response);
    final status = response.statusCode;
    if (status >= 200 && status < 300) {
      if (decoded is Map && decoded.containsKey('data')) return _Done(decoded['data']);
      return _Done(decoded);
    }

    final failure = _failureFrom(status, decoded);
    if (failure == null) return const _Unauthenticated();
    throw failure;
  }

  static Object? _decodeBody(http.Response response) {
    if (response.bodyBytes.isEmpty) return null;
    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } catch (_) {
      return null;
    }
  }

  /// The failure for an error response, or null when the session must be
  /// refreshed (`unauthenticated`).
  static AppFailure? _failureFrom(int status, Object? body) {
    final error = body is Map ? body['error'] : null;
    if (error is Map) {
      final code = error['code'];
      if (code == 'unauthenticated') return null;
      final failureCode = FailureCode.values.where((c) => c.name == code).firstOrNull ?? FailureCode.unknown;
      final message = error['message'] is String && (error['message'] as String).isNotEmpty
          ? error['message'] as String
          : _defaultMessage(failureCode);
      final rawFields = error['fieldErrors'];
      final fields = <String, String>{
        if (rawFields is Map)
          for (final e in rawFields.entries)
            if (e.value != null) e.key.toString(): e.value.toString(),
      };
      final retryable = error['retryable'] is bool
          ? error['retryable'] as bool
          : failureCode == FailureCode.unavailable;
      return AppFailure(
        failureCode,
        message,
        fieldErrors: fields,
        retryable: retryable || failureCode == FailureCode.unavailable,
        cause: error['details'],
      );
    }
    // No error envelope (proxy, gateway, crash page).
    if (status == 401) return null;
    if (status >= 500 || status == 408 || status == 429) {
      return const AppFailure(FailureCode.unavailable, 'FiNN is unavailable right now. Please try again.',
          retryable: true);
    }
    final code = switch (status) {
      403 => FailureCode.notPermitted,
      404 => FailureCode.notFound,
      409 => FailureCode.conflict,
      400 || 422 => FailureCode.validation,
      _ => FailureCode.unknown,
    };
    return AppFailure(code, _defaultMessage(code));
  }

  static String _defaultMessage(FailureCode code) => switch (code) {
        FailureCode.validation => 'Please check the details and try again.',
        FailureCode.notFound => 'This record no longer exists.',
        FailureCode.conflict => 'This conflicts with another change.',
        FailureCode.staleData => 'This record changed since you last saw it. Review it and try again.',
        FailureCode.notPermitted => 'You are not allowed to do that.',
        FailureCode.unavailable => 'FiNN is unavailable right now. Please try again.',
        _ => 'Something went wrong. Nothing was changed.',
      };

  void close() => _http.close();
}

sealed class _Attempt {
  const _Attempt();
}

final class _Done extends _Attempt {
  const _Done(this.data);
  final Object? data;
}

final class _Unauthenticated extends _Attempt {
  const _Unauthenticated();
}
