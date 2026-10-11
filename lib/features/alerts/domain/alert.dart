import 'package:flutter/foundation.dart';

import '../../../core/money/money.dart';

enum AlertType {
  emiDue('Upcoming EMI'),
  emiOverdue('Overdue EMI'),
  pendingOverdue('Pending payment'),
  collectDue('Money to collect'),
  subscriptionRenewal('Subscription renewal'),
  subscriptionOverdue('Unpaid subscription'),
  budgetNearLimit('Budget near limit'),
  budgetBreached('Budget exceeded'),
  emergencyFundLow('Low emergency fund'),
  emergencyFundNotSet('Emergency fund not set'),
  goalMilestone('Goal milestone'),
  goalAtRisk('Goal behind schedule'),
  monthlyDeficit('Spending above income');

  const AlertType(this.label);
  final String label;
}

enum AlertSeverity {
  critical(0, 'Urgent'),
  warning(1, 'Soon'),
  info(2, 'FYI'),
  positive(3, 'Good news');

  const AlertSeverity(this.rank, this.label);

  /// Lower ranks are more urgent.
  final int rank;
  final String label;
}

/// Kind of record an alert points to (used to build a deep link).
enum AlertTarget { loan, pending, subscription, budget, emergencyFund, goal, transactions }

/// An actionable item for the "What needs attention" list.
///
/// [key] is deterministic (type + record + period) so read/dismissed state
/// survives regeneration and the same alert is never shown twice.
@immutable
class FinancialAlert {
  const FinancialAlert({
    required this.key,
    required this.type,
    required this.severity,
    required this.title,
    required this.message,
    required this.reason,
    required this.actionLabel,
    required this.target,
    this.recordId,
    this.dueDate,
    this.amount,
    this.dismissible = true,
    this.visual,
  });

  final String key;
  final AlertType type;
  final AlertSeverity severity;

  /// What is happening.
  final String title;

  /// Details with numbers.
  final String message;

  /// Why it matters.
  final String reason;

  /// What the user can do next (button label).
  final String actionLabel;
  final AlertTarget target;
  final String? recordId;
  final DateTime? dueDate;
  final Money? amount;
  final bool dismissible;

  /// Numbers behind the alert, for drawing it as a picture rather than text.
  final AlertVisual? visual;

  @override
  bool operator ==(Object other) =>
      other is FinancialAlert &&
      other.key == key &&
      other.title == title &&
      other.message == message &&
      other.severity == severity;

  @override
  int get hashCode => Object.hash(key, title, message, severity);
}

/// Structured figures behind an alert, so the UI can show it as a picture
/// (a calendar, a gauge, a filling shield) instead of sentences.
@immutable
sealed class AlertVisual {
  const AlertVisual();
}

/// Who is on the other side of a payment.
enum DueParty { bank, person, service }

/// Money that has to move on a date: an EMI, a pending payment, a renewal.
class DueVisual extends AlertVisual {
  const DueVisual({
    required this.outgoing,
    required this.party,
    required this.counterparty,
    required this.daysUntil,
    this.recurring = false,
  });

  /// True when the user pays; false when the user receives.
  final bool outgoing;
  final DueParty party;
  final String counterparty;

  /// Days until the due date; negative when late.
  final int daysUntil;

  /// A renewal that repeats (subscriptions).
  final bool recurring;

  bool get isLate => daysUntil < 0;
}

/// Money still unsettled with someone, open for [daysOpen] days.
class AgedVisual extends AlertVisual {
  const AgedVisual({required this.counterparty, required this.daysOpen, this.outgoing = false});

  final String counterparty;
  final int daysOpen;

  /// True when the user owes; false when the user is owed.
  final bool outgoing;
}

/// A category budget filling up.
class BudgetVisual extends AlertVisual {
  const BudgetVisual({required this.category, required this.spent, required this.limit, required this.daysLeft});

  final String category;
  final Money spent;
  final Money limit;
  final int daysLeft;

  /// Spent ÷ limit (1.0 = at the limit).
  double get fraction => limit.paise <= 0 ? 1 : spent.paise / limit.paise;
  bool get isOver => spent > limit;
  Money get left => limit - spent;
}

/// Emergency-fund safety net; [target] is null when not set up.
class SafetyNetVisual extends AlertVisual {
  const SafetyNetVisual({this.saved, this.target, this.coverageMonths, this.targetMonths});

  final Money? saved;
  final Money? target;
  final double? coverageMonths;
  final int? targetMonths;

  bool get isConfigured => target != null;
  double get fraction {
    final s = saved, t = target;
    if (s == null || t == null || t.paise <= 0) return 0;
    return (s.paise / t.paise).clamp(0.0, 1.0);
  }
}

/// A savings goal: reached, nearly there, or falling behind.
class GoalVisual extends AlertVisual {
  const GoalVisual({
    required this.name,
    required this.saved,
    required this.target,
    this.requiredMonthly,
    this.targetDate,
  });

  final String name;
  final Money saved;
  final Money target;

  /// Monthly amount needed to finish on time (set when behind schedule).
  final Money? requiredMonthly;
  final DateTime? targetDate;

  double get fraction => target.paise <= 0 ? 1 : (saved.paise / target.paise).clamp(0.0, 1.0);
  bool get isReached => saved >= target;
  bool get isBehind => requiredMonthly != null;
}

/// Month-to-date money in versus money out.
class CashFlowVisual extends AlertVisual {
  const CashFlowVisual({required this.income, required this.expense});

  final Money income;
  final Money expense;

  Money get gap => expense - income;
}

/// Read/dismissed bookkeeping for alerts.
@immutable
class AlertInboxState {
  const AlertInboxState({this.readKeys = const {}, this.dismissedKeys = const {}});

  final Set<String> readKeys;
  final Set<String> dismissedKeys;

  AlertInboxState copyWith({Set<String>? readKeys, Set<String>? dismissedKeys}) =>
      AlertInboxState(readKeys: readKeys ?? this.readKeys, dismissedKeys: dismissedKeys ?? this.dismissedKeys);

  @override
  bool operator ==(Object other) =>
      other is AlertInboxState && setEquals(other.readKeys, readKeys) && setEquals(other.dismissedKeys, dismissedKeys);

  @override
  int get hashCode => Object.hash(readKeys.length, dismissedKeys.length);
}
