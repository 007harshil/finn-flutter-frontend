import 'package:flutter/foundation.dart';

import '../core/money/money.dart';
import '../core/time/dates.dart';
import '../features/accounts/domain/money_account.dart';
import '../features/accounts/domain/transfer.dart';
import '../features/budgets/domain/budget.dart';
import '../features/budgets/domain/budget_calculator.dart';
import '../features/categories/domain/category.dart';
import '../features/emergency_fund/domain/emergency_fund.dart';
import '../features/emergency_fund/domain/emergency_fund_calculator.dart';
import '../features/goals/domain/goal.dart';
import '../features/goals/domain/goal_calculator.dart';
import '../features/loans/domain/loan.dart';
import '../features/loans/domain/loan_calculator.dart';
import '../features/net_worth/domain/asset.dart';
import '../features/net_worth/domain/net_worth.dart';
import '../features/pending/domain/pending_payment.dart';
import '../features/settings/domain/financial_profile.dart';
import '../features/subscriptions/domain/subscription.dart';
import '../features/transactions/domain/transaction.dart';
import 'ledger.dart';

/// An immutable, consistent view of all financial data at one moment.
///
/// Every projection (balances, budget usage, alerts, analytics) is derived
/// from a single snapshot, so they can never disagree with each other.
/// Derived values are computed lazily and memoised for the lifetime of the
/// snapshot; any data change produces a new snapshot (explicit invalidation).
class FinanceSnapshot {
  FinanceSnapshot({
    required DateTime today,
    required this.monthStartDay,
    required this.profile,
    required this.categories,
    required this.transactions,
    required this.budgets,
    required this.goals,
    required this.savingsMovements,
    required this.emergencyPlan,
    required this.loans,
    required this.loanPayments,
    required this.subscriptions,
    required this.pending,
    required this.settlements,
    required this.assets,
    List<MoneyAccount> accounts = const [],
    this.transfers = const [],
  })  : today = today.dateOnly,
        accounts = sortAccounts(accounts);

  factory FinanceSnapshot.empty(DateTime today) => FinanceSnapshot(
        today: today,
        monthStartDay: 1,
        profile: null,
        categories: const [],
        transactions: const [],
        budgets: const [],
        goals: const [],
        savingsMovements: const [],
        emergencyPlan: null,
        loans: const [],
        loanPayments: const [],
        subscriptions: const [],
        pending: const [],
        settlements: const [],
        assets: const [],
        accounts: const [],
        transfers: const [],
      );

  final DateTime today;
  final int monthStartDay;
  final FinancialProfile? profile;
  final List<TransactionCategory> categories;

  /// Sorted newest first.
  final List<Transaction> transactions;
  final List<Budget> budgets;
  final List<SavingsGoal> goals;
  final List<SavingsMovement> savingsMovements;
  final EmergencyFundPlan? emergencyPlan;
  final List<Loan> loans;
  final List<LoanPayment> loanPayments;
  final List<Subscription> subscriptions;
  final List<PendingPayment> pending;
  final List<PendingSettlement> settlements;
  final List<Asset> assets;

  /// Money accounts (cash, banks, cards), ordered by sortOrder then createdAt.
  final List<MoneyAccount> accounts;
  final List<Transfer> transfers;

  static const ledgerCalc = LedgerCalculator();
  static const cashFlowCalc = CashFlowCalculator();
  static const budgetCalc = BudgetCalculator();
  static const goalCalc = GoalCalculator();
  static const loanCalc = LoanCalculator();
  static const pendingCalc = PendingCalculator();
  static const emergencyCalc = EmergencyFundCalculator();
  static const subscriptionCalc = SubscriptionCalculator();
  static const netWorthCalc = NetWorthCalculator();

  bool get isFreshUser =>
      transactions.isEmpty && pending.isEmpty && loans.isEmpty && goals.isEmpty;

  MonthKey get currentMonth => today.monthKey;

  late final Map<String, TransactionCategory> categoryById = {for (final c in categories) c.id: c};
  late final Map<String, Transaction> transactionById = {for (final t in transactions) t.id: t};

  TransactionCategory? category(String id) => categoryById[id];

  late final Map<String, MoneyAccount> accountById = {for (final a in accounts) a.id: a};

  MoneyAccount? account(String id) => accountById[id];

  /// Accounts shown in pickers and on Home (not archived), in display order.
  late final List<MoneyAccount> activeAccounts = [for (final a in accounts) if (!a.isArchived) a];

  /// The non-archived default account; falls back to the first active one.
  MoneyAccount? get defaultAccount =>
      activeAccounts.where((a) => a.isDefault).firstOrNull ?? activeAccounts.firstOrNull;

  /// Id used when an input omits `accountId`.
  String get defaultAccountId => defaultAccount?.id ?? cashAccountId;

  /// Per-account balances (owed for credit cards) in display order.
  List<AccountBalance> get accountBalances => balance.accounts;

  late final BalanceSnapshot balance = ledgerCalc.balance(
    profile: profile,
    accounts: accounts,
    transfers: transfers,
    transactions: transactions,
    movements: savingsMovements,
    asOf: today,
  );

  final Map<DateRange, PeriodSummary> _summaries = {};

  /// Cash-flow summary for any range (memoised per range).
  PeriodSummary summary(DateRange range) =>
      _summaries.putIfAbsent(range, () => cashFlowCalc.summarize(transactions, range));

  PeriodSummary monthSummary(MonthKey month) => summary(month.range);

  /// The current budget period (honours the month start day).
  DateRange get currentBudgetPeriod => budgetCalc.monthlyPeriod(today, monthStartDay);

  late final List<BudgetUsage> budgetUsages = [
    for (final b in budgets)
      budgetCalc.usage(
        budget: b,
        transactions: transactions,
        subscriptions: subscriptions,
        today: today,
        monthStartDay: monthStartDay,
      ),
  ];

  BudgetUsage? budgetUsage(String budgetId) =>
      budgetUsages.where((u) => u.budget.id == budgetId).firstOrNull;

  /// The budget month (keyed by the month its period starts in) of today.
  MonthKey get currentBudgetMonth => currentBudgetPeriod.start.monthKey;

  /// First budget month any budget covers (null when there are none).
  MonthKey? get firstBudgetMonth => budgets.isEmpty
      ? null
      : budgets.map((b) => budgetCalc.monthOf(b.createdAt, monthStartDay)).reduce((a, b) => a < b ? a : b);

  final Map<MonthKey, List<BudgetUsage>> _budgetMonths = {};

  /// Budgets as they stood in budget [month]. The current month is
  /// [budgetUsages]. A past month is read-only history: every budget that
  /// existed then, with the limit it had then, measured against that
  /// month's expenses (pausing only affects the current month).
  List<BudgetUsage> budgetUsagesFor(MonthKey month) {
    if (month >= currentBudgetMonth) return budgetUsages;
    return _budgetMonths.putIfAbsent(month, () {
      final period = budgetCalc.periodOf(month, monthStartDay);
      return [
        for (final b in budgets)
          if (budgetCalc.monthOf(b.createdAt, monthStartDay) <= month)
            budgetCalc.usage(
              budget: b.isPaused ? b.copyWith(status: BudgetStatus.active) : b,
              transactions: transactions,
              subscriptions: subscriptions,
              today: today,
              monthStartDay: monthStartDay,
              period: period,
            ),
      ];
    });
  }

  late final List<GoalProgress> goalProgress = [
    for (final g in goals) goalCalc.progress(g, savingsMovements, today),
  ];

  GoalProgress? goal(String id) => goalProgress.where((g) => g.goal.id == id).firstOrNull;

  late final List<LoanState> loanStates = [for (final l in loans) loanCalc.state(l, loanPayments, today)];

  LoanState? loan(String id) => loanStates.where((l) => l.loan.id == id).firstOrNull;

  late final List<PendingView> pendingViews = [
    for (final p in pending) pendingCalc.view(p, settlements, today),
  ];

  PendingView? pendingView(String id) => pendingViews.where((p) => p.payment.id == id).firstOrNull;

  late final EmergencyFundStatus emergency = emergencyCalc.status(
    plan: emergencyPlan,
    movements: savingsMovements,
    transactions: transactions,
    categories: categoryById,
    today: today,
  );

  late final NetWorthSnapshot netWorth = netWorthCalc.compute(
    balance: balance,
    assets: assets,
    loans: loanStates,
    pending: pendingViews,
  );

  /// Total outstanding principal on borrowed loans.
  late final Money totalDebt = Money.sum(
    loanStates.where((l) => l.loan.isBorrowed && !l.isClosed).map((l) => l.outstanding),
  );

  late final Money pendingToPay = Money.sum(pendingViews
      .where((p) => p.payment.direction == PendingDirection.iOwe)
      .map((p) => p.outstanding));

  late final Money pendingToCollect = Money.sum(pendingViews
      .where((p) => p.payment.direction == PendingDirection.owedToMe)
      .map((p) => p.outstanding));

  late final Money monthlySubscriptionCommitment = subscriptionCalc.monthlyCommitment(subscriptions);

  /// Transactions created by a specific origin record (e.g. a loan).
  List<Transaction> linkedTransactions(String originRefId) =>
      transactions.where((t) => t.originRefId == originRefId).toList();

  @visibleForTesting
  int get memoisedSummaryCount => _summaries.length;
}
