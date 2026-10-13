import 'package:flutter/foundation.dart';

/// Provider-neutral types exchanged between the agent and an [LlmProvider]
/// (see `llm_provider.dart`). Nothing here knows about a vendor's wire
/// format; providers translate to and from these types.

enum LlmRole { user, assistant, tool }

/// A function call requested by the model.
@immutable
class LlmToolCall {
  const LlmToolCall({required this.id, required this.name, required this.arguments});

  /// Provider-assigned call id; the result must be sent back with it.
  final String id;
  final String name;

  /// Raw JSON text as produced by the model. Never trusted: the caller
  /// parses and validates it.
  final String arguments;
}

/// One entry of the conversation sent to the model.
@immutable
class LlmMessage {
  const LlmMessage._({
    required this.role,
    this.content,
    this.toolCalls = const [],
    this.toolCallId,
    this.toolName,
    this.providerState,
  });

  const LlmMessage.user(String text) : this._(role: LlmRole.user, content: text);

  /// An assistant turn. [providerState] is opaque data the provider needs to
  /// replay this turn exactly (e.g. encrypted reasoning items); the agent
  /// stores it but never inspects it.
  const LlmMessage.assistant({String? text, List<LlmToolCall> toolCalls = const [], Object? providerState})
    : this._(role: LlmRole.assistant, content: text, toolCalls: toolCalls, providerState: providerState);

  /// The result of the tool call [callId] (to tool [toolName]), as JSON text.
  const LlmMessage.toolResult({required String callId, required String content, String? toolName})
    : this._(role: LlmRole.tool, content: content, toolCallId: callId, toolName: toolName);

  final LlmRole role;
  final String? content;
  final List<LlmToolCall> toolCalls;
  final String? toolCallId;
  final String? toolName;
  final Object? providerState;
}

/// A function the model may call. [parameters] is a JSON Schema object.
@immutable
class LlmToolSpec {
  const LlmToolSpec({required this.name, required this.description, required this.parameters});
  final String name;
  final String description;
  final Map<String, Object?> parameters;
}

enum LlmToolChoice { auto, none, required }

/// What the reply must contain.
enum LlmOutputFormat {
  /// Free text (and tool calls when tools are offered).
  text,

  /// A single JSON object. The instructions describe its shape; the caller
  /// still validates it (providers guarantee syntax at most).
  json,
}

@immutable
class LlmRequest {
  const LlmRequest({
    required this.instructions,
    required this.messages,
    this.tools = const [],
    this.toolChoice = LlmToolChoice.auto,
    this.parallelToolCalls,
    this.maxOutputTokens,
    this.output = LlmOutputFormat.text,
  });

  /// System instructions for this request. Keep them identical across
  /// requests (no dates, names or user data): providers cache a stable
  /// prefix, and per-request context belongs in [messages].
  final String instructions;
  final List<LlmMessage> messages;
  final List<LlmToolSpec> tools;
  final LlmToolChoice toolChoice;

  /// Null leaves the provider default (some models ignore or reject it).
  final bool? parallelToolCalls;
  final int? maxOutputTokens;
  final LlmOutputFormat output;
}

enum LlmFinishReason {
  /// The model finished its answer.
  stop,

  /// The model wants tool results before continuing.
  toolCalls,

  /// Output was cut off by the token limit.
  length,

  /// Anything else the provider reports (content filter, unknown).
  other,
}

/// Token counts of one or more model calls, as the provider reports them.
@immutable
class LlmUsage {
  const LlmUsage({
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.cachedInputTokens = 0,
    this.cacheWriteTokens = 0,
    this.reasoningTokens = 0,
    this.calls = 0,
  });

  /// All input tokens, cached ones included.
  final int inputTokens;

  /// All output tokens, reasoning included.
  final int outputTokens;

  /// Input tokens read from the provider's prompt cache (billed lower).
  final int cachedInputTokens;

  /// Input tokens written to the prompt cache.
  final int cacheWriteTokens;
  final int reasoningTokens;

  /// Model requests these counts cover.
  final int calls;

  LlmUsage operator +(LlmUsage o) => LlmUsage(
    inputTokens: inputTokens + o.inputTokens,
    outputTokens: outputTokens + o.outputTokens,
    cachedInputTokens: cachedInputTokens + o.cachedInputTokens,
    cacheWriteTokens: cacheWriteTokens + o.cacheWriteTokens,
    reasoningTokens: reasoningTokens + o.reasoningTokens,
    calls: calls + o.calls,
  );
}

@immutable
class LlmResponse {
  const LlmResponse({
    this.text,
    this.toolCalls = const [],
    this.finishReason = LlmFinishReason.stop,
    this.usage = const LlmUsage(),
    this.providerState,
    this.refusal,
  });

  final String? text;
  final List<LlmToolCall> toolCalls;
  final LlmFinishReason finishReason;
  final LlmUsage usage;

  /// Opaque replay data; copied into [LlmMessage.assistant].
  final Object? providerState;

  /// The model declined to answer (a safety refusal); safe to show.
  final String? refusal;

  /// The assistant message to append to the conversation.
  LlmMessage toMessage() => LlmMessage.assistant(text: text, toolCalls: toolCalls, providerState: providerState);
}

enum LlmErrorKind {
  /// The assistant is not set up (no backend, no key).
  notConfigured,

  /// Too many requests; wait before trying again.
  rateLimited,

  /// The provider or network did not answer in time.
  timeout,

  /// Temporary outage or network failure.
  unavailable,

  /// The provider answered with something we cannot use.
  invalidResponse,

  /// The request was refused (bad request, session expired, not permitted).
  rejected,

  /// The caller cancelled the request.
  cancelled,
}

/// A failure talking to the model. [message] is safe to show to the user.
class LlmException implements Exception {
  const LlmException(this.kind, this.message, {this.retryable = false, this.retryAfter});

  final LlmErrorKind kind;
  final String message;
  final bool retryable;
  final Duration? retryAfter;

  @override
  String toString() => 'LlmException($kind, $message)';
}
