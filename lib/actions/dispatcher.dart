import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/result/result.dart';
import 'action.dart';
import 'action_policy.dart';
import 'audit_log.dart';

/// Result of dispatching an action.
sealed class ActionOutcome<O> {
  const ActionOutcome();
}

/// The action ran (or an identical request already ran: [replayed]).
final class ActionCompleted<O> extends ActionOutcome<O> {
  const ActionCompleted(this.value, this.preview, {this.replayed = false});
  final O value;
  final ActionPreview preview;
  final bool replayed;
}

/// The action is valid but needs explicit approval of [preview].
final class ActionNeedsConfirmation<O> extends ActionOutcome<O> {
  const ActionNeedsConfirmation(this.preview);
  final ActionPreview preview;
}

/// The action was refused (validation, conflict, policy, failure).
final class ActionRejected<O> extends ActionOutcome<O> {
  const ActionRejected(this.failure);
  final AppFailure failure;
}

/// Single entry point for every financial operation, whichever channel
/// initiates it (form, agent, voice, import).
///
/// Guarantees:
/// * **Validation** on a fresh snapshot right before execution.
/// * **Confirmation**: consequential actions run only with an
///   [ActionConfirmation] whose fingerprint matches the current preview.
/// * **Idempotency**: a repeated [idempotencyKey] never executes twice —
///   in-flight duplicates are rejected, completed ones replay the result.
/// * **Policy**: an [ActionPolicy] decides what each channel may do.
/// * **Audit**: every execution is recorded in the [AuditLog].
class OperationDispatcher {
  OperationDispatcher({required this.environment, ActionPolicy? policy, AuditLog? audit, this.maxRememberedKeys = 500})
    : policy = policy ?? const DefaultActionPolicy(),
      audit = audit ?? AuditLog();

  final ActionEnvironment environment;
  final ActionPolicy policy;
  final AuditLog audit;
  final int maxRememberedKeys;

  final Map<String, _IdempotencyEntry> _keys = {};
  final List<String> _keyOrder = [];

  /// Validates and previews without executing.
  Future<Result<ActionPreview>> preview<I extends ActionInput, O>(
    FinancialAction<I, O> action,
    I input, {
    ActionChannel channel = ActionChannel.ui,
  }) async {
    final decision = policy.check(action.descriptor, channel);
    if (decision != null) return Result.err(decision);
    try {
      final snapshot = await environment.loadSnapshot();
      return action.prepare(input, snapshot, environment);
    } on AppFailure catch (f) {
      return Result.err(f);
    }
  }

  Future<ActionOutcome<O>> dispatch<I extends ActionInput, O>(
    FinancialAction<I, O> action,
    I input, {
    required String idempotencyKey,
    ActionConfirmation? confirmation,
    ActionChannel channel = ActionChannel.ui,
  }) async {
    final descriptor = action.descriptor;
    final decision = policy.check(descriptor, channel);
    if (decision != null) return ActionRejected(decision);

    final requestFingerprint = fingerprintOf(descriptor.id, input);
    final existing = _keys[idempotencyKey];
    if (existing != null) {
      if (existing.actionId != descriptor.id || existing.fingerprint != requestFingerprint) {
        return const ActionRejected(
          AppFailure(FailureCode.conflict, 'This request id was already used for a different operation.'),
        );
      }
      if (existing.inFlight) {
        return const ActionRejected(AppFailure(FailureCode.duplicate, 'This is already being processed.'));
      }
      return ActionCompleted(existing.result as O, existing.preview!, replayed: true);
    }

    // Claim the key *before* the first await so a concurrent duplicate
    // (double tap, agent retry) sees it as in flight and never executes.
    _remember(idempotencyKey, _IdempotencyEntry(descriptor.id, requestFingerprint));

    Result<ActionPreview> prepared;
    try {
      final snapshot = await environment.loadSnapshot();
      prepared = action.prepare(input, snapshot, environment);
      if (prepared case Err(:final failure)) {
        _forget(idempotencyKey);
        return ActionRejected(failure);
      }
      final preview = (prepared as Ok<ActionPreview>).value;

      final needsApproval = preview.requiresConfirmation || policy.requiresConfirmation(descriptor, channel);
      if (needsApproval && confirmation?.fingerprint != preview.fingerprint) {
        _forget(idempotencyKey);
        return ActionNeedsConfirmation(preview);
      }

      final result = await action.execute(input, snapshot, environment);
      switch (result) {
        case Ok(:final value):
          _keys[idempotencyKey]!
            ..inFlight = false
            ..result = value
            ..preview = preview;
          audit.record(
            AuditEntry(
              actionId: descriptor.id,
              summary: preview.summary,
              channel: channel,
              at: environment.clock.now(),
              confirmedBy: confirmation?.confirmedBy,
              succeeded: true,
            ),
          );
          return ActionCompleted(value, preview);
        case Err(:final failure):
          _forget(idempotencyKey); // failed attempts may be retried
          audit.record(
            AuditEntry(
              actionId: descriptor.id,
              summary: preview.summary,
              channel: channel,
              at: environment.clock.now(),
              succeeded: false,
              failure: failure.message,
            ),
          );
          return ActionRejected(failure);
      }
    } on AppFailure catch (f) {
      _forget(idempotencyKey);
      return ActionRejected(f);
    } catch (e, st) {
      _forget(idempotencyKey);
      debugPrint('Action ${descriptor.id} failed: $e\n$st');
      return ActionRejected(
        AppFailure(FailureCode.unknown, 'Something went wrong. Nothing was changed.', cause: e, retryable: true),
      );
    }
  }

  void _remember(String key, _IdempotencyEntry entry) {
    _keys[key] = entry;
    _keyOrder.add(key);
    while (_keyOrder.length > maxRememberedKeys) {
      _keys.remove(_keyOrder.removeAt(0));
    }
  }

  void _forget(String key) {
    _keys.remove(key);
    _keyOrder.remove(key);
  }
}

class _IdempotencyEntry {
  _IdempotencyEntry(this.actionId, this.fingerprint);
  final String actionId;
  final String fingerprint;
  bool inFlight = true;
  Object? result;
  ActionPreview? preview;
}
