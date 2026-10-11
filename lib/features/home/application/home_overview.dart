import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/data_providers.dart';
import '../../../core/money/money.dart';
import '../../../core/time/dates.dart';
import '../../../finance/finance_snapshot.dart';
import '../../../finance/ledger.dart';
import '../../goals/domain/goal.dart';
import '../../pending/domain/pending_payment.dart';

AsyncValue<T> _derive<T>(Ref ref, T Function(FinanceSnapshot s) f) => ref.watch(financeSnapshotProvider).whenData(f);

// ---------------------------------------------------------------------------
// Fresh user & setup checklist
// ---------------------------------------------------------------------------

/// True until the user records anything (transactions, pending, loans, goals).
final isFreshUserProvider = Provider<AsyncValue<bool>>((ref) => _derive(ref, (s) => s.isFreshUser));

enum SetupStep {
  profile('Add your name and opening balance', 'So balances start from the right number.'),
  emergencyFund('Plan your emergency fund', 'A safety net for 3–6 months of essentials.'),
  goal('Create a savings goal', 'Set money aside for something that matters.'),
  budget('Set a monthly budget', 'Stay comfortably within a spending limit.');

  const SetupStep(this.title, this.description);
  final String title;
  final String description;
}

@immutable
class SetupChecklist {
  const SetupChecklist(this.done);

  final Set<SetupStep> done;

  int get completed => done.length;
  int get total => SetupStep.values.length;
  bool isDone(SetupStep step) => done.contains(step);

  @override
  bool operator ==(Object other) => other is SetupChecklist && setEquals(other.done, done);

  @override
  int get hashCode => done.length;
}

SetupChecklist setupChecklist(FinanceSnapshot s) => SetupChecklist({
  if (s.profile != null && s.profile!.displayName.trim().isNotEmpty) SetupStep.profile,
  if (s.emergencyPlan != null) SetupStep.emergencyFund,
  if (s.goals.isNotEmpty) SetupStep.goal,
  if (s.budgets.isNotEmpty) SetupStep.budget,
});

final setupChecklistProvider = Provider<AsyncValue<SetupChecklist>>((ref) => _derive(ref, setupChecklist));

// ---------------------------------------------------------------------------
// Savings health (savings rate for a month)
// ---------------------------------------------------------------------------

enum SavingsHealthLevel {
  noData('Not enough data'),
  strong('Healthy'),
  steady('Steady'),
  thin('Thin margin'),
  deficit('Spending above income');

  const SavingsHealthLevel(this.label);
  final String label;
}

@immutable
class SavingsHealth {
  const SavingsHealth({required this.level, required this.rateBps, required this.explanation});

  final SavingsHealthLevel level;

  /// Net ÷ income in basis points; null when there was no income.
  final int? rateBps;
  final String explanation;

  /// 0..1 for a gauge (negative rates show as empty).
  double get gauge => ((rateBps ?? 0).clamp(0, 5000)) / 5000.0;

  @override
  bool operator ==(Object other) => other is SavingsHealth && other.level == level && other.rateBps == rateBps;

  @override
  int get hashCode => Object.hash(level, rateBps);
}

/// Classifies a month's savings rate. 20%+ is healthy, 10–20% steady,
/// 0–10% thin, below zero means spending exceeded income.
SavingsHealth savingsHealth(PeriodSummary summary) {
  final bps = summary.savingsRateBps;
  if (bps == null) {
    return const SavingsHealth(
      level: SavingsHealthLevel.noData,
      rateBps: null,
      explanation: 'No income recorded for this month yet, so a savings rate cannot be calculated.',
    );
  }
  if (bps >= 2000) {
    return SavingsHealth(
      level: SavingsHealthLevel.strong,
      rateBps: bps,
      explanation: 'You kept a healthy share of what you earned. 20% or more is a comfortable cushion.',
    );
  }
  if (bps >= 1000) {
    return SavingsHealth(
      level: SavingsHealthLevel.steady,
      rateBps: bps,
      explanation: 'You are saving steadily. Nudging this towards 20% builds a stronger cushion.',
    );
  }
  if (bps >= 0) {
    return SavingsHealth(
      level: SavingsHealthLevel.thin,
      rateBps: bps,
      explanation: 'Most of your income was spent. A little trimming would widen your margin.',
    );
  }
  return SavingsHealth(
    level: SavingsHealthLevel.deficit,
    rateBps: bps,
    explanation: 'Spending was higher than income this month, so savings or earlier balances covered the gap.',
  );
}

final savingsHealthProvider = Provider.family<AsyncValue<SavingsHealth>, MonthKey>(
  (ref, m) => ref.watch(monthSummaryProvider(m)).whenData(savingsHealth),
);

// ---------------------------------------------------------------------------
// Debt overview
// ---------------------------------------------------------------------------

@immutable
class DebtOverview {
  const DebtOverview({
    required this.totalOutstanding,
    required this.activeLoans,
    this.nextLoanId,
    this.nextLoanName,
    this.nextDueDate,
    this.nextAmount,
    this.overdueCount = 0,
  });

  /// Outstanding principal across active borrowed loans.
  final Money totalOutstanding;
  final int activeLoans;
  final String? nextLoanId;
  final String? nextLoanName;
  final DateTime? nextDueDate;
  final Money? nextAmount;

  /// Overdue instalments across all borrowed loans.
  final int overdueCount;

  bool get hasDebt => activeLoans > 0;

  @override
  bool operator ==(Object other) =>
      other is DebtOverview &&
      other.totalOutstanding == totalOutstanding &&
      other.activeLoans == activeLoans &&
      other.nextLoanId == nextLoanId &&
      other.nextDueDate == nextDueDate &&
      other.nextAmount == nextAmount &&
      other.overdueCount == overdueCount;

  @override
  int get hashCode => Object.hash(totalOutstanding, activeLoans, nextLoanId, nextDueDate, overdueCount);
}

DebtOverview debtOverview(FinanceSnapshot s) {
  final active = s.loanStates.where((l) => l.loan.isBorrowed && !l.isClosed).toList();
  final withDue = active.where((l) => l.nextDue != null).toList()
    ..sort((a, b) => a.nextDue!.dueDate.compareTo(b.nextDue!.dueDate));
  final next = withDue.firstOrNull;
  return DebtOverview(
    totalOutstanding: s.totalDebt,
    activeLoans: active.length,
    nextLoanId: next?.loan.id,
    nextLoanName: next?.loan.name,
    nextDueDate: next?.nextDue?.dueDate,
    nextAmount: next?.nextDue?.payment,
    overdueCount: active.fold(0, (n, l) => n + l.overdueCount),
  );
}

final debtOverviewProvider = Provider<AsyncValue<DebtOverview>>((ref) => _derive(ref, debtOverview));

// ---------------------------------------------------------------------------
// Pending overview
// ---------------------------------------------------------------------------

@immutable
class PendingOverview {
  const PendingOverview({
    required this.toPay,
    required this.toCollect,
    required this.payCount,
    required this.collectCount,
    this.longPending = const [],
  });

  final Money toPay;
  final Money toCollect;
  final int payCount;
  final int collectCount;

  /// Open longer than [PendingView.longPendingDays], oldest first.
  /// Informative only: pending items are never "late".
  final List<PendingView> longPending;

  int get activeCount => payCount + collectCount;

  @override
  bool operator ==(Object other) =>
      other is PendingOverview &&
      other.toPay == toPay &&
      other.toCollect == toCollect &&
      other.payCount == payCount &&
      other.collectCount == collectCount &&
      listEquals(other.longPending, longPending);

  @override
  int get hashCode => Object.hash(toPay, toCollect, payCount, collectCount, Object.hashAll(longPending));
}

PendingOverview pendingOverview(FinanceSnapshot s) {
  final active = s.pendingViews.where((p) => p.status.isActive);
  return PendingOverview(
    toPay: s.pendingToPay,
    toCollect: s.pendingToCollect,
    payCount: active.where((p) => p.payment.direction == PendingDirection.iOwe).length,
    collectCount: active.where((p) => p.payment.direction == PendingDirection.owedToMe).length,
    longPending: active.where((p) => p.isLongPending).toList()..sort((a, b) => b.daysOpen.compareTo(a.daysOpen)),
  );
}

final pendingOverviewProvider = Provider<AsyncValue<PendingOverview>>((ref) => _derive(ref, pendingOverview));

// ---------------------------------------------------------------------------
// Subscriptions overview
// ---------------------------------------------------------------------------

@immutable
class SubscriptionOverview {
  const SubscriptionOverview({required this.monthlyCommitment, required this.activeCount});

  /// Monthly-equivalent cost of active subscriptions (projected).
  final Money monthlyCommitment;
  final int activeCount;

  @override
  bool operator ==(Object other) =>
      other is SubscriptionOverview && other.monthlyCommitment == monthlyCommitment && other.activeCount == activeCount;

  @override
  int get hashCode => Object.hash(monthlyCommitment, activeCount);
}

final subscriptionOverviewProvider = Provider<AsyncValue<SubscriptionOverview>>(
  (ref) => _derive(
    ref,
    (s) => SubscriptionOverview(
      monthlyCommitment: s.monthlySubscriptionCommitment,
      activeCount: s.subscriptions.where((x) => x.isActive).length,
    ),
  ),
);

// ---------------------------------------------------------------------------
// Goals
// ---------------------------------------------------------------------------

/// Active goals not yet reached, closest to completion first.
List<GoalProgress> topActiveGoals(List<GoalProgress> all, {int take = 3}) {
  final active = all.where((g) => g.goal.status == GoalStatus.active && !g.isAchieved).toList()
    ..sort((a, b) => b.progressBps.compareTo(a.progressBps));
  return active.take(take).toList();
}

final topGoalsProvider = Provider<AsyncValue<List<GoalProgress>>>(
  (ref) => ref.watch(goalProgressListProvider).whenData((l) => topActiveGoals(l)),
);
