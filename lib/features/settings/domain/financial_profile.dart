import 'package:flutter/foundation.dart';

import '../../../core/money/money.dart';

/// The user's starting point. Cash balance = opening balance + all
/// completed transactions on/after [openingDate].
@immutable
class FinancialProfile {
  const FinancialProfile({
    required this.displayName,
    required this.openingBalance,
    required this.openingDate,
    this.monthlyIncomeEstimate,
  });

  final String displayName;

  /// Cash (bank + wallet) the user had when they started tracking.
  final Money openingBalance;
  final DateTime openingDate;

  /// Optional, used only for guidance when there is no income history.
  final Money? monthlyIncomeEstimate;

  FinancialProfile copyWith({
    String? displayName,
    Money? openingBalance,
    DateTime? openingDate,
    Money? Function()? monthlyIncomeEstimate,
  }) =>
      FinancialProfile(
        displayName: displayName ?? this.displayName,
        openingBalance: openingBalance ?? this.openingBalance,
        openingDate: openingDate ?? this.openingDate,
        monthlyIncomeEstimate:
            monthlyIncomeEstimate != null ? monthlyIncomeEstimate() : this.monthlyIncomeEstimate,
      );

  @override
  bool operator ==(Object other) =>
      other is FinancialProfile &&
      other.displayName == displayName &&
      other.openingBalance == openingBalance &&
      other.openingDate == openingDate &&
      other.monthlyIncomeEstimate == monthlyIncomeEstimate;

  @override
  int get hashCode => Object.hash(displayName, openingBalance, openingDate, monthlyIncomeEstimate);
}
