import 'package:flutter/foundation.dart';

import '../../transactions/domain/transaction.dart';

/// A spending or income category. [iconKey] maps to an icon in the
/// presentation layer (`CategoryIcons`), [colorIndex] to `AccentSwatches`.
@immutable
class TransactionCategory {
  const TransactionCategory({
    required this.id,
    required this.name,
    required this.type,
    required this.iconKey,
    required this.colorIndex,
    this.description = '',
    this.isSystem = false,
    this.isArchived = false,
    this.isEssential = false,
    this.version = 1,
  });

  final String id;
  final String name;
  final TransactionType type;
  final String iconKey;
  final int colorIndex;

  /// What belongs here, e.g. "Restaurants, cafés, food delivery".
  final String description;

  /// System categories back linked operations (EMI, settlements) and
  /// cannot be deleted.
  final bool isSystem;
  final bool isArchived;

  /// Essential spending (rent, groceries, utilities). Used for the
  /// emergency-fund suggestion and lifestyle ratio.
  final bool isEssential;
  final int version;

  TransactionCategory copyWith({
    String? name,
    TransactionType? type,
    String? iconKey,
    int? colorIndex,
    String? description,
    bool? isArchived,
    bool? isEssential,
    int? version,
  }) =>
      TransactionCategory(
        id: id,
        name: name ?? this.name,
        type: type ?? this.type,
        iconKey: iconKey ?? this.iconKey,
        colorIndex: colorIndex ?? this.colorIndex,
        description: description ?? this.description,
        isSystem: isSystem,
        isArchived: isArchived ?? this.isArchived,
        isEssential: isEssential ?? this.isEssential,
        version: version ?? this.version,
      );

  @override
  bool operator ==(Object other) =>
      other is TransactionCategory && other.id == id && other.version == version;

  @override
  int get hashCode => Object.hash(id, version);
}

/// Ids of system categories used by linked operations.
abstract final class SystemCategories {
  static const loanEmi = 'cat_sys_emi';
  static const loanReceived = 'cat_sys_loan_in';
  static const loanGiven = 'cat_sys_loan_out';
  static const loanRepaymentReceived = 'cat_sys_loan_repay_in';
  static const settlementPaid = 'cat_sys_settle_out';
  static const settlementReceived = 'cat_sys_settle_in';
  static const uncategorizedExpense = 'cat_sys_other_out';
  static const uncategorizedIncome = 'cat_sys_other_in';
}
