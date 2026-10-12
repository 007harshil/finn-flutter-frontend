import 'package:flutter/foundation.dart';

import '../../actions/action.dart';
import '../tools/agent_tool.dart';

/// An action the model asked for, validated and previewed by the app, that
/// waits for the user's approval. Nothing has been written yet.
@immutable
class ProposedAction {
  const ProposedAction({
    required this.id,
    required this.toolCallId,
    required this.tool,
    required this.input,
    required this.preview,
    required this.idempotencyKey,
    this.notes = const [],
  });

  /// Unique within the conversation, e.g. `p3`.
  final String id;
  final String toolCallId;
  final ActionTool tool;
  final ActionInput input;

  /// The dispatcher's preview (title, summary, lines, warnings, fingerprint).
  final ActionPreview preview;
  final String idempotencyKey;

  /// Agent-side notes for the user, e.g. a possible duplicate.
  final List<String> notes;

  ActionDescriptor get descriptor => tool.descriptor;
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

  /// The run was stopped before this action ran.
  cancelled,
}

/// Ground truth about one proposed action, taken from the dispatcher's
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
