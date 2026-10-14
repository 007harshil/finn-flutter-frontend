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
      loading: const LedgerSkeleton(height: 180, radius: Rad.lg),
      builder: (context, s) => _FlowPanel(summary: s, before: before, month: month, isCurrent: isCurrent),
    );
  }
}

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
      return LedgerPanel(
        children: [
          LedgerRow(
            leading: const IconWell(icon: LucideIcons.notebookPen),
            title: isCurrent ? 'Nothing recorded yet' : 'Nothing recorded',
            subtitle: 'Add income or an expense to see this month take shape.',
          ),
        ],
      );
    }
    final kept = !s.net.isNegative;
    final rate = s.income.isPositive ? (s.net.paise.abs() / s.income.paise * 100).round() : null;
    final delta = hidden ? null : _delta(context, s.expense, before?.expense);
    return LedgerPanel(
      children: [
        LedgerRow(
          title: 'Money in',
          semanticLabel: 'Money in, ${AmountText.spokenLabel(s.income)}. Opens these transactions.',
          trailing: AnimatedAmount(s.income, style: t.figure.copyWith(color: c.green), sign: SignDisplay.always, decimals: DecimalDisplay.none),
          chevron: true,
          onTap: () => context.push(AppRoutes.transactionsFiltered(type: TransactionType.income, month: month)),
        ),
        LedgerRow(
          title: 'Money out',
          semanticLabel: 'Money out, ${AmountText.spokenLabel(s.expense)}. Opens these transactions.',
          trailing: AnimatedAmount(s.expense, style: t.figure, decimals: DecimalDisplay.none),
          trailingSub: delta,
          chevron: true,
          onTap: () => context.push(AppRoutes.transactionsFiltered(type: TransactionType.expense, month: month)),
        ),
        LedgerRow(
          title: kept ? (isCurrent ? 'Kept so far' : 'Kept') : 'Overspent',
          subtitle: rate == null || hidden
              ? null
              : kept
                  ? '$rate% of what came in'
                  : 'Spent $rate% more than came in',
          trailing: AnimatedAmount(
            s.net.abs(),
            style: t.figure.copyWith(color: kept ? c.ink : c.red),
            decimals: DecimalDisplay.none,
          ),
        ),
      ],
    );
  }

  /// "12% less than Sep", coloured by whether that is good news.
  Widget? _delta(BuildContext context, Money now, Money? then) {
    if (then == null || !then.isPositive) return null;
    final c = context.ink;
    final t = context.type;
    final pct = ((now.paise - then.paise) / then.paise * 100).round();
    final name = DateFormats.shortMonth.format(month.previous.start);
    final text = pct == 0 ? 'Same as $name' : '${pct.abs()}% ${pct < 0 ? 'less' : 'more'} than $name';
    final color = pct == 0 ? c.inkSoft : (pct < 0 ? c.green : c.red);
    return Text(text, style: t.small.copyWith(color: color));
  }
}
