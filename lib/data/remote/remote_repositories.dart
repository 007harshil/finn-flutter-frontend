import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/persistence/entity_collection.dart' show JsonMap;
import '../../core/result/result.dart';
import '../../domain/finance_repositories.dart';
import '../../domain/repositories.dart';
import '../../features/alerts/domain/alert.dart';
import '../../features/budgets/domain/budget.dart';
import '../../features/categories/domain/category.dart';
import '../../features/emergency_fund/domain/emergency_fund.dart';
import '../../features/goals/domain/goal.dart';
import '../../features/loans/domain/loan.dart';
import '../../features/net_worth/domain/asset.dart';
import '../../features/pending/domain/pending_payment.dart';
import '../../features/settings/domain/financial_profile.dart';
import '../../features/subscriptions/domain/subscription.dart';
import '../../features/transactions/domain/transaction.dart';
import '../dto/dtos.dart';
import 'api_client.dart';
import 'sync_engine.dart';

/// Thrown by direct repository writes: when connected, every change goes
/// through an action endpoint so the server validates it in one transaction.
const remoteDirectWriteFailure = AppFailure(
  FailureCode.notPermitted,
  'This change can only be made through FiNN’s actions while connected.',
);

/// Read-only view of one synced collection. Decodes the cached DTO JSON
/// with the existing codecs and re-emits on every change.
class RemoteCollection<T> implements CrudRepository<T> {
  RemoteCollection(this.engine, this.name, this.decode);

  final SyncEngine engine;
  final String name;
  final T Function(JsonMap) decode;

  int _revision = -1;
  List<T> _items = const [];

  /// Decoded records, cached per engine revision (stable identity between
  /// changes so listeners can skip work).
  List<T> get current {
    final rev = engine.revisionOf(name);
    if (rev != _revision) {
      final out = <T>[];
      for (final json in engine.records(name)) {
        try {
          out.add(decode(json));
        } catch (e) {
          debugPrint('Skipping unreadable $name record ${json['id']}: $e');
        }
      }
      _items = List<T>.unmodifiable(out);
      _revision = rev;
    }
    return _items;
  }

  @override
  Stream<List<T>> watchAll() async* {
    yield current;
    yield* engine.changes.where((c) => c.contains(name)).map((_) => current);
  }

  @override
  Future<List<T>> getAll() async => current;

  @override
  Future<T?> getById(String id) async {
    final json = engine.record(name, id);
    return json == null ? null : decode(json);
  }

  @override
  Future<void> save(T item) => Future.error(remoteDirectWriteFailure);

  @override
  Future<void> saveAll(Iterable<T> items) => Future.error(remoteDirectWriteFailure);

  @override
  Future<void> delete(String id) => Future.error(remoteDirectWriteFailure);
}

class RemoteTransactionRepository extends RemoteCollection<Transaction> implements TransactionRepository {
  RemoteTransactionRepository(SyncEngine e) : super(e, SyncCollections.transactions, TransactionDto.fromJson);
}

class RemoteCategoryRepository extends RemoteCollection<TransactionCategory> implements CategoryRepository {
  RemoteCategoryRepository(SyncEngine e) : super(e, SyncCollections.categories, CategoryDto.fromJson);
}

class RemoteBudgetRepository extends RemoteCollection<Budget> implements BudgetRepository {
  RemoteBudgetRepository(SyncEngine e) : super(e, SyncCollections.budgets, BudgetDto.fromJson);
}

class RemoteGoalRepository extends RemoteCollection<SavingsGoal> implements GoalRepository {
  RemoteGoalRepository(SyncEngine e) : super(e, SyncCollections.goals, GoalDto.fromJson);
}

class RemoteSavingsMovementRepository extends RemoteCollection<SavingsMovement> implements SavingsMovementRepository {
  RemoteSavingsMovementRepository(SyncEngine e)
    : super(e, SyncCollections.savingsMovements, SavingsMovementDto.fromJson);
}

class RemoteLoanRepository extends RemoteCollection<Loan> implements LoanRepository {
  RemoteLoanRepository(SyncEngine e) : super(e, SyncCollections.loans, LoanDto.fromJson);
}

class RemoteLoanPaymentRepository extends RemoteCollection<LoanPayment> implements LoanPaymentRepository {
  RemoteLoanPaymentRepository(SyncEngine e) : super(e, SyncCollections.loanPayments, LoanPaymentDto.fromJson);
}

class RemoteSubscriptionRepository extends RemoteCollection<Subscription> implements SubscriptionRepository {
  RemoteSubscriptionRepository(SyncEngine e) : super(e, SyncCollections.subscriptions, SubscriptionDto.fromJson);
}

class RemotePendingRepository extends RemoteCollection<PendingPayment> implements PendingRepository {
  RemotePendingRepository(SyncEngine e) : super(e, SyncCollections.pending, PendingDto.fromJson);
}

class RemoteSettlementRepository extends RemoteCollection<PendingSettlement> implements SettlementRepository {
  RemoteSettlementRepository(SyncEngine e) : super(e, SyncCollections.settlements, SettlementDto.fromJson);
}

class RemoteAssetRepository extends RemoteCollection<Asset> implements AssetRepository {
  RemoteAssetRepository(SyncEngine e) : super(e, SyncCollections.assets, AssetDto.fromJson);
}

/// A synced single value, hydrated synchronously from the cache.
class RemoteValue<T> implements ValueRepository<T> {
  RemoteValue(this.engine, this.name, this.decode, this.fallback);

  final SyncEngine engine;
  final String name;
  final T Function(JsonMap) decode;
  final T fallback;

  int _revision = -1;
  late T _value = fallback;

  @override
  T get current {
    final rev = engine.revisionOf(name);
    if (rev != _revision) {
      final json = engine.value(name);
      try {
        _value = json == null ? fallback : decode(json);
      } catch (e) {
        debugPrint('Unreadable $name value: $e');
        _value = fallback;
      }
      _revision = rev;
    }
    return _value;
  }

  @override
  Stream<T> watch() async* {
    yield current;
    yield* engine.changes.where((c) => c.contains(name)).map((_) => current);
  }

  @override
  Future<void> set(T value) => Future.error(remoteDirectWriteFailure);
}

/// The financial profile. Writes outside actions (onboarding) go through
/// the `profile.update` action endpoint.
class RemoteProfileRepository extends RemoteValue<FinancialProfile?> implements ProfileRepository {
  RemoteProfileRepository(SyncEngine e, this.api, {String Function()? newKey})
    : _newKey = newKey ?? _defaultKey,
      super(e, SyncValues.profile, ProfileDto.fromJson, null);

  final ApiClient api;
  final String Function() _newKey;

  static String _defaultKey() => 'profile_${DateTime.now().microsecondsSinceEpoch}';

  @override
  Future<void> set(FinancialProfile? value) async {
    if (value == null) throw remoteDirectWriteFailure;
    final data = await api.post(
      '/actions/profile.update',
      headers: {'Idempotency-Key': _newKey()},
      body: {
        'input': {
          'displayName': value.displayName,
          'openingBalance': value.openingBalance.toDecimalString(),
          'openingDate': _date(value.openingDate),
          'monthlyIncomeEstimate': value.monthlyIncomeEstimate?.toDecimalString(),
        },
        'confirmation': null,
        'channel': 'ui',
      },
    );
    if (data is! Map) return;
    if (data['status'] == 'needsConfirmation') {
      throw const AppFailure(
        FailureCode.confirmationRequired,
        'Changing your opening balance needs a review. Edit it from your profile instead.',
      );
    }
    final changes = data['changes'];
    if (changes is Map) engine.applyChanges(Map<String, Object?>.from(changes));
    unawaited(engine.sync().catchError((Object e) => debugPrint('Sync after profile update failed: $e')));
  }

  static String _date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

class RemoteEmergencyPlanRepository extends RemoteValue<EmergencyFundPlan?> implements EmergencyPlanRepository {
  RemoteEmergencyPlanRepository(SyncEngine e) : super(e, SyncValues.emergencyPlan, EmergencyPlanDto.fromJson, null);
}

/// Read / dismissed alert keys, written with `PUT /alerts/inbox`
/// (`read` / `dismissed` add keys, `restore` un-dismisses keys). Shown
/// optimistically and reverted if the server refuses. Read keys are never
/// removed (no endpoint, and nothing in the app un-reads an alert).
class RemoteAlertInboxRepository extends RemoteValue<AlertInboxState> implements AlertInboxRepository {
  RemoteAlertInboxRepository(SyncEngine e, this.api)
    : super(e, SyncValues.alertInbox, AlertInboxDto.fromJson, const AlertInboxState());

  final ApiClient api;

  @override
  Future<void> set(AlertInboxState value) async {
    final before = current;
    if (!value.readKeys.containsAll(before.readKeys)) {
      throw const AppFailure(FailureCode.notPermitted, 'Alerts cannot be marked unread.');
    }
    final read = value.readKeys.difference(before.readKeys);
    final dismissed = value.dismissedKeys.difference(before.dismissedKeys);
    final restore = before.dismissedKeys.difference(value.dismissedKeys);
    if (read.isEmpty && dismissed.isEmpty && restore.isEmpty) return;
    final previous = engine.value(SyncValues.alertInbox);
    engine.setValue(SyncValues.alertInbox, AlertInboxDto.toJson(value));
    try {
      final data = await api.put(
        '/alerts/inbox',
        body: {'read': read.toList(), 'dismissed': dismissed.toList(), 'restore': restore.toList()},
      );
      if (data is Map) engine.setValue(SyncValues.alertInbox, Map<String, Object?>.from(data));
    } catch (_) {
      engine.setValue(SyncValues.alertInbox, previous ?? AlertInboxDto.toJson(before));
      rethrow;
    }
  }
}

/// Shared pending items are mirrored by the server; nothing is kept here.
class RemoteSharedLedgerRepository implements SharedLedgerRepository {
  @override
  Stream<List<MirrorEntry>> watchAll() => Stream.value(const []);

  @override
  Future<List<MirrorEntry>> getAll() async => const [];

  @override
  Future<MirrorEntry?> getById(String id) async => null;

  @override
  Future<void> save(MirrorEntry item) async {}

  @override
  Future<void> saveAll(Iterable<MirrorEntry> items) async {}

  @override
  Future<void> delete(String id) async {}
}

/// FiNN users: `me` from sync, search via `GET /users/search`.
class RemoteUserDirectory implements UserDirectory {
  RemoteUserDirectory(this.engine, this.api);

  final SyncEngine engine;
  final ApiClient api;
  final Map<String, FinnUser> _seen = {};

  @override
  FinnUser get me {
    final json = engine.value(SyncValues.me);
    if (json != null && json['id'] is String) return _userFrom(json);
    final name = engine.value(SyncValues.profile)?['displayName'] as String?;
    return FinnUser(id: engine.userId ?? 'me', name: (name == null || name.trim().isEmpty) ? 'You' : name, handle: '');
  }

  @override
  Future<List<FinnUser>> search(String query) async {
    final q = query.trim();
    if (q.length < 2) return const [];
    final data = await api.get('/users/search', query: {'q': q});
    final items = data is Map ? data['items'] : null;
    if (items is! List) return const [];
    final users = [
      for (final item in items.whereType<Map>())
        if (item['id'] is String) _userFrom(Map<String, Object?>.from(item)),
    ];
    for (final u in users) {
      _seen[u.id] = u;
    }
    return users;
  }

  @override
  FinnUser? known(String id) {
    if (id == me.id) return me;
    final seen = _seen[id];
    if (seen != null) return seen;
    for (final json in engine.records(SyncCollections.pending)) {
      final link = json['link'];
      if (link is Map && link['userId'] == id) {
        return FinnUser(id: id, name: json['counterparty'] as String? ?? '', handle: link['handle'] as String? ?? '');
      }
    }
    return null;
  }

  static FinnUser _userFrom(JsonMap j) => FinnUser(
    id: j['id'] as String,
    name: (j['name'] as String?) ?? '',
    handle: (j['handle'] as String?) ?? '',
    phoneHint: j['phoneHint'] as String?,
  );
}

/// Builds the repository bundle over [engine].
FinanceRepositories buildRemoteRepositories(SyncEngine engine, ApiClient api) => FinanceRepositories(
  transactions: RemoteTransactionRepository(engine),
  categories: RemoteCategoryRepository(engine),
  budgets: RemoteBudgetRepository(engine),
  goals: RemoteGoalRepository(engine),
  savingsMovements: RemoteSavingsMovementRepository(engine),
  loans: RemoteLoanRepository(engine),
  loanPayments: RemoteLoanPaymentRepository(engine),
  subscriptions: RemoteSubscriptionRepository(engine),
  pending: RemotePendingRepository(engine),
  settlements: RemoteSettlementRepository(engine),
  assets: RemoteAssetRepository(engine),
  profile: RemoteProfileRepository(engine, api),
  emergencyPlan: RemoteEmergencyPlanRepository(engine),
  alertInbox: RemoteAlertInboxRepository(engine, api),
  users: RemoteUserDirectory(engine, api),
  sharedLedger: RemoteSharedLedgerRepository(),
);
