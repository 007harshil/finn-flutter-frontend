import 'package:flutter/foundation.dart';

import '../../actions/action.dart';

/// An operation from the model's plan, resolved and previewed by the app,
/// that waits for the user's approval. Nothing has been written yet.
@immutable
class ProposedAction {
  const ProposedAction({
    required this.id,
    required this.opRef,
    required this.action,
    required this.input,
    required this.preview,
    required this.stepId,
    required this.idempotencyKey,
    this.notes = const [],
  });

  /// Unique within the conversation, e.g. `p3`.
  final String id;

  /// The op of the plan it came from (`o1`, `o2`…).
  final String opRef;
  final FinancialAction<ActionInput, Object?> action;
  final ActionInput input;

  /// The preview (title, summary, lines, warnings, fingerprint), from the
  /// FiNN API in remote mode.
  final ActionPreview preview;

  /// Plan step id, derived from the request itself (see `PlanExecution`).
  final String stepId;

  /// What the server stores the write under (`<planId>:<stepId>`).
  final String idempotencyKey;

  /// Agent-side notes for the user, e.g. a possible duplicate.
  final List<String> notes;

  ActionDescriptor get descriptor => action.descriptor;
}

enum ActionResultStatus {
  /// The application confirmed the change.
  completed,

  /// The same request had already been carried out; nothing new was written.
  alreadyDone,

  /// The user did not approve it.
  declined,

  /// The application refused it or it could not be completed.
  failed,

  /// The record changed after the user reviewed it; needs a new review.
  needsReapproval,

  /// Not run because a change it depends on was not saved.
  skipped,

  /// The run was stopped before this action ran.
  cancelled,
}

/// Ground truth about one proposed action, taken from the backend's
/// outcome (never from the model's words). Shown to the user next to the
/// agent's reply.
@immutable
class ActionRecord {
  const ActionRecord({
    required this.proposal,
    required this.status,
    this.message,
    this.outcomeUnknown = false,
    this.recordId,
  });

  final ProposedAction proposal;
  final ActionResultStatus status;

  /// Failure reason, safe to show.
  final String? message;

  /// The request may or may not have reached the server (network failure
  /// after sending). Repeating the same request reuses its idempotency key,
  /// so it can never be applied twice.
  final bool outcomeUnknown;

  /// Id(s) of the record created or changed (for follow-up actions).
  final Object? recordId;

  String get summary => proposal.preview.summary;

  bool get succeeded => status == ActionResultStatus.completed || status == ActionResultStatus.alreadyDone;
}
