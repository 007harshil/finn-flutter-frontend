import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../design_system/design_system.dart';
import '../../application/agent_controller.dart';
import '../../execution/proposals.dart';
import '../../orchestration/agent_runner.dart';

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
                FinnDivider(),
                const SizedBox(height: Space.x2),
                for (final a in entry.actions) ActionOutcomeRow(record: a),
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

/// One action and what actually happened to it.
class ActionOutcomeRow extends StatelessWidget {
  const ActionOutcomeRow({super.key, required this.record});
  final ActionRecord record;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final (IconData icon, Color color, String label) = switch (record.status) {
      ActionResultStatus.completed => (LucideIcons.circleCheck, c.positive, 'Saved'),
      ActionResultStatus.alreadyDone => (LucideIcons.circleCheck, c.positive, 'Already saved'),
      ActionResultStatus.declined => (LucideIcons.circleX, c.textTertiary, 'Not approved'),
      ActionResultStatus.cancelled => (LucideIcons.circleStop, c.textTertiary, 'Stopped'),
      ActionResultStatus.needsReapproval => (LucideIcons.circleAlert, c.warning, 'Needs review again'),
      ActionResultStatus.failed when record.outcomeUnknown => (LucideIcons.circleHelp, c.warning, 'Not confirmed'),
      ActionResultStatus.failed => (LucideIcons.circleX, c.negative, 'Failed'),
    };
    return Semantics(
      label: '$label: ${record.summary}${record.message == null ? '' : '. ${record.message}'}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.x1),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: Space.x2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(record.summary, style: t.bodyStrong),
                  Text(
                    record.message == null ? label : '$label · ${record.message}',
                    style: t.caption.copyWith(color: c.textSecondary),
                  ),
                ],
              ),
            ),
          ],
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
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: c.primary),
          ),
          const SizedBox(width: Space.x2),
          Flexible(child: Text(label, style: context.text.caption.copyWith(color: c.textSecondary))),
        ],
      ),
    );
  }
}
