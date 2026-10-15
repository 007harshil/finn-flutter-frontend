import 'package:flutter/material.dart';

import '../../../kit/kit.dart';

/// What the agent is busy with while nothing waits on the user.
enum AgentWork {
  /// Reading the request and planning (waiting for the model).
  understanding,

  /// Checking the plan against the user's data and previewing changes.
  preparing,

  /// Writing approved changes.
  saving,

  /// Closing a review where nothing was approved.
  wrappingUp,

  /// Regenerating a declined change.
  regenerating,
}

/// The agent at work: one quiet line saying what is happening over a thin
/// progress bar. Shown in the transcript whenever the agent is busy and
/// nothing waits on the user.
class AgentWorking extends StatelessWidget {
  const AgentWorking({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    return Semantics(
      liveRegion: true,
      label: label,
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Sp.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AnimatedSwitcher(
              duration: context.motion.fast,
              layoutBuilder: (current, previous) =>
                  Stack(alignment: Alignment.centerLeft, children: [...previous, ?current]),
              child: Text(label, key: ValueKey(label), maxLines: 2, overflow: TextOverflow.ellipsis, style: t.label),
            ),
            const SizedBox(height: Sp.sm),
            const AgentProgressLine(),
          ],
        ),
      ),
    );
  }
}

/// Thin indeterminate progress line in ink on the sunken track. Reduced
/// motion shows the track only.
class AgentProgressLine extends StatelessWidget {
  const AgentProgressLine({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    return ClipRRect(
      borderRadius: Rad.pill,
      child: context.reduceMotion
          ? Container(height: 3, color: c.sunken)
          : LinearProgressIndicator(minHeight: 3, color: c.ink, backgroundColor: c.sunken),
    );
  }
}
