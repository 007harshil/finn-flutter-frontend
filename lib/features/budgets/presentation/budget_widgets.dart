import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/data_providers.dart';
import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/time/dates.dart';
import '../../../kit/kit.dart';
import '../application/budget_view.dart';

/// The single status word per budget, and the colour that carries it.
/// Colour is only used for meaning: red over, amber at risk, green on
/// track, ink-soft when paused.
extension BudgetStateUi on BudgetState {
  Color color(LedgerColors c) => switch (this) {
        BudgetState.over => c.red,
        BudgetState.risk => c.amber,
        BudgetState.onTrack => c.green,
        BudgetState.paused => c.inkSoft,
      };

  /// Text colour for a hint line: only over and at risk stand out.
  Color hintColor(LedgerColors c) => switch (this) {
        BudgetState.over => c.red,
        BudgetState.risk => c.amber,
        _ => c.inkSoft,
      };

  /// Status word; a finished month reads "Within limit" / "Near limit".
  String labelFor({bool past = false}) => switch (this) {
        BudgetState.risk when past => 'Near limit',
        BudgetState.onTrack when past => 'Within limit',
        _ => label,
      };

  /// Short filter-chip label ("Over", "At risk").
  String chipLabel({bool past = false}) => this == BudgetState.over ? 'Over' : labelFor(past: past);
}

/// Money as text, respecting "hide balances". Whole rupees by default:
/// these strings sit in sentences, not in columns.
String budgetMoney(
  BuildContext context,
  Money m, {
  SignDisplay sign = SignDisplay.auto,
  DecimalDisplay decimals = DecimalDisplay.none,
}) =>
    AmountVisibility.hiddenOf(context) ? MoneyFormatter.masked : m.format(sign: sign, decimals: decimals);

/// "1 Oct – 31 Oct 2026" (adds the start year when the range crosses years).
String periodLabel(DateRange r) {
  final sameYear = r.start.year == r.end.year;
  final start = sameYear ? DateFormats.dayMonth.format(r.start) : DateFormats.dayMonthYear.format(r.start);
  return '$start – ${DateFormats.dayMonthYear.format(r.end)}';
}

String daysLeftLabel(int days) => switch (days) {
      0 => 'Period ended',
      1 => 'Last day',
      _ => '$days days left',
    };

/// One line that tells what to do with a budget, e.g. "₹1,800 left, ₹90 a
/// day" or "Runs out around 24 Oct".
String budgetHint(BuildContext context, BudgetPace p, {bool past = false}) {
  final u = p.usage;
  String m(Money x) => budgetMoney(context, x);
  return switch (p.state) {
    BudgetState.over when past => 'Went over by ${m(-u.remaining)}',
    _ when past => '${m(u.remaining)} left unspent',
    BudgetState.paused => 'Paused, ${m(u.spent)} spent',
    BudgetState.over => 'Over by ${m(-u.remaining)}',
    _ when p.runsOutOn != null => 'Runs out around ${DateFormats.dayMonth.format(p.runsOutOn!)}',
    _ when p.safePerDay != null => '${m(u.remaining)} left, ${m(p.safePerDay!)} a day',
    _ => '${m(u.remaining)} left',
  };
}

/// One budget in the list: category, what to do next, spent of limit and a
/// thin bar with a tick for where spending should be by today.
class BudgetRow extends ConsumerWidget {
  const BudgetRow({super.key, required this.pace, required this.onTap, this.onLongPress, this.past = false});

  final BudgetPace pace;

  /// Row of a finished (read-only) month.
  final bool past;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.ink;
    final t = context.type;
    final p = pace;
    final u = p.usage;
    final category = ref.watch(categoryProvider(u.budget.categoryId));
    final name = category?.name ?? 'Deleted category';
    final paused = p.state == BudgetState.paused;
    final hint = budgetHint(context, p, past: past);
    final row = LedgerRow(
      leading: CategoryMark(category: category),
      title: name,
      subtitle: hint,
      subtitleColor: p.state.hintColor(c),
      subtitleLines: 2,
      trailing: AmountText(u.spent, style: t.figure, color: u.isOver ? c.red : null),
      trailingSub: Text('of ${budgetMoney(context, u.budget.limit)}', style: t.small),
      below: LedgerBar(
        value: p.used,
        marker: past || paused ? null : p.elapsed,
        color: switch (p.state) {
          BudgetState.risk => c.amber,
          BudgetState.paused => c.inkFaint,
          _ => c.green,
        },
      ),
      semanticLabel: '$name budget, ${p.state.labelFor(past: past)}. Spent ${budgetMoney(context, u.spent)} of '
          '${budgetMoney(context, u.budget.limit)}. $hint.',
      onTap: onTap,
      onLongPress: onLongPress,
    );
    return paused ? Opacity(opacity: 0.6, child: row) : row;
  }
}
