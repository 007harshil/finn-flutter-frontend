import 'package:flutter/foundation.dart';

import '../core/result/result.dart';
import 'action.dart';
import 'action_registry.dart';
import 'dispatcher.dart';

/// One step of a multi-action plan (e.g. produced by a future agent from
/// "Pay Rahul 500 and add 2,000 to my Japan goal").
@immutable
class PlannedStep {
  const PlannedStep({required this.stepId, required this.actionId, required this.input, this.dependsOn = const []});
  final String stepId;
  final String actionId;
  final Map<String, Object?> input;

  /// Steps that must succeed first; otherwise this step is skipped.
  final List<String> dependsOn;
}

@immutable
class ActionPlan {
  const ActionPlan({required this.planId, required this.steps, this.channel = ActionChannel.agent});
  final String planId;
  final List<PlannedStep> steps;
  final ActionChannel channel;
}

enum StepStatus { ready, invalid, succeeded, failed, skipped, notApproved }

@immutable
class StepReport {
  const StepReport({required this.step, required this.status, this.preview, this.failure, this.result});
  final PlannedStep step;
  final StepStatus status;
  final ActionPreview? preview;
  final AppFailure? failure;
  final Object? result;
}

/// Validates and runs plans step by step.
///
/// There is **no atomicity**: each step commits independently because the
/// eventual backend cannot be assumed to support multi-operation
/// transactions. Failures are reported per step; already-completed steps
/// are not rolled back automatically (the report makes this explicit).
/// Steps are validated against fresh data right before they run, so a
/// step made invalid by an earlier one (stale data) fails safely.
class PlanExecutor {
  PlanExecutor({required this.registry, required this.dispatcher});

  final ActionRegistry registry;
  final OperationDispatcher dispatcher;

  /// Decodes, validates and previews every step without executing.
  Future<List<StepReport>> prepare(ActionPlan plan) async {
    final reports = <StepReport>[];
    for (final step in plan.steps) {
      final action = registry.lookup(step.actionId);
      final decoded = registry.decode(step.actionId, step.input);
      if (action == null || decoded is Err<ActionInput>) {
        reports.add(StepReport(step: step, status: StepStatus.invalid, failure: decoded.failureOrNull));
        continue;
      }
      final preview = await dispatcher.preview<ActionInput, Object?>(
        action,
        (decoded as Ok<ActionInput>).value,
        channel: plan.channel,
      );
      reports.add(
        preview.fold(
          (p) => StepReport(step: step, status: StepStatus.ready, preview: p),
          (f) => StepReport(step: step, status: StepStatus.invalid, failure: f),
        ),
      );
    }
    return reports;
  }

  /// Executes steps in order. Only steps whose preview fingerprints appear
  /// in [approvedFingerprints] run (the user approved those exact previews).
  /// A step approved for the same input but whose record changed since
  /// (different state basis) is reported as [StepStatus.notApproved] with a
  /// [FailureCode.staleData] failure and is not executed.
  Future<List<StepReport>> execute(
    ActionPlan plan, {
    required Set<String> approvedFingerprints,
    bool stopOnFailure = true,
  }) async {
    final reports = <StepReport>[];
    final succeeded = <String>{};
    var halted = false;
    for (final step in plan.steps) {
      if (halted || step.dependsOn.any((d) => !succeeded.contains(d))) {
        reports.add(StepReport(step: step, status: StepStatus.skipped));
        continue;
      }
      final action = registry.lookup(step.actionId);
      final decoded = registry.decode(step.actionId, step.input);
      if (action == null || decoded is Err<ActionInput>) {
        reports.add(StepReport(step: step, status: StepStatus.invalid, failure: decoded.failureOrNull));
        halted = stopOnFailure;
        continue;
      }
      final input = (decoded as Ok<ActionInput>).value;
      final request = fingerprintOf(step.actionId, input);
      final fp = approvedFingerprints.where((a) => fingerprintMatchesRequest(a, request)).firstOrNull;
      if (fp == null) {
        reports.add(StepReport(step: step, status: StepStatus.notApproved));
        continue;
      }
      final outcome = await dispatcher.dispatch<ActionInput, Object?>(
        action,
        input,
        idempotencyKey: '${plan.planId}:${step.stepId}',
        confirmation: ActionConfirmation(fp, confirmedBy: 'plan:${plan.planId}'),
        channel: plan.channel,
      );
      switch (outcome) {
        case ActionCompleted(:final value, :final preview):
          succeeded.add(step.stepId);
          reports.add(StepReport(step: step, status: StepStatus.succeeded, preview: preview, result: value));
        case ActionNeedsConfirmation(:final preview):
          // Data changed since approval: the preview no longer matches.
          reports.add(
            StepReport(
              step: step,
              status: StepStatus.notApproved,
              preview: preview,
              failure: const AppFailure(FailureCode.staleData, 'Details changed since approval. Please review again.'),
            ),
          );
          halted = stopOnFailure;
        case ActionRejected(:final failure):
          reports.add(StepReport(step: step, status: StepStatus.failed, failure: failure));
          halted = stopOnFailure;
      }
    }
    return reports;
  }
}
