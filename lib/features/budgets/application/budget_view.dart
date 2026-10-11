import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/data_providers.dart';
import '../../../core/money/money.dart';
import '../../../core/time/dates.dart';
import '../../../finance/finance_snapshot.dart';
import '../../transactions/domain/transaction.dart';
import '../domain/budget.dart';

/// Read models for the redesigned budgets screens. Everything here is a
/// pure function of a [BudgetUsage] (or the snapshot) so the UI only
/// renders, never computes money.

/// The one status a person needs per budget. Health (near/over the limit)
/// and pace (will it run out before the period ends) collapse into a single
/// word so the list can be scanned without reading numbers.
enum BudgetState {
  over('Over limit'),
  risk('At risk'),
  onTrack('On track'),
  paused('Paused');

  const BudgetState(this.label);
  final String label;
}

/// Pace and safe-spend figures for one budget in its current period.
@immutable
class BudgetPace {
  const BudgetPace._({
    required this.usage,
    required this.state,
    required this.daysLeft,
    required this.elapsedDays,
    required this.projected,
    required this.safePerDay,
    required this.runsOutOn,
  });

  factory BudgetPace.of(BudgetUsage u, DateTime today) {
    final p = u.period;
    final t0 = today.dateOnly;
    final started = !t0.isBefore(p.start);
    final ended = t0.isAfter(p.end);
    final elapsed = !started ? 0 : (ended ? p.dayCount : daysBetween(p.start, t0) + 1);
    final daysLeft = ended ? 0 : (started ? daysBetween(t0, p.end) + 1 : p.dayCount);

    // Straight-line projection of the period's total at today's pace. Only
    // honest once at least a couple of days have passed.
    Money? projected;
    if (elapsed >= 2 && !ended) {
      projected = u.spent.scale(p.dayCount, elapsed);
    } else if (ended) {
      projected = u.spent;
    }

    final remaining = u.remaining;
    final safe = remaining.isPositive && daysLeft > 0 ? remaining.scale(1, daysLeft) : null;

    // Day the limit is crossed at today's pace (only when it is still ahead).
    DateTime? runsOut;
    if (projected != null && projected > u.budget.limit && !u.isOver && u.spent.isPositive && elapsed > 0) {
      final day = roundDiv(u.budget.limit.paise * elapsed, u.spent.paise, RoundingMode.up);
      final d = DateTime(p.start.year, p.start.month, p.start.day + day - 1);
      if (!d.isAfter(p.end)) runsOut = d;
    }

    final BudgetState state;
    if (u.budget.isPaused) {
      state = BudgetState.paused;
    } else if (u.isOver) {
      state = BudgetState.over;
    } else if (u.health == BudgetHealth.warning || (projected != null && projected > u.budget.limit)) {
      state = BudgetState.risk;
    } else {
      state = BudgetState.onTrack;
    }
    return BudgetPace._(
      usage: u,
      state: state,
      daysLeft: daysLeft,
      elapsedDays: elapsed,
      projected: projected,
      safePerDay: safe,
      runsOutOn: runsOut,
    );
  }

  final BudgetUsage usage;
  final BudgetState state;
  final int daysLeft;
  final int elapsedDays;

  /// Period total if spending continues at the same daily rate.
  final Money? projected;

  /// What can be spent per remaining day without crossing the limit.
  final Money? safePerDay;

  /// When the limit will be crossed at the current pace (null if never).
  final DateTime? runsOutOn;

  /// The period is over: a past month, shown read-only.
  bool get isPast => daysLeft == 0;

  /// Share of the period gone (0..1), for the "today" marker.
  double get elapsed => usage.elapsedBps / 10000;

  /// Spent share of the limit; may exceed 1.
  double get used => usage.budget.limit.isPositive ? usage.spent.paise / usage.budget.limit.paise : 0;

  /// Projected share of the limit; may exceed 1.
  double? get projectedShare =>
      projected == null || !usage.budget.limit.isPositive ? null : projected!.paise / usage.budget.limit.paise;

  @override
  bool operator ==(Object other) => other is BudgetPace && other.usage == usage && other.daysLeft == daysLeft;

  @override
  int get hashCode => Object.hash(usage, daysLeft);
}

enum BudgetSort {
  urgency('Most urgent'),
  used('Most used'),
  left('Most left'),
  limit('Biggest limit'),
  name('Name');

  const BudgetSort(this.label);
  final String label;
}

/// What the budgets list shows: one status (null = all) and a sort.
@immutable
class BudgetListFilter {
  const BudgetListFilter({this.state, this.sort = BudgetSort.urgency});

  final BudgetState? state;
  final BudgetSort sort;

  /// Options changed beyond the status tabs (for the options badge).
  int get optionCount => sort == BudgetSort.urgency ? 0 : 1;

  BudgetListFilter copyWith({BudgetState? Function()? state, BudgetSort? sort}) => BudgetListFilter(
        state: state != null ? state() : this.state,
        sort: sort ?? this.sort,
      );

  bool accepts(BudgetPace p) => state == null || p.state == state;

  @override
  bool operator ==(Object other) => other is BudgetListFilter && other.state == state && other.sort == sort;

  @override
  int get hashCode => Object.hash(state, sort);
}

int _stateRank(BudgetState s) => BudgetState.values.indexOf(s);

/// Applies [f] to [all]; [names] resolves category names for sorting.
List<BudgetPace> filterBudgets(List<BudgetPace> all, BudgetListFilter f, String Function(BudgetPace) names) {
  final out = all.where(f.accepts).toList();
  int byUsed(BudgetPace a, BudgetPace b) => b.usage.utilizationBps.compareTo(a.usage.utilizationBps);
  out.sort(switch (f.sort) {
    BudgetSort.urgency => (a, b) {
        final s = _stateRank(a.state).compareTo(_stateRank(b.state));
        if (s != 0) return s;
        // Within a state, the one furthest ahead of the calendar first.
        final ahead = (b.used - b.elapsed).compareTo(a.used - a.elapsed);
        return ahead != 0 ? ahead : byUsed(a, b);
      },
    BudgetSort.used => byUsed,
    BudgetSort.left => (a, b) => b.usage.remaining.compareTo(a.usage.remaining),
    BudgetSort.limit => (a, b) => b.usage.budget.limit.compareTo(a.usage.budget.limit),
    BudgetSort.name => (a, b) => names(a).toLowerCase().compareTo(names(b).toLowerCase()),
  });
  return out;
}

/// One budget month at a glance: totals of active budgets with the same
/// pace maths as a single budget. Past months are read-only history.
@immutable
class BudgetsPulse {
  const BudgetsPulse({
    required this.month,
    required this.currentMonth,
    required this.firstMonth,
    required this.period,
    required this.limit,
    required this.spent,
    required this.committed,
    required this.daysLeft,
    required this.elapsed,
    required this.projected,
    required this.paces,
  });

  /// The budget month shown (keyed by the month its period starts in).
  final MonthKey month;
  final MonthKey currentMonth;

  /// Earliest month with a budget (navigation lower bound).
  final MonthKey firstMonth;
  final DateRange period;
  final Money limit;
  final Money spent;
  final Money committed;
  final int daysLeft;

  /// Share of the period gone (0..1).
  final double elapsed;
  final Money? projected;

  /// Every budget (active and paused), unsorted.
  final List<BudgetPace> paces;

  /// Past months can be viewed but not changed.
  bool get isPast => month < currentMonth;
  Money get remaining => limit - spent;
  bool get isOver => spent > limit;
  bool get hasTotals => limit.isPositive;
  double get used => limit.isPositive ? spent.paise / limit.paise : 0;
  double? get projectedShare => projected == null || !limit.isPositive ? null : projected!.paise / limit.paise;
  Money? get safePerDay => remaining.isPositive && daysLeft > 0 ? remaining.scale(1, daysLeft) : null;

  int count(BudgetState s) => paces.where((p) => p.state == s).length;
  Map<BudgetState, int> get counts => {for (final s in BudgetState.values) s: count(s)};

  @override
  bool operator ==(Object other) =>
      other is BudgetsPulse &&
      other.month == month &&
      other.currentMonth == currentMonth &&
      other.firstMonth == firstMonth &&
      other.limit == limit &&
      other.spent == spent &&
      other.committed == committed &&
      other.daysLeft == daysLeft &&
      listEquals(other.paces, paces);

  @override
  int get hashCode => Object.hash(month, limit, spent, committed, daysLeft, paces.length);
}

/// Pulse of budget [month] (default: this month).
BudgetsPulse buildBudgetsPulse(FinanceSnapshot s, {MonthKey? month}) {
  final current = s.currentBudgetMonth;
  final m = month == null || month > current ? current : month;
  final period = m == current ? s.currentBudgetPeriod : FinanceSnapshot.budgetCalc.periodOf(m, s.monthStartDay);
  final paces = [for (final u in s.budgetUsagesFor(m)) BudgetPace.of(u, s.today)];
  var limit = Money.zero;
  var spent = Money.zero;
  var committed = Money.zero;
  for (final p in paces) {
    final u = p.usage;
    if (u.budget.isPaused) continue;
    limit += u.budget.limit;
    spent += u.spent;
    committed += u.committed;
  }
  final ended = s.today.isAfter(period.end);
  final elapsedDays = ended ? period.dayCount : (daysBetween(period.start, s.today) + 1).clamp(0, period.dayCount);
  final daysLeft = ended ? 0 : (daysBetween(s.today, period.end) + 1).clamp(0, period.dayCount);
  final first = s.firstBudgetMonth;
  return BudgetsPulse(
    month: m,
    currentMonth: current,
    firstMonth: first == null || first > current ? current : first,
    period: period,
    limit: limit,
    spent: spent,
    committed: committed,
    daysLeft: daysLeft,
    elapsed: elapsedDays / period.dayCount,
    projected: ended ? spent : (elapsedDays >= 2 ? spent.scale(period.dayCount, elapsedDays) : null),
    paces: paces,
  );
}

/// Pulse per budget month (null = this month).
final budgetsPulseProvider = Provider.family<AsyncValue<BudgetsPulse>, MonthKey?>(
    (ref, month) => ref.watch(financeSnapshotProvider).whenData((s) => buildBudgetsPulse(s, month: month)));

BudgetUsage? _usageIn(FinanceSnapshot s, String id, MonthKey? month) =>
    (month == null ? s.budgetUsages : s.budgetUsagesFor(month)).where((u) => u.budget.id == id).firstOrNull;

/// Pace of (budget id, budget month); null month = this month.
final budgetPaceProvider = Provider.family<AsyncValue<BudgetPace?>, (String, MonthKey?)>((ref, key) {
  return ref.watch(financeSnapshotProvider).whenData((s) {
    final u = _usageIn(s, key.$1, key.$2);
    return u == null ? null : BudgetPace.of(u, s.today);
  });
});

/// Day-by-day spending of one budget in its current period.
@immutable
class BudgetBurn {
  const BudgetBurn({required this.period, required this.daily, required this.todayIndex, required this.transactions});

  final DateRange period;

  /// Paise spent on each day of [period] (index 0 = first day).
  final List<int> daily;

  /// Index of today in [daily] (−1 before the period, length after it).
  final int todayIndex;

  /// The period's transactions, newest first.
  final List<Transaction> transactions;

  /// Running total per day.
  List<int> get cumulative {
    var sum = 0;
    return [for (final d in daily) sum += d];
  }

  DateTime dayAt(int i) => DateTime(period.start.year, period.start.month, period.start.day + i);

  int indexOf(DateTime d) => daysBetween(period.start, d.dateOnly);

  @override
  bool operator ==(Object other) =>
      other is BudgetBurn && other.period == period && listEquals(other.daily, daily) && other.todayIndex == todayIndex;

  @override
  int get hashCode => Object.hash(period, Object.hashAll(daily), todayIndex);
}

BudgetBurn buildBudgetBurn(FinanceSnapshot s, BudgetUsage u) {
  final p = u.period;
  final daily = List<int>.filled(p.dayCount, 0);
  final txs = <Transaction>[];
  for (final id in u.transactionIds) {
    final t = s.transactionById[id];
    if (t == null) continue;
    txs.add(t);
    final i = daysBetween(p.start, t.date.dateOnly);
    if (i >= 0 && i < daily.length) daily[i] += t.amount.paise;
  }
  txs.sort((a, b) {
    final d = b.date.compareTo(a.date);
    return d != 0 ? d : b.createdAt.compareTo(a.createdAt);
  });
  final today = daysBetween(p.start, s.today).clamp(-1, p.dayCount);
  return BudgetBurn(period: p, daily: daily, todayIndex: today, transactions: txs);
}

/// Burn of (budget id, budget month); null month = this month.
final budgetBurnProvider = Provider.family<AsyncValue<BudgetBurn?>, (String, MonthKey?)>((ref, key) {
  return ref.watch(financeSnapshotProvider).whenData((s) {
    final u = _usageIn(s, key.$1, key.$2);
    return u == null ? null : buildBudgetBurn(s, u);
  });
});

/// "Where it went": spending in a budget grouped by merchant / payee.
List<(String, Money, int)> topPayees(List<Transaction> txs, {int limit = 4}) {
  final sums = <String, int>{};
  final counts = <String, int>{};
  for (final t in txs) {
    final key = payeeOf(t);
    sums[key] = (sums[key] ?? 0) + t.amount.paise;
    counts[key] = (counts[key] ?? 0) + 1;
  }
  final out = [for (final e in sums.entries) (e.key, Money.fromPaise(e.value), counts[e.key]!)]
    ..sort((a, b) => b.$2.compareTo(a.$2));
  return out.take(limit).toList();
}

/// The label a transaction is grouped under in [topPayees].
String payeeOf(Transaction t) => t.displayTitle?.trim() ?? 'Other';
