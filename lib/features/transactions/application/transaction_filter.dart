import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/core_providers.dart';
import '../../../app/di/data_providers.dart';
import '../../../core/money/money.dart';
import '../../../core/time/dates.dart';
import '../../categories/domain/category.dart';
import '../domain/transaction.dart';

/// Sort orders offered on the Activity screen.
enum TransactionSort {
  newest('Newest first'),
  oldest('Oldest first'),
  highest('Highest amount'),
  lowest('Lowest amount');

  const TransactionSort(this.label);
  final String label;

  /// Date-ordered lists are grouped under day headers; amount-ordered
  /// lists are flat (each row shows its date instead).
  bool get groupsByDate => this == newest || this == oldest;
}

/// Inclusive amount bounds in paise; a null side is open-ended.
@immutable
class AmountRange {
  const AmountRange({this.minPaise, this.maxPaise})
      : assert(minPaise == null || maxPaise == null || minPaise <= maxPaise, 'min above max');

  final int? minPaise;
  final int? maxPaise;

  bool get isOpen => minPaise == null && maxPaise == null;

  bool contains(Money m) =>
      (minPaise == null || m.paise >= minPaise!) && (maxPaise == null || m.paise <= maxPaise!);

  @override
  bool operator ==(Object other) => other is AmountRange && other.minPaise == minPaise && other.maxPaise == maxPaise;

  @override
  int get hashCode => Object.hash(minPaise, maxPaise);
}

/// Everything the Activity screen filters on. Immutable; persisted in
/// [transactionFilterProvider] so it survives tab switches.
@immutable
class TransactionFilter {
  const TransactionFilter({
    required this.month,
    this.customRange,
    this.query = '',
    this.type,
    this.categoryIds = const {},
    this.amount,
    this.methods = const {},
    this.origins = const {},
    this.sort = TransactionSort.newest,
  });

  /// Month shown when no [customRange] is set.
  final MonthKey month;

  /// Explicit date range; overrides [month] when present.
  final DateRange? customRange;
  final String query;

  /// Null means income and expense.
  final TransactionType? type;
  final Set<String> categoryIds;

  /// Amount bounds; null means any amount.
  final AmountRange? amount;

  /// Payment methods to keep; empty means all. Transactions without a
  /// method count as [PaymentMethod.other].
  final Set<PaymentMethod> methods;

  /// Where the transaction came from (manual, subscription, EMI …);
  /// empty means all.
  final Set<TransactionOrigin> origins;
  final TransactionSort sort;

  DateRange get range => customRange ?? month.range;
  bool get hasCustomRange => customRange != null;

  /// Whether anything narrows the list beyond the period.
  bool get hasRefinements => query.trim().isNotEmpty || type != null || advancedCount > 0;

  /// Number of filter groups set in the filter sheet (badge count).
  int get advancedCount =>
      (categoryIds.isNotEmpty ? 1 : 0) +
      (amount != null ? 1 : 0) +
      (methods.isNotEmpty ? 1 : 0) +
      (origins.isNotEmpty ? 1 : 0);

  TransactionFilter copyWith({
    MonthKey? month,
    DateRange? Function()? customRange,
    String? query,
    TransactionType? Function()? type,
    Set<String>? categoryIds,
    AmountRange? Function()? amount,
    Set<PaymentMethod>? methods,
    Set<TransactionOrigin>? origins,
    TransactionSort? sort,
  }) =>
      TransactionFilter(
        month: month ?? this.month,
        customRange: customRange != null ? customRange() : this.customRange,
        query: query ?? this.query,
        type: type != null ? type() : this.type,
        categoryIds: categoryIds ?? this.categoryIds,
        amount: amount != null ? amount() : this.amount,
        methods: methods ?? this.methods,
        origins: origins ?? this.origins,
        sort: sort ?? this.sort,
      );

  @override
  bool operator ==(Object other) =>
      other is TransactionFilter &&
      other.month == month &&
      other.customRange == customRange &&
      other.query == query &&
      other.type == type &&
      setEquals(other.categoryIds, categoryIds) &&
      other.amount == amount &&
      setEquals(other.methods, methods) &&
      setEquals(other.origins, origins) &&
      other.sort == sort;

  @override
  int get hashCode => Object.hash(month, customRange, query, type, Object.hashAllUnordered(categoryIds), amount,
      Object.hashAllUnordered(methods), Object.hashAllUnordered(origins), sort);
}

/// Holds the Activity filter. Deliberately not auto-disposed: filters
/// persist while the user visits other tabs and comes back.
class TransactionFilterController extends Notifier<TransactionFilter> {
  @override
  TransactionFilter build() => TransactionFilter(month: ref.read(todayProvider).monthKey);

  void setMonth(MonthKey month) => state = state.copyWith(month: month, customRange: () => null);

  void setRange(DateRange range) => state = state.copyWith(customRange: () => range);

  /// Leaves the custom range and returns to the month containing its end.
  void clearRange() {
    final r = state.customRange;
    state = state.copyWith(month: r?.end.monthKey, customRange: () => null);
  }

  void setQuery(String query) {
    if (query == state.query) return;
    state = state.copyWith(query: query);
  }

  /// Changing the type drops selected categories of the other type.
  void setType(TransactionType? type, {Map<String, TransactionCategory> categories = const {}}) {
    final keep = type == null
        ? state.categoryIds
        : state.categoryIds.where((id) => categories[id] == null || categories[id]!.type == type).toSet();
    state = state.copyWith(type: () => type, categoryIds: keep);
  }

  void setCategories(Set<String> ids) => state = state.copyWith(categoryIds: Set.unmodifiable(ids));

  /// Adds or removes one category (quick toggle from the summary card).
  void toggleCategory(String id) {
    final next = Set<String>.of(state.categoryIds);
    if (!next.remove(id)) next.add(id);
    setCategories(next);
  }

  void setAmount(AmountRange? amount) =>
      state = state.copyWith(amount: () => amount == null || amount.isOpen ? null : amount);

  void setMethods(Set<PaymentMethod> methods) => state = state.copyWith(methods: Set.unmodifiable(methods));

  void setOrigins(Set<TransactionOrigin> origins) => state = state.copyWith(origins: Set.unmodifiable(origins));

  /// Applies everything chosen in the filter sheet at once.
  void applyAdvanced(TransactionFilter from) => state = state.copyWith(
        type: () => from.type,
        categoryIds: Set.unmodifiable(from.categoryIds),
        amount: () => from.amount == null || from.amount!.isOpen ? null : from.amount,
        methods: Set.unmodifiable(from.methods),
        origins: Set.unmodifiable(from.origins),
      );

  void setSort(TransactionSort sort) => state = state.copyWith(sort: sort);

  /// Clears search, type and every sheet filter; keeps the period and sort.
  void clearRefinements() => state = state.copyWith(
        query: '',
        type: () => null,
        categoryIds: const {},
        amount: () => null,
        methods: const {},
        origins: const {},
      );

  /// Applies filters requested by a deep link (e.g. "see all income this
  /// month" from Home). Only the provided values change.
  void applyRoute({TransactionType? type, MonthKey? month}) {
    if (type == null && month == null) return;
    var next = state;
    if (type != null) next = next.copyWith(type: () => type, categoryIds: const {});
    if (month != null) next = next.copyWith(month: month, customRange: () => null);
    state = next;
  }
}

final transactionFilterProvider =
    NotifierProvider<TransactionFilterController, TransactionFilter>(TransactionFilterController.new);

// ---------------------------------------------------------------------------
// Derived feed
// ---------------------------------------------------------------------------

/// One entry of the Activity list: either a day header or a transaction.
@immutable
sealed class FeedEntry {
  const FeedEntry();
}

final class FeedDayHeader extends FeedEntry {
  const FeedDayHeader(this.date, this.net, this.count);
  final DateTime date;

  /// Signed total of the day's (filtered) transactions.
  final Money net;
  final int count;
}

final class FeedTransaction extends FeedEntry {
  const FeedTransaction(this.transaction);
  final Transaction transaction;
}

/// Spending (or earning) of one category within the feed.
@immutable
class CategoryShare {
  const CategoryShare(this.categoryId, this.amount, this.count);
  final String categoryId;
  final Money amount;
  final int count;
}

/// Filtered, sorted and grouped transactions plus totals for the summary.
@immutable
class TransactionFeed {
  const TransactionFeed({
    required this.filter,
    required this.transactions,
    required this.entries,
    required this.rowEntryEnd,
    required this.income,
    required this.expense,
    this.previousIncome = Money.zero,
    this.previousExpense = Money.zero,
    this.dailyExpense = const [],
    this.expenseByCategory = const [],
    this.incomeByCategory = const [],
    this.largestExpense,
  });

  final TransactionFilter filter;
  final List<Transaction> transactions;
  final List<FeedEntry> entries;

  /// `rowEntryEnd[i]` = number of [entries] needed to show the first
  /// `i + 1` transactions (headers included). Used for incremental paging.
  final List<int> rowEntryEnd;

  /// Cash-flow totals (loan disbursements excluded, as in analytics).
  final Money income;
  final Money expense;

  /// Same filters over the comparison period (see
  /// [TransactionQuery.previousPeriod]).
  final Money previousIncome;
  final Money previousExpense;

  /// Spending per day of the period in paise, oldest day first.
  final List<int> dailyExpense;

  /// Category totals, largest first.
  final List<CategoryShare> expenseByCategory;
  final List<CategoryShare> incomeByCategory;
  final Transaction? largestExpense;

  Money get net => income - expense;
  int get count => transactions.length;
  bool get isEmpty => transactions.isEmpty;

  /// Entries to render when showing the first [rows] transactions.
  int entryCountFor(int rows) {
    if (rows <= 0 || transactions.isEmpty) return 0;
    if (rows >= transactions.length) return entries.length;
    return rowEntryEnd[rows - 1];
  }
}

/// Pure filtering/sorting/grouping so it can be tested without widgets.
abstract final class TransactionQuery {
  /// What the period is compared against: the previous calendar month (only
  /// up to the same day when browsing the current month, so a half month is
  /// not compared with a full one), or the equal-length range before a
  /// custom range.
  static DateRange previousPeriod(TransactionFilter filter, DateTime today) {
    if (filter.hasCustomRange) return filter.range.previous;
    final prev = filter.month.previous;
    if (!filter.month.contains(today)) return prev.range;
    return DateRange(prev.start, DateTime(prev.year, prev.month, today.day.clamp(1, prev.dayCount)));
  }

  /// Whether [t] passes every filter except the period.
  static bool passes(
    Transaction t,
    TransactionFilter filter,
    Map<String, TransactionCategory> categories, {
    String? normalisedQuery,
    String? amountQuery,
  }) {
    if (filter.type != null && t.type != filter.type) return false;
    if (filter.categoryIds.isNotEmpty && !filter.categoryIds.contains(t.categoryId)) return false;
    final amount = filter.amount;
    if (amount != null && !amount.contains(t.amount)) return false;
    if (filter.methods.isNotEmpty && !filter.methods.contains(t.paymentMethod ?? PaymentMethod.other)) return false;
    if (filter.origins.isNotEmpty && !filter.origins.contains(t.origin)) return false;
    final q = normalisedQuery ?? _normalise(filter.query);
    if (q.isNotEmpty && !_matches(t, q, amountQuery ?? _amountDigits(filter.query), categories)) return false;
    return true;
  }

  /// How many transactions [filter] would show (live count in the sheet).
  static int count(
    List<Transaction> transactions,
    TransactionFilter filter,
    Map<String, TransactionCategory> categories,
  ) {
    final range = filter.range;
    final q = _normalise(filter.query);
    final amountQuery = _amountDigits(filter.query);
    var n = 0;
    for (final t in transactions) {
      if (range.contains(t.date) && passes(t, filter, categories, normalisedQuery: q, amountQuery: amountQuery)) n++;
    }
    return n;
  }

  static TransactionFeed build(
    List<Transaction> sortedNewestFirst,
    TransactionFilter filter,
    Map<String, TransactionCategory> categories, {
    DateTime? today,
  }) {
    final range = filter.range;
    final prevRange = previousPeriod(filter, today ?? range.end);
    final q = _normalise(filter.query);
    final amountQuery = _amountDigits(filter.query);
    final result = <Transaction>[];
    var prevIncome = 0;
    var prevExpense = 0;
    for (final t in sortedNewestFirst) {
      final inRange = range.contains(t.date);
      if (!inRange && !prevRange.contains(t.date)) continue;
      if (!passes(t, filter, categories, normalisedQuery: q, amountQuery: amountQuery)) continue;
      if (inRange) {
        result.add(t);
      } else if (t.countsInCashFlowAnalytics) {
        if (t.isIncome) {
          prevIncome += t.amount.paise;
        } else {
          prevExpense += t.amount.paise;
        }
      }
    }

    switch (filter.sort) {
      case TransactionSort.newest:
        break; // input is already newest first
      case TransactionSort.oldest:
        result.setAll(0, result.reversed.toList());
      case TransactionSort.highest:
        result.sort((a, b) {
          final c = b.amount.compareTo(a.amount);
          return c != 0 ? c : b.date.compareTo(a.date);
        });
      case TransactionSort.lowest:
        result.sort((a, b) {
          final c = a.amount.compareTo(b.amount);
          return c != 0 ? c : b.date.compareTo(a.date);
        });
    }

    var income = 0;
    var expense = 0;
    final days = range.dayCount;
    final daily = List<int>.filled(days, 0);
    final expenseCats = <String, (int, int)>{};
    final incomeCats = <String, (int, int)>{};
    Transaction? largest;
    for (final t in result) {
      if (!t.countsInCashFlowAnalytics) continue;
      final cats = t.isIncome ? incomeCats : expenseCats;
      final prev = cats[t.categoryId] ?? (0, 0);
      cats[t.categoryId] = (prev.$1 + t.amount.paise, prev.$2 + 1);
      if (t.isIncome) {
        income += t.amount.paise;
      } else {
        expense += t.amount.paise;
        daily[daysBetween(range.start, t.date).clamp(0, days - 1)] += t.amount.paise;
        if (largest == null || t.amount > largest.amount) largest = t;
      }
    }
    List<CategoryShare> shares(Map<String, (int, int)> m) => List.unmodifiable(
          m.entries.map((e) => CategoryShare(e.key, Money.fromPaise(e.value.$1), e.value.$2)).toList()
            ..sort((a, b) => b.amount.compareTo(a.amount)),
        );

    final entries = <FeedEntry>[];
    final rowEnd = <int>[];
    if (filter.sort.groupsByDate) {
      var i = 0;
      while (i < result.length) {
        final day = result[i].date;
        var j = i;
        var net = 0;
        while (j < result.length && result[j].date.isSameDay(day)) {
          net += result[j].signedAmount.paise;
          j++;
        }
        entries.add(FeedDayHeader(day, Money.fromPaise(net), j - i));
        for (var k = i; k < j; k++) {
          entries.add(FeedTransaction(result[k]));
          rowEnd.add(entries.length);
        }
        i = j;
      }
    } else {
      for (final t in result) {
        entries.add(FeedTransaction(t));
        rowEnd.add(entries.length);
      }
    }

    return TransactionFeed(
      filter: filter,
      transactions: List.unmodifiable(result),
      entries: List.unmodifiable(entries),
      rowEntryEnd: List.unmodifiable(rowEnd),
      income: Money.fromPaise(income),
      expense: Money.fromPaise(expense),
      previousIncome: Money.fromPaise(prevIncome),
      previousExpense: Money.fromPaise(prevExpense),
      dailyExpense: List.unmodifiable(daily),
      expenseByCategory: shares(expenseCats),
      incomeByCategory: shares(incomeCats),
      largestExpense: largest,
    );
  }

  static String _normalise(String s) => s.trim().toLowerCase();

  /// Digits of the query when it looks like an amount ("₹1,250" → "1250").
  static String? _amountDigits(String query) {
    final cleaned = query.replaceAll(RegExp(r'[₹,\s]'), '');
    if (cleaned.isEmpty || !RegExp(r'^\d+(\.\d{0,2})?$').hasMatch(cleaned)) return null;
    return cleaned;
  }

  static bool _matches(Transaction t, String q, String? amountDigits, Map<String, TransactionCategory> categories) {
    if ((t.counterparty ?? '').toLowerCase().contains(q)) return true;
    if ((t.note ?? '').toLowerCase().contains(q)) return true;
    final cat = categories[t.categoryId];
    if (cat != null && cat.name.toLowerCase().contains(q)) return true;
    if (amountDigits != null) {
      final rupees = t.amount.rupeePart.toString();
      if (amountDigits.contains('.')) return t.amount.toDecimalString().startsWith(amountDigits);
      if (rupees.contains(amountDigits)) return true;
    }
    return false;
  }
}

/// The Activity list for the current filter. Recomputed only when the
/// transactions, categories or filter change — never in `build`.
final transactionFeedProvider = Provider<AsyncValue<TransactionFeed>>((ref) {
  final filter = ref.watch(transactionFilterProvider);
  final txs = ref.watch(sortedTransactionsProvider);
  final cats = ref.watch(categoriesByIdProvider);
  if (txs.hasError) return AsyncError(txs.error!, txs.stackTrace ?? StackTrace.current);
  if (cats.hasError) return AsyncError(cats.error!, cats.stackTrace ?? StackTrace.current);
  if (!txs.hasValue || !cats.hasValue) return const AsyncLoading();
  final today = ref.watch(todayProvider);
  return AsyncData(TransactionQuery.build(txs.requireValue, filter, cats.requireValue, today: today));
});

/// Earliest and latest month that can be browsed (bounds the month switcher).
@immutable
class ActivityMonthBounds {
  const ActivityMonthBounds(this.first, this.last);
  final MonthKey first;
  final MonthKey last;

  @override
  bool operator ==(Object other) => other is ActivityMonthBounds && other.first == first && other.last == last;

  @override
  int get hashCode => Object.hash(first, last);
}

final activityMonthBoundsProvider = Provider<ActivityMonthBounds>((ref) {
  final today = ref.watch(todayProvider).monthKey;
  final list = ref.watch(sortedTransactionsProvider).value;
  final oldest = (list == null || list.isEmpty) ? today : list.last.date.monthKey;
  final newest = (list == null || list.isEmpty) ? today : list.first.date.monthKey;
  return ActivityMonthBounds(oldest < today ? oldest : today, newest > today ? newest : today);
});
