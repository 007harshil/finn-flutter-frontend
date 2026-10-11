import 'package:flutter/foundation.dart';

import '../../../core/money/money.dart';
import '../../../core/time/dates.dart';

enum BudgetStatus { active, paused }

/// The limit a budget had up to and including [until] (a budget month,
/// keyed by the month its period starts in). Recorded when the limit is
/// edited so past months keep showing the limit that applied then.
@immutable
class BudgetLimitChange {
  const BudgetLimitChange({required this.until, required this.limit});

  final MonthKey until;
  final Money limit;

  @override
  bool operator ==(Object other) => other is BudgetLimitChange && other.until == until && other.limit == limit;

  @override
  int get hashCode => Object.hash(until, limit);
}

/// A monthly spending limit for one category. Budgets are always monthly:
/// a budget covers the whole month it is created in (whatever the day) and
/// renews every month. Spending is *never stored* on the budget: it is
/// derived from expenses in the category, so adding, editing or deleting an
/// expense updates the budget automatically.
@immutable
class Budget {
  const Budget({
    required this.id,
    required this.categoryId,
    required this.limit,
    required this.createdAt,
    required this.updatedAt,
    this.status = BudgetStatus.active,
    this.warningThresholdBps = 8000,
    this.note,
    this.previousLimits = const [],
    this.version = 1,
  });

  final String id;
  final String categoryId;

  /// The current limit (this month onwards).
  final Money limit;
  final BudgetStatus status;

  /// Utilisation (basis points) at which the budget enters "warning".
  final int warningThresholdBps;
  final String? note;

  /// Earlier limits, oldest first; see [limitFor].
  final List<BudgetLimitChange> previousLimits;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int version;

  bool get isPaused => status == BudgetStatus.paused;

  /// The limit that applied in budget month [month].
  Money limitFor(MonthKey month) {
    for (final c in previousLimits) {
      if (month <= c.until) return c.limit;
    }
    return limit;
  }

  Budget copyWith({
    String? categoryId,
    Money? limit,
    BudgetStatus? status,
    int? warningThresholdBps,
    String? Function()? note,
    List<BudgetLimitChange>? previousLimits,
    DateTime? updatedAt,
    int? version,
  }) =>
      Budget(
        id: id,
        categoryId: categoryId ?? this.categoryId,
        limit: limit ?? this.limit,
        status: status ?? this.status,
        warningThresholdBps: warningThresholdBps ?? this.warningThresholdBps,
        note: note != null ? note() : this.note,
        previousLimits: previousLimits ?? this.previousLimits,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        version: version ?? this.version,
      );

  @override
  bool operator ==(Object other) =>
      other is Budget && other.id == id && other.version == version && other.limit == limit && other.status == status;

  @override
  int get hashCode => Object.hash(id, version, limit, status);
}

enum BudgetHealth {
  healthy('On track'),
  warning('Near limit'),
  breached('Over limit'),
  paused('Paused');

  const BudgetHealth(this.label);
  final String label;
}

/// Derived view of a budget for one period.
@immutable
class BudgetUsage {
  const BudgetUsage({
    required this.budget,
    required this.period,
    required this.spent,
    required this.committed,
    required this.transactionIds,
    required this.health,
    required this.elapsedBps,
  });

  final Budget budget;
  final DateRange period;

  /// Actual completed spending in the period.
  final Money spent;

  /// Expected but not yet paid charges in the period (e.g. subscription
  /// renewals in this category). Shown separately — never added to [spent].
  final Money committed;
  final List<String> transactionIds;
  final BudgetHealth health;

  /// Share of the period already elapsed (basis points), for pacing.
  final int elapsedBps;

  Money get remaining => budget.limit - spent;
  Money get remainingAfterCommitted => budget.limit - spent - committed;

  /// Utilisation in basis points (0 when the limit is zero).
  int get utilizationBps => spent.ratioBps(budget.limit) ?? 0;

  double get utilization => utilizationBps / 10000.0;

  bool get isOver => spent > budget.limit;

  @override
  bool operator ==(Object other) =>
      other is BudgetUsage &&
      other.budget == budget &&
      other.period == period &&
      other.spent == spent &&
      other.committed == committed &&
      other.health == health &&
      listEquals(other.transactionIds, transactionIds);

  @override
  int get hashCode => Object.hash(budget, period, spent, committed, health);
}
