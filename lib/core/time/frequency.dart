import '../money/money.dart';
import 'dates.dart';

/// Recurrence used by subscriptions and repayment schedules.
enum Frequency {
  weekly('Weekly', 'week', 0),
  monthly('Monthly', 'month', 1),
  quarterly('Quarterly', 'quarter', 3),
  halfYearly('Half-yearly', 'half-year', 6),
  yearly('Yearly', 'year', 12);

  const Frequency(this.label, this.unit, this.months);

  final String label;
  final String unit;

  /// Months per period; 0 for [weekly].
  final int months;

  /// Number of periods in a year.
  int get periodsPerYear => switch (this) {
        Frequency.weekly => 52,
        Frequency.monthly => 12,
        Frequency.quarterly => 4,
        Frequency.halfYearly => 2,
        Frequency.yearly => 1,
      };

  /// The occurrence after [date]. Month-based steps keep [anchorDay] so a
  /// bill on the 31st returns to the 31st after February.
  DateTime next(DateTime date, {int? anchorDay}) {
    if (this == Frequency.weekly) {
      return DateTime(date.year, date.month, date.day + 7);
    }
    return addMonthsClamped(date, months, anchorDay: anchorDay);
  }

  /// The [count]-th occurrence after [start] (count 0 returns [start]).
  DateTime nth(DateTime start, int count) {
    if (this == Frequency.weekly) {
      return DateTime(start.year, start.month, start.day + 7 * count);
    }
    return addMonthsClamped(start, months * count, anchorDay: start.day);
  }

  /// Monthly-equivalent of a per-period [amount], rounded half-up.
  /// Weekly uses 52 weeks / 12 months.
  Money monthlyEquivalent(Money amount) => switch (this) {
        Frequency.weekly => amount.scale(52, 12),
        Frequency.monthly => amount,
        _ => amount.scale(1, months),
      };

  /// Annualised cost of a per-period [amount] (exact).
  Money annualized(Money amount) => amount.times(periodsPerYear);
}
