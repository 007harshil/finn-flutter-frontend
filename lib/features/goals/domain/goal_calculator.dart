import '../../../core/money/money.dart';
import '../../../core/time/dates.dart';
import 'goal.dart';

/// Derives goal progress and honest completion estimates.
class GoalCalculator {
  const GoalCalculator();

  GoalProgress progress(SavingsGoal goal, List<SavingsMovement> all, DateTime today) {
    final t0 = today.dateOnly;
    final movements = all
        .where((m) => m.bucketType == SavingsBucketType.goal && m.bucketId == goal.id && !m.date.isAfter(t0))
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    final saved = Money.sum(movements.map((m) => m.signedAmount));
    final remaining = Money.max(goal.target - saved, Money.zero);

    // Average net contribution over the last 3 full months.
    Money? average;
    final windowStart = DateTime(t0.year, t0.month - 3, 1);
    final windowEnd = DateTime(t0.year, t0.month, 0);
    final hasHistory = movements.any((m) => !m.date.isAfter(windowEnd));
    if (hasHistory) {
      final inWindow = movements.where((m) => !m.date.isBefore(windowStart) && !m.date.isAfter(windowEnd));
      average = Money.sum(inWindow.map((m) => m.signedAmount)).scale(1, 3);
    }

    // Monthly amount needed to hit the target date.
    Money? required;
    if (goal.targetDate != null && remaining.isPositive) {
      final months = _monthsBetween(t0, goal.targetDate!);
      required = months <= 0 ? remaining : remaining.scale(1, months, mode: RoundingMode.up);
    }

    // Estimate: prefer the user's plan, else recent average. Never estimate
    // from zero or negative rates.
    DateTime? estimate;
    final rate = goal.plannedMonthlyContribution ?? average;
    if (remaining.isZero) {
      estimate = movements.isEmpty ? null : movements.first.date;
    } else if (rate != null && rate.isPositive) {
      final months = roundDiv(remaining.paise, rate.paise, RoundingMode.up);
      if (months <= 600) estimate = addMonthsClamped(t0, months);
    }

    bool? onTrack;
    if (goal.targetDate != null && remaining.isPositive && estimate != null) {
      onTrack = !estimate.isAfter(goal.targetDate!);
    } else if (remaining.isZero) {
      onTrack = true;
    }

    return GoalProgress(
      goal: goal,
      saved: saved,
      movements: movements,
      estimatedCompletion: estimate,
      requiredMonthly: required,
      averageMonthlyContribution: average,
      onTrack: onTrack,
    );
  }

  /// Whole months from [from] to [to], counting a partial month as one.
  int _monthsBetween(DateTime from, DateTime to) {
    final months = (to.year - from.year) * 12 + (to.month - from.month);
    return to.day > from.day ? months + 1 : months;
  }
}
