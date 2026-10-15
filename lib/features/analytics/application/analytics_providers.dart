import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/core_providers.dart';
import '../../../app/di/data_providers.dart';
import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/time/dates.dart';
import '../../../finance/finance_snapshot.dart';
import '../../../finance/ledger.dart';
import '../../accounts/domain/money_account.dart';
import '../../budgets/domain/budget.dart';
import '../../goals/domain/goal.dart';
import '../../loans/domain/loan_calculator.dart';
import '../../subscriptions/domain/subscription.dart';
import '../../transactions/domain/transaction.dart';
import '../domain/analytics.dart';

/// Time window shown on the Insights screen.
enum InsightsPeriod {
  month('This month', 1),
  quarter('3 months', 3),
  half('6 months', 6),
  year('12 months', 12);

  const InsightsPeriod(this.label, this.months);
  final String label;
  final int months;
}

@immutable
class InsightsFilter {
  const InsightsFilter({required this.period, required this.month});

  final InsightsPeriod period;

  /// Month shown in single-month view (multi-month views end this month).
  final MonthKey month;

  InsightsFilter copyWith({InsightsPeriod? period, MonthKey? month}) =>
      InsightsFilter(period: period ?? this.period, month: month ?? this.month);

  @override
  bool operator ==(Object other) => other is InsightsFilter && other.period == period && other.month == month;

  @override
  int get hashCode => Object.hash(period, month);
}

/// How far back the month switcher goes.
const int insightsHistoryMonths = 24;

class InsightsFilterController extends Notifier<InsightsFilter> {
  @override
  InsightsFilter build() => InsightsFilter(period: InsightsPeriod.month, month: ref.watch(todayProvider).monthKey);

  MonthKey get _current => ref.read(todayProvider).monthKey;

  void setPeriod(InsightsPeriod p) {
    // Multi-month views always end with the current month.
    state = InsightsFilter(period: p, month: p == InsightsPeriod.month ? state.month : _current);
  }

  void setMonth(MonthKey m) {
    final max = _current;
    final min = max.shift(-(insightsHistoryMonths - 1));
    final clamped = m > max ? max : (m < min ? min : m);
    state = state.copyWith(period: InsightsPeriod.month, month: clamped);
  }
}

final insightsFilterProvider =
    NotifierProvider<InsightsFilterController, InsightsFilter>(InsightsFilterController.new);

/// The topic chips on the Insights screen. Each one shows only its own
/// numbers and charts.
enum InsightsSection {
  overview('Overview'),
  spending('Daily spend'),
  cashFlow('In vs out'),
  categories('Categories'),
  payments('Payments'),
  budgets('Budgets'),
  savings('Savings'),
  loans('Loans'),
  subscriptions('Subscriptions');

  const InsightsSection(this.label);
  final String label;
}

class InsightsSectionController extends Notifier<InsightsSection> {
  @override
  InsightsSection build() => InsightsSection.overview;

  void select(InsightsSection s) => state = s;
}

final insightsSectionProvider =
    NotifierProvider<InsightsSectionController, InsightsSection>(InsightsSectionController.new);

/// Spending on one calendar day.
@immutable
class DaySpend {
  const DaySpend(this.date, this.amount, {this.isFuture = false});
  final DateTime date;
  final Money amount;

  /// Day after today: nothing could have been spent yet.
  final bool isFuture;
}

/// Formats amounts inside headline copy (lets the UI mask them).
typedef MoneyText = String Function(Money m);

String _defaultMoney(Money m) => m.format(decimals: DecimalDisplay.none);

/// Spending through one money account in the analysed period.
@immutable
class AccountSpend {
  const AccountSpend({required this.accountId, required this.name, required this.kind, required this.amount});
  final String accountId;
  final String name;
  final MoneyAccountKind kind;
  final Money amount;
}

/// Everything the Insights screen shows, computed once per snapshot and
/// filter. Widgets only lay this out.
@immutable
class InsightsData {
  const InsightsData({
    required this.filter,
    required this.range,
    required this.previousRange,
    required this.isPartial,
    required this.periodLabel,
    required this.previousLabel,
    required this.current,
    required this.previous,
    required this.dailyBurn,
    required this.months,
    required this.categories,
    required this.accountSpend,
    required this.budgets,
    required this.budgetPeriod,
    required this.savings,
    required this.debt,
    required this.subscriptionsMonthly,
    required this.subscriptionsAnnual,
    required this.topSubscriptions,
    required this.activeSubscriptionCount,
    required this.insights,
    required this.today,
    this.dailySpend = const [],
    this.weekdayAverages = const [],
    this.topExpenses = const [],
    this.goals = const [],
    this.loans = const [],
  });

  final InsightsFilter filter;

  /// Selected period (ends today when it includes today).
  final DateRange range;
  final DateRange previousRange;

  /// True when [range] is still in progress.
  final bool isPartial;
  final String periodLabel;

  /// e.g. "September" or "the previous 3 months".
  final String previousLabel;
  final PeriodSummary current;
  final PeriodSummary previous;
  final Money dailyBurn;

  /// Monthly series for the trend charts, oldest first.
  final List<MonthlyCashFlow> months;
  final List<CategorySlice> categories;
  /// Spending per account in the period, biggest first.
  final List<AccountSpend> accountSpend;
  final List<BudgetUsage> budgets;
  final DateRange budgetPeriod;
  final List<TrendPoint> savings;
  final List<TrendPoint> debt;
  final Money subscriptionsMonthly;
  final Money subscriptionsAnnual;
  final List<Subscription> topSubscriptions;
  final int activeSubscriptionCount;
  final List<Insight> insights;
  final DateTime today;

  /// Every day of the selected month (single-month view only; empty for
  /// multi-month views, which use [months]).
  final List<DaySpend> dailySpend;

  /// Average spend on each weekday in the period, Monday first (7 items).
  final List<Money> weekdayAverages;

  /// Largest single expenses in the period, biggest first.
  final List<Transaction> topExpenses;
  final List<GoalProgress> goals;

  /// Borrowed loans that still have money outstanding.
  final List<LoanState> loans;

  bool get hasActivity => current.transactionCount > 0;
  bool get monthsHaveActivity => months.any((m) => m.income.isPositive || m.expense.isPositive);
  int get windowMonths => months.length;

  int? get expenseChangeBps =>
      previous.expense.isZero ? null : (current.expense - previous.expense).ratioBps(previous.expense);

  /// Savings rate in bps clamped to ±100%; null without income.
  int? get savingsRateBps => current.savingsRateBps?.clamp(-10000, 10000);

  Money get windowNet => Money.sum(months.map((m) => m.net));

  // ---- Baselines --------------------------------------------------------

  /// Months in the window that have any income or spending.
  List<MonthlyCashFlow> get activeMonths =>
      [for (final m in months) if (m.income.isPositive || m.expense.isPositive) m];

  static Money _avg(Iterable<Money> xs) {
    final l = xs.toList();
    return l.isEmpty ? Money.zero : Money.sum(l).scale(1, l.length);
  }

  /// Typical month, averaged over months that have activity.
  Money get avgMonthlyIncome => _avg(activeMonths.map((m) => m.income));
  Money get avgMonthlyExpense => _avg(activeMonths.map((m) => m.expense));
  Money get avgMonthlyNet => _avg(activeMonths.map((m) => m.net));

  /// The day with the most spending (single-month view).
  DaySpend? get peakDay {
    DaySpend? best;
    for (final d in dailySpend) {
      if (d.amount.isPositive && (best == null || d.amount > best.amount)) best = d;
    }
    return best;
  }

  /// Days in the selected month with no spending at all (up to today).
  int get noSpendDays => dailySpend.where((d) => !d.isFuture && d.amount.isZero).length;

  /// Days of the selected month that have happened (today included).
  int get elapsedDays => dailySpend.where((d) => !d.isFuture).length;

  /// Where spending lands at month end if the daily average holds. Only
  /// for a month still in progress.
  Money? get projectedMonthSpend {
    if (filter.period != InsightsPeriod.month || !isPartial || dailySpend.isEmpty) return null;
    return dailyBurn.times(dailySpend.length);
  }

  /// Index (0 = Monday) of the weekday with the highest average spend.
  int? get busiestWeekday {
    var best = -1;
    for (var i = 0; i < weekdayAverages.length; i++) {
      if (weekdayAverages[i].isPositive && (best < 0 || weekdayAverages[i] > weekdayAverages[best])) best = i;
    }
    return best < 0 ? null : best;
  }

  /// Index (0 = Monday) of the weekday with the lowest average spend.
  int? get quietestWeekday {
    if (busiestWeekday == null) return null;
    var best = 0;
    for (var i = 1; i < weekdayAverages.length; i++) {
      if (weekdayAverages[i] < weekdayAverages[best]) best = i;
    }
    return best;
  }

  /// Share of spending paid digitally (everything except cash), in bps.
  int? get digitalShareBps {
    if (current.expense.isZero) return null;
    final cash = Money.sum(accountSpend.where((a) => a.kind == MoneyAccountKind.cash).map((a) => a.amount));
    return (current.expense - cash).ratioBps(current.expense);
  }

  Iterable<BudgetUsage> get _activeBudgets => budgets.where((b) => b.health != BudgetHealth.paused);

  /// Totals across active (not paused) budgets.
  Money get budgetLimitTotal => Money.sum(_activeBudgets.map((b) => b.budget.limit));
  Money get budgetSpentTotal => Money.sum(_activeBudgets.map((b) => b.spent));

  /// How far through the budget period today is, in bps.
  int get budgetElapsedBps {
    final total = budgetPeriod.dayCount;
    final end = today.isAfter(budgetPeriod.end) ? budgetPeriod.end : today;
    final done = end.isBefore(budgetPeriod.start) ? 0 : daysBetween(budgetPeriod.start, end) + 1;
    return (done * 10000 / total).round().clamp(0, 10000);
  }

  /// Days left in the budget period, today included.
  int get budgetDaysLeft {
    if (today.isAfter(budgetPeriod.end)) return 0;
    final from = today.isBefore(budgetPeriod.start) ? budgetPeriod.start : today;
    return daysBetween(from, budgetPeriod.end) + 1;
  }

  /// Amount that can be spent each remaining day without crossing the
  /// combined budget limit. Null without active budgets.
  Money? get budgetSafeDaily {
    if (budgetLimitTotal.isZero || budgetDaysLeft == 0) return null;
    final left = budgetLimitTotal - budgetSpentTotal;
    return left.isNegative ? Money.zero : left.scale(1, budgetDaysLeft);
  }

  /// Net change in earmarked savings across the window.
  Money get savingsChange => savings.isEmpty ? Money.zero : savings.last.value - savings.first.value;

  /// Average monthly change in savings across the window.
  Money get avgMonthlySavingsChange =>
      savings.length < 2 ? Money.zero : savingsChange.scale(1, savings.length - 1);

  /// Debt repaid across the window (positive when debt went down).
  Money get debtRepaid => debt.isEmpty ? Money.zero : debt.first.value - debt.last.value;

  Money get avgMonthlyDebtRepaid => debt.length < 2 ? Money.zero : debtRepaid.scale(1, debt.length - 1);

  /// Months until debt reaches zero at the recent repayment pace; null
  /// when debt is not going down.
  int? get monthsToDebtFree {
    final pace = avgMonthlyDebtRepaid;
    if (debt.isEmpty || !pace.isPositive || debt.last.value.isZero) return null;
    return (debt.last.value.paise / pace.paise).ceil();
  }

  // ---- Takeaway headlines ----------------------------------------------

  String spendingHeadline([MoneyText f = _defaultMoney]) {
    if (!hasActivity) return 'No spending recorded for $periodLabel';
    final c = expenseChangeBps;
    if (c == null) return 'You spent ${f(current.expense)} in $periodLabel';
    if (c.abs() < 100) return 'Spending is level with $previousLabel';
    final pct = formatBps(c.abs(), decimals: 0);
    final verb = isPartial ? 'So far you have spent' : 'You spent';
    return '$verb $pct ${c < 0 ? 'less' : 'more'} than $previousLabel';
  }

  String get incomeVsExpenseHeadline {
    final active = months.where((m) => m.income.isPositive || m.expense.isPositive).toList();
    if (active.isEmpty) return 'No income or spending recorded yet';
    final covered = active.where((m) => m.income >= m.expense).length;
    if (covered == active.length) {
      return active.length == 1 ? 'Income covered spending' : 'Income covered spending in every month';
    }
    return 'Income covered spending in $covered of ${active.length} months';
  }

  String netHeadline([MoneyText f = _defaultMoney]) {
    if (!monthsHaveActivity) return 'No cash flow to show yet';
    final net = windowNet;
    final span = windowMonths == 1 ? 'this month' : 'over $windowMonths months';
    if (net.isZero) return 'You broke even $span';
    return net.isPositive ? 'You kept ${f(net)} $span' : 'Spending exceeded income by ${f(net.abs())} $span';
  }

  String get categoryHeadline {
    if (categories.isEmpty) return 'No spending by category yet';
    final top = categories.first;
    return '${top.name} was your biggest spend at ${formatBps(top.shareBps, decimals: 0)}';
  }

  String get methodHeadline {
    if (accountSpend.isEmpty) return 'No payments recorded yet';
    final top = accountSpend.first;
    final share = top.amount.ratioBps(current.expense) ?? 0;
    return '${top.name} carried ${formatBps(share, decimals: 0)} of your spending';
  }

  int get budgetsOver => budgets.where((b) => b.health == BudgetHealth.breached).length;
  int get budgetsActive => budgets.where((b) => b.health != BudgetHealth.paused).length;

  String get budgetHeadline {
    final active = budgetsActive;
    if (active == 0) return budgets.isEmpty ? 'No budgets set yet' : 'All budgets are paused';
    final over = budgetsOver;
    if (over == 0) return active == 1 ? 'Your budget is on track' : 'All $active budgets are within their limits';
    return over == 1 ? '1 of $active budgets is over its limit' : '$over of $active budgets are over their limits';
  }

  String savingsHeadline([MoneyText f = _defaultMoney]) {
    if (savings.isEmpty || savings.every((p) => p.value.isZero)) return 'No savings earmarked yet';
    final change = savings.last.value - savings.first.value;
    final span = '${savings.length} months';
    if (change.isZero) return 'Savings held steady at ${f(savings.last.value)}';
    return change.isPositive ? 'Savings grew ${f(change)} in $span' : 'Savings dipped ${f(change.abs())} in $span';
  }

  String debtHeadline([MoneyText f = _defaultMoney]) {
    if (debt.isEmpty || debt.every((p) => p.value.isZero)) return 'No outstanding borrowed loans';
    final change = debt.last.value - debt.first.value;
    final span = '${debt.length} months';
    if (change.isZero) return 'Debt is unchanged at ${f(debt.last.value)}';
    return change.isNegative ? 'Debt is down ${f(change.abs())} in $span' : 'Debt is up ${f(change)} in $span';
  }

  String subscriptionHeadline([MoneyText f = _defaultMoney]) {
    if (activeSubscriptionCount == 0) return 'No active subscriptions';
    return '${f(subscriptionsMonthly)} a month in subscriptions';
  }
}

const _monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June', //
  'July', 'August', 'September', 'October', 'November', 'December',
];

String _shortMonth(MonthKey m) => _monthNames[m.month - 1].substring(0, 3);

/// Pure builder for [InsightsData] (unit-testable without Flutter).
InsightsData buildInsightsData(FinanceSnapshot s, InsightsFilter f, {AnalyticsService service = const AnalyticsService()}) {
  final today = s.today;
  final currentMonth = s.currentMonth;
  final n = f.period.months;
  final anchor = f.period == InsightsPeriod.month ? f.month : currentMonth;
  final firstMonth = anchor.shift(-(n - 1));
  final fullEnd = anchor.end;
  final isPartial = !fullEnd.isBefore(today);
  final range = DateRange(firstMonth.start, isPartial ? (today.isBefore(firstMonth.start) ? firstMonth.start : today) : fullEnd);
  final prevFirst = firstMonth.shift(-n);
  final previousRange = DateRange(prevFirst.start, firstMonth.start.subtract(const Duration(days: 1)));

  final String periodLabel;
  final String previousLabel;
  if (n == 1) {
    periodLabel = anchor == currentMonth ? 'this month' : '${_monthNames[anchor.month - 1]} ${anchor.year}';
    previousLabel = isPartial ? 'all of ${_monthNames[prevFirst.month - 1]}' : _monthNames[prevFirst.month - 1];
  } else {
    final sameYear = firstMonth.year == anchor.year;
    periodLabel = '${_shortMonth(firstMonth)}${sameYear ? '' : ' ${firstMonth.year}'} – ${_shortMonth(anchor)} ${anchor.year}';
    previousLabel = 'the previous $n months';
  }

  final windowCount = n == 1 ? 6 : n;
  final spend = _SpendPatterns.of(s, range, single: n == 1 ? anchor : null);
  final current = s.summary(range);
  final previous = s.summary(previousRange);
  final subs = s.subscriptions.where((x) => x.isActive).toList()
    ..sort((a, b) => b.monthlyEquivalent.compareTo(a.monthlyEquivalent));

  return InsightsData(
    filter: f,
    range: range,
    previousRange: previousRange,
    isPartial: isPartial,
    periodLabel: periodLabel,
    previousLabel: previousLabel,
    current: current,
    previous: previous,
    dailyBurn: service.dailyBurn(s, range),
    months: service.cashFlow(s, anchor, windowCount),
    categories: service.categoryBreakdown(s, range, compareTo: previousRange),
    accountSpend: [
      for (final e in current.byAccount)
        AccountSpend(
          accountId: e.key,
          name: s.account(e.key)?.name ?? 'Unknown account',
          kind: s.account(e.key)?.kind ?? MoneyAccountKind.bank,
          amount: e.value,
        ),
    ],
    budgets: s.budgetUsages,
    budgetPeriod: s.currentBudgetPeriod,
    savings: service.savingsTrend(s, anchor, windowCount),
    debt: service.debtTrend(s, anchor, windowCount),
    subscriptionsMonthly: s.monthlySubscriptionCommitment,
    subscriptionsAnnual: FinanceSnapshot.subscriptionCalc.annualCommitment(s.subscriptions),
    topSubscriptions: subs.take(5).toList(),
    activeSubscriptionCount: subs.length,
    insights: service.insights(s, anchor),
    today: today,
    dailySpend: spend.daily,
    weekdayAverages: spend.weekday,
    topExpenses: spend.top,
    goals: s.goalProgress,
    loans: [for (final l in s.loanStates) if (l.loan.isBorrowed && !l.isClosed) l],
  );
}

/// Day-level spending patterns for a period: daily totals, weekday
/// averages and the largest expenses.
class _SpendPatterns {
  const _SpendPatterns(this.daily, this.weekday, this.top);

  final List<DaySpend> daily;
  final List<Money> weekday;
  final List<Transaction> top;

  static const _topCount = 5;

  factory _SpendPatterns.of(FinanceSnapshot s, DateRange range, {MonthKey? single}) {
    final today = s.today;
    final perDay = <DateTime, int>{};
    final expenses = <Transaction>[];
    for (final t in s.transactions) {
      final d = t.date.dateOnly;
      if (!t.isExpense || !t.countsInCashFlowAnalytics || !range.contains(d) || d.isAfter(today)) continue;
      expenses.add(t);
      perDay[d] = (perDay[d] ?? 0) + t.amount.paise;
    }

    final daily = <DaySpend>[];
    if (single != null) {
      for (var d = single.start; !d.isAfter(single.end); d = DateTime(d.year, d.month, d.day + 1)) {
        daily.add(DaySpend(d, Money.fromPaise(perDay[d] ?? 0), isFuture: d.isAfter(today)));
      }
    }

    final sums = List<int>.filled(7, 0);
    final counts = List<int>.filled(7, 0);
    final last = range.end.isAfter(today) ? today : range.end;
    for (var d = range.start; !d.isAfter(last); d = DateTime(d.year, d.month, d.day + 1)) {
      final w = d.weekday - 1;
      counts[w]++;
      sums[w] += perDay[d] ?? 0;
    }
    final weekday = [
      for (var i = 0; i < 7; i++) counts[i] == 0 ? Money.zero : Money.fromPaise(sums[i]).scale(1, counts[i]),
    ];

    expenses.sort((a, b) => b.amount.compareTo(a.amount));
    return _SpendPatterns(daily, weekday, expenses.take(_topCount).toList());
  }
}

/// Insights for the current filter. Recomputed only when the snapshot or
/// the filter changes.
final insightsDataProvider = Provider<AsyncValue<InsightsData>>((ref) {
  final filter = ref.watch(insightsFilterProvider);
  return ref.watch(financeSnapshotProvider).whenData((s) => buildInsightsData(s, filter, service: analyticsService));
});
