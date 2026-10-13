import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../actions/action.dart';
import '../../../app/di/data_providers.dart';
import '../../../core/money/money.dart';
import '../../../core/time/dates.dart';
import '../../../design_system/design_system.dart';
import '../../../finance/finance_snapshot.dart';
import '../../../shared/presentation/action_runner.dart';
import '../../../shared/presentation/category_icons.dart';
import '../../../ui/ui.dart';
import '../../categories/domain/category.dart';
import '../../transactions/domain/transaction.dart';
import '../application/subscription_actions.dart';
import '../domain/subscription.dart';

const _calc = SubscriptionCalculator();

/// One expected (not yet paid) charge.
@immutable
class ExpectedCharge {
  const ExpectedCharge(this.subscription, this.date);
  final Subscription subscription;
  final DateTime date;
}

/// Everything the subscriptions screen shows, derived once per snapshot.
@immutable
class SubscriptionsOverview {
  const SubscriptionsOverview({
    required this.today,
    required this.monthly,
    required this.annual,
    required this.lastMonthIncome,
    required this.incomeShareBps,
    required this.upcoming,
    required this.upcomingTotal,
    required this.active,
    required this.paused,
    required this.cancelled,
    required this.overdueCount,
  });

  factory SubscriptionsOverview.of(FinanceSnapshot s) {
    int byDue(Subscription a, Subscription b) => a.nextDueDate.compareTo(b.nextDueDate);
    final subs = s.subscriptions;
    final active = subs.where((x) => x.status == SubscriptionStatus.active).toList()..sort(byDue);
    final income = s.monthSummary(s.currentMonth.previous).income;
    final monthly = _calc.monthlyCommitment(subs);
    final window = DateRange(s.today, s.today.add(const Duration(days: 30)));
    final upcoming = [
      for (final x in active)
        for (final d in _calc.occurrencesIn(x, window)) ExpectedCharge(x, d),
    ]..sort((a, b) => a.date.compareTo(b.date));
    return SubscriptionsOverview(
      today: s.today,
      monthly: monthly,
      annual: _calc.annualCommitment(subs),
      lastMonthIncome: income,
      incomeShareBps: monthly.ratioBps(income),
      upcoming: upcoming,
      upcomingTotal: Money.sum(upcoming.map((e) => e.subscription.amount)),
      active: active,
      paused: subs.where((x) => x.status == SubscriptionStatus.paused).toList()..sort(byDue),
      cancelled: subs.where((x) => x.status == SubscriptionStatus.cancelled).toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())),
      overdueCount: active.where((x) => _calc.dueState(x, s.today) == DueState.overdue).length,
    );
  }

  final DateTime today;
  final Money monthly;
  final Money annual;
  final Money lastMonthIncome;

  /// Monthly commitment ÷ last month's income; null without income.
  final int? incomeShareBps;
  final List<ExpectedCharge> upcoming;

  /// Sum of [upcoming] (projected, not yet paid).
  final Money upcomingTotal;
  final List<Subscription> active;
  final List<Subscription> paused;
  final List<Subscription> cancelled;
  final int overdueCount;

  bool get isEmpty => active.isEmpty && paused.isEmpty && cancelled.isEmpty;

  IncomeImpact? get incomeImpact => incomeShareBps == null ? null : IncomeImpact.of(incomeShareBps!);
}

/// How much of last month's income recurring costs take.
enum IncomeImpact {
  healthy('Healthy', 'Well within comfortable limits.'),
  moderate('Moderate', 'Balanced, but worth keeping an eye on.'),
  high('High', 'Consider trimming a few fixed costs.'),
  critical('Critical', 'Recurring costs take a large share of income.');

  const IncomeImpact(this.label, this.description);
  final String label;
  final String description;

  static IncomeImpact of(int shareBps) {
    if (shareBps > 4000) return IncomeImpact.critical;
    if (shareBps > 2500) return IncomeImpact.high;
    if (shareBps > 1500) return IncomeImpact.moderate;
    return IncomeImpact.healthy;
  }

  /// Colour only when it needs attention.
  Color? color(UiColors c) => switch (this) {
    IncomeImpact.healthy => null,
    IncomeImpact.moderate || IncomeImpact.high => c.warning,
    IncomeImpact.critical => c.negative,
  };
}

final subscriptionsOverviewProvider = Provider<AsyncValue<SubscriptionsOverview>>(
  (ref) => ref.watch(financeSnapshotProvider).whenData(SubscriptionsOverview.of),
);

/// Data for one subscription's detail page.
@immutable
class SubscriptionDetail {
  const SubscriptionDetail({
    required this.subscription,
    required this.category,
    required this.today,
    required this.dueState,
    required this.expected,
    required this.payments,
    required this.paidTotal,
  });

  final Subscription subscription;
  final TransactionCategory? category;
  final DateTime today;
  final DueState dueState;

  /// Next three projected charges (active only).
  final List<DateTime> expected;

  /// Recorded payments (linked transactions), newest first.
  final List<Transaction> payments;

  /// Sum of [payments].
  final Money paidTotal;
}

final subscriptionDetailProvider = Provider.family<AsyncValue<SubscriptionDetail?>, String>((ref, id) {
  return ref.watch(financeSnapshotProvider).whenData((s) {
    final sub = s.subscriptions.where((x) => x.id == id).firstOrNull;
    if (sub == null) return null;
    final third = sub.frequency.nth(sub.nextDueDate, 2);
    final payments = s.linkedTransactions(sub.id)..sort((a, b) => b.date.compareTo(a.date));
    return SubscriptionDetail(
      subscription: sub,
      category: s.category(sub.categoryId),
      today: s.today,
      dueState: _calc.dueState(sub, s.today),
      expected: _calc.occurrencesIn(sub, DateRange(sub.nextDueDate, third)).take(3).toList(),
      payments: payments,
      paidTotal: Money.sum(payments.map((t) => t.amount)),
    );
  });
});

/// "3 days late", "Due today", "In 5 days", "Paused"; a colour only when
/// it needs attention.
({String label, Color? color}) subscriptionDue(UiColors c, Subscription s, DateTime today) {
  if (!s.isActive) return (label: s.status.label, color: null);
  final days = daysBetween(today, s.nextDueDate);
  if (days < 0) return (label: '${-days} ${-days == 1 ? 'day' : 'days'} late', color: c.negative);
  if (days == 0) return (label: 'Due today', color: c.warning);
  if (days == 1) return (label: 'Tomorrow', color: null);
  if (days <= 30) return (label: 'In $days days', color: null);
  return (label: DateFormats.dayMonth.format(s.nextDueDate), color: null);
}

/// Records the current renewal as paid (review sheet confirms details).
Future<Transaction?> markSubscriptionPaid(BuildContext context, WidgetRef ref, Subscription s) => runAction(
  context,
  ref,
  action: const MarkSubscriptionPaidAction(),
  input: MarkSubscriptionPaidInput(subscriptionId: s.id, cycleDate: s.nextDueDate, method: s.paymentMethod),
  // Stable per cycle: double taps never record twice.
  idempotencyKey: 'sub-paid-${s.id}-${Out.date(s.nextDueDate)}',
  celebrate: true,
  successTitle: '${s.name} marked as paid',
  successSubtitle: 'Next renewal ${DateFormats.dayMonthYear.format(SubscriptionSchedule.nextCycleAfterCurrent(s))}',
);

/// Category mark for a subscription (watches only its category).
class SubscriptionMark extends ConsumerWidget {
  const SubscriptionMark({super.key, required this.categoryId});

  final String categoryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      UiMark(icon: CategoryIcons.of(ref.watch(categoryProvider(categoryId))?.iconKey));
}

/// Label above a non-text form control.
class SubscriptionFieldLabel extends StatelessWidget {
  const SubscriptionFieldLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: Space.x1_5),
    child: Text(text, style: context.text.label),
  );
}
