import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../actions/action.dart';
import '../../../app/di/data_providers.dart';
import '../../../core/money/money.dart';
import '../../../core/time/dates.dart';
import '../../../kit/kit.dart';
import '../../../finance/finance_snapshot.dart';
import '../../../shared/presentation/action_runner.dart';
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

  /// Only the worrying levels carry colour.
  Color? color(LedgerColors c) => switch (this) {
    IncomeImpact.healthy || IncomeImpact.moderate => null,
    IncomeImpact.high => c.amber,
    IncomeImpact.critical => c.red,
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

/// Days until [s] is next charged; negative when overdue.
int subscriptionDaysUntil(Subscription s, DateTime today) => daysBetween(today, s.nextDueDate);

/// Renewal that needs a look: overdue, due today or due within three days.
bool subscriptionIsDueSoon(Subscription s, DateTime today) => s.isActive && subscriptionDaysUntil(s, today) <= 3;

/// "2 days overdue", "Due today", "Due tomorrow", "Due in 3 days", else the
/// date. Red when overdue, amber when close, otherwise no colour.
({String label, Color? color}) subscriptionNextCharge(BuildContext context, Subscription s, DateTime today) {
  final c = context.ink;
  final days = subscriptionDaysUntil(s, today);
  if (days < 0) return (label: '${-days} ${-days == 1 ? 'day' : 'days'} overdue', color: c.red);
  if (days == 0) return (label: 'Due today', color: c.amber);
  if (days == 1) return (label: 'Due tomorrow', color: c.amber);
  if (days <= 3) return (label: 'Due in $days days', color: c.amber);
  return (label: 'Next ${DateFormats.dayMonth.format(s.nextDueDate)}', color: null);
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
class SubscriptionAvatar extends ConsumerWidget {
  const SubscriptionAvatar({super.key, required this.categoryId, this.size = 40});

  final String categoryId;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      CategoryMark(category: ref.watch(categoryProvider(categoryId)), size: size);
}

/// One subscription row: name, cycle and next charge, amount. Overdue or
/// due-today renewals carry a small "Mark paid".
class SubscriptionTile extends StatelessWidget {
  const SubscriptionTile({
    super.key,
    required this.subscription,
    required this.today,
    required this.onTap,
    this.onMarkPaid,
  });

  final Subscription subscription;
  final DateTime today;
  final VoidCallback onTap;
  final VoidCallback? onMarkPaid;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final t = context.type;
    final s = subscription;
    final inactive = !s.isActive;
    final next = inactive ? null : subscriptionNextCharge(context, s, today);
    final subtitle = next == null ? s.frequency.label : '${s.frequency.label}, ${next.label.toLowerCaseFirst()}';
    final pay = onMarkPaid;
    return LedgerRow(
      title: s.name,
      leading: SubscriptionAvatar(categoryId: s.categoryId),
      subtitle: subtitle,
      subtitleColor: next?.color,
      trailing: AmountText(s.amount, style: t.figure.copyWith(color: inactive ? c.inkSoft : null)),
      below: pay == null
          ? null
          : Align(
              alignment: Alignment.centerRight,
              child: LedgerButton(
                label: 'Mark paid',
                icon: LucideIcons.circleCheck,
                variant: LedgerButtonVariant.secondary,
                small: true,
                onPressed: pay,
              ),
            ),
      onTap: onTap,
      semanticLabel: '${s.name}, ${AmountText.spokenLabel(s.amount)} ${s.frequency.label}, ${next?.label ?? s.status.label}',
    );
  }
}

extension on String {
  String toLowerCaseFirst() => isEmpty ? this : '${this[0].toLowerCase()}${substring(1)}';
}

/// Label above a non-text form control.
class SubscriptionFieldLabel extends StatelessWidget {
  const SubscriptionFieldLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: Sp.sm),
    child: Text(text, style: context.type.label),
  );
}
