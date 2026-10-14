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
import '../../../../core/time/dates.dart';
import '../../../../design_system/design_system.dart';
import '../../../../design_system/luxe/luxe.dart';
import '../../../../finance/ledger.dart';
import '../../../transactions/domain/transaction.dart';

/// The month as an equation: money in, money out, what you kept. Both bars
/// share one scale; the ring is the share of income kept. Swipe sideways
/// (or use the arrows) to change month; tap a line for its transactions.
class PeriodOverview extends ConsumerStatefulWidget {
  const PeriodOverview({super.key});

  @override
  ConsumerState<PeriodOverview> createState() => _PeriodOverviewState();
}

class _PeriodOverviewState extends ConsumerState<PeriodOverview> {
  MonthKey? _month;

  void _go(MonthKey to, MonthKey min, MonthKey max) {
    if (to < min || to > max) return;
    HapticFeedback.selectionClick();
    setState(() => _month = to);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.lt;
    final today = ref.watch(todayProvider);
    final current = today.monthKey;
    final min = current.shift(-35);
    var month = _month ?? current;
    if (month > current) month = current;
    final isCurrent = month == current;
    void go(MonthKey to) => _go(to, min, current);

    return LuxeCard(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Row(
              children: [
                Expanded(
                  child: Semantics(header: true, child: Text('CASH FLOW', style: t.eyebrow, maxLines: 1)),
                ),
                Icon(LucideIcons.arrowLeftRight, size: 14, color: context.luxe.inkMute),
              ],
            ),
          ),
          const SizedBox(height: 4),
          LuxeMonthStepper(
            month: month,
            min: min,
            max: current,
            compact: true,
            subtitle: isCurrent ? 'so far' : 'full month',
            onChanged: go,
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onHorizontalDragEnd: (d) {
                final v = d.primaryVelocity ?? 0;
                if (v < -200) go(month.next);
                if (v > 200) go(month.previous);
              },
              child: _MonthFlow(month: month, today: today, isCurrent: isCurrent),
            ),
          ),
        ],
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
    // Like with like: a month in progress is measured against the same days
    // of the month before, a finished month against all of it.
    final prev = month.previous;
    final compare = isCurrent
        ? DateRange(prev.start, DateTime(prev.year, prev.month, math.min(today.day, prev.dayCount)))
        : prev.range;
    final before = ref.watch(rangeSummaryProvider(compare)).value;
    final value = ref.watch(monthSummaryProvider(month));
    final s = value.value;
    if (s == null) {
      if (value.hasError) {
        return Text('Could not load this month.', style: context.lt.caption.c(context.luxe.negative));
      }
      return const LuxeShimmer(child: LuxeBone(height: 112));
    }
    return AnimatedSwitcher(
      duration: context.reduceMotion ? Duration.zero : LuxeDurations.base,
      child: _FlowBody(key: ValueKey(month), summary: s, before: before, month: month, isCurrent: isCurrent),
    );
  }
}

class _FlowBody extends StatelessWidget {
  const _FlowBody({
    super.key,
    required this.summary,
    required this.before,
    required this.month,
    required this.isCurrent,
  });

  final PeriodSummary summary;
  final PeriodSummary? before;
  final MonthKey month;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    final p = context.luxe;
    final hidden = AmountVisibility.hiddenOf(context);
    final income = summary.income;
    final expense = summary.expense;
    final top = math.max(income.paise, expense.paise);
    double share(Money m) => top <= 0 ? 0 : m.paise / top;
    final rate = income.isPositive ? summary.net.paise / income.paise : null;
    final prevName = DateFormats.shortMonth.format(month.previous.start);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _KeptRing(rate: hidden ? null : rate, hidden: hidden),
        const SizedBox(width: 18),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _FlowLine(
                label: 'Income',
                icon: LucideIcons.arrowDownLeft,
                amount: income,
                share: share(income),
                color: p.positive,
                semanticLabel: 'Money in',
                onTap: () => context.push(AppRoutes.transactionsFiltered(type: TransactionType.income, month: month)),
              ),
              const SizedBox(height: 6),
              _FlowLine(
                label: 'Spent',
                icon: LucideIcons.arrowUpRight,
                amount: expense,
                share: share(expense),
                color: p.ink,
                semanticLabel: 'Money out',
                trailing: hidden ? null : _SpendDelta(now: expense, before: before?.expense, against: prevName),
                onTap: () => context.push(AppRoutes.transactionsFiltered(type: TransactionType.expense, month: month)),
              ),
              const SizedBox(height: 10),
              _KeptLine(summary: summary, isCurrent: isCurrent),
            ],
          ),
        ),
      ],
    );
  }
}

class _FlowLine extends StatelessWidget {
  const _FlowLine({
    required this.label,
    required this.icon,
    required this.amount,
    required this.share,
    required this.color,
    required this.semanticLabel,
    required this.onTap,
    this.trailing,
  });

  final String label;
  final IconData icon;
  final Money amount;
  final double share;
  final Color color;
  final String semanticLabel;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final p = context.luxe;
    final t = context.lt;
    final end = trailing;
    return Squish(
      onTap: onTap,
      scale: 0.98,
      semanticLabel: '$semanticLabel. Opens these transactions.',
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, size: 13, color: color),
                const SizedBox(width: 5),
                Text(label, style: t.caption.w(650).c(p.inkSoft)),
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: LuxeAmount(
                    amount,
                    style: t.number.copyWith(fontSize: 16),
                    textAlign: TextAlign.end,
                    countFromZero: true,
                    symbolScale: 0.75,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            LuxeProgressLine(value: share, color: color, height: 4),
            if (end != null) Align(alignment: Alignment.centerRight, child: end),
          ],
        ),
      ),
    );
  }
}

/// "↓ 12% vs Sep": spending against the same stretch of last month. Less
/// spending is good news, so it reads in green.
class _SpendDelta extends StatelessWidget {
  const _SpendDelta({required this.now, required this.before, required this.against});

  final Money now;
  final Money? before;
  final String against;

  @override
  Widget build(BuildContext context) {
    final b = before;
    if (b == null || !b.isPositive) return const SizedBox.shrink();
    final p = context.luxe;
    final pct = ((now.paise - b.paise) / b.paise * 100).round();
    final down = pct < 0;
    final color = pct == 0 ? p.inkMute : (down ? p.positive : p.negative);
    final text = pct == 0 ? 'same as $against' : '${pct.abs()}% vs $against';
    return Semantics(
      label: pct == 0
          ? 'Spending is the same as $against'
          : 'Spending is ${pct.abs()} percent ${down ? 'lower' : 'higher'} than $against',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (pct != 0) Icon(down ? LucideIcons.trendingDown : LucideIcons.trendingUp, size: 11, color: color),
          if (pct != 0) const SizedBox(width: 2),
          Flexible(
            child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.lt.micro.w(700).c(color)),
          ),
        ],
      ),
    );
  }
}

/// The result of the equation: kept or overspent.
class _KeptLine extends StatelessWidget {
  const _KeptLine({required this.summary, required this.isCurrent});

  final PeriodSummary summary;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    final p = context.luxe;
    final t = context.lt;
    final net = summary.net;
    if (summary.income.isZero && summary.expense.isZero) {
      return Text(isCurrent ? 'Nothing recorded yet this month' : 'Nothing recorded this month', style: t.caption);
    }
    final kept = !net.isNegative;
    final color = kept ? p.positive : p.negative;
    return Container(
      padding: const EdgeInsets.only(top: 10),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: p.line)),
      ),
      child: MergeSemantics(
        child: Row(
          children: [
            Icon(kept ? LucideIcons.piggyBank : LucideIcons.triangleAlert, size: 14, color: color),
            const SizedBox(width: 6),
            Flexible(
              flex: 2,
              child: Text(
                kept ? (isCurrent ? 'Kept so far' : 'Kept') : 'Overspent by',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.caption.w(700).c(color),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 3,
              child: LuxeAmount(
                net.abs(),
                style: t.figure.copyWith(fontSize: 22, color: color),
                textAlign: TextAlign.end,
                symbolScale: 0.6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Share of income kept, as a fine ring with the figure set in serif.
class _KeptRing extends StatelessWidget {
  const _KeptRing({required this.rate, required this.hidden});

  /// net / income; null when there is no income or amounts are hidden.
  final double? rate;
  final bool hidden;

  @override
  Widget build(BuildContext context) {
    final p = context.luxe;
    final t = context.lt;
    final r = rate;
    final String label;
    if (r == null) {
      label = hidden ? 'Savings rate hidden' : 'No income recorded';
    } else if (r >= 0) {
      label = 'Kept ${(r * 100).round()} percent of income';
    } else {
      label = 'Spent ${(-r * 100).round()} percent more than income';
    }
    final color = (r ?? 0) >= 0 ? p.positive : p.negative;
    return Semantics(
      label: label,
      excludeSemantics: true,
      child: LuxeRing(
        value: (r ?? 0).clamp(-1.0, 1.0),
        color: color,
        size: 92,
        stroke: 3,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              r == null ? (hidden ? '••' : '—') : '${(r * 100).round()}%',
              style: t.figure.copyWith(fontSize: 26, color: r == null ? p.inkMute : p.ink),
            ),
            Text(r == null ? (hidden ? 'hidden' : 'no income') : (r >= 0 ? 'kept' : 'over'), style: t.micro),
          ],
        ),
      ),
    );
  }
}
