import 'dart:async';

import 'llm_types.dart';

export 'llm_types.dart';

/// The only boundary between the agent and a language model vendor.
///
/// Implementations own the wire format, authentication path and response
/// parsing. They throw [LlmException] for every failure and must not retry
/// on their own (the agent decides; see `AgentRunner`).
abstract interface class LlmProvider {
  /// Short name for diagnostics, e.g. `groq`.
  String get name;

  Future<LlmResponse> complete(LlmRequest request, {CancellationToken? cancel});
}

/// Cooperative cancellation for an agent run.
class CancellationToken {
  final _completer = Completer<void>();

  bool get isCancelled => _completer.isCompleted;

  /// Completes when [cancel] is called.
  Future<void> get whenCancelled => _completer.future;

  void cancel() {
    if (!_completer.isCompleted) _completer.complete();
  }

  /// Throws [LlmException] (cancelled) if already cancelled.
  void throwIfCancelled() {
    if (isCancelled) throw const LlmException(LlmErrorKind.cancelled, 'Stopped.');
  }

  /// Completes with [future], or throws a cancellation as soon as [cancel]
  /// is called. The underlying work is not aborted, only abandoned.
  Future<T> guard<T>(Future<T> future) {
    throwIfCancelled();
    return Future.any<T>([
      future,
      whenCancelled.then<T>((_) => throw const LlmException(LlmErrorKind.cancelled, 'Stopped.')),
    ]);
  }
}
