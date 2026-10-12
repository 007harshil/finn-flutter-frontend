import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/data_providers.dart';
import '../../categories/domain/category.dart';
import '../domain/transaction.dart';

/// Remembers the last payment method used per transaction type for the
/// current session, so repeat entries need fewer taps. Not persisted.
class LastPaymentMethodController extends Notifier<Map<TransactionType, PaymentMethod>> {
  @override
  Map<TransactionType, PaymentMethod> build() => const {};

  void remember(TransactionType type, PaymentMethod? method) {
    if (method == null || state[type] == method) return;
    state = {...state, type: method};
  }
}

final lastPaymentMethodProvider = NotifierProvider<LastPaymentMethodController, Map<TransactionType, PaymentMethod>>(
  LastPaymentMethodController.new,
);

/// Default method when nothing was used yet this session.
PaymentMethod defaultPaymentMethod(TransactionType type) =>
    type.isIncome ? PaymentMethod.bankTransfer : PaymentMethod.upi;

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
