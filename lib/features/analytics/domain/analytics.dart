import 'package:flutter/foundation.dart';

import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/time/dates.dart';
import '../../../finance/finance_snapshot.dart';
import '../../../finance/ledger.dart';
import '../../categories/domain/category.dart';
import '../../goals/domain/goal.dart';

@immutable
class MonthlyCashFlow {
  const MonthlyCashFlow(this.month, this.summary);
  final MonthKey month;
  final PeriodSummary summary;
  Money get income => summary.income;
  Money get expense => summary.expense;
  Money get net => summary.net;
}

@immutable
class CategorySlice {
  const CategorySlice({required this.category, required this.categoryId, required this.amount, required this.shareBps, this.previous});
  final TransactionCategory? category;
  final String categoryId;
  final Money amount;
  final int shareBps;

  /// Same category in the comparison period (null when not compared).
  final Money? previous;

  String get name => category?.name ?? 'Uncategorised';

  /// Change vs previous in bps; null when previous is zero/unknown.
  int? get changeBps => previous == null || previous!.isZero ? null : (amount - previous!).ratioBps(previous!);
}

@immutable
class PeriodComparison {
  const PeriodComparison(this.current, this.previous);
  final PeriodSummary current;
  final PeriodSummary previous;

  int? get incomeChangeBps => previous.income.isZero ? null : (current.income - previous.income).ratioBps(previous.income);
  int? get expenseChangeBps => previous.expense.isZero ? null : (current.expense - previous.expense).ratioBps(previous.expense);
}

@immutable
class TrendPoint {
  const TrendPoint(this.month, this.value);
  final MonthKey month;
  final Money value;
}

enum InsightTone { positive, neutral, caution }

@immutable
class Insight {
  const Insight({required this.title, required this.body, required this.tone});
  final String title;
  final String body;
  final InsightTone tone;
}

/// Turns records into chart series and plain-language insights.
class AnalyticsService {
  const AnalyticsService();

  /// Last [count] months ending with [last] (inclusive), oldest first.
  List<MonthlyCashFlow> cashFlow(FinanceSnapshot s, MonthKey last, int count) => [
        for (var i = count - 1; i >= 0; i--) MonthlyCashFlow(last.shift(-i), s.monthSummary(last.shift(-i))),
      ];

  List<CategorySlice> categoryBreakdown(FinanceSnapshot s, DateRange range, {DateRange? compareTo}) {
    final current = s.summary(range);
    final prev = compareTo == null ? null : s.summary(compareTo);
    final prevMap = {for (final e in prev?.byCategory ?? const <MapEntry<String, Money>>[]) e.key: e.value};
    return [
      for (final e in current.byCategory)
        CategorySlice(
          category: s.category(e.key),
          categoryId: e.key,
          amount: e.value,
          shareBps: e.value.ratioBps(current.expense) ?? 0,
          previous: prev == null ? null : (prevMap[e.key] ?? Money.zero),
        ),
    ];
  }

  /// Compares [range] with the period before it. Whole calendar months are
  /// compared with the previous calendar month (not "same number of days").
  PeriodComparison compare(FinanceSnapshot s, DateRange range) {
    final isMonth = range.start.day == 1 && range.end == range.start.endOfMonth;
    final previous = isMonth ? range.start.monthKey.previous.range : range.previous;
    return PeriodComparison(s.summary(range), s.summary(previous));
  }

  /// Outstanding borrowed principal at each month end.
  List<TrendPoint> debtTrend(FinanceSnapshot s, MonthKey last, int count) => [
        for (var i = count - 1; i >= 0; i--)
          TrendPoint(
            last.shift(-i),
            Money.sum(s.loans.where((l) => l.isBorrowed).map((l) {
              final end = last.shift(-i).end;
              final d = end.isAfter(s.today) ? s.today : end;
              return FinanceSnapshot.loanCalc.outstandingOn(l, s.loanPayments, d);
            })),
          ),
      ];

  /// Total earmarked savings (goals + emergency fund) at each month end.
  List<TrendPoint> savingsTrend(FinanceSnapshot s, MonthKey last, int count) => [
        for (var i = count - 1; i >= 0; i--)
          TrendPoint(
            last.shift(-i),
            Money.sum(s.savingsMovements
                .where((m) => !m.date.isAfter(last.shift(-i).end))
                .map((m) => m.signedAmount)),
          ),
      ];

  /// Average spend per elapsed day in [range] (up to today).
  Money dailyBurn(FinanceSnapshot s, DateRange range) {
    final end = range.end.isAfter(s.today) ? s.today : range.end;
    if (end.isBefore(range.start)) return Money.zero;
    final days = daysBetween(range.start, end) + 1;
    return s.summary(range).expense.scale(1, days);
  }

  /// Share of spending in non-essential categories (bps); null if no spend.
  int? discretionaryShareBps(FinanceSnapshot s, DateRange range) {
    final sum = s.summary(range);
    if (sum.expense.isZero) return null;
    final discretionary = Money.sum(sum.byCategory.where((e) {
      final c = s.category(e.key);
      return c != null && !c.isEssential && !c.isSystem;
    }).map((e) => e.value));
    return discretionary.ratioBps(sum.expense);
  }

  /// Plain-language observations for a month. Non-judgemental by design.
  List<Insight> insights(FinanceSnapshot s, MonthKey month) {
    final out = <Insight>[];
    final cmp = compare(s, month.range);
    final cur = cmp.current;
    String f(Money m) => m.format(decimals: DecimalDisplay.none);

    final rate = cur.savingsRateBps;
    if (rate != null) {
      out.add(rate >= 2000
          ? Insight(title: 'You kept ${formatBps(rate, decimals: 0)} of your income', body: '${f(cur.net)} more came in than went out. A healthy cushion.', tone: InsightTone.positive)
          : rate >= 0
              ? Insight(title: 'Savings rate is ${formatBps(rate, decimals: 0)}', body: 'Income covered spending with ${f(cur.net)} to spare.', tone: InsightTone.neutral)
              : Insight(title: 'Spending exceeded income', body: 'Outflows were ${f(cur.net.abs())} more than income for this period.', tone: InsightTone.caution));
    }
    final slices = categoryBreakdown(s, month.range, compareTo: month.previous.range);
    final rising = slices.where((x) => (x.changeBps ?? 0) >= 2000 && x.amount >= const Money.rupees(1000)).toList();
    if (rising.isNotEmpty) {
      final x = rising.first;
      out.add(Insight(
        title: '${x.name} is up ${formatBps(x.changeBps!, decimals: 0)}',
        body: '${f(x.amount)} vs ${f(x.previous!)} last month.',
        tone: InsightTone.caution,
      ));
    }
    final falling = slices.where((x) => (x.changeBps ?? 0) <= -2000 && x.previous! >= const Money.rupees(1000)).toList();
    if (falling.isNotEmpty) {
      final x = falling.first;
      out.add(Insight(
        title: '${x.name} is down ${formatBps(x.changeBps!.abs(), decimals: 0)}',
        body: 'You spent ${f(x.previous! - x.amount)} less than last month.',
        tone: InsightTone.positive,
      ));
    }
    if (slices.isNotEmpty) {
      final top = slices.first;
      out.add(Insight(
        title: 'Top category: ${top.name}',
        body: '${formatBps(top.shareBps, decimals: 0)} of spending (${f(top.amount)}).',
        tone: InsightTone.neutral,
      ));
    }
    final subs = s.monthlySubscriptionCommitment;
    if (subs.isPositive && cur.income.isPositive) {
      final share = subs.ratioBps(cur.income)!;
      out.add(Insight(
        title: 'Subscriptions take ${formatBps(share)} of income',
        body: '${f(subs)} a month in recurring commitments.',
        tone: share > 1000 ? InsightTone.caution : InsightTone.neutral,
      ));
    }
    return out;
  }

  /// A short human summary of the month for the dashboard.
  List<String> monthlyNarrative(FinanceSnapshot s, MonthKey month) {
    final cmp = compare(s, month.range);
    final cur = cmp.current;
    String f(Money m) => m.format(decimals: DecimalDisplay.none);
    final lines = <String>[];
    if (cur.transactionCount == 0) {
      return ['No transactions recorded for ${DateFormats.monthYear.format(month.start)} yet.'];
    }
    final change = cmp.expenseChangeBps;
    final isCurrent = month == s.currentMonth;
    final spentPhrase = isCurrent ? 'So far this month you have spent' : 'You spent';
    lines.add(change == null
        ? '$spentPhrase ${f(cur.expense)} and received ${f(cur.income)}.'
        : '$spentPhrase ${f(cur.expense)} — ${formatBps(change.abs(), decimals: 0)} ${change >= 0 ? 'more' : 'less'} than ${isCurrent ? 'all of' : ''} last month.'.replaceAll('  ', ' '));
    if (cur.byCategory.isNotEmpty) {
      final top = cur.byCategory.first;
      lines.add('${s.category(top.key)?.name ?? 'One category'} was your largest spend at ${f(top.value)}.');
    }
    final saved = Money.sum(s.savingsMovements.where((m) => month.contains(m.date)).map((m) => m.signedAmount));
    if (saved.isPositive) {
      lines.add('You moved ${f(saved)} into goals and your emergency fund.');
    }
    final repaid = Money.sum(s.loanPayments.where((p) => month.contains(p.date)).map((p) => p.principalComponent));
    if (repaid.isPositive) lines.add('Loan principal went down by ${f(repaid)}.');
    return lines;
  }

  /// Goal contributions in [range] (net).
  Money goalContributions(List<SavingsMovement> movements, DateRange range) =>
      Money.sum(movements.where((m) => range.contains(m.date)).map((m) => m.signedAmount));
}
