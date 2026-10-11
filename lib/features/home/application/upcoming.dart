import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/data_providers.dart';
import '../../../core/money/money.dart';
import '../../../core/time/dates.dart';
import '../../../finance/finance_snapshot.dart';

/// What kind of record an upcoming commitment comes from.
enum UpcomingKind {
  loanPayment('EMI'),
  loanReceipt('Repayment due to you'),
  subscription('Subscription');

  const UpcomingKind(this.label);
  final String label;
}

/// A projected (not yet recorded) money movement with a due date.
@immutable
class UpcomingItem {
  const UpcomingItem({
    required this.kind,
    required this.recordId,
    required this.title,
    required this.date,
    required this.amount,
    required this.daysUntil,
  });

  final UpcomingKind kind;

  /// Loan or subscription id.
  final String recordId;
  final String title;
  final DateTime date;
  final Money amount;

  /// Negative when overdue.
  final int daysUntil;

  /// Money expected to come in (lent loans, money to collect).
  bool get isInflow => kind == UpcomingKind.loanReceipt;
  bool get isOverdue => daysUntil < 0;

  @override
  bool operator ==(Object other) =>
      other is UpcomingItem &&
      other.kind == kind &&
      other.recordId == recordId &&
      other.date == date &&
      other.amount == amount &&
      other.daysUntil == daysUntil &&
      other.title == title;

  @override
  int get hashCode => Object.hash(kind, recordId, date, amount, daysUntil);
}

/// Scheduled commitments (EMIs, subscriptions) due within [horizonDays] of
/// today, overdue items included, soonest first. Everything here is a
/// projection: nothing has moved yet.
///
/// Pending payments are left out on purpose: they are never "late", so they
/// are surfaced by age (see `PendingView.isLongPending`) instead of by date.
List<UpcomingItem> upcomingCommitments(FinanceSnapshot s, {int horizonDays = UpcomingWindow.days}) {
  final today = s.today;
  final horizon = DateTime(today.year, today.month, today.day + horizonDays);
  final out = <UpcomingItem>[];

  for (final l in s.loanStates) {
    final next = l.nextDue;
    if (next == null || next.dueDate.isAfter(horizon)) continue;
    out.add(
      UpcomingItem(
        kind: l.loan.isBorrowed ? UpcomingKind.loanPayment : UpcomingKind.loanReceipt,
        recordId: l.loan.id,
        title: l.loan.isBorrowed ? l.loan.name : '${l.loan.counterparty} · ${l.loan.name}',
        date: next.dueDate,
        amount: next.payment,
        daysUntil: daysBetween(today, next.dueDate),
      ),
    );
  }

  for (final sub in s.subscriptions) {
    if (!sub.isActive) continue;
    final due = sub.nextDueDate.dateOnly;
    if (due.isAfter(horizon)) continue;
    final start = due.isBefore(today) ? due : today;
    for (final d in FinanceSnapshot.subscriptionCalc.occurrencesIn(sub, DateRange(start, horizon))) {
      out.add(
        UpcomingItem(
          kind: UpcomingKind.subscription,
          recordId: sub.id,
          title: sub.name,
          date: d,
          amount: sub.amount,
          daysUntil: daysBetween(today, d),
        ),
      );
    }
  }

  out.sort((a, b) {
    final c = a.date.compareTo(b.date);
    return c != 0 ? c : a.title.compareTo(b.title);
  });
  return out;
}

abstract final class UpcomingWindow {
  /// How far ahead the home dashboard looks.
  static const days = 7;
}

/// The upcoming window plus the cash it needs.
@immutable
class UpcomingOverview {
  const UpcomingOverview({required this.items, required this.toArrange, required this.expectedIn});

  /// Soonest first; overdue items lead.
  final List<UpcomingItem> items;

  /// Total going out in the window, overdue included: what to keep ready.
  final Money toArrange;

  /// Total expected to come in over the same window.
  final Money expectedIn;

  int get outflowCount => items.where((i) => !i.isInflow).length;

  @override
  bool operator ==(Object other) =>
      other is UpcomingOverview &&
      listEquals(other.items, items) &&
      other.toArrange == toArrange &&
      other.expectedIn == expectedIn;

  @override
  int get hashCode => Object.hash(Object.hashAll(items), toArrange, expectedIn);
}

UpcomingOverview upcomingOverview(FinanceSnapshot s) {
  final items = upcomingCommitments(s);
  return UpcomingOverview(
    items: items,
    toArrange: Money.sum(items.where((i) => !i.isInflow).map((i) => i.amount)),
    expectedIn: Money.sum(items.where((i) => i.isInflow).map((i) => i.amount)),
  );
}

/// Upcoming commitments for the next [UpcomingWindow.days] days (home dashboard).
final upcomingCommitmentsProvider = Provider<AsyncValue<UpcomingOverview>>(
  (ref) => ref.watch(financeSnapshotProvider).whenData(upcomingOverview),
);
