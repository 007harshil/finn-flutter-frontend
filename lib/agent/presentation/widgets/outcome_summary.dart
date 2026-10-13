import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/router/routes.dart';
import '../../../design_system/design_system.dart';
import '../../execution/proposals.dart';
import 'action_visuals.dart';

/// Final summary of a turn's changes: how many were saved, a status bar per
/// change and a row for each with what actually happened. Built from the
/// dispatcher's outcomes only. Saved changes link to their record when
/// [onOpen] is given.
class OutcomeSummary extends StatelessWidget {
  const OutcomeSummary({super.key, required this.actions, this.onOpen});

  final List<ActionRecord> actions;

  /// Opens an app location (see [actionRecordRoute]).
  final ValueChanged<String>? onOpen;

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
            for (final a in actions) ActionOutcomeRow(record: a, onOpen: onOpen),
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
      ActionResultStatus.skipped => (LucideIcons.circleMinus, c.textTertiary, 'Skipped'),
      ActionResultStatus.failed when record.outcomeUnknown => (LucideIcons.circleHelp, c.warning, 'Not confirmed'),
      ActionResultStatus.failed => (LucideIcons.circleX, c.negative, 'Failed'),
    };

/// Where to see the record a saved action created or changed, or null
/// (nothing to show, e.g. after a delete).
String? actionRecordRoute(ActionRecord record) {
  if (!record.succeeded) return null;
  final actionId = record.proposal.descriptor.id;
  final dot = actionId.indexOf('.');
  final module = dot < 0 ? actionId : actionId.substring(0, dot);
  final op = dot < 0 ? '' : actionId.substring(dot + 1);
  if (op == 'delete') return null;
  final json = record.proposal.input.toJson();
  // The target named in the input wins (a goal payment returns the
  // movement, not the goal); otherwise the record the action returned.
  final key = switch (module) {
    'goals' => 'goalId',
    'loans' => 'loanId',
    'pending' => 'pendingId',
    'subscriptions' => 'subscriptionId',
    _ => null,
  };
  final rid = record.recordId;
  final returned = rid is List ? (rid.isEmpty ? null : rid.first) : rid;
  final id = [if (key != null) json[key], json['id'], returned].whereType<String>().firstOrNull;
  return switch (module) {
    'transactions' when id != null => AppRoutes.transaction(id),
    'budgets' when id != null => AppRoutes.budget(id),
    'goals' when id != null => AppRoutes.goal(id),
    'loans' when id != null => AppRoutes.loan(id),
    'pending' when id != null => AppRoutes.pendingItem(id),
    'subscriptions' when id != null => AppRoutes.subscription(id),
    'emergencyFund' => AppRoutes.emergencyFund,
    'categories' => AppRoutes.categories,
    'assets' => AppRoutes.netWorth,
    'profile' => AppRoutes.profile,
    _ => null,
  };
}

/// One action and what actually happened to it.
class ActionOutcomeRow extends StatelessWidget {
  const ActionOutcomeRow({super.key, required this.record, this.onOpen});
  final ActionRecord record;
  final ValueChanged<String>? onOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final (icon, color, label) = _statusOf(record, c);
    final visual = actionVisualFor(record.proposal.descriptor.id, c);
    final route = actionRecordRoute(record);
    final open = onOpen;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.x1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Semantics(
              label: '$label: ${record.summary}${record.message == null ? '' : '. ${record.message}'}',
              excludeSemantics: true,
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
          ),
          if (route != null && open != null) ...[
            const SizedBox(width: Space.x2),
            _ViewLink(label: 'View ${visual.module.toLowerCase()} details', onTap: () => open(route)),
          ],
        ],
      ),
    );
  }
}

/// Small "View" pill that opens the saved record.
class _ViewLink extends StatelessWidget {
  const _ViewLink({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: PressableScale(
        onTap: onTap,
        scale: 0.94,
        child: Container(
          constraints: const BoxConstraints(minHeight: 32),
          padding: const EdgeInsets.symmetric(horizontal: Space.x2_5, vertical: Space.x1_5),
          decoration: BoxDecoration(
            color: c.info.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(Radii.full),
            border: Border.all(color: c.info.withValues(alpha: 0.35)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('View', style: context.text.caption.copyWith(color: c.info, fontWeight: FontWeight.w700)),
              const SizedBox(width: 2),
              Icon(LucideIcons.chevronRight, size: 14, color: c.info),
            ],
          ),
        ),
      ),
    );
  }
}
