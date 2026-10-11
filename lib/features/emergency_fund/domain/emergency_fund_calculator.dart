import '../../../core/money/money.dart';
import '../../../core/time/dates.dart';
import '../../categories/domain/category.dart';
import '../../goals/domain/goal.dart';
import '../../transactions/domain/transaction.dart';
import 'emergency_fund.dart';

class EmergencyFundCalculator {
  const EmergencyFundCalculator();

  /// Coverage below this many months is "critical".
  static const criticalMonths = 2;

  EmergencyFundStatus status({
    required EmergencyFundPlan? plan,
    required List<SavingsMovement> movements,
    required List<Transaction> transactions,
    required Map<String, TransactionCategory> categories,
    required DateTime today,
  }) {
    final t0 = today.dateOnly;
    final own = movements
        .where((m) => m.bucketType == SavingsBucketType.emergencyFund && !m.date.isAfter(t0))
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    final saved = Money.sum(own.map((m) => m.signedAmount));
    final suggestion = suggestEssentialMonthly(transactions, categories, t0);

    int? coverage;
    final essential = plan?.essentialMonthlyExpenses;
    if (essential != null && essential.isPositive) {
      coverage = roundDiv(saved.paise * 10, essential.paise, RoundingMode.down);
    }

    final EmergencyFundLevel level;
    if (plan == null || !plan.target.isPositive) {
      level = EmergencyFundLevel.notConfigured;
    } else if (saved >= plan.target) {
      level = EmergencyFundLevel.funded;
    } else if (coverage != null && coverage < criticalMonths * 10) {
      level = EmergencyFundLevel.critical;
    } else {
      level = EmergencyFundLevel.building;
    }

    return EmergencyFundStatus(
      plan: plan,
      saved: saved,
      movements: own,
      coverageTenths: coverage,
      level: level,
      suggestedEssentialMonthly: suggestion,
    );
  }

  /// Average monthly essential spending (essential categories + EMIs) over
  /// the last three full months. Null when there is no such history.
  Money? suggestEssentialMonthly(
    List<Transaction> transactions,
    Map<String, TransactionCategory> categories,
    DateTime today,
  ) {
    final start = DateTime(today.year, today.month - 3, 1);
    final end = DateTime(today.year, today.month, 0);
    var total = 0;
    var seen = false;
    for (final t in transactions) {
      if (!t.isExpense || t.date.isBefore(start) || t.date.isAfter(end)) continue;
      final c = categories[t.categoryId];
      final essential = (c?.isEssential ?? false) || t.categoryId == SystemCategories.loanEmi;
      if (!essential) continue;
      total += t.amount.paise;
      seen = true;
    }
    if (!seen) return null;
    return Money.fromPaise(total).scale(1, 3).roundToRupee();
  }
}
