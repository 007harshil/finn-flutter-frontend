import 'package:flutter/foundation.dart';

import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/time/dates.dart';
import '../../../finance/finance_snapshot.dart';
import '../../goals/domain/goal.dart';
import '../../loans/domain/loan.dart';
import '../../pending/domain/pending_payment.dart';
import '../../transactions/domain/transaction.dart';

enum TimelineEventKind {
  income('Income received'),
  majorExpense('Major expense'),
  loanPayment('Loan payment'),
  goalContribution('Goal contribution'),
  goalWithdrawal('Goal withdrawal'),
  emergencyContribution('Emergency fund'),
  settlement('Payment settled'),
  subscriptionPaid('Subscription paid');

  const TimelineEventKind(this.label);
  final String label;
}

/// Theme keys mirror the design reference's story colours.
enum StoryTheme { celebration, success, warning, fun, adventurous, growth, neutral, vision, victory, asset, freedom }

/// A meaningful moment in the user's financial story.
@immutable
class TimelineEvent {
  const TimelineEvent({
    required this.id,
    required this.kind,
    required this.date,
    required this.title,
    required this.description,
    required this.emoji,
    required this.theme,
    required this.amount,
    required this.isInflow,
    this.route,
  });

  final String id;
  final TimelineEventKind kind;
  final DateTime date;
  final String title;
  final String description;
  final String emoji;
  final StoryTheme theme;
  final Money amount;

  /// Direction of the money from the user's perspective (for colour/sign).
  final bool isInflow;

  /// Deep link to the underlying record, when there is one.
  final String? route;
}

@immutable
class StoryChapter {
  const StoryChapter({required this.month, required this.name, required this.summary, required this.theme, required this.events});
  final MonthKey month;
  final String name;
  final String summary;
  final StoryTheme theme;

  /// Newest first.
  final List<TimelineEvent> events;
}

/// Builds the monthly financial story from a snapshot. Routes follow
/// `AppRoutes` path conventions but are plain strings to keep the domain
/// free of navigation code.
class TimelineService {
  const TimelineService();

  List<TimelineEvent> eventsFor(FinanceSnapshot s, DateRange range) {
    final out = <TimelineEvent>[];
    String f(Money m) => m.format(decimals: DecimalDisplay.none);

    // Baseline for "major" expenses: 1.4× the average expense of the
    // previous 3 months, and at least ₹5,000.
    final baseStart = DateTime(range.start.year, range.start.month - 3, 1);
    final base = s.transactions.where((t) =>
        t.isExpense && t.origin == TransactionOrigin.manual && !t.date.isBefore(baseStart) && t.date.isBefore(range.start));
    final avg = base.isEmpty ? const Money.rupees(1000) : Money.sum(base.map((t) => t.amount)).scale(1, base.length);
    final threshold = Money.max(avg.scale(14, 10), const Money.rupees(5000));

    for (final t in s.transactions) {
      if (!range.contains(t.date) || t.date.isAfter(s.today)) continue;
      final cat = s.category(t.categoryId)?.name ?? 'General';
      if (t.origin == TransactionOrigin.manual && t.isIncome) {
        final salary = cat.toLowerCase().contains('salary');
        out.add(TimelineEvent(
          id: 'tl_${t.id}', kind: TimelineEventKind.income, date: t.date,
          title: salary ? 'Hard work paid off' : 'Money came in',
          description: '${t.displayTitle ?? cat} · $cat',
          emoji: salary ? '💰' : '💵', theme: StoryTheme.success, amount: t.amount, isInflow: true,
          route: '/transactions/${t.id}',
        ));
      } else if (t.origin == TransactionOrigin.manual && t.isExpense && t.amount >= threshold) {
        final lc = cat.toLowerCase();
        final (emoji, theme, title) = lc.contains('travel')
            ? ('✈️', StoryTheme.adventurous, 'Expanding horizons')
            : lc.contains('shopping')
                ? ('🛍️', StoryTheme.fun, 'Personal upgrade')
                : lc.contains('food')
                    ? ('🍔', StoryTheme.fun, 'Fuelling up')
                    : ('💳', StoryTheme.neutral, 'Notable $cat');
        out.add(TimelineEvent(
          id: 'tl_${t.id}', kind: TimelineEventKind.majorExpense, date: t.date, title: title,
          description: '${t.displayTitle ?? cat} — a larger-than-usual $cat spend.',
          emoji: emoji, theme: theme, amount: t.amount, isInflow: false, route: '/transactions/${t.id}',
        ));
      } else if (t.origin == TransactionOrigin.subscription && t.amount >= const Money.rupees(1000)) {
        out.add(TimelineEvent(
          id: 'tl_${t.id}', kind: TimelineEventKind.subscriptionPaid, date: t.date, title: '${t.counterparty ?? 'Subscription'} renewed',
          description: 'Recurring charge recorded.', emoji: '🔁', theme: StoryTheme.neutral, amount: t.amount, isInflow: false,
          route: t.originRefId == null ? null : '/more/subscriptions/${t.originRefId}',
        ));
      }
    }

    for (final p in s.loanPayments) {
      if (!range.contains(p.date)) continue;
      final loan = s.loans.where((l) => l.id == p.loanId).firstOrNull;
      if (loan == null) continue;
      final big = p.kind == LoanPaymentKind.principal;
      out.add(TimelineEvent(
        id: 'tl_${p.id}', kind: TimelineEventKind.loanPayment, date: p.date,
        title: loan.isBorrowed ? (big ? 'Power move on ${loan.name}' : '${loan.name} instalment') : '${loan.counterparty} repaid you',
        description: big
            ? 'Principal reduced by ${f(p.principalComponent)}.'
            : '${f(p.interestComponent)} interest · ${f(p.principalComponent)} principal.',
        emoji: big ? '💥' : '🏦', theme: big ? StoryTheme.growth : StoryTheme.neutral, amount: p.total,
        isInflow: !loan.isBorrowed, route: '/more/loans/${loan.id}',
      ));
    }

    for (final m in s.savingsMovements) {
      if (!range.contains(m.date)) continue;
      final isGoal = m.bucketType == SavingsBucketType.goal;
      final goal = isGoal ? s.goals.where((g) => g.id == m.bucketId).firstOrNull : null;
      final contribution = m.kind == SavingsMovementKind.contribution;
      out.add(TimelineEvent(
        id: 'tl_${m.id}',
        kind: isGoal
            ? (contribution ? TimelineEventKind.goalContribution : TimelineEventKind.goalWithdrawal)
            : TimelineEventKind.emergencyContribution,
        date: m.date,
        title: isGoal ? (contribution ? 'Closer to ${goal?.name ?? 'a goal'}' : 'Released from ${goal?.name ?? 'a goal'}') : (contribution ? 'Safety net strengthened' : 'Emergency fund used'),
        description: m.note ?? (contribution ? 'Earmarked for later. Still your money.' : 'Moved back to available cash.'),
        emoji: isGoal ? (contribution ? '🔭' : '↩️') : '🛡️',
        theme: contribution ? (isGoal ? StoryTheme.vision : StoryTheme.asset) : StoryTheme.neutral,
        amount: m.amount, isInflow: !contribution,
        route: isGoal ? '/goals/${m.bucketId}' : '/goals/emergency-fund',
      ));
    }

    for (final st in s.settlements) {
      if (!range.contains(st.date)) continue;
      final p = s.pending.where((x) => x.id == st.pendingId).firstOrNull;
      if (p == null) continue;
      final owe = p.direction == PendingDirection.iOwe;
      out.add(TimelineEvent(
        id: 'tl_${st.id}', kind: TimelineEventKind.settlement, date: st.date,
        title: owe ? 'Squared away with ${p.counterparty}' : '${p.counterparty} paid you back',
        description: p.purpose, emoji: '🤝', theme: StoryTheme.growth, amount: st.amount, isInflow: !owe,
        route: '/more/pending/${p.id}',
      ));
    }

    out.sort((a, b) => b.date.compareTo(a.date));
    return out;
  }

  StoryChapter chapter(FinanceSnapshot s, MonthKey month) {
    final events = eventsFor(s, month.range);
    int count(bool Function(TimelineEvent) p) => events.where(p).length;
    final loans = count((e) => e.kind == TimelineEventKind.loanPayment);
    final goals = count((e) => e.kind == TimelineEventKind.goalContribution);
    final incomes = count((e) => e.kind == TimelineEventKind.income);
    final expenses = count((e) => e.kind == TimelineEventKind.majorExpense);
    final (name, summary, theme) = loans > 2
        ? ('The Debt Slayer', 'Steady action against liabilities.', StoryTheme.adventurous)
        : goals > 1
            ? ('The Visionary Path', 'Your future self is thanking you for these choices.', StoryTheme.vision)
            : incomes > expenses
                ? ('The Wealth Spring', 'More flowed in than flowed out.', StoryTheme.success)
                : expenses > incomes * 1.5
                    ? ('The Big Spend', 'Major purchases and lifestyle shifts happened.', StoryTheme.fun)
                    : ('The Steady Stream', 'A balanced chapter in your financial story.', StoryTheme.neutral);
    return StoryChapter(month: month, name: name, summary: summary, theme: theme, events: events);
  }

  /// Months with events plus the current month, newest first.
  List<MonthKey> availableMonths(FinanceSnapshot s) {
    final set = <MonthKey>{s.currentMonth};
    for (final t in s.transactions) {
      set.add(t.date.monthKey);
    }
    final list = set.where((m) => m <= s.currentMonth).toList()..sort((a, b) => b.compareTo(a));
    return list;
  }
}
