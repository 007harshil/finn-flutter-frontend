import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/time/dates.dart';
import '../../../design_system/design_system.dart';
import '../application/budget_view.dart';
import '../domain/budget.dart';

/// Visual mapping of budget health. Colour is always paired with an icon
/// and a text label.
extension BudgetHealthUi on BudgetHealth {
  FinnTone get tone => switch (this) {
        BudgetHealth.healthy => FinnTone.positive,
        BudgetHealth.warning => FinnTone.warning,
        BudgetHealth.breached => FinnTone.negative,
        BudgetHealth.paused => FinnTone.info,
      };

  Color color(FinnColors c) => this == BudgetHealth.paused ? c.textTertiary : tone.color(c);

  IconData get icon => this == BudgetHealth.paused ? LucideIcons.circlePause : tone.icon;
}

/// The single status word per budget, as colour + icon.
extension BudgetStateUi on BudgetState {
  Color color(FinnColors c) => switch (this) {
        BudgetState.over => c.negative,
        BudgetState.risk => c.warning,
        BudgetState.onTrack => c.positive,
        BudgetState.paused => c.textTertiary,
      };

  IconData get icon => switch (this) {
        BudgetState.over => LucideIcons.triangleAlert,
        BudgetState.risk => LucideIcons.gauge,
        BudgetState.onTrack => LucideIcons.circleCheck,
        BudgetState.paused => LucideIcons.circlePause,
      };

  /// Short chip label ("2 over").
  /// Status word; a finished month reads "Within limit" / "Near limit".
  String labelFor({bool past = false}) => switch (this) {
        BudgetState.risk when past => 'Near limit',
        BudgetState.onTrack when past => 'Within limit',
        _ => label,
      };

  String countLabel(int n, {bool past = false}) => switch (this) {
        BudgetState.over => '$n over',
        BudgetState.risk => past ? '$n near limit' : '$n at risk',
        BudgetState.onTrack => past ? '$n within limit' : '$n on track',
        BudgetState.paused => '$n paused',
      };
}

/// Money as text, respecting "hide balances".
String budgetMoney(BuildContext context, Money m, {SignDisplay sign = SignDisplay.auto}) =>
    AmountVisibility.hiddenOf(context) ? MoneyFormatter.masked : m.format(sign: sign);

/// "1 Oct – 31 Oct" (adds the year when the range crosses years).
String periodLabel(DateRange r) {
  final sameYear = r.start.year == r.end.year;
  final start = sameYear ? DateFormats.dayMonth.format(r.start) : DateFormats.dayMonthYear.format(r.start);
  return '$start – ${DateFormats.dayMonthYear.format(r.end)}';
}

/// Days left in [r] counting today (0 when it has ended).
int daysLeftIn(DateRange r, DateTime today) {
  if (today.isAfter(r.end)) return 0;
  if (today.isBefore(r.start)) return r.dayCount;
  return daysBetween(today, r.end) + 1;
}

String daysLeftLabel(int days) => switch (days) {
      0 => 'Period ended',
      1 => 'Last day',
      _ => '$days days left',
    };

/// One line that tells what to do with a budget, e.g. "₹1,800 left ·
/// ₹90/day" or "Runs out ~24 Oct".
String budgetHint(BuildContext context, BudgetPace p, {bool past = false}) {
  final u = p.usage;
  String m(Money x) => budgetMoney(context, x);
  return switch (p.state) {
    BudgetState.over when past => 'Went over by ${m(-u.remaining)}',
    _ when past => '${m(u.remaining)} left unspent',
    BudgetState.paused => 'Paused · ${m(u.spent)} spent',
    BudgetState.over => 'Over by ${m(-u.remaining)}',
    _ when p.runsOutOn != null => '${m(u.remaining)} left · runs out ~${DateFormats.dayMonth.format(p.runsOutOn!)}',
    _ when p.safePerDay != null => '${m(u.remaining)} left · ${m(p.safePerDay!)}/day',
    _ => '${m(u.remaining)} left',
  };
}
