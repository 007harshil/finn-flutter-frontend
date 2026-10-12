import '../../core/result/result.dart';
import '../../data/remote/api_client.dart';
import 'llm_types.dart';

/// Sends a provider-format request body to whatever holds the provider
/// credentials and returns the provider's JSON reply.
abstract interface class LlmTransport {
  /// Throws [LlmException] on every failure.
  Future<Map<String, Object?>> post(Map<String, Object?> body);
}

/// Transport through the FiNN API relay (`POST /api/v1/agent/completions`).
///
/// The API key never reaches the device: the relay authenticates the user
/// with their normal session, enforces limits and forwards the request to
/// the provider. Reuses [ApiClient] so session refresh and error envelopes
/// behave exactly like every other API call.
class FinnRelayTransport implements LlmTransport {
  FinnRelayTransport(this.api, {this.path = '/agent/completions'});

  final ApiClient api;
  final String path;

  @override
  Future<Map<String, Object?>> post(Map<String, Object?> body) async {
    try {
      final data = await api.post(path, body: body);
      if (data is Map) return Map<String, Object?>.from(data);
      throw const LlmException(LlmErrorKind.invalidResponse, 'The assistant sent an unexpected reply. Please try again.',
          retryable: true);
    } on AppFailure catch (f) {
      throw llmExceptionFromFailure(f);
    }
  }
}

/// Maps a FiNN API failure onto an [LlmException].
LlmException llmExceptionFromFailure(AppFailure f) {
  final details = f.cause is Map ? f.cause! as Map : const {};
  final reason = details['reason'];
  final retryAfter = details['retryAfterSeconds'];
  switch (f.code) {
    case FailureCode.unavailable when reason == 'rateLimited' || reason == 'providerRateLimited':
      return LlmException(LlmErrorKind.rateLimited, f.message,
          retryable: true, retryAfter: retryAfter is num ? Duration(seconds: retryAfter.ceil()) : null);
    case FailureCode.unavailable when reason == 'notConfigured':
      return LlmException(LlmErrorKind.notConfigured, f.message);
    case FailureCode.unavailable:
      // `timeout` from the relay, or the client's own timeout message.
      final timeout = reason == 'timeout' || f.message.contains('too long');
      return LlmException(timeout ? LlmErrorKind.timeout : LlmErrorKind.unavailable, f.message, retryable: true);
    case FailureCode.unknown when f.retryable:
      return LlmException(LlmErrorKind.invalidResponse, f.message, retryable: true);
    default:
      return LlmException(LlmErrorKind.rejected, f.message);
  }
}
