import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../design_system/design_system.dart';
import '../../execution/proposals.dart';
import 'action_visuals.dart';

/// Final summary of a turn's changes: how many were saved, a status bar per
/// change and a row for each with what actually happened. Built from the
/// dispatcher's outcomes only.
class OutcomeSummary extends StatelessWidget {
  const OutcomeSummary({super.key, required this.actions});

  final List<ActionRecord> actions;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final saved = actions.where((a) => a.succeeded).length;
    final total = actions.length;
    final allSaved = saved == total;
    final (IconData icon, Color color, String title) = switch (saved) {
      0 => (LucideIcons.circleSlash, c.textSecondary, 'No changes made'),
      _ when allSaved => (LucideIcons.badgeCheck, c.positive, total == 1 ? 'Change saved' : 'All $total changes saved'),
      _ => (LucideIcons.circleAlert, c.warning, '$saved of $total changes saved'),
    };

    return Semantics(
      container: true,
      label: title,
      child: Container(
        padding: const EdgeInsets.all(Space.x3),
        decoration: BoxDecoration(
          color: c.surfaceMuted,
          borderRadius: BorderRadius.circular(Radii.xl),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: color),
                const SizedBox(width: Space.x2),
                Expanded(child: Text(title, style: t.bodyStrong)),
              ],
            ),
            const SizedBox(height: Space.x2),
            // One segment per change, coloured by its outcome.
            Row(
              children: [
                for (var i = 0; i < total; i++) ...[
                  if (i > 0) const SizedBox(width: 3),
                  Expanded(
                    child: Container(
                      height: 6,
                      decoration: BoxDecoration(
                        color: _statusOf(actions[i], c).$2,
                        borderRadius: BorderRadius.circular(Radii.full),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: Space.x3),
            for (final a in actions) ActionOutcomeRow(record: a),
          ],
        ),
      ),
    );
  }
}

(IconData, Color, String) _statusOf(ActionRecord record, FinnColors c) => switch (record.status) {
      ActionResultStatus.completed => (LucideIcons.circleCheck, c.positive, 'Saved'),
      ActionResultStatus.alreadyDone => (LucideIcons.circleCheck, c.positive, 'Already saved'),
      ActionResultStatus.declined => (LucideIcons.circleX, c.textTertiary, 'Not approved'),
      ActionResultStatus.cancelled => (LucideIcons.circleStop, c.textTertiary, 'Stopped'),
      ActionResultStatus.needsReapproval => (LucideIcons.circleAlert, c.warning, 'Needs review again'),
      ActionResultStatus.failed when record.outcomeUnknown => (LucideIcons.circleHelp, c.warning, 'Not confirmed'),
      ActionResultStatus.failed => (LucideIcons.circleX, c.negative, 'Failed'),
    };

/// One action and what actually happened to it.
class ActionOutcomeRow extends StatelessWidget {
  const ActionOutcomeRow({super.key, required this.record});
  final ActionRecord record;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final (icon, color, label) = _statusOf(record, c);
    final visual = actionVisualFor(record.proposal.descriptor.id, c);
    return Semantics(
      label: '$label: ${record.summary}${record.message == null ? '' : '. ${record.message}'}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.x1),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ActionIconBadge(visual: visual, size: 32),
            const SizedBox(width: Space.x2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(record.summary, style: t.bodyStrong),
                  const SizedBox(height: 2),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: Space.x1_5,
                    runSpacing: Space.x1,
                    children: [
                      StatusPill(label: label, color: color, icon: icon),
                      if (record.message != null)
                        Text(record.message!, style: t.caption.copyWith(color: c.textSecondary)),
                    ],
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
