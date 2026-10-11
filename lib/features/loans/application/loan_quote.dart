import 'package:flutter/foundation.dart';

import '../../../core/money/money.dart';
import '../domain/loan.dart';
import '../domain/loan_calculator.dart';
import 'loan_actions.dart';

const _calc = LoanCalculator();

/// Live estimate of a loan's terms while the form is being filled in.
/// Pure: derived from [LoanCalculator] so widgets never do money maths.
@immutable
class LoanQuote {
  const LoanQuote({
    required this.structure,
    required this.installment,
    this.installments,
    this.totalInterest,
    this.totalPayable,
    this.lastDueDate,
    this.neverRepays = false,
  });

  final LoanStructure structure;

  /// EMI (amortizing) or interest per period (interest-only).
  final Money installment;
  final int? installments;

  /// Interest over the full original schedule (amortizing only).
  final Money? totalInterest;

  /// Principal + total interest (amortizing only).
  final Money? totalPayable;
  final DateTime? lastDueDate;

  /// The instalment never covers the interest (negative amortisation).
  final bool neverRepays;

  /// Returns null while the inputs are incomplete or out of range.
  static LoanQuote? of(LoanInput i) {
    if (!i.principal.isPositive || i.principal > maxLoanQuotePrincipal) return null;
    if (i.rate.bps < 0 || i.rate.bps > 6000) return null;
    final ppy = i.frequency.periodsPerYear;
    if (i.structure == LoanStructure.interestOnly) {
      return LoanQuote(structure: i.structure, installment: _calc.periodInterest(i.principal, i.rate, ppy));
    }
    final n = i.tenureInstallments;
    if (n == null || n < 1 || n > 480) return null;
    final emi = _calc.emi(i.principal, i.rate, n, ppy);
    if (emi <= _calc.periodInterest(i.principal, i.rate, ppy)) {
      return LoanQuote(structure: i.structure, installment: emi, installments: n, neverRepays: true);
    }
    final schedule = _calc.originalSchedule(i.toLoan('quote', i.startDate));
    if (schedule.isEmpty) return null;
    final interest = Money.sum(schedule.map((r) => r.interest));
    return LoanQuote(
      structure: i.structure,
      installment: emi,
      installments: schedule.length,
      totalInterest: interest,
      totalPayable: i.principal + interest,
      lastDueDate: schedule.last.dueDate,
    );
  }
}

/// Upper bound for live quotes (keeps BigInt work bounded while typing).
const maxLoanQuotePrincipal = Money.rupees(100000000000);
