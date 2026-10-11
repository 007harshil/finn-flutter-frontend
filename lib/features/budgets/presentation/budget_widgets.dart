import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/di/core_providers.dart';
import '../../../app/di/data_providers.dart';
import '../../../app/router/routes.dart';
import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/time/dates.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/presentation/category_icons.dart';
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

/// Money as text, respecting "hide balances".
String budgetMoney(BuildContext context, Money m, {SignDisplay sign = SignDisplay.auto}) =>
    AmountVisibility.hiddenOf(context) ? MoneyFormatter.masked : m.format(sign: sign);

/// "62% of month gone, 80% spent".
String pacingHint(BudgetUsage u) {
  final unit = u.budget.periodType == BudgetPeriodType.monthly ? 'month' : 'period';
  return '${formatBps(u.elapsedBps, decimals: 0)} of $unit gone, ${formatBps(u.utilizationBps, decimals: 0)} spent';
}

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

/// Health pill: icon + label + tone colour.
class BudgetHealthPill extends StatelessWidget {
  const BudgetHealthPill({super.key, required this.health});

  final BudgetHealth health;

  @override
  Widget build(BuildContext context) =>
      StatusPill(label: health.label, color: health.color(context.colors), icon: health.icon);
}

/// "₹1,200 left" or "Over by ₹300", with an icon so it never relies on colour.
class BudgetRemainingLabel extends StatelessWidget {
  const BudgetRemainingLabel({super.key, required this.usage, this.style});

  final BudgetUsage usage;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final over = usage.isOver;
    final color = over ? c.negative : (usage.budget.isPaused ? c.textSecondary : c.positive);
    final text = over
        ? 'Over by ${budgetMoney(context, -usage.remaining)}'
        : '${budgetMoney(context, usage.remaining)} left';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(over ? LucideIcons.triangleAlert : LucideIcons.circleCheck, size: 13, color: color),
        const SizedBox(width: Space.x1),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: (style ?? context.text.label).copyWith(color: color, fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }
}

/// One budget in the list.
class BudgetUsageCard extends ConsumerWidget {
  const BudgetUsageCard({super.key, required this.usage});

  final BudgetUsage usage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final t = context.text;
    final u = usage;
    final category = ref.watch(categoryProvider(u.budget.categoryId));
    final today = ref.watch(todayProvider);
    final paused = u.budget.isPaused;
    final name = category?.name ?? 'Deleted category';
    final days = daysLeftIn(u.period, today);
    final periodText = u.budget.periodType == BudgetPeriodType.monthly
        ? 'Monthly · ${daysLeftLabel(days)}'
        : '${periodLabel(u.period)} · ${daysLeftLabel(days)}';
    final semantic = '$name budget, ${u.health.label}. '
        'Spent ${budgetMoney(context, u.spent)} of ${budgetMoney(context, u.budget.limit)}. '
        '${u.isOver ? 'Over by ${budgetMoney(context, -u.remaining)}' : '${budgetMoney(context, u.remaining)} left'}.';
    return FinnCard(
      variant: paused ? FinnCardVariant.muted : FinnCardVariant.surface,
      onTap: () => context.push(AppRoutes.budget(u.budget.id)),
      semanticLabel: semantic,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CategoryAvatar(category: category, size: 40),
              const SizedBox(width: Space.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.bodyStrong),
                    const SizedBox(height: 2),
                    Text(periodText, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.caption),
                  ],
                ),
              ),
              const SizedBox(width: Space.x2),
              BudgetHealthPill(health: u.health),
            ],
          ),
          const SizedBox(height: Space.x4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: AmountText(
                  u.spent,
                  style: t.amountMedium.copyWith(color: u.isOver ? c.negative : c.textPrimary),
                ),
              ),
              const SizedBox(width: Space.x1),
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text('of ${budgetMoney(context, u.budget.limit)}', style: t.caption),
              ),
              const Spacer(),
              Flexible(child: BudgetRemainingLabel(usage: u)),
            ],
          ),
          const SizedBox(height: Space.x2_5),
          FinnProgressBar(
            value: u.utilization,
            color: u.health.color(c),
            semanticsLabel: '$name budget used',
          ),
          const SizedBox(height: Space.x2),
          Row(
            children: [
              Expanded(
                child: Text(
                  paused ? 'Paused — not tracking warnings' : pacingHint(u),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.caption,
                ),
              ),
              if (u.committed.isPositive) ...[
                const SizedBox(width: Space.x2),
                Tooltip(
                  message: 'Expected subscription charges not yet paid',
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(LucideIcons.repeat, size: 12, color: c.textSecondary),
                      const SizedBox(width: Space.x1),
                      Text(
                        '${budgetMoney(context, u.committed, sign: SignDisplay.always)} expected',
                        style: t.caption.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
