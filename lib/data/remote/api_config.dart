import 'package:flutter/foundation.dart';

/// Connection settings for the FiNN API, read from `--dart-define`s.
///
/// Defaults to the production backend so plain `flutter build` works with no
/// flags. Override with `--dart-define=FINN_API_URL=<url>`, or pass an empty
/// value (`--dart-define=FINN_API_URL=`) to run on the local mock backend.
@immutable
class ApiConfig {
  const ApiConfig({
    required this.apiUrl,
    this.timeout = const Duration(seconds: 20),
  });

  /// Production backend used when no `--dart-define` is given.
  static const defaultApiUrl = 'https://finn-backend.vercel.app';

  /// Reads the compile-time `--dart-define`s.
  const ApiConfig.fromEnvironment()
      : apiUrl = const String.fromEnvironment(
          'FINN_API_URL',
          defaultValue: defaultApiUrl,
        ),
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
