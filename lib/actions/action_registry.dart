import '../core/result/result.dart';
import 'action.dart';
import 'dispatcher.dart';

/// Discoverable catalogue of every supported operation. Future channels
/// (natural language, voice, automation) look up actions here by id and
/// read their descriptors to know which inputs are required.
class ActionRegistry {
  ActionRegistry(Iterable<FinancialAction<ActionInput, Object?>> actions) {
    for (final a in actions) {
      final id = a.descriptor.id;
      if (_actions.containsKey(id)) throw StateError('Duplicate action id $id');
      _actions[id] = a;
    }
  }

  final Map<String, FinancialAction<ActionInput, Object?>> _actions = {};

  List<ActionDescriptor> get descriptors => _actions.values.map((a) => a.descriptor).toList();

  FinancialAction<ActionInput, Object?>? lookup(String id) => _actions[id];

  /// Machine-readable catalogue (e.g. to give a language model tool specs).
  List<Map<String, Object?>> describe() => descriptors.map((d) => d.toJson()).toList();

  /// Decodes untrusted JSON input for [actionId].
  Result<ActionInput> decode(String actionId, Map<String, Object?> json) {
    final action = _actions[actionId];
    if (action == null) {
      return Result.err(AppFailure(FailureCode.notFound, 'Unknown operation "$actionId".'));
    }
    try {
      return Result.ok(action.decode(json));
    } on AppFailure catch (f) {
      return Result.err(f);
    }
  }

  /// Decode + dispatch in one call (used by plan execution).
  Future<ActionOutcome<Object?>> dispatchJson(
    OperationDispatcher dispatcher,
    String actionId,
    Map<String, Object?> json, {
    required String idempotencyKey,
    ActionConfirmation? confirmation,
    ActionChannel channel = ActionChannel.agent,
  }) async {
    final action = _actions[actionId];
    final decoded = decode(actionId, json);
    if (action == null || decoded is Err<ActionInput>) {
      return ActionRejected(decoded.failureOrNull!);
    }
    return dispatcher.dispatch<ActionInput, Object?>(
      action,
      (decoded as Ok<ActionInput>).value,
      idempotencyKey: idempotencyKey,
      confirmation: confirmation,
      channel: channel,
    );
  }
}
