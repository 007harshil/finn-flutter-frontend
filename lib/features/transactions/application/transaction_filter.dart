import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/core_providers.dart';
import '../../../app/di/data_providers.dart';
import '../../../core/money/money.dart';
import '../../../core/time/dates.dart';
import '../../accounts/domain/money_account.dart';
import '../../accounts/domain/transfer.dart';
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
    : assert(
        minPaise == null || maxPaise == null || minPaise <= maxPaise,
        'min above max',
      );

  final int? minPaise;
  final int? maxPaise;

  bool get isOpen => minPaise == null && maxPaise == null;

  bool contains(Money m) =>
      (minPaise == null || m.paise >= minPaise!) &&
      (maxPaise == null || m.paise <= maxPaise!);

  @override
  bool operator ==(Object other) =>
      other is AmountRange &&
      other.minPaise == minPaise &&
      other.maxPaise == maxPaise;

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
    this.accountIds = const {},
    this.channels = const {},
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

  /// Money accounts to keep; empty means all.
  final Set<String> accountIds;

  /// Channels to keep (compared case-insensitively); empty means all.
  final Set<String> channels;

  /// Where the transaction came from (manual, subscription, EMI …);
  /// empty means all.
  final Set<TransactionOrigin> origins;
  final TransactionSort sort;

  DateRange get range => customRange ?? month.range;
  bool get hasCustomRange => customRange != null;

  /// Whether anything narrows the list beyond the period.
  bool get hasRefinements =>
      query.trim().isNotEmpty || type != null || advancedCount > 0;

  /// Number of filter groups set in the filter sheet (badge count).
  int get advancedCount =>
      (categoryIds.isNotEmpty ? 1 : 0) +
      (amount != null ? 1 : 0) +
      (accountIds.isNotEmpty ? 1 : 0) +
      (channels.isNotEmpty ? 1 : 0) +
      (origins.isNotEmpty ? 1 : 0);

  TransactionFilter copyWith({
    MonthKey? month,
    DateRange? Function()? customRange,
    String? query,
    TransactionType? Function()? type,
    Set<String>? categoryIds,
    AmountRange? Function()? amount,
    Set<String>? accountIds,
    Set<String>? channels,
    Set<TransactionOrigin>? origins,
    TransactionSort? sort,
  }) => TransactionFilter(
    month: month ?? this.month,
    customRange: customRange != null ? customRange() : this.customRange,
    query: query ?? this.query,
    type: type != null ? type() : this.type,
    categoryIds: categoryIds ?? this.categoryIds,
    amount: amount != null ? amount() : this.amount,
    accountIds: accountIds ?? this.accountIds,
    channels: channels ?? this.channels,
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
      setEquals(other.accountIds, accountIds) &&
      setEquals(other.channels, channels) &&
      setEquals(other.origins, origins) &&
      other.sort == sort;

  @override
  int get hashCode => Object.hash(
    month,
    customRange,
    query,
    type,
    Object.hashAllUnordered(categoryIds),
    amount,
    Object.hashAllUnordered(accountIds),
    Object.hashAllUnordered(channels),
    Object.hashAllUnordered(origins),
    sort,
  );
}

/// Holds the Activity filter. Deliberately not auto-disposed: filters
/// persist while the user visits other tabs and comes back.
class TransactionFilterController extends Notifier<TransactionFilter> {
  @override
  TransactionFilter build() =>
      TransactionFilter(month: ref.read(todayProvider).monthKey);

  void setMonth(MonthKey month) =>
      state = state.copyWith(month: month, customRange: () => null);

  void setRange(DateRange range) =>
      state = state.copyWith(customRange: () => range);

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
  void setType(
    TransactionType? type, {
    Map<String, TransactionCategory> categories = const {},
  }) {
    final keep = type == null
        ? state.categoryIds
        : state.categoryIds
              .where(
                (id) => categories[id] == null || categories[id]!.type == type,
              )
              .toSet();
    state = state.copyWith(type: () => type, categoryIds: keep);
  }

  void setCategories(Set<String> ids) =>
      state = state.copyWith(categoryIds: Set.unmodifiable(ids));

  /// Adds or removes one category (quick toggle from the summary card).
  void toggleCategory(String id) {
    final next = Set<String>.of(state.categoryIds);
    if (!next.remove(id)) next.add(id);
    setCategories(next);
  }

  void setAmount(AmountRange? amount) => state = state.copyWith(
    amount: () => amount == null || amount.isOpen ? null : amount,
  );

  void setAccounts(Set<String> ids) =>
      state = state.copyWith(accountIds: Set.unmodifiable(ids));

  void setChannels(Set<String> channels) =>
      state = state.copyWith(channels: Set.unmodifiable(channels));

  void setOrigins(Set<TransactionOrigin> origins) =>
      state = state.copyWith(origins: Set.unmodifiable(origins));

  /// Applies everything chosen in the filter sheet at once.
  void applyAdvanced(TransactionFilter from) => state = state.copyWith(
    type: () => from.type,
    categoryIds: Set.unmodifiable(from.categoryIds),
    amount: () =>
        from.amount == null || from.amount!.isOpen ? null : from.amount,
    accountIds: Set.unmodifiable(from.accountIds),
    channels: Set.unmodifiable(from.channels),
    origins: Set.unmodifiable(from.origins),
  );

  void setSort(TransactionSort sort) => state = state.copyWith(sort: sort);

  /// Clears search, type and every sheet filter; keeps the period and sort.
  void clearRefinements() => state = state.copyWith(
    query: '',
    type: () => null,
    categoryIds: const {},
    amount: () => null,
    accountIds: const {},
    channels: const {},
    origins: const {},
  );

  /// Applies filters requested by a deep link (e.g. "see all income this
  /// month" from Home). Only the provided values change.
  void applyRoute({TransactionType? type, MonthKey? month}) {
    if (type == null && month == null) return;
    var next = state;
    if (type != null)
      next = next.copyWith(type: () => type, categoryIds: const {});
    if (month != null)
      next = next.copyWith(month: month, customRange: () => null);
    state = next;
  }
}

final transactionFilterProvider =
    NotifierProvider<TransactionFilterController, TransactionFilter>(
      TransactionFilterController.new,
    );

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

/// A transfer between own accounts. Listed in Activity but never part of
/// income, spending or any total.
final class FeedTransfer extends FeedEntry {
  const FeedTransfer(this.transfer);
  final Transfer transfer;
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
    this.transfers = const [],
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

  /// Transfers matching the filter (listed, never counted in totals).
  final List<Transfer> transfers;
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

  /// Rows to list: transactions plus transfers.
  int get rowCount => rowEntryEnd.length;
  bool get isEmpty => transactions.isEmpty;

  /// Nothing at all to list (no transactions and no transfers).
  bool get hasNoRows => rowCount == 0;

  /// Entries to render when showing the first [rows] transactions.
  int entryCountFor(int rows) {
    if (rows <= 0 || rowEntryEnd.isEmpty) return 0;
    if (rows >= rowEntryEnd.length) return entries.length;
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
    return DateRange(
      prev.start,
      DateTime(prev.year, prev.month, today.day.clamp(1, prev.dayCount)),
    );
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
    if (filter.categoryIds.isNotEmpty &&
        !filter.categoryIds.contains(t.categoryId))
      return false;
    final amount = filter.amount;
    if (amount != null && !amount.contains(t.amount)) return false;
    if (filter.accountIds.isNotEmpty &&
        !filter.accountIds.contains(t.accountId))
      return false;
    if (filter.channels.isNotEmpty &&
        !filter.channels.any(
          (c) => c.toLowerCase() == (t.channel ?? '').toLowerCase(),
        )) {
      return false;
    }
    if (filter.origins.isNotEmpty && !filter.origins.contains(t.origin))
      return false;
    final q = normalisedQuery ?? _normalise(filter.query);
    if (q.isNotEmpty &&
        !_matches(t, q, amountQuery ?? _amountDigits(filter.query), categories))
      return false;
    return true;
  }

  /// Whether transfer [t] passes the filter (except the period). Transfers
  /// are not income, spending, categorised or sourced, so any of those
  /// filters hides them.
  static bool passesTransfer(
    Transfer t,
    TransactionFilter filter,
    Map<String, MoneyAccount> accounts,
  ) {
    if (filter.type != null ||
        filter.categoryIds.isNotEmpty ||
        filter.origins.isNotEmpty)
      return false;
    final amount = filter.amount;
    if (amount != null && !amount.contains(t.amount)) return false;
    if (filter.accountIds.isNotEmpty &&
        !filter.accountIds.contains(t.fromAccountId) &&
        !filter.accountIds.contains(t.toAccountId)) {
      return false;
    }
    if (filter.channels.isNotEmpty &&
        !filter.channels.any(
          (c) => c.toLowerCase() == (t.channel ?? '').toLowerCase(),
        )) {
      return false;
    }
    final q = _normalise(filter.query);
    if (q.isEmpty) return true;
    if ((t.note ?? '').toLowerCase().contains(q)) return true;
    if ((t.channel ?? '').toLowerCase().contains(q)) return true;
    if ((accounts[t.fromAccountId]?.name ?? '').toLowerCase().contains(q))
      return true;
    if ((accounts[t.toAccountId]?.name ?? '').toLowerCase().contains(q))
      return true;
    final digits = _amountDigits(filter.query);
    if (digits != null &&
        !digits.contains('.') &&
        t.amount.rupeePart.toString().contains(digits))
      return true;
    return false;
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
      if (range.contains(t.date) &&
          passes(
            t,
            filter,
            categories,
            normalisedQuery: q,
            amountQuery: amountQuery,
          ))
        n++;
    }
    return n;
  }

  static TransactionFeed build(
    List<Transaction> sortedNewestFirst,
    TransactionFilter filter,
    Map<String, TransactionCategory> categories, {
    DateTime? today,
    List<Transfer> transfers = const [],
    Map<String, MoneyAccount> accounts = const {},
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
      if (!passes(
        t,
        filter,
        categories,
        normalisedQuery: q,
        amountQuery: amountQuery,
      ))
        continue;
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

    // Transfers in the period, newest first.
    final shownTransfers =
        <Transfer>[
          for (final t in transfers)
            if (range.contains(t.date) && passesTransfer(t, filter, accounts))
              t,
        ]..sort((a, b) {
          final c = b.date.compareTo(a.date);
          return c != 0 ? c : b.createdAt.compareTo(a.createdAt);
        });
    switch (filter.sort) {
      case TransactionSort.newest:
        break;
      case TransactionSort.oldest:
        shownTransfers.setAll(0, shownTransfers.reversed.toList());
      case TransactionSort.highest:
        shownTransfers.sort((a, b) {
          final c = b.amount.compareTo(a.amount);
          return c != 0 ? c : b.date.compareTo(a.date);
        });
      case TransactionSort.lowest:
        shownTransfers.sort((a, b) {
          final c = a.amount.compareTo(b.amount);
          return c != 0 ? c : b.date.compareTo(a.date);
        });
    }
    // Merge the two sorted lists; a transaction goes first on ties.
    bool txFirst(Transaction t, Transfer r) => switch (filter.sort) {
      TransactionSort.newest => t.date.compareTo(r.date) >= 0,
      TransactionSort.oldest => t.date.compareTo(r.date) <= 0,
      TransactionSort.highest => t.amount.compareTo(r.amount) >= 0,
      TransactionSort.lowest => t.amount.compareTo(r.amount) <= 0,
    };
    final merged = <Object>[];
    {
      var a = 0;
      var b = 0;
      while (a < result.length || b < shownTransfers.length) {
        if (b >= shownTransfers.length ||
            (a < result.length && txFirst(result[a], shownTransfers[b]))) {
          merged.add(result[a++]);
        } else {
          merged.add(shownTransfers[b++]);
        }
      }
    }
    DateTime dateOf(Object o) =>
        o is Transaction ? o.date : (o as Transfer).date;
    FeedEntry entryOf(Object o) =>
        o is Transaction ? FeedTransaction(o) : FeedTransfer(o as Transfer);

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
        daily[daysBetween(range.start, t.date).clamp(0, days - 1)] +=
            t.amount.paise;
        if (largest == null || t.amount > largest.amount) largest = t;
      }
    }
    List<CategoryShare> shares(Map<String, (int, int)> m) => List.unmodifiable(
      m.entries
          .map(
            (e) =>
                CategoryShare(e.key, Money.fromPaise(e.value.$1), e.value.$2),
          )
          .toList()
        ..sort((a, b) => b.amount.compareTo(a.amount)),
    );

    final entries = <FeedEntry>[];
    final rowEnd = <int>[];
    if (filter.sort.groupsByDate) {
      var i = 0;
      while (i < merged.length) {
        final day = dateOf(merged[i]);
        var j = i;
        var net = 0;
        while (j < merged.length && dateOf(merged[j]).isSameDay(day)) {
          final o = merged[j];
          if (o is Transaction) net += o.signedAmount.paise;
          j++;
        }
        entries.add(FeedDayHeader(day, Money.fromPaise(net), j - i));
        for (var k = i; k < j; k++) {
          entries.add(entryOf(merged[k]));
          rowEnd.add(entries.length);
        }
        i = j;
      }
    } else {
      for (final o in merged) {
        entries.add(entryOf(o));
        rowEnd.add(entries.length);
      }
    }

    return TransactionFeed(
      filter: filter,
      transactions: List.unmodifiable(result),
      transfers: List.unmodifiable(shownTransfers),
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
    if (cleaned.isEmpty || !RegExp(r'^\d+(\.\d{0,2})?$').hasMatch(cleaned))
      return null;
    return cleaned;
  }

  static bool _matches(
    Transaction t,
    String q,
    String? amountDigits,
    Map<String, TransactionCategory> categories,
  ) {
    if ((t.counterparty ?? '').toLowerCase().contains(q)) return true;
    if ((t.note ?? '').toLowerCase().contains(q)) return true;
    final cat = categories[t.categoryId];
    if (cat != null && cat.name.toLowerCase().contains(q)) return true;
    if (amountDigits != null) {
      final rupees = t.amount.rupeePart.toString();
      if (amountDigits.contains('.'))
        return t.amount.toDecimalString().startsWith(amountDigits);
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
  if (txs.hasError)
    return AsyncError(txs.error!, txs.stackTrace ?? StackTrace.current);
  if (cats.hasError)
    return AsyncError(cats.error!, cats.stackTrace ?? StackTrace.current);
  if (!txs.hasValue || !cats.hasValue) return const AsyncLoading();
  final today = ref.watch(todayProvider);
  final transfers = ref.watch(transfersProvider).value ?? const <Transfer>[];
  final accounts = {
    for (final a
        in ref.watch(moneyAccountsProvider).value ?? const <MoneyAccount>[])
      a.id: a,
  };
  return AsyncData(
    TransactionQuery.build(
      txs.requireValue,
      filter,
      cats.requireValue,
      today: today,
      transfers: transfers,
      accounts: accounts,
    ),
  );
});

/// Earliest and latest month that can be browsed (bounds the month switcher).
@immutable
class ActivityMonthBounds {
  const ActivityMonthBounds(this.first, this.last);
  final MonthKey first;
  final MonthKey last;

  @override
  bool operator ==(Object other) =>
      other is ActivityMonthBounds &&
      other.first == first &&
      other.last == last;

  @override
  int get hashCode => Object.hash(first, last);
}

final activityMonthBoundsProvider = Provider<ActivityMonthBounds>((ref) {
  final today = ref.watch(todayProvider).monthKey;
  final list = ref.watch(sortedTransactionsProvider).value;
  final oldest = (list == null || list.isEmpty)
      ? today
      : list.last.date.monthKey;
  final newest = (list == null || list.isEmpty)
      ? today
      : list.first.date.monthKey;
  return ActivityMonthBounds(
    oldest < today ? oldest : today,
    newest > today ? newest : today,
  );
});
