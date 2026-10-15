import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../actions/action.dart';
import '../../actions/audit_log.dart';
import '../../actions/dispatcher.dart';
import '../../core/persistence/entity_collection.dart' show JsonMap;
import '../../core/result/result.dart';
import '../dto/dtos.dart';
import 'api_client.dart';
import 'sync_engine.dart';

/// Decodes an action's `result` JSON into the action's declared output.
typedef ActionResultDecoder = Object? Function(Object? json);

JsonMap _map(Object? json) {
  if (json is Map) return Map<String, Object?>.from(json);
  throw FormatException('Expected a record, got ${json.runtimeType}');
}

ActionResultDecoder _record<T>(T Function(JsonMap) decode) =>
    (json) => decode(_map(json));

/// Output decoders keyed by action id. Every action's `O` type
/// (`FinancialAction<I, O>`) is a record DTO, a list of them
/// (`pending.split`) or a single value (profile, emergency plan).
final Map<String, ActionResultDecoder> actionResultDecoders = {
  for (final id in ['transactions.create', 'transactions.update', 'transactions.delete', 'subscriptions.markPaid'])
    id: _record(TransactionDto.fromJson),
  for (final id in ['categories.create', 'categories.update', 'categories.toggleArchive', 'categories.delete'])
    id: _record(CategoryDto.fromJson),
  for (final id in ['budgets.create', 'budgets.update', 'budgets.setPaused', 'budgets.delete'])
    id: _record(BudgetDto.fromJson),
  for (final id in ['pending.create', 'pending.update', 'pending.cancel', 'pending.delete'])
    id: _record(PendingDto.fromJson),
  'pending.split': (json) {
    final list = json is Map ? (json['items'] ?? json['pending'] ?? json['upserted']) : json;
    if (list is! List) throw FormatException('Expected a list, got ${list.runtimeType}');
    return [for (final item in list) PendingDto.fromJson(_map(item))];
  },
  'pending.settle': _record(SettlementDto.fromJson),
  for (final id in ['loans.create', 'loans.update', 'loans.delete']) id: _record(LoanDto.fromJson),
  'loans.recordPayment': _record(LoanPaymentDto.fromJson),
  for (final id in [
    'subscriptions.create',
    'subscriptions.update',
    'subscriptions.setStatus',
    'subscriptions.skipCycle',
    'subscriptions.delete',
  ])
    id: _record(SubscriptionDto.fromJson),
  for (final id in ['goals.create', 'goals.update', 'goals.toggleArchive', 'goals.delete'])
    id: _record(GoalDto.fromJson),
  for (final id in ['goals.contribute', 'goals.withdraw', 'emergencyFund.contribute', 'emergencyFund.withdraw'])
    id: _record(SavingsMovementDto.fromJson),
  'emergencyFund.configure': (json) {
    final j = _map(json);
    final plan = EmergencyPlanDto.fromJson(j.containsKey('configured') ? j : {...j, 'configured': true});
    if (plan == null) throw const FormatException('Emergency plan is not configured');
    return plan;
  },
  for (final id in ['assets.create', 'assets.update', 'assets.delete']) id: _record(AssetDto.fromJson),
  for (final id in [
    'accounts.create',
    'accounts.update',
    'accounts.setBalance',
    'accounts.setDefault',
    'accounts.archive',
    'accounts.delete',
  ])
    id: _record(MoneyAccountDto.fromJson),
  for (final id in ['transfers.create', 'transfers.update', 'transfers.delete']) id: _record(TransferDto.fromJson),
  'profile.update': (json) {
    final j = _map(json);
    final profile = ProfileDto.fromJson(j.containsKey('exists') ? j : {...j, 'exists': true});
    if (profile == null) throw const FormatException('Profile does not exist');
    return profile;
  },
};

/// Decodes the server's preview JSON.
ActionPreview actionPreviewFromJson(JsonMap j) => ActionPreview(
  actionId: j['actionId'] as String? ?? '',
  title: j['title'] as String? ?? '',
  summary: j['summary'] as String? ?? '',
  lines: [
    for (final l in (j['lines'] as List? ?? const []).whereType<Map>())
      PreviewLine(l['label']?.toString() ?? '', l['value']?.toString() ?? '', emphasis: l['emphasis'] == true),
  ],
  warnings: [for (final w in (j['warnings'] as List? ?? const [])) w.toString()],
  fingerprint: j['fingerprint'] as String? ?? '',
  requiresConfirmation: j['requiresConfirmation'] == true,
);

/// [OperationDispatcher] backed by the FiNN API. Validation, confirmation
/// fingerprints, idempotency, policy and audit are enforced by the server;
/// this class translates the HTTP contract into the same [ActionOutcome]s
/// so `runAction(...)`, the review sheet and plans work unchanged.
class RemoteOperationDispatcher extends OperationDispatcher {
  RemoteOperationDispatcher({
    required super.environment,
    required this.api,
    required this.engine,
    super.policy,
    super.audit,
    Map<String, ActionResultDecoder>? decoders,
  }) : decoders = decoders ?? actionResultDecoders;

  final ApiClient api;
  final SyncEngine engine;
  final Map<String, ActionResultDecoder> decoders;

  final Set<String> _inFlight = {};

  @override
  Future<Result<ActionPreview>> preview<I extends ActionInput, O>(
    FinancialAction<I, O> action,
    I input, {
    ActionChannel channel = ActionChannel.ui,
  }) async {
    final decision = policy.check(action.descriptor, channel);
    if (decision != null) return Result.err(decision);
    try {
      final data = await api.post(
        '/actions/${action.descriptor.id}/preview',
        body: {'input': input.toJson(), 'channel': channel.name},
      );
      final preview = data is Map ? data['preview'] : null;
      if (preview is! Map) throw const FormatException('Missing preview');
      return Result.ok(actionPreviewFromJson(Map<String, Object?>.from(preview)));
    } on AppFailure catch (f) {
      return Result.err(f);
    } catch (e) {
      debugPrint('Preview ${action.descriptor.id} failed: $e');
      return Result.err(
        const AppFailure(FailureCode.unknown, 'Something went wrong. Please try again.', retryable: true),
      );
    }
  }

  @override
  Future<ActionOutcome<O>> dispatch<I extends ActionInput, O>(
    FinancialAction<I, O> action,
    I input, {
    required String idempotencyKey,
    ActionConfirmation? confirmation,
    ActionChannel channel = ActionChannel.ui,
  }) async {
    final id = action.descriptor.id;
    final decision = policy.check(action.descriptor, channel);
    if (decision != null) return ActionRejected(decision);
    if (!_inFlight.add(idempotencyKey)) {
      return const ActionRejected(AppFailure(FailureCode.duplicate, 'This is already being processed.'));
    }
    try {
      final data = await api.post(
        '/actions/$id',
        headers: {'Idempotency-Key': idempotencyKey},
        body: {
          'input': input.toJson(),
          'confirmation': confirmation == null
              ? null
              : {'fingerprint': confirmation.fingerprint, 'confirmedBy': confirmation.confirmedBy},
          'channel': channel.name,
        },
      );
      if (data is! Map) throw const FormatException('Unexpected action response');
      final previewJson = data['preview'];
      final preview = previewJson is Map ? actionPreviewFromJson(Map<String, Object?>.from(previewJson)) : null;

      switch (data['status']) {
        case 'needsConfirmation':
          if (preview == null) throw const FormatException('Missing preview');
          return ActionNeedsConfirmation(preview);
        case 'completed':
          final changes = data['changes'];
          if (changes is Map) engine.applyChanges(Map<String, Object?>.from(changes));
          unawaited(engine.sync().catchError((Object e) => debugPrint('Sync after $id failed: $e')));
          final O value;
          try {
            value = _decode<O>(id, data['result']);
          } catch (e) {
            debugPrint('Could not decode the result of $id: $e');
            return const ActionRejected(
              AppFailure(
                FailureCode.unknown,
                'Your change was saved, but the app could not read the reply. It will appear after the next refresh.',
              ),
            );
          }
          return ActionCompleted(
            value,
            preview ??
                ActionPreview(
                  actionId: id,
                  title: '',
                  summary: '',
                  lines: const [],
                  fingerprint: '',
                  requiresConfirmation: false,
                ),
            replayed: data['replayed'] == true,
          );
        default:
          throw FormatException('Unknown action status ${data['status']}');
      }
    } on AppFailure catch (f) {
      return ActionRejected(f);
    } catch (e, st) {
      debugPrint('Action $id failed: $e\n$st');
      return ActionRejected(
        AppFailure(FailureCode.unknown, 'Something went wrong. Please try again.', cause: e, retryable: true),
      );
    } finally {
      _inFlight.remove(idempotencyKey);
    }
  }

  O _decode<O>(String id, Object? json) {
    final decoder = decoders[id];
    final value = decoder == null ? json : decoder(json);
    return value as O;
  }
}

/// Activity log from `GET /audit` (newest first).
Future<List<AuditEntry>> fetchRemoteAudit(ApiClient api, {int limit = 100}) async {
  final data = await api.get('/audit', query: {'limit': '$limit'});
  final items = data is Map ? data['items'] : null;
  if (items is! List) return const [];
  return [
    for (final raw in items.whereType<Map>())
      AuditEntry(
        actionId: raw['actionId']?.toString() ?? '',
        summary: raw['summary']?.toString() ?? '',
        channel: ActionChannel.values.where((c) => c.name == raw['channel']).firstOrNull ?? ActionChannel.ui,
        at: (DateTime.tryParse(raw['at']?.toString() ?? '') ?? DateTime.now()).toLocal(),
        succeeded: raw['succeeded'] == true,
        confirmedBy: raw['confirmedBy'] as String?,
        failure: raw['failure'] is Map ? (raw['failure'] as Map)['message']?.toString() : null,
      ),
  ];
}

/// Audit entries, refreshed whenever synced data changes.
Stream<List<AuditEntry>> watchRemoteAudit(ApiClient api, SyncEngine engine) async* {
  yield await fetchRemoteAudit(api);
  await for (final _ in engine.changes) {
    try {
      yield await fetchRemoteAudit(api);
    } catch (e) {
      debugPrint('Could not refresh the activity log: $e');
    }
  }
}
