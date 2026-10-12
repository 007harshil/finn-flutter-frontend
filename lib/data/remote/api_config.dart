import 'package:flutter/foundation.dart';

/// Connection settings for the FiNN API, read from `--dart-define`s.
///
/// Remote mode is enabled only when `FINN_API_URL` is set; without it the
/// app runs entirely on the local mock backend.
///
/// ```
/// flutter run --dart-define=FINN_API_URL=https://api.example.com
/// ```
@immutable
class ApiConfig {
  const ApiConfig({
    required this.apiUrl,
    this.timeout = const Duration(seconds: 20),
  });

  /// Reads the compile-time `--dart-define`s.
  const ApiConfig.fromEnvironment()
      : apiUrl = const String.fromEnvironment('FINN_API_URL'),
        timeout = const Duration(seconds: 20);

  /// Base URL of the API, without the `/api/v1` suffix. Empty = local mode.
  final String apiUrl;

  /// Per-request timeout.
  final Duration timeout;

  /// Whether the app talks to the FiNN API instead of the local mock.
  bool get enabled => apiUrl.trim().isNotEmpty;

  /// `https://host/api/v1` with no trailing slash.
  String get baseUrl {
    var url = apiUrl.trim();
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    return '$url/api/v1';
  }
}
