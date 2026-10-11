// Small builders for domain tests. Everything is explicit: no seed data.

import 'package:finn/core/money/money.dart';
import 'package:finn/core/time/frequency.dart';
import 'package:finn/data/mock/seed_data.dart';
import 'package:finn/features/budgets/domain/budget.dart';
import 'package:finn/features/categories/domain/category.dart';
import 'package:finn/features/emergency_fund/domain/emergency_fund.dart';
import 'package:finn/features/goals/domain/goal.dart';
import 'package:finn/features/loans/domain/loan.dart';
import 'package:finn/features/net_worth/domain/asset.dart';
import 'package:finn/features/pending/domain/pending_payment.dart';
import 'package:finn/features/settings/domain/financial_profile.dart';
import 'package:finn/features/subscriptions/domain/subscription.dart';
import 'package:finn/features/transactions/domain/transaction.dart';
import 'package:finn/finance/finance_snapshot.dart';

/// Fixed "today" for domain tests: Saturday 10 Oct 2026.
final fxToday = DateTime(2026, 10, 10);
final fxStamp = DateTime(2026, 1, 1);

DateTime d(int y, int m, int day) => DateTime(y, m, day);
Money rs(int rupees) => Money.rupees(rupees);

int _seq = 0;
String _id(String prefix) => '${prefix}_${_seq++}';

final fxCategories = SeedData.standardCategories();

FinancialProfile fxProfile({int opening = 100000, DateTime? openingDate}) => FinancialProfile(
      displayName: 'Test',
      openingBalance: rs(opening),
      openingDate: openingDate ?? d(2026, 1, 1),
    );

Transaction tx(
  int rupees,
  DateTime date, {
  bool income = false,
  String? category,
  TransactionOrigin origin = TransactionOrigin.manual,
  String? originRefId,
  PaymentMethod? method,
  String? counterparty,
  String? id,
}) =>
    Transaction(
      id: id ?? _id('tx'),
      type: income ? TransactionType.income : TransactionType.expense,
      amount: rs(rupees),
      categoryId: category ?? (income ? SeedCategoryIds.salary : SeedCategoryIds.food),
      date: date,
      paymentMethod: method,
      counterparty: counterparty,
      origin: origin,
      originRefId: originRefId,
      createdAt: fxStamp,
      updatedAt: fxStamp,
    );

SavingsMovement goalMove(int rupees, DateTime date, {String goalId = 'g1', bool withdraw = false, String? note}) =>
    SavingsMovement(
      id: _id('sv'),
      bucketType: SavingsBucketType.goal,
      bucketId: goalId,
      kind: withdraw ? SavingsMovementKind.withdrawal : SavingsMovementKind.contribution,
      amount: rs(rupees),
      date: date,
      note: note,
      createdAt: fxStamp,
    );

SavingsMovement efMove(int rupees, DateTime date, {bool withdraw = false}) => SavingsMovement(
      id: _id('sv'),
      bucketType: SavingsBucketType.emergencyFund,
      bucketId: SavingsMovement.emergencyFundBucketId,
      kind: withdraw ? SavingsMovementKind.withdrawal : SavingsMovementKind.contribution,
      amount: rs(rupees),
      date: date,
      createdAt: fxStamp,
    );

SavingsGoal savingsGoal({
  String id = 'g1',
  String name = 'Japan trip',
  int target = 100000,
  DateTime? targetDate,
  int? planned,
  GoalStatus status = GoalStatus.active,
}) =>
    SavingsGoal(
      id: id,
      name: name,
      category: GoalCategory.travel,
      target: rs(target),
      targetDate: targetDate,
      plannedMonthlyContribution: planned == null ? null : rs(planned),
      colorIndex: 1,
      status: status,
      createdAt: fxStamp,
      updatedAt: fxStamp,
    );

Loan emiLoan({
  String id = 'loan1',
  String name = 'Car loan',
  int principal = 600000,
  int rateBps = 950,
  int tenure = 60,
  DateTime? start,
  DateTime? firstDue,
  LoanDirection direction = LoanDirection.borrowed,
  LoanStatus status = LoanStatus.active,
}) =>
    Loan(
      id: id,
      name: name,
      counterparty: direction == LoanDirection.borrowed ? 'HDFC Bank' : 'Ravi',
      direction: direction,
      structure: LoanStructure.amortizing,
      principal: rs(principal),
      rate: InterestRate(rateBps),
      startDate: start ?? d(2026, 1, 1),
      firstDueDate: firstDue ?? d(2026, 2, 5),
      frequency: Frequency.monthly,
      tenureInstallments: tenure,
      status: status,
      createdAt: fxStamp,
      updatedAt: fxStamp,
    );

LoanPayment loanPayment(String loanId, DateTime date, {required int interestPaise, required int principalPaise, int? period}) =>
    LoanPayment(
      id: _id('lp'),
      loanId: loanId,
      kind: period == null ? LoanPaymentKind.principal : LoanPaymentKind.installment,
      date: date,
      interestComponent: Money.fromPaise(interestPaise),
      principalComponent: Money.fromPaise(principalPaise),
      periodNumber: period,
      createdAt: fxStamp,
    );

PendingPayment pendingPayment({
  String? id,
  PendingDirection direction = PendingDirection.iOwe,
  int amount = 5000,
  DateTime? created,
  DateTime? due,
  bool cancelled = false,
  String counterparty = 'Priya',
}) =>
    PendingPayment(
      id: id ?? _id('pend'),
      counterparty: counterparty,
      direction: direction,
      kind: PendingKind.other,
      originalAmount: rs(amount),
      purpose: 'Goa trip share',
      createdDate: created ?? d(2026, 9, 1),
      dueDate: due,
      isCancelled: cancelled,
      createdAt: fxStamp,
      updatedAt: fxStamp,
    );

PendingSettlement settlement(String pendingId, int rupees, DateTime date) => PendingSettlement(
      id: _id('st'),
      pendingId: pendingId,
      amount: rs(rupees),
      date: date,
      createdAt: fxStamp,
    );

Subscription subscription({
  String? id,
  String name = 'Netflix',
  int amount = 649,
  DateTime? nextDue,
  SubscriptionStatus status = SubscriptionStatus.active,
  String category = SeedCategoryIds.subscriptions,
  Frequency frequency = Frequency.monthly,
}) =>
    Subscription(
      id: id ?? _id('sub'),
      name: name,
      amount: rs(amount),
      categoryId: category,
      frequency: frequency,
      nextDueDate: nextDue ?? d(2026, 11, 1),
      status: status,
      createdAt: fxStamp,
      updatedAt: fxStamp,
    );

Budget budget({
  String? id,
  String category = SeedCategoryIds.food,
  int limit = 10000,
  BudgetStatus status = BudgetStatus.active,
  int warningBps = 8000,
}) =>
    Budget(
      id: id ?? _id('bud'),
      categoryId: category,
      limit: rs(limit),
      periodType: BudgetPeriodType.monthly,
      status: status,
      warningThresholdBps: warningBps,
      createdAt: fxStamp,
      updatedAt: fxStamp,
    );

Asset asset(String name, int rupees, {AssetType type = AssetType.investment}) => Asset(
      id: _id('asset'),
      name: name,
      type: type,
      value: rs(rupees),
      valuedOn: d(2026, 9, 30),
      createdAt: fxStamp,
      updatedAt: fxStamp,
    );

EmergencyFundPlan efPlan({int essentials = 40000, int months = 6}) => EmergencyFundPlan(
      essentialMonthlyExpenses: rs(essentials),
      targetMonths: months,
      updatedAt: fxStamp,
    );

FinanceSnapshot snapshotOf({
  DateTime? today,
  FinancialProfile? profile,
  List<TransactionCategory>? categories,
  List<Transaction> transactions = const [],
  List<Budget> budgets = const [],
  List<SavingsGoal> goals = const [],
  List<SavingsMovement> movements = const [],
  EmergencyFundPlan? emergencyPlan,
  List<Loan> loans = const [],
  List<LoanPayment> loanPayments = const [],
  List<Subscription> subscriptions = const [],
  List<PendingPayment> pending = const [],
  List<PendingSettlement> settlements = const [],
  List<Asset> assets = const [],
}) =>
    FinanceSnapshot(
      today: today ?? fxToday,
      monthStartDay: 1,
      profile: profile,
      categories: categories ?? fxCategories,
      transactions: List.of(transactions)..sort((a, b) => b.date.compareTo(a.date)),
      budgets: budgets,
      goals: goals,
      savingsMovements: movements,
      emergencyPlan: emergencyPlan,
      loans: loans,
      loanPayments: loanPayments,
      subscriptions: subscriptions,
      pending: pending,
      settlements: settlements,
      assets: assets,
    );
