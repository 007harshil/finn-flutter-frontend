import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../design_system/design_system.dart';
import '../../application/agent_controller.dart';
import '../../orchestration/agent_runner.dart';
import 'agent_logo.dart';
import 'outcome_summary.dart';

class UserBubble extends StatelessWidget {
  const UserBubble({super.key, required this.entry});
  final UserChatEntry entry;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: Space.x4, vertical: Space.x3),
          decoration: BoxDecoration(
            color: c.primary,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(Radii.lg),
              topRight: Radius.circular(Radii.lg),
              bottomLeft: Radius.circular(Radii.lg),
              bottomRight: Radius.circular(Radii.sm),
            ),
          ),
          child: SelectableText(entry.text, style: context.text.body.copyWith(color: c.onPrimary)),
        ),
      ),
    );
  }
}

/// The assistant's reply plus the confirmed outcome of each action.
class AgentBubble extends StatelessWidget {
  const AgentBubble({super.key, required this.entry, this.onRetry});
  final AgentChatEntry entry;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final failed = entry.end == AgentTurnEnd.failed;
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.88),
        child: Container(
          padding: const EdgeInsets.all(Space.x4),
          decoration: BoxDecoration(
            color: c.surface,
            border: Border.all(color: failed ? c.negative.withValues(alpha: 0.4) : c.border),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(Radii.lg),
              topRight: Radius.circular(Radii.lg),
              bottomLeft: Radius.circular(Radii.sm),
              bottomRight: Radius.circular(Radii.lg),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (failed)
                Padding(
                  padding: const EdgeInsets.only(bottom: Space.x2),
                  child: Row(children: [
                    Icon(LucideIcons.circleAlert, size: 16, color: c.negative),
                    const SizedBox(width: Space.x1),
                    Text('Could not finish', style: t.label.copyWith(color: c.negative)),
                  ]),
                ),
              SelectableText(entry.text, style: t.body),
              if (entry.actions.isNotEmpty) ...[
                const SizedBox(height: Space.x3),
                OutcomeSummary(actions: entry.actions),
              ],
              if (onRetry != null) ...[
                const SizedBox(height: Space.x3),
                FinnButton(
                  label: 'Try again',
                  icon: LucideIcons.rotateCcw,
                  size: FinnButtonSize.sm,
                  variant: FinnButtonVariant.outline,
                  onPressed: onRetry,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The assistant's description of its plan while the review card is open.
class AgentPlanBubble extends StatelessWidget {
  const AgentPlanBubble({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.88),
        child: Container(
          padding: const EdgeInsets.all(Space.x4),
          decoration: BoxDecoration(
            color: c.surface,
            border: Border.all(color: c.border),
            borderRadius: BorderRadius.circular(Radii.lg),
          ),
          child: SelectableText(text, style: context.text.body),
        ),
      ),
    );
  }
}

/// "Thinking…" / tool progress line.
class AgentProgress extends StatelessWidget {
  const AgentProgress({super.key, required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      liveRegion: true,
      label: label,
      child: Row(
        children: [
          const SizedBox.square(dimension: 22, child: AgentOrb(size: 22, active: true)),
          const SizedBox(width: Space.x2),
          Flexible(child: Text(label, style: context.text.caption.copyWith(color: c.textSecondary))),
        ],
      ),
    );
  }
}
