import '../core/time/clock.dart';
import '../finance/finance_snapshot.dart';
import 'repositories.dart';

/// Bundle of every repository, injected into application services and
/// actions. Swapping the implementations here swaps the backend.
class FinanceRepositories {
  const FinanceRepositories({
    required this.transactions,
    required this.categories,
    required this.budgets,
    required this.goals,
    required this.savingsMovements,
    required this.loans,
    required this.loanPayments,
    required this.subscriptions,
    required this.pending,
    required this.settlements,
    required this.assets,
    required this.moneyAccounts,
    required this.transfers,
    required this.profile,
    required this.emergencyPlan,
    required this.alertInbox,
    required this.users,
    required this.sharedLedger,
  });

  final TransactionRepository transactions;
  final CategoryRepository categories;
  final BudgetRepository budgets;
  final GoalRepository goals;
  final SavingsMovementRepository savingsMovements;
  final LoanRepository loans;
  final LoanPaymentRepository loanPayments;
  final SubscriptionRepository subscriptions;
  final PendingRepository pending;
  final SettlementRepository settlements;
  final AssetRepository assets;
  final MoneyAccountRepository moneyAccounts;
  final TransferRepository transfers;
  final ProfileRepository profile;
  final EmergencyPlanRepository emergencyPlan;
  final AlertInboxRepository alertInbox;

  /// People on FiNN, for sharing pending items.
  final UserDirectory users;

  /// The counterparty side of shared pending items.
  final SharedLedgerRepository sharedLedger;

  /// Reads every collection once and builds a consistent snapshot.
  Future<FinanceSnapshot> loadSnapshot(Clock clock, {required int monthStartDay}) async {
    final txs = List.of(await transactions.getAll())..sort((a, b) {
        final c = b.date.compareTo(a.date);
        return c != 0 ? c : b.createdAt.compareTo(a.createdAt);
      });
    return FinanceSnapshot(
      today: clock.today(),
      monthStartDay: monthStartDay,
      profile: profile.current,
      categories: await categories.getAll(),
      transactions: txs,
      budgets: await budgets.getAll(),
      goals: await goals.getAll(),
      savingsMovements: await savingsMovements.getAll(),
      emergencyPlan: emergencyPlan.current,
      loans: await loans.getAll(),
      loanPayments: await loanPayments.getAll(),
      subscriptions: await subscriptions.getAll(),
      pending: await pending.getAll(),
      settlements: await settlements.getAll(),
      assets: await assets.getAll(),
      accounts: await moneyAccounts.getAll(),
      transfers: await transfers.getAll(),
    );
  }
}
