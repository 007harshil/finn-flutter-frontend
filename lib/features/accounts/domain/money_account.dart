import 'package:flutter/foundation.dart';

import '../../../core/money/money.dart';

/// Id of the account every user starts with (and old data migrates into).
const String cashAccountId = 'acc_cash';

enum MoneyAccountKind {
  cash('Cash', 'banknote'),
  bank('Bank account', 'landmark'),
  debitCard('Debit card', 'creditCard'),
  creditCard('Credit card', 'creditCard'),
  promoCard('Promo / gift card', 'gift'),
  otherCard('Other card', 'creditCard');

  const MoneyAccountKind(this.label, this.iconKey);
  final String label;
  final String iconKey;

  /// Credit cards are tracked as amount owed and never count as money.
  bool get isLiability => this == MoneyAccountKind.creditCard;

  /// Debit, credit, promo and other cards (the kinds that may carry last4).
  bool get isCard =>
      this == MoneyAccountKind.debitCard ||
      this == MoneyAccountKind.creditCard ||
      this == MoneyAccountKind.promoCard ||
      this == MoneyAccountKind.otherCard;
}

/// A place money lives: cash, a bank account or a card. Every transaction
/// and transfer names the account it hit.
@immutable
class MoneyAccount {
  const MoneyAccount({
    required this.id,
    required this.name,
    required this.kind,
    required this.opening,
    required this.openingDate,
    required this.createdAt,
    required this.updatedAt,
    this.institution,
    this.last4,
    this.creditLimit,
    this.isDefault = false,
    this.isArchived = false,
    this.sortOrder = 0,
    this.note,
    this.version = 1,
  });

  final String id;
  final String name;
  final MoneyAccountKind kind;

  /// Asset kinds: money in the account on [openingDate]. Credit card: the
  /// amount owed on [openingDate].
  final Money opening;

  /// The balance is "as of" this date; earlier movements are ignored.
  final DateTime openingDate;
  final String? institution;

  /// Exactly four digits; cards only.
  final String? last4;
  final Money? creditLimit;
  final bool isDefault;
  final bool isArchived;
  final int sortOrder;
  final String? note;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int version;

  bool get isLiability => kind.isLiability;

  /// "SBI debit card ····1234" style subtitle parts.
  String get subtitle {
    final parts = <String>[
      kind.label,
      if (last4 != null) '····$last4',
    ];
    return parts.join(' · ');
  }

  MoneyAccount copyWith({
    String? name,
    MoneyAccountKind? kind,
    Money? opening,
    DateTime? openingDate,
    String? Function()? institution,
    String? Function()? last4,
    Money? Function()? creditLimit,
    bool? isDefault,
    bool? isArchived,
    int? sortOrder,
    String? Function()? note,
    DateTime? updatedAt,
    int? version,
  }) =>
      MoneyAccount(
        id: id,
        name: name ?? this.name,
        kind: kind ?? this.kind,
        opening: opening ?? this.opening,
        openingDate: openingDate ?? this.openingDate,
        institution: institution != null ? institution() : this.institution,
        last4: last4 != null ? last4() : this.last4,
        creditLimit: creditLimit != null ? creditLimit() : this.creditLimit,
        isDefault: isDefault ?? this.isDefault,
        isArchived: isArchived ?? this.isArchived,
        sortOrder: sortOrder ?? this.sortOrder,
        note: note != null ? note() : this.note,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        version: version ?? this.version,
      );

  @override
  bool operator ==(Object other) => other is MoneyAccount && other.id == id && other.version == version;

  @override
  int get hashCode => Object.hash(id, version);
}

/// An account with its computed balance (amount owed for credit cards).
@immutable
class AccountBalance {
  const AccountBalance({required this.account, required this.balance, this.earmarked = Money.zero});

  final MoneyAccount account;

  /// Asset accounts: money in it (may be negative = overdrawn).
  /// Credit cards: amount owed.
  final Money balance;

  /// Savings set aside on this account (goals + emergency fund). Always zero
  /// for credit cards, which cannot hold savings.
  final Money earmarked;

  /// Asset accounts: [balance] minus [earmarked] (may be negative =
  /// over-reserved). Credit cards: the balance owed, unchanged.
  Money get available => isLiability ? balance : balance - earmarked;

  bool get isLiability => account.isLiability;

  /// Credit limit minus owed; null unless a credit card with a limit.
  Money? get limitLeft {
    final limit = account.creditLimit;
    if (limit == null || !isLiability) return null;
    return limit - balance;
  }

  @override
  bool operator ==(Object other) =>
      other is AccountBalance && other.account == account && other.balance == balance && other.earmarked == earmarked;

  @override
  int get hashCode => Object.hash(account, balance, earmarked);
}
