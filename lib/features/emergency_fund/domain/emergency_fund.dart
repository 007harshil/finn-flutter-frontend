import 'package:flutter/foundation.dart';

import '../../../core/money/money.dart';
import '../../goals/domain/goal.dart';

/// User-adjustable emergency fund assumptions.
@immutable
class EmergencyFundPlan {
  const EmergencyFundPlan({
    required this.essentialMonthlyExpenses,
    required this.targetMonths,
    required this.updatedAt,
    this.targetOverride,
  });

  /// Estimated essential spending per month (rent, food, EMIs, utilities).
  final Money essentialMonthlyExpenses;

  /// Desired coverage, in months (1–24).
  final int targetMonths;

  /// Explicit target chosen by the user, replacing the computed one.
  final Money? targetOverride;
  final DateTime updatedAt;

  Money get target => targetOverride ?? essentialMonthlyExpenses.times(targetMonths);

  EmergencyFundPlan copyWith({
    Money? essentialMonthlyExpenses,
    int? targetMonths,
    Money? Function()? targetOverride,
    DateTime? updatedAt,
  }) =>
      EmergencyFundPlan(
        essentialMonthlyExpenses: essentialMonthlyExpenses ?? this.essentialMonthlyExpenses,
        targetMonths: targetMonths ?? this.targetMonths,
        targetOverride: targetOverride != null ? targetOverride() : this.targetOverride,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  @override
  bool operator ==(Object other) =>
      other is EmergencyFundPlan &&
      other.essentialMonthlyExpenses == essentialMonthlyExpenses &&
      other.targetMonths == targetMonths &&
      other.targetOverride == targetOverride;

  @override
  int get hashCode => Object.hash(essentialMonthlyExpenses, targetMonths, targetOverride);
}

enum EmergencyFundLevel {
  notConfigured('Not set up'),
  critical('Critical'),
  building('Building'),
  funded('Funded');

  const EmergencyFundLevel(this.label);
  final String label;
}

/// Derived emergency-fund status.
@immutable
class EmergencyFundStatus {
  const EmergencyFundStatus({
    required this.plan,
    required this.saved,
    required this.movements,
    required this.coverageTenths,
    required this.level,
    required this.suggestedEssentialMonthly,
  });

  final EmergencyFundPlan? plan;
  final Money saved;
  final List<SavingsMovement> movements;

  /// Months of essential expenses covered, in tenths (e.g. 24 = 2.4 months).
  /// Null when essential expenses are unknown.
  final int? coverageTenths;
  final EmergencyFundLevel level;

  /// Average essential spending over the last 3 full months (null if no
  /// history). Offered as a suggestion, never applied silently.
  final Money? suggestedEssentialMonthly;

  Money get target => plan?.target ?? Money.zero;
  Money get remaining => Money.max(target - saved, Money.zero);
  int get progressBps => (saved.ratioBps(target) ?? 0).clamp(0, 10000);
  double get progress => progressBps / 10000.0;
  double? get coverageMonths => coverageTenths == null ? null : coverageTenths! / 10.0;

  /// True when the recent essentials average differs from the planned
  /// essentials by 10% or more, so the plan may be worth reviewing.
  bool get suggestionDiffersFromPlan {
    final s = suggestedEssentialMonthly;
    final p = plan?.essentialMonthlyExpenses;
    if (s == null || p == null || !p.isPositive) return false;
    return (s - p).abs().paise * 10 >= p.paise;
  }

  @override
  bool operator ==(Object other) =>
      other is EmergencyFundStatus &&
      other.plan == plan &&
      other.saved == saved &&
      other.movements.length == movements.length &&
      other.level == level &&
      other.suggestedEssentialMonthly == suggestedEssentialMonthly;

  @override
  int get hashCode => Object.hash(plan, saved, movements.length, level);
}
