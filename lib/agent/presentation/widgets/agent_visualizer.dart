import 'package:flutter/material.dart';

import 'agent_logo.dart';

/// What the agent is doing; drives the status line of the experience.
enum AgentPresence { idle, listening, transcribing, thinking, reviewing, executing }

/// The agent's brand mark on the agent surface: the existing [AgentOrb],
/// untouched. It plays its short attention burst when it appears and again
/// when [pulse] changes (a new reply), then rests. Tapping it starts or
/// finishes voice input.
class AgentVisualizer extends StatelessWidget {
  const AgentVisualizer({
    super.key,
    required this.size,
    required this.presence,
    this.pulse = 0,
    this.onTap,
    this.semanticLabel,
  });

  final double size;
  final AgentPresence presence;

  /// Bumped when the agent answers: replays the orb's short burst.
  final int pulse;
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    Widget content = SizedBox.square(
      dimension: size < 48 ? 48 : size,
      child: Center(
        // Finite animation only: never `active`, never `listening`.
        child: AgentOrb(size: size, attentionKey: pulse, idleLoops: 1),
      ),
    );
    if (onTap != null) {
      content = GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: content);
    }
    return Semantics(button: onTap != null, label: semanticLabel, excludeSemantics: true, child: content);
  }
}
