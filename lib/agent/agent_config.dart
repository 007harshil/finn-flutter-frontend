import 'package:flutter/foundation.dart';

/// Runtime limits for the agent. Model choice, reasoning effort and token
/// caps on the provider side are configured on the FiNN API relay (see
/// `finn-backend` env `GROQ_*` / `AGENT_*`), so a model change never needs an
/// app release.
@immutable
class AgentConfig {
  const AgentConfig({
    // Models without parallel tool calls (e.g. gpt-oss) need one step per
    // call, so a multi-task request takes several steps.
    this.maxModelCallsPerTurn = 10,
    this.maxToolCallsPerStep = 8,
    this.maxToolCallsPerTurn = 24,
    this.maxOutputTokens = 1536,
    // Small on purpose: free Groq tiers allow only a few thousand tokens
    // per minute, and every step resends the window.
    this.maxHistoryTurns = 6,
    this.maxHistoryChars = 12000,
    this.maxUserMessageChars = 2000,
    this.requestTimeout = const Duration(seconds: 75),
    this.transientRetries = 1,
    this.defaultRateLimitWait = const Duration(seconds: 5),
    // Free Groq tiers measure tokens per minute, so a wait can approach a
    // minute; the screen shows a countdown meanwhile.
    this.maxRateLimitWait = const Duration(seconds: 60),
    this.rateLimitRetries = 2,
  });

  /// Model round trips in one user turn (tool loop limit).
  final int maxModelCallsPerTurn;

  /// Tool calls handled from one model response.
  final int maxToolCallsPerStep;

  /// Tool calls handled in one user turn.
  final int maxToolCallsPerTurn;

  /// Requested cap on output per model call (includes reasoning tokens).
  final int maxOutputTokens;

  /// Earlier user turns kept as conversation context.
  final int maxHistoryTurns;

  /// Rough cap on the size of the conversation sent to the model.
  final int maxHistoryChars;

  final int maxUserMessageChars;

  /// Client-side timeout of one model call (the relay has its own).
  final Duration requestTimeout;

  /// Automatic retries of a model call after a timeout or outage. Model
  /// calls have no side effects; tool mutations are never retried.
  final int transientRetries;

  /// Wait before the single retry after a rate limit without a hint.
  final Duration defaultRateLimitWait;

  /// Longer requested waits are not retried; the user is told instead.
  final Duration maxRateLimitWait;

  /// Retries of a model call after rate limits within one step.
  final int rateLimitRetries;
}
