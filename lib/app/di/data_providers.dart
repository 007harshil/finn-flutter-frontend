import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money/money.dart';
import '../../core/time/dates.dart';
import '../../features/accounts/domain/money_account.dart';
import '../../features/accounts/domain/transfer.dart';
import '../../features/alerts/domain/alert.dart';
import '../../features/alerts/domain/alert_engine.dart';
import '../../features/analytics/domain/analytics.dart';
import '../../features/budgets/domain/budget.dart';
import '../../features/categories/domain/category.dart';
import '../../features/emergency_fund/domain/emergency_fund.dart';
import '../../features/goals/domain/goal.dart';
import '../../features/loans/domain/loan.dart';
import '../../features/loans/domain/loan_calculator.dart';
import '../../features/net_worth/domain/asset.dart';
import '../../features/net_worth/domain/net_worth.dart';
import '../../features/pending/domain/pending_payment.dart';
import '../../features/settings/domain/financial_profile.dart';
import '../../features/subscriptions/domain/subscription.dart';
import '../../features/timeline/domain/timeline.dart';
import '../../features/transactions/domain/transaction.dart';
import '../../finance/finance_snapshot.dart';
import '../../finance/ledger.dart';
import '../../domain/friend_directory.dart';
import '../../domain/repositories.dart';
import '../../features/friends/domain/friends.dart';
import 'core_providers.dart';

// ---------------------------------------------------------------------------
// Raw collections (one stream per repository).
// ---------------------------------------------------------------------------

final transactionsStreamProvider = StreamProvider<List<Transaction>>(
    (ref) => ref.watch(financeRepositoriesProvider).transactions.watchAll());
final categoriesStreamProvider = StreamProvider<List<TransactionCategory>>(
    (ref) => ref.watch(financeRepositoriesProvider).categories.watchAll());
final budgetsStreamProvider =
    StreamProvider<List<Budget>>((ref) => ref.watch(financeRepositoriesProvider).budgets.watchAll());
final goalsStreamProvider =
    StreamProvider<List<SavingsGoal>>((ref) => ref.watch(financeRepositoriesProvider).goals.watchAll());
final savingsMovementsStreamProvider = StreamProvider<List<SavingsMovement>>(
    (ref) => ref.watch(financeRepositoriesProvider).savingsMovements.watchAll());
final loansStreamProvider =
    StreamProvider<List<Loan>>((ref) => ref.watch(financeRepositoriesProvider).loans.watchAll());
final loanPaymentsStreamProvider = StreamProvider<List<LoanPayment>>(
    (ref) => ref.watch(financeRepositoriesProvider).loanPayments.watchAll());
final subscriptionsStreamProvider = StreamProvider<List<Subscription>>(
    (ref) => ref.watch(financeRepositoriesProvider).subscriptions.watchAll());
final pendingStreamProvider =
    StreamProvider<List<PendingPayment>>((ref) => ref.watch(financeRepositoriesProvider).pending.watchAll());
final settlementsStreamProvider = StreamProvider<List<PendingSettlement>>(
    (ref) => ref.watch(financeRepositoriesProvider).settlements.watchAll());
final assetsStreamProvider =
    StreamProvider<List<Asset>>((ref) => ref.watch(financeRepositoriesProvider).assets.watchAll());
final moneyAccountsStreamProvider = StreamProvider<List<MoneyAccount>>(
    (ref) => ref.watch(financeRepositoriesProvider).moneyAccounts.watchAll());
final transfersStreamProvider =
    StreamProvider<List<Transfer>>((ref) => ref.watch(financeRepositoriesProvider).transfers.watchAll());
final profileStreamProvider =
    StreamProvider<FinancialProfile?>((ref) => ref.watch(financeRepositoriesProvider).profile.watch());
final emergencyPlanStreamProvider =
    StreamProvider<EmergencyFundPlan?>((ref) => ref.watch(financeRepositoriesProvider).emergencyPlan.watch());
final alertInboxStreamProvider =
    StreamProvider<AlertInboxState>((ref) => ref.watch(financeRepositoriesProvider).alertInbox.watch());

/// Transactions sorted newest first. Re-sorted only when the list changes.
final sortedTransactionsProvider = Provider<AsyncValue<List<Transaction>>>((ref) {
  return ref.watch(transactionsStreamProvider).whenData((list) => List.of(list)
    ..sort((a, b) {
      final c = b.date.compareTo(a.date);
      return c != 0 ? c : b.createdAt.compareTo(a.createdAt);
    }));
});

// ---------------------------------------------------------------------------
// The consistent snapshot every projection derives from.
// ---------------------------------------------------------------------------

/// Combines all collections into one [FinanceSnapshot]. Loading until every
/// collection has emitted; errors if any collection fails.
final financeSnapshotProvider = Provider<AsyncValue<FinanceSnapshot>>((ref) {
  final today = ref.watch(todayProvider);
  final monthStartDay = ref.watch(settingsProvider.select((s) => s.monthStartDay));
  final parts = <AsyncValue<Object?>>[
    ref.watch(categoriesStreamProvider),
    ref.watch(sortedTransactionsProvider),
    ref.watch(budgetsStreamProvider),
    ref.watch(goalsStreamProvider),
    ref.watch(savingsMovementsStreamProvider),
    ref.watch(loansStreamProvider),
    ref.watch(loanPaymentsStreamProvider),
    ref.watch(subscriptionsStreamProvider),
    ref.watch(pendingStreamProvider),
    ref.watch(settlementsStreamProvider),
    ref.watch(assetsStreamProvider),
    ref.watch(profileStreamProvider),
    ref.watch(emergencyPlanStreamProvider),
    ref.watch(moneyAccountsStreamProvider),
    ref.watch(transfersStreamProvider),
  ];
  for (final p in parts) {
    if (p.hasError) return AsyncError(p.error!, p.stackTrace ?? StackTrace.current);
  }
  if (parts.any((p) => !p.hasValue)) return const AsyncLoading();
  return AsyncData(FinanceSnapshot(
    today: today,
    monthStartDay: monthStartDay,
    categories: parts[0].requireValue! as List<TransactionCategory>,
    transactions: parts[1].requireValue! as List<Transaction>,
    budgets: parts[2].requireValue! as List<Budget>,
    goals: parts[3].requireValue! as List<SavingsGoal>,
    savingsMovements: parts[4].requireValue! as List<SavingsMovement>,
    loans: parts[5].requireValue! as List<Loan>,
    loanPayments: parts[6].requireValue! as List<LoanPayment>,
    subscriptions: parts[7].requireValue! as List<Subscription>,
    pending: parts[8].requireValue! as List<PendingPayment>,
    settlements: parts[9].requireValue! as List<PendingSettlement>,
    assets: parts[10].requireValue! as List<Asset>,
    profile: parts[11].value as FinancialProfile?,
    emergencyPlan: parts[12].value as EmergencyFundPlan?,
    accounts: parts[13].requireValue! as List<MoneyAccount>,
    transfers: parts[14].requireValue! as List<Transfer>,
  ));
});

/// Retries every data stream (used by error-state "Try again" buttons).
void refreshFinanceData(WidgetRef ref) {
  for (final p in [
    categoriesStreamProvider, transactionsStreamProvider, budgetsStreamProvider, goalsStreamProvider,
    savingsMovementsStreamProvider, loansStreamProvider, loanPaymentsStreamProvider,
    subscriptionsStreamProvider, pendingStreamProvider, settlementsStreamProvider, assetsStreamProvider,
    moneyAccountsStreamProvider, transfersStreamProvider,
  ]) {
    ref.invalidate(p);
  }
  ref.invalidate(profileStreamProvider);
  ref.invalidate(emergencyPlanStreamProvider);
}

// ---------------------------------------------------------------------------
// Derived projections. Riverpod only notifies dependants when the derived
// value changes (==), so e.g. editing a transaction in one category does not
// rebuild unrelated goal widgets.
// ---------------------------------------------------------------------------

AsyncValue<T> _derive<T>(Ref ref, T Function(FinanceSnapshot s) f) => ref.watch(financeSnapshotProvider).whenData(f);

final balanceProvider = Provider<AsyncValue<BalanceSnapshot>>((ref) => _derive(ref, (s) => s.balance));

/// Every account (archived included) in display order.
final moneyAccountsProvider = Provider<AsyncValue<List<MoneyAccount>>>((ref) => _derive(ref, (s) => s.accounts));

/// Accounts for pickers and Home (not archived), in display order.
final activeAccountsProvider =
    Provider<AsyncValue<List<MoneyAccount>>>((ref) => _derive(ref, (s) => s.activeAccounts));

/// Balance (owed for credit cards) of every account, sorted by sortOrder.
final accountBalancesProvider =
    Provider<AsyncValue<List<AccountBalance>>>((ref) => _derive(ref, (s) => s.accountBalances));

/// One account with its balance; null when it does not exist.
final accountBalanceProvider = Provider.family<AsyncValue<AccountBalance?>, String>(
    (ref, id) => _derive(ref, (s) => s.accountBalances.where((b) => b.account.id == id).firstOrNull));

/// The default account (preselected in forms).
final defaultAccountProvider = Provider<AsyncValue<MoneyAccount?>>((ref) => _derive(ref, (s) => s.defaultAccount));

final transfersProvider = Provider<AsyncValue<List<Transfer>>>((ref) => _derive(ref, (s) => s.transfers));

/// Total owed on credit cards.
final creditOwedProvider = Provider<AsyncValue<Money>>((ref) => _derive(ref, (s) => s.balance.creditOwed));

final categoriesByIdProvider =
    Provider<AsyncValue<Map<String, TransactionCategory>>>((ref) => _derive(ref, (s) => s.categoryById));

final categoryProvider = Provider.family<TransactionCategory?, String>(
    (ref, id) => ref.watch(categoriesByIdProvider).value?[id]);

final transactionByIdProvider = Provider.family<AsyncValue<Transaction?>, String>(
    (ref, id) => _derive(ref, (s) => s.transactionById[id]));

final monthSummaryProvider =
    Provider.family<AsyncValue<PeriodSummary>, MonthKey>((ref, m) => _derive(ref, (s) => s.monthSummary(m)));

final rangeSummaryProvider =
    Provider.family<AsyncValue<PeriodSummary>, DateRange>((ref, r) => _derive(ref, (s) => s.summary(r)));

final budgetUsagesProvider = Provider<AsyncValue<List<BudgetUsage>>>((ref) => _derive(ref, (s) => s.budgetUsages));

final budgetUsageProvider =
    Provider.family<AsyncValue<BudgetUsage?>, String>((ref, id) => _derive(ref, (s) => s.budgetUsage(id)));

final goalProgressListProvider = Provider<AsyncValue<List<GoalProgress>>>((ref) => _derive(ref, (s) => s.goalProgress));

final goalProgressProvider =
    Provider.family<AsyncValue<GoalProgress?>, String>((ref, id) => _derive(ref, (s) => s.goal(id)));

final loanStatesProvider = Provider<AsyncValue<List<LoanState>>>((ref) => _derive(ref, (s) => s.loanStates));

final loanStateProvider =
    Provider.family<AsyncValue<LoanState?>, String>((ref, id) => _derive(ref, (s) => s.loan(id)));

final pendingViewsProvider = Provider<AsyncValue<List<PendingView>>>((ref) => _derive(ref, (s) => s.pendingViews));

final pendingViewProvider =
    Provider.family<AsyncValue<PendingView?>, String>((ref, id) => _derive(ref, (s) => s.pendingView(id)));

/// People on FiNN (search + the signed-in user).
final userDirectoryProvider = Provider<UserDirectory>((ref) => ref.watch(financeRepositoriesProvider).users);

/// Friends, requests and FiNN ID lookup.
final friendDirectoryProvider = Provider<FriendDirectory>((ref) => ref.watch(financeRepositoriesProvider).friends);

/// Friends and requests; emits the current state first, then every change.
final friendStateProvider = StreamProvider<FriendState>((ref) async* {
  final directory = ref.watch(friendDirectoryProvider);
  yield directory.current;
  // Pick up requests that arrived while the app was closed.
  unawaited(directory.refresh().catchError((Object _) {}));
  yield* directory.watch();
});

/// Every mirrored (counterparty-side) entry of shared pending items.
final sharedLedgerStreamProvider =
    StreamProvider<List<MirrorEntry>>((ref) => ref.watch(financeRepositoriesProvider).sharedLedger.watchAll());

/// The other person's side of a shared item, or null for private items.
final mirrorProvider = Provider.family<MirrorEntry?, PendingLink>((ref, link) {
  final all = ref.watch(sharedLedgerStreamProvider).value ?? const <MirrorEntry>[];
  final key = MirrorEntry.keyOf(link.userId, link.sharedId);
  return all.where((m) => m.key == key).firstOrNull;
});

final emergencyStatusProvider = Provider<AsyncValue<EmergencyFundStatus>>((ref) => _derive(ref, (s) => s.emergency));

final netWorthProvider = Provider<AsyncValue<NetWorthSnapshot>>((ref) => _derive(ref, (s) => s.netWorth));

final subscriptionsProvider = Provider<AsyncValue<List<Subscription>>>((ref) => _derive(ref, (s) => s.subscriptions));

final subscriptionProvider = Provider.family<AsyncValue<Subscription?>, String>(
    (ref, id) => _derive(ref, (s) => s.subscriptions.where((x) => x.id == id).firstOrNull));

final assetsProvider = Provider<AsyncValue<List<Asset>>>((ref) => _derive(ref, (s) => s.assets));

final debtTotalProvider = Provider<AsyncValue<Money>>((ref) => _derive(ref, (s) => s.totalDebt));

// Alerts ---------------------------------------------------------------------

const _alertEngine = AlertEngine();

/// All generated alerts (including dismissed), sorted by urgency.
final allAlertsProvider = Provider<AsyncValue<List<FinancialAlert>>>((ref) {
  final settings = ref.watch(settingsProvider);
  return _derive(ref, (s) => _alertEngine.generate(s, settings));
});

/// Alerts the user has not dismissed.
final activeAlertsProvider = Provider<AsyncValue<List<FinancialAlert>>>((ref) {
  final inbox = ref.watch(alertInboxStreamProvider).value ?? const AlertInboxState();
  return ref.watch(allAlertsProvider).whenData(
        (list) => list.where((a) => !inbox.dismissedKeys.contains(a.key)).toList(),
      );
});

final unreadAlertCountProvider = Provider<int>((ref) {
  final inbox = ref.watch(alertInboxStreamProvider).value ?? const AlertInboxState();
  final alerts = ref.watch(activeAlertsProvider).value ?? const [];
  return alerts.where((a) => !inbox.readKeys.contains(a.key)).length;
});

final alertInboxProvider = Provider<AlertInboxState>(
    (ref) => ref.watch(alertInboxStreamProvider).value ?? const AlertInboxState());

/// Marks alerts as read / dismissed (UI bookkeeping, not a financial action).
class AlertInboxController {
  AlertInboxController(this._ref);
  final Ref _ref;

  Future<void> markRead(Iterable<String> keys) async {
    final repo = _ref.read(financeRepositoriesProvider).alertInbox;
    final cur = repo.current;
    final next = {...cur.readKeys, ...keys};
    if (next.length == cur.readKeys.length) return;
    await repo.set(cur.copyWith(readKeys: next));
  }

  Future<void> dismiss(String key) async {
    final repo = _ref.read(financeRepositoriesProvider).alertInbox;
    final cur = repo.current;
    await repo.set(cur.copyWith(dismissedKeys: {...cur.dismissedKeys, key}, readKeys: {...cur.readKeys, key}));
  }

  Future<void> restoreAll() async {
    final repo = _ref.read(financeRepositoriesProvider).alertInbox;
    await repo.set(repo.current.copyWith(dismissedKeys: {}));
  }
}

final alertInboxControllerProvider = Provider<AlertInboxController>((ref) => AlertInboxController(ref));

// Analytics & timeline -----------------------------------------------------------

const analyticsService = AnalyticsService();
const timelineService = TimelineService();

final insightsProvider =
    Provider.family<AsyncValue<List<Insight>>, MonthKey>((ref, m) => _derive(ref, (s) => analyticsService.insights(s, m)));

final monthlyNarrativeProvider =
    Provider.family<AsyncValue<List<String>>, MonthKey>((ref, m) => _derive(ref, (s) => analyticsService.monthlyNarrative(s, m)));

final storyChapterProvider =
    Provider.family<AsyncValue<StoryChapter>, MonthKey>((ref, m) => _derive(ref, (s) => timelineService.chapter(s, m)));

final timelineMonthsProvider = Provider<AsyncValue<List<MonthKey>>>((ref) => _derive(ref, timelineService.availableMonths));
