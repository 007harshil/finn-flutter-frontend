import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../actions/action.dart';
import '../../actions/dispatcher.dart';
import '../../core/result/result.dart';
import '../../data/remote/api_client.dart';
import '../../data/remote/remote_dispatcher.dart' show actionPreviewFromJson;
import '../../data/remote/sync_engine.dart';
import '../history/agent_history.dart';
import 'proposals.dart';

/// One operation of a plan, ready for the backend.
@immutable
class PlanStep {
  const PlanStep({required this.stepId, required this.action, required this.input, this.label});
  final String stepId;
  final FinancialAction<ActionInput, Object?> action;
  final ActionInput input;

  /// Summary for history when the server has no preview of it (declined).
  final String? label;
}

@immutable
class StepPreview {
  const StepPreview(this.stepId, {this.preview, this.failure});
  final String stepId;
  final ActionPreview? preview;
  final AppFailure? failure;
}

@immutable
class StepResult {
  const StepResult(this.stepId, this.status, {this.message, this.recordId, this.outcomeUnknown = false});
  final String stepId;
  final ActionResultStatus status;
  final String? message;
  final Object? recordId;
  final bool outcomeUnknown;
}

/// The agent history entry an execution writes (see `agent_history.dart`).
@immutable
class HistoryWrite {
  const HistoryWrite({required this.runId, required this.request, this.notes = const []});
  final String runId;
  final String request;
  final List<String> notes;
}

/// How the agent previews and executes a plan. Independent steps go to the
/// backend together: in remote mode one `POST /plans/preview` and one
/// `POST /plans/execute` per wave, instead of one request per action.
/// Each step still commits on its own (never atomic across steps), and the
/// server runs them in order under the user's write lock, which is what
/// keeps balance checks consistent (parallel requests would be serialised by
/// that lock anyway).
abstract interface class PlanGateway {
  Future<List<StepPreview>> preview(String planId, List<PlanStep> steps);

  /// Runs the steps whose ids are in [approved] (step id → approved preview
  /// fingerprint); the rest are reported as declined. With [history], the
  /// confirmed outcome is recorded as one agent history entry.
  Future<List<StepResult>> execute(
    String planId,
    List<PlanStep> steps, {
    required Map<String, String> approved,
    HistoryWrite? history,
  });
}

/// Id(s) of the record an action result describes, for follow-ups.
Object? recordIdOf(Object? value) {
  if (value == null) return null;
  if (value is Map) {
    final id = value['id'];
    if (id is String) return id;
    for (final key in ['items', 'pending', 'upserted']) {
      if (value[key] is List) return recordIdOf(value[key]);
    }
    return null;
  }
  if (value is List) return [for (final v in value) recordIdOf(v)];
  try {
    final dynamic d = value;
    final Object? id = d.id;
    return id;
  } catch (_) {
    return null;
  }
}

/// History status of a step result, as the server names it.
String historyStatusOf(StepResult r) => switch (r.status) {
  ActionResultStatus.completed => 'saved',
  ActionResultStatus.alreadyDone => 'alreadySaved',
  ActionResultStatus.declined || ActionResultStatus.cancelled => 'declined',
  ActionResultStatus.skipped => 'skipped',
  ActionResultStatus.needsReapproval => 'changed',
  ActionResultStatus.failed => 'failed',
};

/// Runs plans through an [OperationDispatcher] (local mode and tests), one
/// step after another. With [history], entries go to that store.
class DispatcherPlanGateway implements PlanGateway {
  DispatcherPlanGateway(this.dispatcher, {this.history, DateTime Function()? now}) : _now = now ?? DateTime.now;

  final OperationDispatcher dispatcher;
  final InMemoryAgentHistory? history;
  final DateTime Function() _now;

  @override
  Future<List<StepPreview>> preview(String planId, List<PlanStep> steps) async => [
    for (final s in steps)
      switch (await dispatcher.preview<ActionInput, Object?>(s.action, s.input, channel: ActionChannel.agent)) {
        Ok(:final value) => StepPreview(s.stepId, preview: value),
        Err(:final failure) => StepPreview(s.stepId, failure: failure),
      },
  ];

  @override
  Future<List<StepResult>> execute(
    String planId,
    List<PlanStep> steps, {
    required Map<String, String> approved,
    HistoryWrite? history,
  }) async {
    final results = <StepResult>[];
    for (final s in steps) {
      final fingerprint = approved[s.stepId];
      if (fingerprint == null) {
        results.add(StepResult(s.stepId, ActionResultStatus.declined));
        continue;
      }
      results.add(await _run(planId, s, fingerprint));
    }
    if (history != null) _record(history, steps, results);
    return results;
  }

  Future<StepResult> _run(String planId, PlanStep s, String fingerprint) async {
    final ActionOutcome<Object?> outcome;
    try {
      outcome = await dispatcher.dispatch<ActionInput, Object?>(
        s.action,
        s.input,
        idempotencyKey: '$planId:${s.stepId}',
        confirmation: ActionConfirmation(fingerprint, confirmedBy: 'user:agent'),
        channel: ActionChannel.agent,
      );
    } catch (e) {
      debugPrint('Agent step ${s.action.descriptor.id} threw: $e');
      return StepResult(s.stepId, ActionResultStatus.failed, message: 'Something went wrong.', outcomeUnknown: true);
    }
    return switch (outcome) {
      ActionCompleted(:final value, :final replayed) => StepResult(
        s.stepId,
        replayed ? ActionResultStatus.alreadyDone : ActionResultStatus.completed,
        message: replayed ? 'This had already been recorded; it was not added twice.' : null,
        recordId: recordIdOf(value),
      ),
      ActionNeedsConfirmation() => StepResult(
        s.stepId,
        ActionResultStatus.needsReapproval,
        message: 'The details changed after you reviewed them, so nothing was changed.',
      ),
      ActionRejected(:final failure) => StepResult(
        s.stepId,
        ActionResultStatus.failed,
        message: failure.message,
        outcomeUnknown: failure.code == FailureCode.unavailable || failure.code == FailureCode.unknown,
      ),
    };
  }

  void _record(HistoryWrite h, List<PlanStep> steps, List<StepResult> results) {
    final store = history;
    if (store == null) return;
    final ops = [
      for (var i = 0; i < steps.length; i++)
        AgentHistoryOperation(
          ref: steps[i].stepId,
          actionId: steps[i].action.descriptor.id,
          summary: steps[i].label ?? steps[i].action.descriptor.title,
          status: historyStatusOf(results[i]),
          recordIds: [
            if (results[i].recordId case final String id) id,
            if (results[i].recordId case final List<Object?> ids) ...ids.whereType<String>(),
          ],
          message: results[i].status == ActionResultStatus.declined ? null : results[i].message,
        ),
    ];
    store.record(AgentHistoryEntry(
      id: h.runId,
      request: h.request.length <= 500 ? h.request : h.request.substring(0, 500),
      status: runStatusOf(ops),
      summary: runSummaryOf(ops),
      createdAt: _now(),
      operations: ops,
      notes: h.notes,
    ));
  }
}

/// Plans through the FiNN API (`POST /plans/preview`, `POST /plans/execute`).
/// The server validates, previews, checks approvals against fresh data,
/// stores idempotency keys (`<planId>:<stepId>`) and writes the history entry
/// from its own outcomes.
class RemotePlanGateway implements PlanGateway {
  RemotePlanGateway(this.api, {this.engine});

  final ApiClient api;

  /// Refreshed once after an execution (the plan endpoints do not return
  /// changed records).
  final SyncEngine? engine;

  Map<String, Object?> _body(String planId, List<PlanStep> steps) => {
    'planId': planId,
    'channel': 'agent',
    'steps': [
      for (final s in steps) {'stepId': s.stepId, 'actionId': s.action.descriptor.id, 'input': s.input.toJson()},
    ],
  };

  static AppFailure? _failure(Object? raw) {
    if (raw is! Map) return null;
    final code = FailureCode.values.where((c) => c.name == raw['code']).firstOrNull ?? FailureCode.unknown;
    final fields = raw['fieldErrors'];
    return AppFailure(
      code,
      raw['message']?.toString() ?? 'This could not be done.',
      fieldErrors: fields is Map ? {for (final e in fields.entries) e.key.toString(): e.value.toString()} : const {},
    );
  }

  static bool _transient(AppFailure f) => f.code == FailureCode.unavailable || (f.code == FailureCode.unknown && f.retryable);

  /// Plan calls are safe to repeat: previews write nothing, and an execution
  /// replays its stored results. One retry after a dropped connection.
  Future<Object?> _post(String path, Map<String, Object?> body) async {
    try {
      return await api.post(path, body: body);
    } on AppFailure catch (f) {
      if (!_transient(f)) rethrow;
      await Future<void>.delayed(const Duration(milliseconds: 600));
      return api.post(path, body: body);
    }
  }

  List<Map<String, Object?>> _steps(Object? data) {
    final steps = data is Map ? data['steps'] : null;
    if (steps is! List) throw const AppFailure(FailureCode.unknown, 'Unexpected reply from FiNN.', retryable: true);
    return [for (final s in steps.whereType<Map>()) Map<String, Object?>.from(s)];
  }

  @override
  Future<List<StepPreview>> preview(String planId, List<PlanStep> steps) async {
    final List<Map<String, Object?>> reports;
    try {
      reports = _steps(await _post('/plans/preview', _body(planId, steps)));
    } on AppFailure catch (f) {
      return [for (final s in steps) StepPreview(s.stepId, failure: f)];
    }
    final byId = {for (final r in reports) r['stepId']: r};
    return [
      for (final s in steps)
        switch (byId[s.stepId]) {
          final r? when r['status'] == 'ready' && r['preview'] is Map => StepPreview(
            s.stepId,
            preview: actionPreviewFromJson(Map<String, Object?>.from(r['preview'] as Map)),
          ),
          final r => StepPreview(
            s.stepId,
            failure: _failure(r?['failure']) ?? const AppFailure(FailureCode.unknown, 'This could not be checked.'),
          ),
        },
    ];
  }

  @override
  Future<List<StepResult>> execute(
    String planId,
    List<PlanStep> steps, {
    required Map<String, String> approved,
    HistoryWrite? history,
  }) async {
    final body = {
      ..._body(planId, steps),
      'approvedFingerprints': approved.values.toList(),
      'stopOnFailure': false,
      if (history != null)
        'history': {
          'runId': history.runId,
          'request': history.request,
          if (history.notes.isNotEmpty) 'notes': history.notes.take(10).toList(),
          'labels': {for (final s in steps) if (s.label != null) s.stepId: s.label},
        },
    };
    final List<Map<String, Object?>> reports;
    try {
      reports = _steps(await _post('/plans/execute', body));
    } on AppFailure catch (f) {
      // The reply was lost: approved steps may or may not have run. Repeating
      // the same request later replays them instead of writing twice.
      return [
        for (final s in steps)
          approved.containsKey(s.stepId)
              ? StepResult(s.stepId, ActionResultStatus.failed, message: f.message, outcomeUnknown: _transient(f))
              : StepResult(s.stepId, ActionResultStatus.declined),
      ];
    }
    unawaited(engine?.sync().catchError((Object e) => debugPrint('Sync after agent plan failed: $e')));
    final byId = {for (final r in reports) r['stepId']: r};
    return [
      for (final s in steps)
        switch (byId[s.stepId]) {
          final r? when r['status'] == 'succeeded' => StepResult(
            s.stepId,
            r['replayed'] == true ? ActionResultStatus.alreadyDone : ActionResultStatus.completed,
            message: r['replayed'] == true ? 'This had already been recorded; it was not added twice.' : null,
            recordId: recordIdOf(r['result']),
          ),
          final r? when r['status'] == 'skipped' => StepResult(
            s.stepId,
            ActionResultStatus.skipped,
            message: 'Skipped because a change it depends on was not saved.',
          ),
          final r? when r['status'] == 'notApproved' && r['failure'] != null => StepResult(
            s.stepId,
            ActionResultStatus.needsReapproval,
            message: 'The details changed after you reviewed them, so nothing was changed.',
          ),
          final r? when r['status'] == 'notApproved' => StepResult(s.stepId, ActionResultStatus.declined),
          final r => StepResult(
            s.stepId,
            ActionResultStatus.failed,
            message: _failure(r?['failure'])?.message ?? 'This could not be saved.',
          ),
        },
    ];
  }
}
