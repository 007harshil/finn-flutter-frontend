import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/data_providers.dart';
import '../../categories/domain/category.dart';
import '../domain/transaction.dart';

/// Categories a manual transaction of [type] may use: active, non-system
/// categories plus the "Other" fallback (see `validateTransaction`).
/// "Other" is listed last.
final pickableCategoriesProvider = Provider.family<AsyncValue<List<TransactionCategory>>, TransactionType>((ref, type) {
  return ref.watch(categoriesByIdProvider).whenData((byId) {
    final regular = <TransactionCategory>[];
    final fallback = <TransactionCategory>[];
    for (final c in byId.values) {
      if (c.type != type || c.isArchived) continue;
      if (!c.isSystem) {
        regular.add(c);
      } else if (isFallbackCategory(c.id)) {
        fallback.add(c);
      }
    }
    return List.unmodifiable([...regular, ...fallback]);
  });
});

/// The system "Other expense" / "Other income" categories.
bool isFallbackCategory(String id) =>
    id == SystemCategories.uncategorizedExpense || id == SystemCategories.uncategorizedIncome;
