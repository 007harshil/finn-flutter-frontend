import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../app/di/core_providers.dart';
import '../../../../app/di/data_providers.dart';
import '../../../../app/router/routes.dart';
import '../../../../core/money/money.dart';
import '../../../../core/money/money_format.dart';
import '../../../../core/time/dates.dart';
import '../../../../finance/ledger.dart';
import '../../../analytics/presentation/spend_pulse.dart';
import '../../../../kit/kit.dart';
import '../../../../shared/presentation/async_view.dart';
import '../../../transactions/domain/transaction.dart';

/// Money in, money out and what was kept, for one month. Arrows (or a
/// swipe across the panel) step back up to three years. Each flow row
/// opens Activity filtered to it.
class PeriodOverview extends ConsumerStatefulWidget {
  const PeriodOverview({super.key});

  @override
  ConsumerState<PeriodOverview> createState() => _PeriodOverviewState();
}

class _PeriodOverviewState extends ConsumerState<PeriodOverview> {
  MonthKey? _month;

  @override
  Widget build(BuildContext context) {
    final today = ref.watch(todayProvider);
    final current = today.monthKey;
    final min = current.shift(-35);
    var month = _month ?? current;
    if (month > current) month = current;
    final isCurrent = month == current;
    void go(MonthKey to) {
      if (to < min || to > current) return;
      HapticFeedback.selectionClick();
      setState(() => _month = to);
    }

    return LedgerSection(
      title: isCurrent ? 'This month' : DateFormats.monthYear.format(month.start),
      trailing: Transform.translate(
        offset: const Offset(10, 0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            LedgerIconButton(
              icon: LucideIcons.chevronLeft,
              tooltip: 'Previous month',
              onPressed: month > min ? () => go(month.previous) : null,
            ),
            LedgerIconButton(
              icon: LucideIcons.chevronRight,
              tooltip: 'Next month',
              onPressed: isCurrent ? null : () => go(month.next),
            ),
          ],
        ),
      ),
      child: GestureDetector(
        onHorizontalDragEnd: (d) {
          final v = d.primaryVelocity ?? 0;
          if (v < -200) go(month.next);
          if (v > 200) go(month.previous);
        },
        child: _MonthFlow(month: month, today: today, isCurrent: isCurrent),
      ),
    );
  }
}

class _MonthFlow extends ConsumerWidget {
  const _MonthFlow({required this.month, required this.today, required this.isCurrent});

  final MonthKey month;
  final DateTime today;
  final bool isCurrent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Compare like with like: a month in progress is measured against the
    // same days of the month before, a finished month against all of it.
    final prev = month.previous;
    final compare = isCurrent
        ? DateRange(prev.start, DateTime(prev.year, prev.month, math.min(today.day, prev.dayCount)))
        : prev.range;
    final before = ref.watch(rangeSummaryProvider(compare)).value;
    return AsyncView<PeriodSummary>(
      value: ref.watch(monthSummaryProvider(month)),
      loading: const LedgerSkeleton(height: 132, radius: Rad.lg),
      builder: (context, s) => _FlowPanel(summary: s, before: before, month: month, isCurrent: isCurrent),
    );
  }
}

/// Monsoon pulse: running spend this month (rain) against last month
/// (soft line). Drag across it to read any day.
class _MonthPulse extends ConsumerWidget {
  const _MonthPulse({required this.month});

  final MonthKey month;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.ink;
    final pulse = ref.watch(spendPulseProvider(month)).value;
    if (pulse == null || (pulse.spent <= 0 && (pulse.lastMonth.lastOrNull ?? 0) <= 0)) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: Sp.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SpendPulseChart(pulse: pulse, height: 120, readout: false),
          const SizedBox(height: Sp.sm),
          Wrap(
            spacing: Sp.lg,
            children: [
              ChartDot(color: c.rain, label: DateFormats.shortMonth.format(month.start)),
              ChartDot(color: c.inkSoft.withValues(alpha: 0.5), label: DateFormats.shortMonth.format(month.previous.start)),
            ],
          ),
        ],
      ),
    );
  }
}

/// In, out and kept side by side on one Monsoon card, the running-spend
/// pulse under them. In and out open Activity filtered.
class _FlowPanel extends StatelessWidget {
  const _FlowPanel({required this.summary, required this.before, required this.month, required this.isCurrent});

  final PeriodSummary summary;
  final PeriodSummary? before;
  final MonthKey month;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final t = context.type;
    final hidden = AmountVisibility.hiddenOf(context);
    final s = summary;
    if (s.income.isZero && s.expense.isZero) {
      return MonsoonCard(
        child: Row(
          children: [
            Icon(LucideIcons.notebookPen, size: 18, color: c.inkSoft),
            const SizedBox(width: Sp.md),
            Text(isCurrent ? 'Nothing recorded yet' : 'Nothing recorded', style: t.label),
          ],
        ),
      );
    }
    final kept = !s.net.isNegative;
    final rate = s.income.isPositive ? (s.net.paise.abs() / s.income.paise * 100).round() : null;
    final delta = hidden ? null : _delta(context, s.expense, before?.expense);
    Widget figure(Money m, {Color? color, SignDisplay sign = SignDisplay.auto}) => FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: AnimatedAmount(m, style: t.figure.copyWith(color: color), sign: sign, decimals: DecimalDisplay.none),
        );
    Widget sub(String? text, {Color? color}) => Text(
          text ?? '',
          style: t.small.copyWith(color: color ?? c.inkSoft),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );
    return MonsoonCard(
      padding: const EdgeInsets.all(Sp.md + 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: LedgerStat(
                  label: 'Money in',
                  value: figure(s.income, color: c.green, sign: SignDisplay.always),
                  semanticLabel: 'Money in, ${AmountText.spokenLabel(s.income)}. Opens these transactions.',
                  onTap: () => context.push(AppRoutes.transactionsFiltered(type: TransactionType.income, month: month)),
                ),
              ),
              const SizedBox(width: Sp.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LedgerStat(
                      label: 'Money out',
                      value: figure(s.expense),
                      semanticLabel: 'Money out, ${AmountText.spokenLabel(s.expense)}. Opens these transactions.',
                      onTap: () => context.push(AppRoutes.transactionsFiltered(type: TransactionType.expense, month: month)),
                    ),
                    if (delta != null) sub(delta.$1, color: delta.$2),
                  ],
                ),
              ),
              const SizedBox(width: Sp.sm),
              Expanded(
                child: Padding(
                  // Tappable stats carry vertical padding; match it so labels line up.
                  padding: const EdgeInsets.symmetric(vertical: Sp.xs),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LedgerStat(
                        label: kept ? (isCurrent ? 'Kept so far' : 'Kept') : 'Overspent',
                        value: figure(s.net.abs(), color: kept ? c.ink : c.red),
                      ),
                      if (rate != null && !hidden) sub(kept ? '$rate% of in' : '$rate% over'),
                    ],
                  ),
                ),
              ),
            ],
          ),
          _MonthPulse(month: month),
        ],
      ),
    );
  }

  /// "12% less than Sep", coloured by whether that is good news.
  (String, Color)? _delta(BuildContext context, Money now, Money? then) {
    if (then == null || !then.isPositive) return null;
    final c = context.ink;
    final pct = ((now.paise - then.paise) / then.paise * 100).round();
    final name = DateFormats.shortMonth.format(month.previous.start);
    final text = pct == 0 ? 'Same as $name' : '${pct.abs()}% ${pct < 0 ? 'less' : 'more'} than $name';
    final color = pct == 0 ? c.inkSoft : (pct < 0 ? c.green : c.red);
    return (text, color);
  }
}
