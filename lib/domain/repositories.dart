// Repository contracts shared by all features.
//
// The UI and application services depend only on these interfaces. The
// current implementations are local mocks (lib/data/local); a REST/GraphQL
// implementation can be swapped in by overriding `financeRepositoriesProvider`
// (lib/app/di/core_providers.dart) without touching features.

import '../core/data/crud_repository.dart';
import '../features/alerts/domain/alert.dart';
import '../features/budgets/domain/budget.dart';
import '../features/categories/domain/category.dart';
import '../features/emergency_fund/domain/emergency_fund.dart';
import '../features/goals/domain/goal.dart';
import '../features/loans/domain/loan.dart';
import '../features/net_worth/domain/asset.dart';
import '../features/pending/domain/pending_payment.dart';
import '../features/settings/domain/financial_profile.dart';
import '../features/subscriptions/domain/subscription.dart';
import '../features/transactions/domain/transaction.dart';

export '../core/data/crud_repository.dart';

abstract interface class TransactionRepository implements CrudRepository<Transaction> {}

abstract interface class CategoryRepository implements CrudRepository<TransactionCategory> {}

abstract interface class BudgetRepository implements CrudRepository<Budget> {}

abstract interface class GoalRepository implements CrudRepository<SavingsGoal> {}

abstract interface class SavingsMovementRepository implements CrudRepository<SavingsMovement> {}

abstract interface class LoanRepository implements CrudRepository<Loan> {}

abstract interface class LoanPaymentRepository implements CrudRepository<LoanPayment> {}

abstract interface class SubscriptionRepository implements CrudRepository<Subscription> {}

abstract interface class PendingRepository implements CrudRepository<PendingPayment> {}

abstract interface class SettlementRepository implements CrudRepository<PendingSettlement> {}

abstract interface class AssetRepository implements CrudRepository<Asset> {}

/// A single persisted value.
abstract interface class ValueRepository<T> {
  Stream<T> watch();
  T get current;
  Future<void> set(T value);
}

abstract interface class ProfileRepository implements ValueRepository<FinancialProfile?> {}

abstract interface class EmergencyPlanRepository implements ValueRepository<EmergencyFundPlan?> {}

abstract interface class AlertInboxRepository implements ValueRepository<AlertInboxState> {}

/// People who use FiNN. Searching never reveals more than name, handle and
/// a phone hint.
abstract interface class UserDirectory {
  /// The signed-in user.
  FinnUser get me;

  /// Users whose name or handle matches [query]. Callers debounce typing;
  /// queries shorter than two characters return nothing.
  Future<List<FinnUser>> search(String query);

  /// A user already known on this device (searched before or linked to an
  /// item). Synchronous so actions can validate without a round trip.
  FinnUser? known(String id);
}

/// The other side of every shared pending item (double entry): one
/// [MirrorEntry] per counterparty and shared item. A backend stores these in
/// the counterparty's account; the local mock keeps them on device so both
/// sides can be inspected.
abstract interface class SharedLedgerRepository implements CrudRepository<MirrorEntry> {}
