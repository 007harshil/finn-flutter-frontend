import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../actions/action.dart';
import '../../../app/di/data_providers.dart';
import '../../../core/money/money.dart';
import '../../../core/time/dates.dart';
import '../../../design_system/design_system.dart';
import '../../../finance/finance_snapshot.dart';
import '../../../shared/presentation/action_runner.dart';
import '../../../shared/presentation/category_icons.dart';
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

  Color color(FinnColors c) => switch (this) {
    IncomeImpact.healthy => c.positive,
    IncomeImpact.moderate => c.warning,
    IncomeImpact.high => c.attention,
    IncomeImpact.critical => c.negative,
  };

  IconData get icon => switch (this) {
    IncomeImpact.healthy => LucideIcons.circleCheck,
    IncomeImpact.moderate => LucideIcons.gauge,
    IncomeImpact.high => LucideIcons.triangleAlert,
    IncomeImpact.critical => LucideIcons.triangleAlert,
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

/// "Overdue · 2 days", "Due today", "in 5 days".
({String label, Color color, IconData icon}) subscriptionDueLabel(
  BuildContext context,
  Subscription s,
  DateTime today,
) {
  final c = context.colors;
  if (!s.isActive) {
    return s.status == SubscriptionStatus.paused
        ? (label: 'Paused', color: c.textSecondary, icon: LucideIcons.pause)
        : (label: 'Cancelled', color: c.textSecondary, icon: LucideIcons.circleX);
  }
  final days = daysBetween(today, s.nextDueDate);
  if (days < 0) {
    return (
      label: 'Overdue · ${-days} ${-days == 1 ? 'day' : 'days'}',
      color: c.negative,
      icon: LucideIcons.triangleAlert,
    );
  }
  if (days == 0) return (label: 'Due today', color: c.attention, icon: LucideIcons.bell);
  if (days == 1) return (label: 'Tomorrow', color: c.warning, icon: LucideIcons.clock);
  if (days <= 7) return (label: 'in $days days', color: c.warning, icon: LucideIcons.clock);
  return (label: 'in $days days', color: c.textSecondary, icon: LucideIcons.calendar);
}

class SubscriptionDueChip extends StatelessWidget {
  const SubscriptionDueChip({super.key, required this.subscription, required this.today});

  final Subscription subscription;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final d = subscriptionDueLabel(context, subscription, today);
    return StatusPill(label: d.label, color: d.color, icon: d.icon);
  }
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

/// Category avatar for a subscription (watches only its category).
class SubscriptionAvatar extends ConsumerWidget {
  const SubscriptionAvatar({super.key, required this.categoryId, this.size = 40});

  final String categoryId;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      CategoryAvatar(category: ref.watch(categoryProvider(categoryId)), size: size);
}

/// One subscription row.
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
    final c = context.colors;
    final t = context.text;
    final s = subscription;
    final inactive = !s.isActive;
    final due = subscriptionDueLabel(context, s, today);
    return FinnCard(
      padding: const EdgeInsets.all(Space.x3),
      onTap: onTap,
      semanticLabel: '${s.name}, ${AmountText.spokenLabel(s.amount)} ${s.frequency.label}, ${due.label}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Opacity(
                opacity: inactive ? 0.5 : 1,
                child: SubscriptionAvatar(categoryId: s.categoryId),
              ),
              const SizedBox(width: Space.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.bodyStrong.copyWith(color: inactive ? c.textSecondary : null),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(LucideIcons.repeat, size: 11, color: c.textTertiary),
                        const SizedBox(width: Space.x1),
                        Flexible(
                          child: Text(
                            s.isActive
                                ? '${s.frequency.label} · next ${DateFormats.dayMonth.format(s.nextDueDate)}'
                                : s.frequency.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: t.caption,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Space.x2),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  AmountText(s.amount, style: t.amountMedium.copyWith(color: inactive ? c.textSecondary : null)),
                  const SizedBox(height: Space.x1),
                  StatusPill(label: due.label, color: due.color, icon: due.icon),
                ],
              ),
            ],
          ),
          if (onMarkPaid != null) ...[
            const SizedBox(height: Space.x2_5),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Renewal due ${DateFormats.relativeDay(s.nextDueDate, today).toLowerCase()} — not yet paid',
                    style: t.micro,
                    maxLines: 2,
                  ),
                ),
                const SizedBox(width: Space.x2),
                FinnButton(
                  label: 'Mark paid',
                  icon: LucideIcons.circleCheck,
                  size: FinnButtonSize.sm,
                  variant: FinnButtonVariant.attention,
                  onPressed: onMarkPaid,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
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
