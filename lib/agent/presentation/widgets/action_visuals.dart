import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// How an action is drawn in the agent's review and summary panels.
@immutable
class ActionVisual {
  const ActionVisual({required this.icon, required this.module, required this.verb});

  final IconData icon;

  /// Module name for people, e.g. "Goals".
  final String module;

  /// What kind of change, e.g. "New", "Edit", "Payment".
  final String verb;
}

/// Visual for an action id such as `transactions.create`.
ActionVisual actionVisualFor(String actionId) {
  final dot = actionId.indexOf('.');
  final module = dot < 0 ? actionId : actionId.substring(0, dot);
  final op = dot < 0 ? '' : actionId.substring(dot + 1);
  final (IconData icon, String name) = switch (module) {
    'transactions' => (LucideIcons.arrowLeftRight, 'Transactions'),
    'budgets' => (LucideIcons.chartPie, 'Budgets'),
    'goals' => (LucideIcons.target, 'Goals'),
    'emergencyFund' => (LucideIcons.shieldPlus, 'Emergency fund'),
    'loans' => (LucideIcons.landmark, 'Loans'),
    'subscriptions' => (LucideIcons.repeat, 'Subscriptions'),
    'pending' => (LucideIcons.handCoins, 'Pending'),
    'categories' => (LucideIcons.tag, 'Categories'),
    _ => (LucideIcons.circleDot, 'FiNN'),
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
  return ActionVisual(icon: icon, module: name, verb: verb);
}
