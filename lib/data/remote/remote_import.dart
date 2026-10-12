import '../../core/persistence/entity_collection.dart' show JsonMap;
import '../dto/dtos.dart';
import '../local/local_data_store.dart';
import 'api_client.dart';
import 'sync_engine.dart';

/// One-time upload of the records kept on this device (local mode) into a
/// new FiNN account (`POST /import`). Only offered, never automatic.
class RemoteImporter {
  RemoteImporter({required this.api, required this.engine, this.local});

  final ApiClient api;
  final SyncEngine engine;

  /// The device's local store, or null when nothing was stored.
  final LocalDataStore? local;

  /// Whether the device holds financial records worth uploading (system
  /// categories alone do not count).
  bool get hasLocalData {
    final s = local;
    if (s == null) return false;
    return s.profile.current != null ||
        s.transactions.current.isNotEmpty ||
        s.budgets.current.isNotEmpty ||
        s.goals.current.isNotEmpty ||
        s.savingsMovements.current.isNotEmpty ||
        s.loans.current.isNotEmpty ||
        s.subscriptions.current.isNotEmpty ||
        s.pending.current.isNotEmpty ||
        s.assets.current.isNotEmpty;
  }

  /// The `/import` body: the local store's DTO JSON. Pending items shared
  /// with this user by someone else are left out (the server re-creates
  /// sharing online), and links are dropped.
  JsonMap buildPayload() {
    final s = local;
    if (s == null) throw StateError('No local data');
    final ownPending = s.pending.current.where((p) => p.link == null || p.link!.createdByMe).toList();
    final ownPendingIds = {for (final p in ownPending) p.id};
    return {
      'categories': [for (final c in s.categories.current) CategoryDto.toJson(c)],
      'transactions': [for (final t in s.transactions.current) TransactionDto.toJson(t)],
      'budgets': [for (final b in s.budgets.current) BudgetDto.toJson(b)],
      'goals': [for (final g in s.goals.current) GoalDto.toJson(g)],
      'savingsMovements': [for (final m in s.savingsMovements.current) SavingsMovementDto.toJson(m)],
      'loans': [for (final l in s.loans.current) LoanDto.toJson(l)],
      'loanPayments': [for (final p in s.loanPayments.current) LoanPaymentDto.toJson(p)],
      'subscriptions': [for (final x in s.subscriptions.current) SubscriptionDto.toJson(x)],
      'pending': [
        for (final p in ownPending) {...PendingDto.toJson(p), 'link': null},
      ],
      'settlements': [
        for (final x in s.settlements.current)
          if (ownPendingIds.contains(x.pendingId)) SettlementDto.toJson(x),
      ],
      'assets': [for (final a in s.assets.current) AssetDto.toJson(a)],
      'profile': ProfileDto.toJson(s.profile.current),
      'emergencyPlan': EmergencyPlanDto.toJson(s.emergencyPlan.current),
    };
  }

  /// Uploads everything and adopts the returned full sync payload.
  /// Throws `AppFailure(conflict)` when the account already has records.
  Future<void> upload({required String idempotencyKey}) async {
    final data = await api.post('/import', headers: {'Idempotency-Key': idempotencyKey}, body: buildPayload());
    if (data is Map) {
      engine.replaceWith(Map<String, Object?>.from(data));
      if (data['hasMore'] == true) await engine.sync();
    } else {
      await engine.sync();
    }
  }
}
