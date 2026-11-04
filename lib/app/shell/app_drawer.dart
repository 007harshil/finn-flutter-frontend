import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../agent/agent.dart' show AgentOrb, voiceInputProvider, VoicePhase;
import '../../design_system/components/cards.dart' show PressableScale;
import '../../kit/kit.dart';

/// Lets screens inside the shell open the side drawer (Profile, Net worth,
/// Subscriptions, Settings…) and the FiNN agent from their headers.
/// Provided by the app shell; screens built without it simply show no
/// menu or agent button.
class AppDrawerScope extends InheritedWidget {
  const AppDrawerScope({super.key, required this.open, this.openAgent, required super.child});

  final VoidCallback open;

  /// Toggles full-screen agent mode.
  final VoidCallback? openAgent;

  static VoidCallback? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppDrawerScope>()?.open;

  static VoidCallback? agentOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppDrawerScope>()?.openAgent;

  @override
  bool updateShouldNotify(AppDrawerScope oldWidget) => oldWidget.open != open || oldWidget.openAgent != openAgent;
}

/// The "menu" button that opens the side drawer from a tab's header.
/// Prefer [LedgerMenuButton]; kept for existing callers.
class AppMenuButton extends StatelessWidget {
  const AppMenuButton({super.key});

  @override
  Widget build(BuildContext context) => const LedgerMenuButton();
}

/// The FiNN mark in a tab's header: opens the agent. Renders nothing
/// outside the app shell.
class AppAgentButton extends ConsumerWidget {
  const AppAgentButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final open = AppDrawerScope.agentOf(context);
    if (open == null) return const SizedBox.shrink();
    final listening = ref.watch(voiceInputProvider.select((v) => v.phase == VoicePhase.listening));
    return Tooltip(
      message: 'FiNN Agent',
      child: Semantics(
        button: true,
        label: 'FiNN Agent',
        excludeSemantics: true,
        child: PressableScale(
          onTap: open,
          scale: 0.9,
          child: SizedBox.square(
            dimension: 44,
            child: Center(child: AgentOrb(size: 34, listening: listening)),
          ),
        ),
      ),
    );
  }
}
