import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../design_system/design_system.dart';

/// How an action is drawn in the agent's review and summary panels.
@immutable
class ActionVisual {
  const ActionVisual({required this.icon, required this.color, required this.module, required this.verb});

  final IconData icon;
  final Color color;

  /// Module name for people, e.g. "Goals".
  final String module;

  /// What kind of change, e.g. "New", "Edit", "Payment".
  final String verb;
}

/// Visual for an action id such as `transactions.create`.
ActionVisual actionVisualFor(String actionId, FinnColors c) {
  final dot = actionId.indexOf('.');
  final module = dot < 0 ? actionId : actionId.substring(0, dot);
  final op = dot < 0 ? '' : actionId.substring(dot + 1);
  final (IconData icon, Color color, String name) = switch (module) {
    'transactions' => (LucideIcons.arrowLeftRight, c.accentTransactions, 'Transactions'),
    'budgets' => (LucideIcons.chartPie, c.accentBudgets, 'Budgets'),
    'goals' => (LucideIcons.target, c.accentGoals, 'Goals'),
    'emergencyFund' => (LucideIcons.shieldPlus, c.accentEmergency, 'Emergency fund'),
    'loans' => (LucideIcons.landmark, c.accentLoans, 'Loans'),
    'subscriptions' => (LucideIcons.repeat, c.accentSubscriptions, 'Subscriptions'),
    'pending' => (LucideIcons.handCoins, c.accentPending, 'Pending'),
    'categories' => (LucideIcons.tag, c.accentNetWorth, 'Categories'),
    _ => (LucideIcons.circleDot, c.textSecondary, 'FiNN'),
  };
  final verb = switch (op) {
    'create' => 'New',
    'update' => 'Edit',
    'settle' => 'Settle',
    'split' => 'Split',
    'cancel' => 'Write off',
    'contribute' => 'Add money',
    'withdraw' => 'Withdraw',
    'recordPayment' => 'Payment',
    'setPaused' => 'Pause / resume',
    'setStatus' => 'Status',
    'markPaid' => 'Mark paid',
    'skipCycle' => 'Skip cycle',
    'configure' => 'Set up',
    'toggleArchive' => 'Archive',
    'delete' => 'Delete',
    _ => 'Change',
  };
  return ActionVisual(icon: icon, color: color, module: name, verb: verb);
}

/// Rounded module icon tile.
class ActionIconBadge extends StatelessWidget {
  const ActionIconBadge({super.key, required this.visual, this.size = 36});

  final ActionVisual visual;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: visual.color.withValues(alpha: context.colors.isDark ? 0.22 : 0.12),
        borderRadius: BorderRadius.circular(Radii.lg),
      ),
      child: Icon(visual.icon, size: size * 0.5, color: visual.color),
    );
  }
}
