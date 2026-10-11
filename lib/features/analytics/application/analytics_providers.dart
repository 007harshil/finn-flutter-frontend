import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/core_providers.dart';
import '../../../app/di/data_providers.dart';
import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/time/dates.dart';
import '../../../finance/finance_snapshot.dart';
import '../../../finance/ledger.dart';
import '../../budgets/domain/budget.dart';
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

/// Formats amounts inside headline copy (lets the UI mask them).
typedef MoneyText = String Function(Money m);

String _defaultMoney(Money m) => m.format(decimals: DecimalDisplay.none);

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
    required this.methods,
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
  final List<MapEntry<PaymentMethod, Money>> methods;
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

  bool get hasActivity => current.transactionCount > 0;
  bool get monthsHaveActivity => months.any((m) => m.income.isPositive || m.expense.isPositive);
  int get windowMonths => months.length;

  int? get expenseChangeBps =>
      previous.expense.isZero ? null : (current.expense - previous.expense).ratioBps(previous.expense);

  /// Savings rate in bps clamped to ±100%; null without income.
  int? get savingsRateBps => current.savingsRateBps?.clamp(-10000, 10000);

  Money get windowNet => Money.sum(months.map((m) => m.net));

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
    if (methods.isEmpty) return 'No payments recorded yet';
    final top = methods.first;
    final share = top.value.ratioBps(current.expense) ?? 0;
    return '${top.key.label} carried ${formatBps(share, decimals: 0)} of your spending';
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
    methods: current.byMethod,
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
  );
}

/// Insights for the current filter. Recomputed only when the snapshot or
/// the filter changes.
final insightsDataProvider = Provider<AsyncValue<InsightsData>>((ref) {
  final filter = ref.watch(insightsFilterProvider);
  return ref.watch(financeSnapshotProvider).whenData((s) => buildInsightsData(s, filter, service: analyticsService));
});
