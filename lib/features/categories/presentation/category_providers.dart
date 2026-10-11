import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/core_providers.dart';
import '../../../app/di/data_providers.dart';
import '../../../core/time/dates.dart';
import '../../transactions/domain/transaction.dart';
import '../application/category_actions.dart';
import '../domain/category.dart';

/// Categories of one type split into active and archived, sorted for display.
@immutable
class CategoryGroup {
  const CategoryGroup({required this.active, required this.archived});
  final List<TransactionCategory> active;
  final List<TransactionCategory> archived;
}

/// Both groups, keyed by type.
final categoryGroupsProvider = Provider<AsyncValue<Map<TransactionType, CategoryGroup>>>((ref) {
  return ref.watch(categoriesByIdProvider).whenData((byId) {
    int order(TransactionCategory a, TransactionCategory b) {
      if (a.isSystem != b.isSystem) return a.isSystem ? 1 : -1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    }

    return {
      for (final type in TransactionType.values)
        type: CategoryGroup(
          active: byId.values.where((c) => c.type == type && !c.isArchived).toList()..sort(order),
          archived: byId.values.where((c) => c.type == type && c.isArchived).toList()..sort(order),
        ),
    };
  });
});

/// Number of transactions per category in the current calendar month.
final categoryMonthCountsProvider = Provider<Map<String, int>>((ref) {
  final month = ref.watch(todayProvider).monthKey;
  final list = ref.watch(sortedTransactionsProvider).value ?? const <Transaction>[];
  final counts = <String, int>{};
  for (final t in list) {
    // Sorted newest first: stop once we pass the month.
    if (t.date.isBefore(month.start)) break;
    if (!month.contains(t.date)) continue;
    counts[t.categoryId] = (counts[t.categoryId] ?? 0) + 1;
  }
  return counts;
});

/// Where a category is referenced (transactions, budgets, subscriptions).
final categoryUsageProvider = Provider.family<AsyncValue<CategoryUsage>, String>(
    (ref, id) => ref.watch(financeSnapshotProvider).whenData((s) => categoryUsage(id, s)));
