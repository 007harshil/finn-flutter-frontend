import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/di/data_providers.dart';
import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/time/dates.dart';
import '../../../design_system/design_system.dart' show AmountText, AmountVisibility;
import '../../../shared/presentation/category_icons.dart';
import '../../../ui/ui.dart';
import '../application/budget_view.dart';

/// The single status word per budget, as colour + icon. Colour is always
/// paired with an icon or a word; on-track budgets stay ink.
extension BudgetStateUi on BudgetState {
  Color color(UiColors c) => switch (this) {
    BudgetState.over => c.negative,
    BudgetState.risk => c.warning,
    BudgetState.onTrack => c.ink,
    BudgetState.paused => c.inkFaint,
  };

  IconData get icon => switch (this) {
    BudgetState.over => LucideIcons.triangleAlert,
    BudgetState.risk => LucideIcons.gauge,
    BudgetState.onTrack => LucideIcons.circleCheck,
    BudgetState.paused => LucideIcons.circlePause,
  };

  /// Status word; a finished month reads "Within limit" / "Near limit".
  String labelFor({bool past = false}) => switch (this) {
    BudgetState.risk when past => 'Near limit',
    BudgetState.onTrack when past => 'Within limit',
    _ => label,
  };

  /// Filter chip label ("2 over", "1 at risk").
  String countLabel(int n, {bool past = false}) => switch (this) {
    BudgetState.over => '$n over',
    BudgetState.risk => past ? '$n near limit' : '$n at risk',
    BudgetState.onTrack => past ? '$n within limit' : '$n on track',
    BudgetState.paused => '$n paused',
  };
}

/// Money as text, respecting "hide balances".
String budgetMoney(BuildContext context, Money m, {SignDisplay sign = SignDisplay.auto}) =>
    AmountVisibility.hiddenOf(context) ? MoneyFormatter.masked : m.format(sign: sign, decimals: DecimalDisplay.none);

/// "1 Oct – 31 Oct" (adds the year when the range crosses years).
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

/// One line that tells what to do with a budget, e.g. "₹1,800 left ·
/// ₹90/day" or "Runs out ~24 Oct".
String budgetHint(BuildContext context, BudgetPace p, {bool past = false}) {
  final u = p.usage;
  String m(Money x) => budgetMoney(context, x);
  return switch (p.state) {
    BudgetState.over when past => 'Went over by ${m(-u.remaining)}',
    _ when past => '${m(u.remaining)} left unspent',
    BudgetState.paused => 'Paused',
    BudgetState.over => 'Over by ${m(-u.remaining)}',
    _ when p.runsOutOn != null => '${m(u.remaining)} left · runs out ~${DateFormats.dayMonth.format(p.runsOutOn!)}',
    _ when p.safePerDay != null => '${m(u.remaining)} left · ${m(p.safePerDay!)}/day',
    _ => '${m(u.remaining)} left',
  };
}

/// One budget as a row of a kit panel: category mark, name and what was
/// spent, a thin bar of the limit used, and one line on what is left.
/// Colour appears only when the budget needs attention.
class BudgetRow extends ConsumerWidget {
  const BudgetRow({super.key, required this.pace, required this.onTap, this.onLongPress, this.past = false});

  final BudgetPace pace;

  /// Row of a finished (read-only) month.
  final bool past;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = UiColors.of(context);
    final t = UiType.of(context);
    final p = pace;
    final u = p.usage;
    final category = ref.watch(categoryProvider(u.budget.categoryId));
    final name = category?.name ?? 'Deleted category';
    final paused = p.state == BudgetState.paused;
    final color = p.state.color(c);
    final calm = p.state == BudgetState.onTrack || paused;
    final hint = budgetHint(context, p, past: past);
    final long = onLongPress;
    return Semantics(
      button: true,
      label:
          '$name budget, ${p.state.labelFor(past: past)}. Spent ${budgetMoney(context, u.spent)} of '
          '${budgetMoney(context, u.budget.limit)}. $hint.',
      excludeSemantics: true,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        onLongPress: long == null
            ? null
            : () {
                HapticFeedback.mediumImpact();
                long();
              },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(UiSpace.lg, 14, UiSpace.lg, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Opacity(
                opacity: paused ? 0.5 : 1,
                child: UiMark(icon: CategoryIcons.of(category?.iconKey)),
              ),
              const SizedBox(width: UiSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: t.body.copyWith(color: paused ? c.inkSoft : null),
                          ),
                        ),
                        const SizedBox(width: UiSpace.sm),
                        AmountText(u.spent, style: t.figureSmall.copyWith(color: u.isOver ? c.negative : null)),
                      ],
                    ),
                    const SizedBox(height: UiSpace.sm),
                    UiProgress(value: p.used, color: color, height: 4),
                    const SizedBox(height: UiSpace.sm),
                    Row(
                      children: [
                        if (!calm) ...[Icon(p.state.icon, size: 13, color: color), const SizedBox(width: 4)],
                        Expanded(
                          child: Text(
                            hint,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: t.small.copyWith(color: calm ? null : color),
                          ),
                        ),
                        const SizedBox(width: UiSpace.sm),
                        Text('of ${budgetMoney(context, u.budget.limit)}', style: t.small),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
