import '../../core/persistence/entity_collection.dart';
import '../../core/persistence/persistence_driver.dart';
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
import '../mock/finn_users.dart';
import '../mock/seed_data.dart';

class LocalTransactionRepository extends EntityCollection<Transaction> implements TransactionRepository {
  LocalTransactionRepository(PersistenceDriver d, MockBehavior b)
      : super(storageKey: 'transactions', idOf: (e) => e.id, encode: TransactionDto.toJson, decode: TransactionDto.fromJson, driver: d, behavior: b);
}

class LocalCategoryRepository extends EntityCollection<TransactionCategory> implements CategoryRepository {
  LocalCategoryRepository(PersistenceDriver d, MockBehavior b)
      : super(storageKey: 'categories', idOf: (e) => e.id, encode: CategoryDto.toJson, decode: CategoryDto.fromJson, driver: d, behavior: b);
}

class LocalBudgetRepository extends EntityCollection<Budget> implements BudgetRepository {
  LocalBudgetRepository(PersistenceDriver d, MockBehavior b)
      : super(storageKey: 'budgets', idOf: (e) => e.id, encode: BudgetDto.toJson, decode: BudgetDto.fromJson, driver: d, behavior: b);
}

class LocalGoalRepository extends EntityCollection<SavingsGoal> implements GoalRepository {
  LocalGoalRepository(PersistenceDriver d, MockBehavior b)
      : super(storageKey: 'goals', idOf: (e) => e.id, encode: GoalDto.toJson, decode: GoalDto.fromJson, driver: d, behavior: b);
}

class LocalSavingsMovementRepository extends EntityCollection<SavingsMovement>
    implements SavingsMovementRepository {
  LocalSavingsMovementRepository(PersistenceDriver d, MockBehavior b)
      : super(storageKey: 'savings_movements', idOf: (e) => e.id, encode: SavingsMovementDto.toJson, decode: SavingsMovementDto.fromJson, driver: d, behavior: b);
}

class LocalLoanRepository extends EntityCollection<Loan> implements LoanRepository {
  LocalLoanRepository(PersistenceDriver d, MockBehavior b)
      : super(storageKey: 'loans', idOf: (e) => e.id, encode: LoanDto.toJson, decode: LoanDto.fromJson, driver: d, behavior: b);
}

class LocalLoanPaymentRepository extends EntityCollection<LoanPayment> implements LoanPaymentRepository {
  LocalLoanPaymentRepository(PersistenceDriver d, MockBehavior b)
      : super(storageKey: 'loan_payments', idOf: (e) => e.id, encode: LoanPaymentDto.toJson, decode: LoanPaymentDto.fromJson, driver: d, behavior: b);
}

class LocalSubscriptionRepository extends EntityCollection<Subscription> implements SubscriptionRepository {
  LocalSubscriptionRepository(PersistenceDriver d, MockBehavior b)
      : super(storageKey: 'subscriptions', idOf: (e) => e.id, encode: SubscriptionDto.toJson, decode: SubscriptionDto.fromJson, driver: d, behavior: b);
}

class LocalPendingRepository extends EntityCollection<PendingPayment> implements PendingRepository {
  LocalPendingRepository(PersistenceDriver d, MockBehavior b)
      : super(storageKey: 'pending', idOf: (e) => e.id, encode: PendingDto.toJson, decode: PendingDto.fromJson, driver: d, behavior: b);
}

class LocalSettlementRepository extends EntityCollection<PendingSettlement> implements SettlementRepository {
  LocalSettlementRepository(PersistenceDriver d, MockBehavior b)
      : super(storageKey: 'settlements', idOf: (e) => e.id, encode: SettlementDto.toJson, decode: SettlementDto.fromJson, driver: d, behavior: b);
}

class LocalAssetRepository extends EntityCollection<Asset> implements AssetRepository {
  LocalAssetRepository(PersistenceDriver d, MockBehavior b)
      : super(storageKey: 'assets', idOf: (e) => e.id, encode: AssetDto.toJson, decode: AssetDto.fromJson, driver: d, behavior: b);
}

class LocalSharedLedgerRepository extends EntityCollection<MirrorEntry> implements SharedLedgerRepository {
  LocalSharedLedgerRepository(PersistenceDriver d, MockBehavior b)
      : super(storageKey: 'shared_ledger', idOf: (e) => e.key, encode: MirrorEntryDto.toJson, decode: MirrorEntryDto.fromJson, driver: d, behavior: b);
}

/// In-memory directory over [mockFinnUsers]. "Me" follows the profile name.
class LocalUserDirectory implements UserDirectory {
  LocalUserDirectory(this._profile);

  final LocalProfileRepository _profile;

  @override
  FinnUser get me => mockMe(_profile.current?.displayName);

  @override
  Future<List<FinnUser>> search(String query) async {
    final q = query.trim().toLowerCase().replaceFirst('@', '');
    if (q.length < 2) return const [];
    return mockFinnUsers
        .where((u) => u.name.toLowerCase().contains(q) || u.handle.toLowerCase().contains(q))
        .toList();
  }

  @override
  FinnUser? known(String id) =>
      id == mockMyUserId ? me : mockFinnUsers.where((u) => u.id == id).firstOrNull;
}

class _LocalValueRepository<T> implements ValueRepository<T> {
  _LocalValueRepository(this.store);
  final ValueStore<T> store;

  @override
  T get current => store.value;

  @override
  Future<void> set(T value) => store.set(value);

  @override
  Stream<T> watch() => store.watch();
}

class LocalProfileRepository extends _LocalValueRepository<FinancialProfile?> implements ProfileRepository {
  LocalProfileRepository(PersistenceDriver d, MockBehavior b)
      : super(ValueStore<FinancialProfile?>(
            storageKey: 'profile', encode: ProfileDto.toJson, decode: ProfileDto.fromJson, driver: d, initial: null, behavior: b));
}

class LocalEmergencyPlanRepository extends _LocalValueRepository<EmergencyFundPlan?>
    implements EmergencyPlanRepository {
  LocalEmergencyPlanRepository(PersistenceDriver d, MockBehavior b)
      : super(ValueStore<EmergencyFundPlan?>(
            storageKey: 'emergency_plan', encode: EmergencyPlanDto.toJson, decode: EmergencyPlanDto.fromJson, driver: d, initial: null, behavior: b));
}

class LocalAlertInboxRepository extends _LocalValueRepository<AlertInboxState> implements AlertInboxRepository {
  LocalAlertInboxRepository(PersistenceDriver d)
      : super(ValueStore<AlertInboxState>(
            storageKey: 'alert_inbox', encode: AlertInboxDto.toJson, decode: AlertInboxDto.fromJson, driver: d, initial: const AlertInboxState()));
}

/// Which dataset the local mock backend starts with.
enum DataScenario {
  /// Realistic six months of Indian personal-finance data.
  demo,

  /// A brand-new user (only system categories).
  empty,

  /// Edge cases: overdue everything, breached budgets, zero income month.
  stressed,
}

/// Owns every local repository. Acts as the mock "backend".
class LocalDataStore {
  LocalDataStore({required this.driver, MockBehavior? behavior})
      : behavior = behavior ?? MockBehavior() {
    transactions = LocalTransactionRepository(driver, this.behavior);
    categories = LocalCategoryRepository(driver, this.behavior);
    budgets = LocalBudgetRepository(driver, this.behavior);
    goals = LocalGoalRepository(driver, this.behavior);
    savingsMovements = LocalSavingsMovementRepository(driver, this.behavior);
    loans = LocalLoanRepository(driver, this.behavior);
    loanPayments = LocalLoanPaymentRepository(driver, this.behavior);
    subscriptions = LocalSubscriptionRepository(driver, this.behavior);
    pending = LocalPendingRepository(driver, this.behavior);
    settlements = LocalSettlementRepository(driver, this.behavior);
    assets = LocalAssetRepository(driver, this.behavior);
    profile = LocalProfileRepository(driver, this.behavior);
    emergencyPlan = LocalEmergencyPlanRepository(driver, this.behavior);
    alertInbox = LocalAlertInboxRepository(driver);
    sharedLedger = LocalSharedLedgerRepository(driver, this.behavior);
    users = LocalUserDirectory(profile);
  }

  final PersistenceDriver driver;
  final MockBehavior behavior;

  late final LocalTransactionRepository transactions;
  late final LocalCategoryRepository categories;
  late final LocalBudgetRepository budgets;
  late final LocalGoalRepository goals;
  late final LocalSavingsMovementRepository savingsMovements;
  late final LocalLoanRepository loans;
  late final LocalLoanPaymentRepository loanPayments;
  late final LocalSubscriptionRepository subscriptions;
  late final LocalPendingRepository pending;
  late final LocalSettlementRepository settlements;
  late final LocalAssetRepository assets;
  late final LocalProfileRepository profile;
  late final LocalEmergencyPlanRepository emergencyPlan;
  late final LocalAlertInboxRepository alertInbox;
  late final LocalSharedLedgerRepository sharedLedger;
  late final LocalUserDirectory users;

  List<EntityCollection<Object?>> get _collections => [
        transactions, categories, budgets, goals, savingsMovements, loans,
        loanPayments, subscriptions, pending, settlements, assets, sharedLedger,
      ].cast<EntityCollection<Object?>>();

  /// Loads persisted data; seeds [scenario] when nothing is stored yet.
  Future<void> open({required DataScenario scenario, required DateTime today, bool forceSeed = false}) async {
    var hasData = false;
    if (!forceSeed) {
      final loaded = await transactions.load();
      if (loaded) {
        hasData = true;
        await Future.wait([
          categories.load(), budgets.load(), goals.load(), savingsMovements.load(), loans.load(),
          loanPayments.load(), subscriptions.load(), pending.load(), settlements.load(), assets.load(), sharedLedger.load(),
          profile.store.load(), emergencyPlan.store.load(), alertInbox.store.load(),
        ]);
      }
    }
    if (!hasData) await reseed(scenario, today);
  }

  /// Replaces all data with [scenario].
  Future<void> reseed(DataScenario scenario, DateTime today) async {
    final seed = SeedData.build(scenario, today);
    categories.seed(seed.categories);
    transactions.seed(seed.transactions);
    budgets.seed(seed.budgets);
    goals.seed(seed.goals);
    savingsMovements.seed(seed.savingsMovements);
    loans.seed(seed.loans);
    loanPayments.seed(seed.loanPayments);
    subscriptions.seed(seed.subscriptions);
    pending.seed(seed.pending);
    settlements.seed(seed.settlements);
    sharedLedger.seed(seed.mirrors);
    assets.seed(seed.assets);
    await profile.store.set(seed.profile, simulate: false);
    await emergencyPlan.store.set(seed.emergencyPlan, simulate: false);
    await alertInbox.store.set(const AlertInboxState(), simulate: false);
    await flush();
  }

  Future<void> flush() => Future.wait(_collections.map((c) => c.flush()));
}
