import '../core/result/result.dart';
import 'action.dart';

/// Authorization boundary between interaction channels and operations.
abstract interface class ActionPolicy {
  /// Returns a failure when [channel] may not run [action] at all.
  AppFailure? check(ActionDescriptor action, ActionChannel channel);

  /// Whether [channel] must obtain confirmation even for low-risk actions.
  bool requiresConfirmation(ActionDescriptor action, ActionChannel channel);
}

/// Default rules:
/// * UI may run everything (consequential actions still need a reviewed
///   confirmation via their preview).
/// * Agent/voice channels must confirm *every* action, and may never
///   delete records (deletion stays a deliberate in-app choice).
/// * Imports may only create.
class DefaultActionPolicy implements ActionPolicy {
  const DefaultActionPolicy();

  @override
  AppFailure? check(ActionDescriptor action, ActionChannel channel) {
    final isDelete = action.id.endsWith('.delete');
    switch (channel) {
      case ActionChannel.agent || ActionChannel.voice:
        if (isDelete) {
          return const AppFailure(FailureCode.notPermitted, 'Deleting records is only possible from within the app.');
        }
      case ActionChannel.import:
        if (!action.id.endsWith('.create')) {
          return const AppFailure(FailureCode.notPermitted, 'Imports can only create new records.');
        }
      case ActionChannel.ui || ActionChannel.system:
        break;
    }
    return null;
  }

  @override
  bool requiresConfirmation(ActionDescriptor action, ActionChannel channel) =>
      channel == ActionChannel.agent || channel == ActionChannel.voice;
}
