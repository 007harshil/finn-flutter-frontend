import 'package:flutter/foundation.dart';

/// Runtime limits for the agent. Model choice, reasoning effort, prompt
/// caching and the token ceiling on the provider side are configured on the
/// FiNN API relay (see `finn-backend` env `OPENAI_*` / `AGENT_*`), so a
/// model change never needs an app release.
@immutable
class AgentConfig {
  const AgentConfig({
    // A 12-op plan with notes is about 450 tokens; there are no reasoning
    // tokens at effort "none".
    this.maxOutputTokens = 700,
    this.maxUserMessageChars = 2000,
    this.requestTimeout = const Duration(seconds: 75),
    this.transientRetries = 1,
    this.invalidPlanRetries = 1,
    this.maxWaves = 3,
    this.defaultRateLimitWait = const Duration(seconds: 5),
    this.maxRateLimitWait = const Duration(seconds: 60),
    this.rateLimitWaitBudget = const Duration(seconds: 150),
  });

  /// Requested cap on output per model call (includes reasoning tokens).
  final int maxOutputTokens;

  final int maxUserMessageChars;

  /// Client-side timeout of one model call (the relay has its own).
  final Duration requestTimeout;

  /// Automatic retries of a model call after a timeout or outage. Model
  /// calls have no side effects.
  final int transientRetries;

  /// Extra model calls when the reply is not a usable JSON plan (the only
  /// case where asking again can fix the answer).
  final int invalidPlanRetries;

  /// Rounds of dependent changes in one turn (e.g. a new category, then the
  /// expense filed under it). Each round is one review and one backend call.
  final int maxWaves;

  /// Wait before retrying after a rate limit without a hint.
  final Duration defaultRateLimitWait;

  /// Longer requested waits are not retried; the user is told instead.
  final Duration maxRateLimitWait;

  /// Total rate-limit waiting allowed in one user turn.
  final Duration rateLimitWaitBudget;
}
