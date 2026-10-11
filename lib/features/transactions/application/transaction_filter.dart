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
  final TransactionSort sort;

  DateRange get range => customRange ?? month.range;
  bool get hasCustomRange => customRange != null;

  /// Whether anything narrows the list beyond the period.
  bool get hasRefinements => query.trim().isNotEmpty || type != null || categoryIds.isNotEmpty;

  TransactionFilter copyWith({
    MonthKey? month,
    DateRange? Function()? customRange,
    String? query,
    TransactionType? Function()? type,
    Set<String>? categoryIds,
    TransactionSort? sort,
  }) =>
      TransactionFilter(
        month: month ?? this.month,
        customRange: customRange != null ? customRange() : this.customRange,
        query: query ?? this.query,
        type: type != null ? type() : this.type,
        categoryIds: categoryIds ?? this.categoryIds,
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
      other.sort == sort;

  @override
  int get hashCode =>
      Object.hash(month, customRange, query, type, Object.hashAllUnordered(categoryIds), sort);
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

  void setSort(TransactionSort sort) => state = state.copyWith(sort: sort);

  /// Clears search, type and categories; keeps the period and sort.
  void clearRefinements() => state = state.copyWith(query: '', type: () => null, categoryIds: const {});

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

/// Filtered, sorted and grouped transactions plus totals for the strip.
@immutable
class TransactionFeed {
  const TransactionFeed({
    required this.filter,
    required this.transactions,
    required this.entries,
    required this.rowEntryEnd,
    required this.income,
    required this.expense,
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
  static TransactionFeed build(
    List<Transaction> sortedNewestFirst,
    TransactionFilter filter,
    Map<String, TransactionCategory> categories,
  ) {
    final range = filter.range;
    final q = _normalise(filter.query);
    final amountQuery = _amountDigits(filter.query);
    final result = <Transaction>[];
    for (final t in sortedNewestFirst) {
      if (!range.contains(t.date)) continue;
      if (filter.type != null && t.type != filter.type) continue;
      if (filter.categoryIds.isNotEmpty && !filter.categoryIds.contains(t.categoryId)) continue;
      if (q.isNotEmpty && !_matches(t, q, amountQuery, categories)) continue;
      result.add(t);
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
    for (final t in result) {
      if (!t.countsInCashFlowAnalytics) continue;
      if (t.isIncome) {
        income += t.amount.paise;
      } else {
        expense += t.amount.paise;
      }
    }

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
  return AsyncData(TransactionQuery.build(txs.requireValue, filter, cats.requireValue));
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
