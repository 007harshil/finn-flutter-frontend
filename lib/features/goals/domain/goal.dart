import 'package:flutter/foundation.dart';

import '../../../core/money/money.dart';

enum GoalCategory {
  travel('Travel', 'plane'),
  purchase('Purchase', 'shoppingBag'),
  education('Education', 'graduationCap'),
  investment('Investment', 'trendingUp'),
  home('Home', 'home'),
  vehicle('Vehicle', 'car'),
  wedding('Wedding', 'heart'),
  health('Health', 'heartPulse'),
  other('Other', 'target');

  const GoalCategory(this.label, this.iconKey);
  final String label;
  final String iconKey;
}

enum GoalStatus { active, archived }

/// A savings goal. The saved amount is *derived* from explicit
/// [SavingsMovement]s; it is never edited directly.
@immutable
class SavingsGoal {
  const SavingsGoal({
    required this.id,
    required this.name,
    required this.category,
    required this.target,
    required this.colorIndex,
    required this.createdAt,
    required this.updatedAt,
    this.targetDate,
    this.plannedMonthlyContribution,
    this.status = GoalStatus.active,
    this.note,
    this.version = 1,
  });

  final String id;
  final String name;
  final GoalCategory category;
  final Money target;
  final DateTime? targetDate;

  /// Optional contribution plan used for completion estimates.
  final Money? plannedMonthlyContribution;
  final int colorIndex;
  final GoalStatus status;
  final String? note;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int version;

  SavingsGoal copyWith({
    String? name,
    GoalCategory? category,
    Money? target,
    DateTime? Function()? targetDate,
    Money? Function()? plannedMonthlyContribution,
    int? colorIndex,
    GoalStatus? status,
    String? Function()? note,
    DateTime? updatedAt,
    int? version,
  }) =>
      SavingsGoal(
        id: id,
        name: name ?? this.name,
        category: category ?? this.category,
        target: target ?? this.target,
        targetDate: targetDate != null ? targetDate() : this.targetDate,
        plannedMonthlyContribution: plannedMonthlyContribution != null
            ? plannedMonthlyContribution()
            : this.plannedMonthlyContribution,
        colorIndex: colorIndex ?? this.colorIndex,
        status: status ?? this.status,
        note: note != null ? note() : this.note,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        version: version ?? this.version,
      );

  @override
  bool operator ==(Object other) => other is SavingsGoal && other.id == id && other.version == version;

  @override
  int get hashCode => Object.hash(id, version);
}

/// Which earmarked pot a [SavingsMovement] belongs to.
enum SavingsBucketType { goal, emergencyFund }

enum SavingsMovementKind {
  /// Earmarks available cash for the bucket.
  contribution('Contribution'),

  /// Releases earmarked money back to available cash.
  withdrawal('Withdrawal');

  const SavingsMovementKind(this.label);
  final String label;
}

/// An internal allocation between "available to spend" and an earmarked
/// pot. It is not income, not an expense, and does not change net worth.
@immutable
class SavingsMovement {
  const SavingsMovement({
    required this.id,
    required this.bucketType,
    required this.bucketId,
    required this.kind,
    required this.amount,
    required this.date,
    required this.createdAt,
    this.note,
    this.accountId,
  });

  final String id;
  final SavingsBucketType bucketType;

  /// Goal id, or [emergencyFundBucketId].
  final String bucketId;
  final SavingsMovementKind kind;

  /// Always positive.
  final Money amount;
  final DateTime date;
  final DateTime createdAt;
  final String? note;

  /// Account the money is set aside on; null = on no account (old data).
  final String? accountId;

  static const emergencyFundBucketId = 'emergency_fund';

  Money get signedAmount => kind == SavingsMovementKind.contribution ? amount : -amount;

  @override
  bool operator ==(Object other) => other is SavingsMovement && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Derived progress for a goal.
@immutable
class GoalProgress {
  const GoalProgress({
    required this.goal,
    required this.saved,
    required this.movements,
    required this.estimatedCompletion,
    required this.requiredMonthly,
    required this.averageMonthlyContribution,
    required this.onTrack,
  });

  final SavingsGoal goal;
  final Money saved;
  final List<SavingsMovement> movements;

  /// Null when there is not enough information to estimate honestly.
  final DateTime? estimatedCompletion;

  /// Monthly amount needed to reach the target by the target date.
  final Money? requiredMonthly;

  /// Average net monthly contribution over the last 3 months (null if
  /// fewer than one month of history).
  final Money? averageMonthlyContribution;

  /// Null when unknown (no target date or no contribution data).
  final bool? onTrack;

  Money get remaining => Money.max(goal.target - saved, Money.zero);
  bool get isAchieved => goal.target.isPositive && saved >= goal.target;
  int get progressBps => (saved.ratioBps(goal.target) ?? 0).clamp(0, 10000);
  double get progress => progressBps / 10000.0;

  @override
  bool operator ==(Object other) =>
      other is GoalProgress &&
      other.goal == goal &&
      other.saved == saved &&
      other.movements.length == movements.length &&
      other.estimatedCompletion == estimatedCompletion &&
      other.requiredMonthly == requiredMonthly;

  @override
  int get hashCode => Object.hash(goal, saved, movements.length, estimatedCompletion);
}
