import 'package:flutter/foundation.dart';

import '../../../core/money/money.dart';
import '../../../core/time/dates.dart';
import '../../transactions/domain/transaction.dart';
import 'shared_pending.dart';

export 'shared_pending.dart';

enum PendingDirection {
  /// The user has to pay someone.
  iOwe('I owe', 'To pay'),

  /// Someone has to pay the user.
  owedToMe('I will receive', 'To collect');

  const PendingDirection(this.label, this.shortLabel);
  final String label;
  final String shortLabel;
}

enum PendingKind {
  borrowed('Borrowed money'),
  lent('Lent money'),
  sharedExpense('Shared expense'),
  reimbursement('Reimbursement'),
  other('Other');

  const PendingKind(this.label);
  final String label;
}

/// An obligation between the user and another person or organisation.
/// Creating one never changes cash; only settlements can.
@immutable
class PendingPayment {
  const PendingPayment({
    required this.id,
    required this.counterparty,
    required this.direction,
    required this.kind,
    required this.originalAmount,
    required this.purpose,
    required this.createdDate,
    required this.createdAt,
    required this.updatedAt,
    this.notes,
    this.isCancelled = false,
    this.version = 1,
    this.link,
  });

  final String id;
  final String counterparty;
  final PendingDirection direction;
  final PendingKind kind;
  final Money originalAmount;

  /// Short description, e.g. "Goa trip hotel share".
  final String purpose;
  final DateTime createdDate;
  final String? notes;

  /// Written off / no longer expected. Outstanding becomes zero.
  final bool isCancelled;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int version;

  /// Set when the counterparty is a FiNN user and the item is shared
  /// with them (double entry). Null for private items.
  final PendingLink? link;

  bool get isShared => link != null;

  PendingPayment copyWith({
    String? counterparty,
    PendingKind? kind,
    Money? originalAmount,
    String? purpose,
    DateTime? createdDate,
    String? Function()? notes,
    bool? isCancelled,
    DateTime? updatedAt,
    int? version,
    PendingLink? Function()? link,
  }) =>
      PendingPayment(
        id: id,
        counterparty: counterparty ?? this.counterparty,
        direction: direction,
        kind: kind ?? this.kind,
        originalAmount: originalAmount ?? this.originalAmount,
        purpose: purpose ?? this.purpose,
        createdDate: createdDate ?? this.createdDate,
        notes: notes != null ? notes() : this.notes,
        isCancelled: isCancelled ?? this.isCancelled,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        version: version ?? this.version,
        link: link != null ? link() : this.link,
      );

  @override
  bool operator ==(Object other) => other is PendingPayment && other.id == id && other.version == version;

  @override
  int get hashCode => Object.hash(id, version);
}

/// A full or partial settlement of a [PendingPayment].
@immutable
class PendingSettlement {
  const PendingSettlement({
    required this.id,
    required this.pendingId,
    required this.amount,
    required this.date,
    required this.createdAt,
    this.method,
    this.transactionId,
    this.note,
  });

  final String id;
  final String pendingId;
  final Money amount;
  final DateTime date;
  final PaymentMethod? method;

  /// Linked cash transaction. Null when settled outside tracked cash
  /// (e.g. offset against another debt).
  final String? transactionId;
  final String? note;
  final DateTime createdAt;

  @override
  bool operator ==(Object other) => other is PendingSettlement && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

enum PendingStatus {
  open('Open'),
  partiallySettled('Partially settled'),
  settled('Settled'),
  cancelled('Cancelled');

  const PendingStatus(this.label);
  final String label;

  bool get isActive => this == open || this == partiallySettled;
}

/// Derived view of a pending payment.
@immutable
class PendingView {
  const PendingView({
    required this.payment,
    required this.settlements,
    required this.settled,
    required this.today,
  });

  final PendingPayment payment;

  /// Newest first.
  final List<PendingSettlement> settlements;
  final Money settled;
  final DateTime today;

  Money get outstanding =>
      payment.isCancelled ? Money.zero : Money.max(payment.originalAmount - settled, Money.zero);

  PendingStatus get status {
    if (payment.isCancelled) return PendingStatus.cancelled;
    if (outstanding.isZero) return PendingStatus.settled;
    if (settled.isPositive) return PendingStatus.partiallySettled;
    return PendingStatus.open;
  }

  /// Days since the obligation began. Pending items have no deadline;
  /// age alone tells the user whom to ask (or pay) first.
  int get daysOpen => daysBetween(payment.createdDate, today);

  /// Most recent settlement, if any.
  DateTime? get lastPaymentOn => settlements.isEmpty ? null : settlements.first.date;

  /// Days since the last settlement; null when nothing was settled yet.
  int? get daysSinceLastPayment => lastPaymentOn == null ? null : daysBetween(lastPaymentOn!, today);

  /// Days an item stays open before it is gently surfaced as long pending.
  static const longPendingDays = 21;

  /// Still unsettled more than [longPendingDays] days after it was created.
  bool get isLongPending => status.isActive && daysOpen > longPendingDays;

  int get settledBps => (settled.ratioBps(payment.originalAmount) ?? 0).clamp(0, 10000);

  DateTime? get settledOn => status == PendingStatus.settled && settlements.isNotEmpty
      ? settlements.first.date
      : null;

  @override
  bool operator ==(Object other) =>
      other is PendingView &&
      other.payment == payment &&
      other.settled == settled &&
      other.settlements.length == settlements.length &&
      other.today == today;

  @override
  int get hashCode => Object.hash(payment, settled, settlements.length, today);
}

class PendingCalculator {
  const PendingCalculator();

  PendingView view(PendingPayment p, List<PendingSettlement> all, DateTime today) {
    final s = all.where((x) => x.pendingId == p.id).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    return PendingView(
      payment: p,
      settlements: s,
      settled: Money.sum(s.map((x) => x.amount)),
      today: today.dateOnly,
    );
  }
}
