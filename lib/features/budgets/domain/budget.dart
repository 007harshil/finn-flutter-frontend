import 'package:flutter/foundation.dart';

import '../../../core/money/money.dart';
import '../../../core/time/dates.dart';

enum BudgetPeriodType {
  /// Repeats every calendar month (respecting the user's month start day).
  monthly('Monthly'),

  /// A single explicit date range.
  custom('Custom period');

  const BudgetPeriodType(this.label);
  final String label;
}

enum BudgetStatus { active, paused }

/// A spending limit for one category. Spending is *never stored* on the
/// budget: it is always derived from eligible transactions, so edits,
/// deletions and re-categorisation are reflected automatically.
@immutable
class Budget {
  const Budget({
    required this.id,
    required this.categoryId,
    required this.limit,
    required this.periodType,
    required this.createdAt,
    required this.updatedAt,
    this.customRange,
    this.status = BudgetStatus.active,
    this.warningThresholdBps = 8000,
    this.note,
    this.version = 1,
  });

  final String id;
  final String categoryId;
  final Money limit;
  final BudgetPeriodType periodType;

  /// Only for [BudgetPeriodType.custom].
  final DateRange? customRange;
  final BudgetStatus status;

  /// Utilisation (basis points) at which the budget enters "warning".
  final int warningThresholdBps;
  final String? note;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int version;

  bool get isPaused => status == BudgetStatus.paused;

  Budget copyWith({
    String? categoryId,
    Money? limit,
    BudgetPeriodType? periodType,
    DateRange? Function()? customRange,
    BudgetStatus? status,
    int? warningThresholdBps,
    String? Function()? note,
    DateTime? updatedAt,
    int? version,
  }) =>
      Budget(
        id: id,
        categoryId: categoryId ?? this.categoryId,
        limit: limit ?? this.limit,
        periodType: periodType ?? this.periodType,
        customRange: customRange != null ? customRange() : this.customRange,
        status: status ?? this.status,
        warningThresholdBps: warningThresholdBps ?? this.warningThresholdBps,
        note: note != null ? note() : this.note,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        version: version ?? this.version,
      );

  @override
  bool operator ==(Object other) => other is Budget && other.id == id && other.version == version;

  @override
  int get hashCode => Object.hash(id, version);
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
