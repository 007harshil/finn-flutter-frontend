import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/application/auth_controller.dart';
import '../voice/voice_input_controller.dart';

/// Whether agent mode is on. While on, the rest of the app is locked behind
/// the agent panel so the only way to change records is through the agent's
/// reviewed proposals (or by closing agent mode).
final agentModeProvider = NotifierProvider<AgentModeController, bool>(AgentModeController.new);

class AgentModeController extends Notifier<bool> {
  @override
  bool build() {
    // Signing out or switching accounts always leaves agent mode.
    ref.watch(authControllerProvider.select((s) => s?.email));
    return false;
  }

  void open() => state = true;

  void close() {
    if (!state) return;
    state = false;
    // Never keep the microphone open behind a closed panel.
    ref.read(voiceInputProvider.notifier).cancel();
  }

  void toggle() => state ? close() : open();
}
