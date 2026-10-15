import 'package:flutter/foundation.dart';

import '../../../core/money/money.dart';
import '../../../core/time/dates.dart';
import '../../../core/time/frequency.dart';

enum SubscriptionStatus {
  active('Active'),
  paused('Paused'),
  cancelled('Cancelled');

  const SubscriptionStatus(this.label);
  final String label;
}

/// A recurring commitment. Upcoming charges are *projections*; a payment
/// only becomes a transaction through the explicit "mark as paid" action.
@immutable
class Subscription {
  const Subscription({
    required this.id,
    required this.name,
    required this.amount,
    required this.categoryId,
    required this.frequency,
    required this.nextDueDate,
    required this.createdAt,
    required this.updatedAt,
    this.startDate,
    this.status = SubscriptionStatus.active,
    this.autoRenews = true,
    this.accountId,
    this.note,
    this.version = 1,
  });

  final String id;
  final String name;
  final Money amount;
  final String categoryId;
  final Frequency frequency;
  final DateTime nextDueDate;
  final DateTime? startDate;
  final SubscriptionStatus status;

  /// Whether the provider renews automatically (informational).
  final bool autoRenews;
  /// Account it is usually charged to.
  final String? accountId;
  final String? note;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int version;

  bool get isActive => status == SubscriptionStatus.active;

  Money get monthlyEquivalent => frequency.monthlyEquivalent(amount);
  Money get annualized => frequency.annualized(amount);

  Subscription copyWith({
    String? name,
    Money? amount,
    String? categoryId,
    Frequency? frequency,
    DateTime? nextDueDate,
    DateTime? Function()? startDate,
    SubscriptionStatus? status,
    bool? autoRenews,
    String? Function()? accountId,
    String? Function()? note,
    DateTime? updatedAt,
    int? version,
  }) =>
      Subscription(
        id: id,
        name: name ?? this.name,
        amount: amount ?? this.amount,
        categoryId: categoryId ?? this.categoryId,
        frequency: frequency ?? this.frequency,
        nextDueDate: nextDueDate ?? this.nextDueDate,
        startDate: startDate != null ? startDate() : this.startDate,
        status: status ?? this.status,
        autoRenews: autoRenews ?? this.autoRenews,
        accountId: accountId != null ? accountId() : this.accountId,
        note: note != null ? note() : this.note,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        version: version ?? this.version,
      );

  @override
  bool operator ==(Object other) => other is Subscription && other.id == id && other.version == version;

  @override
  int get hashCode => Object.hash(id, version);
}

enum DueState {
  overdue('Overdue'),
  dueToday('Due today'),
  dueSoon('Due soon'),
  upcoming('Upcoming');

  const DueState(this.label);
  final String label;
}

/// Pure projection helpers for subscriptions.
class SubscriptionCalculator {
  const SubscriptionCalculator();

  DueState dueState(Subscription s, DateTime today, {int soonDays = 7}) {
    final d = daysBetween(today, s.nextDueDate);
    if (d < 0) return DueState.overdue;
    if (d == 0) return DueState.dueToday;
    if (d <= soonDays) return DueState.dueSoon;
    return DueState.upcoming;
  }

  /// Expected (unpaid) charge dates for [s] that fall inside [range].
  List<DateTime> occurrencesIn(Subscription s, DateRange range) {
    if (!s.isActive) return const [];
    final result = <DateTime>[];
    var date = s.nextDueDate.dateOnly;
    final anchor = s.nextDueDate.day;
    var guard = 0;
    while (!date.isAfter(range.end) && guard < 500) {
      if (range.contains(date)) result.add(date);
      date = s.frequency.next(date, anchorDay: anchor);
      guard++;
    }
    return result;
  }

  /// Total monthly-equivalent commitment of active subscriptions.
  Money monthlyCommitment(Iterable<Subscription> subs) =>
      Money.sum(subs.where((s) => s.isActive).map((s) => s.monthlyEquivalent));

  Money annualCommitment(Iterable<Subscription> subs) =>
      Money.sum(subs.where((s) => s.isActive).map((s) => s.annualized));
}
