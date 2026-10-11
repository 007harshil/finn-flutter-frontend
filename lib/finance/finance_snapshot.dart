import 'package:flutter/foundation.dart';

import '../core/money/money.dart';
import '../core/time/dates.dart';
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
  }) : today = today.dateOnly;

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

  late final BalanceSnapshot balance = ledgerCalc.balance(
    profile: profile,
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
