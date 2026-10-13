import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/router/routes.dart';
import '../../../ui/ui.dart';
import '../../execution/proposals.dart';

/// Icon, colour and label of what happened to an action.
(IconData, Color, String) actionStatusVisual(ActionRecord record, UiColors c) => switch (record.status) {
      ActionResultStatus.completed => (LucideIcons.circleCheck, c.positive, 'Saved'),
      ActionResultStatus.alreadyDone => (LucideIcons.circleCheck, c.positive, 'Already saved'),
      ActionResultStatus.declined => (LucideIcons.circleX, c.inkSoft, 'Not approved'),
      ActionResultStatus.cancelled => (LucideIcons.circleStop, c.inkSoft, 'Stopped'),
      ActionResultStatus.needsReapproval => (LucideIcons.circleAlert, c.warning, 'Needs review again'),
      ActionResultStatus.skipped => (LucideIcons.circleMinus, c.inkSoft, 'Skipped'),
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

/// Quiet "View" text action that opens the saved record; [label] is what
/// screen readers hear.
class RecordViewLink extends StatelessWidget {
  const RecordViewLink({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => UiTextButton(label: 'View', semanticLabel: label, onTap: onTap);
}
