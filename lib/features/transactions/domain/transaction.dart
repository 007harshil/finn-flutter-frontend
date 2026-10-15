import 'package:flutter/foundation.dart';

import '../../../core/money/money.dart';

enum TransactionType {
  income('Income'),
  expense('Expense');

  const TransactionType(this.label);
  final String label;

  bool get isIncome => this == TransactionType.income;
}

/// Where a transaction came from. Linked transactions are created by a
/// financial operation in another module and can only be changed there,
/// which prevents a settlement or repayment from being double-counted.
enum TransactionOrigin {
  manual('Manual entry'),
  subscription('Subscription payment'),
  loanRepayment('Loan repayment'),
  loanDisbursement('Loan disbursement'),
  pendingSettlement('Pending settlement');

  const TransactionOrigin(this.label);
  final String label;

  bool get isLinked => this != TransactionOrigin.manual;
}

/// A completed movement of cash into or out of the user's money.
///
/// Projections (upcoming subscription charges), obligations (pending
/// payments) and internal allocations (goal contributions) are *not*
/// transactions.
@immutable
class Transaction {
  const Transaction({
    required this.id,
    required this.type,
    required this.amount,
    required this.categoryId,
    required this.date,
    required this.createdAt,
    required this.updatedAt,
    required this.accountId,
    this.channel,
    this.counterparty,
    this.note,
    this.origin = TransactionOrigin.manual,
    this.originRefId,
    this.version = 1,
  });

  final String id;
  final TransactionType type;

  /// Always positive; direction is given by [type].
  final Money amount;
  final String categoryId;

  /// Calendar date the money moved.
  final DateTime date;

  /// The money account this movement hit (see `MoneyAccount`).
  final String accountId;

  /// Optional free-text sub-type: UPI, IMPS, NEFT, Cheque, ATM …
  final String? channel;

  /// Merchant or person, e.g. "Swiggy" or "Priya".
  final String? counterparty;
  final String? note;
  final TransactionOrigin origin;

  /// Id of the record in the originating module (loan, subscription …).
  final String? originRefId;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Optimistic-concurrency version, incremented on every update.
  final int version;

  bool get isIncome => type == TransactionType.income;
  bool get isExpense => type == TransactionType.expense;
  bool get isLinked => origin.isLinked;

  /// Signed cash effect: positive inflow, negative outflow.
  Money get signedAmount => isIncome ? amount : -amount;

  /// Whether this counts as income/spending in analytics and budgets.
  /// Loan disbursements move cash but are neither income nor spending.
  bool get countsInCashFlowAnalytics => origin != TransactionOrigin.loanDisbursement;

  /// Display title: counterparty, else note, else empty.
  String? get displayTitle {
    if (counterparty != null && counterparty!.trim().isNotEmpty) return counterparty;
    if (note != null && note!.trim().isNotEmpty) return note;
    return null;
  }

  Transaction copyWith({
    TransactionType? type,
    Money? amount,
    String? categoryId,
    DateTime? date,
    String? accountId,
    String? Function()? channel,
    String? Function()? counterparty,
    String? Function()? note,
    DateTime? updatedAt,
    int? version,
  }) {
    return Transaction(
      id: id,
      type: type ?? this.type,
      amount: amount ?? this.amount,
      categoryId: categoryId ?? this.categoryId,
      date: date ?? this.date,
      accountId: accountId ?? this.accountId,
      channel: channel != null ? channel() : this.channel,
      counterparty: counterparty != null ? counterparty() : this.counterparty,
      note: note != null ? note() : this.note,
      origin: origin,
      originRefId: originRefId,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      version: version ?? this.version,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Transaction && other.id == id && other.version == version;

  @override
  int get hashCode => Object.hash(id, version);
}
