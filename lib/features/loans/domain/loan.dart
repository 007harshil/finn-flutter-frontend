import 'package:flutter/foundation.dart';

import '../../../core/money/money.dart';
import '../../../core/time/frequency.dart';

enum LoanDirection {
  /// The user owes money (liability).
  borrowed('Borrowed', 'I borrowed'),

  /// The user lent money (receivable asset).
  lent('Lent', 'I lent');

  const LoanDirection(this.label, this.phrase);
  final String label;
  final String phrase;
}

enum LoanStructure {
  /// Equated instalments that repay interest and principal (bank loans).
  amortizing('EMI loan', 'Fixed instalments of interest + principal'),

  /// Only periodic interest is paid; principal stays until repaid
  /// (common for family and informal loans).
  interestOnly('Interest-only', 'Periodic interest, principal repaid separately');

  const LoanStructure(this.label, this.description);
  final String label;
  final String description;
}

/// What happens to future instalments after a principal prepayment.
enum PrepaymentStrategy {
  reduceTenure('Reduce tenure', 'Keep the EMI, finish earlier'),
  reduceEmi('Reduce EMI', 'Keep the end date, lower the EMI');

  const PrepaymentStrategy(this.label, this.description);
  final String label;
  final String description;
}

enum LoanStatus { active, closed }

/// Annual interest rate in basis points (1050 = 10.50% p.a.).
extension type const InterestRate(int bps) {
  String get label {
    final whole = bps ~/ 100;
    final frac = bps % 100;
    return frac == 0 ? '$whole%' : '$whole.${frac.toString().padLeft(2, '0').replaceFirst(RegExp(r'0$'), '')}%';
  }

  /// Parses "10.5" / "10.50" / "9" into basis points.
  static InterestRate? tryParse(String input) {
    final m = RegExp(r'^\s*(\d{1,2})(?:\.(\d{1,2}))?\s*%?\s*$').firstMatch(input);
    if (m == null) return null;
    final whole = int.parse(m.group(1)!);
    final frac = int.parse((m.group(2) ?? '0').padRight(2, '0'));
    return InterestRate(whole * 100 + frac);
  }
}

@immutable
class Loan {
  const Loan({
    required this.id,
    required this.name,
    required this.counterparty,
    required this.direction,
    required this.structure,
    required this.principal,
    required this.rate,
    required this.startDate,
    required this.firstDueDate,
    required this.frequency,
    required this.createdAt,
    required this.updatedAt,
    this.tenureInstallments,
    this.maturityDate,
    this.prepaymentStrategy = PrepaymentStrategy.reduceTenure,
    this.status = LoanStatus.active,
    this.disbursementTransactionId,
    this.note,
    this.version = 1,
  });

  final String id;

  /// Label, e.g. "Car loan".
  final String name;

  /// Bank or person, e.g. "HDFC Bank" or "Ramesh Uncle".
  final String counterparty;
  final LoanDirection direction;
  final LoanStructure structure;

  /// Original principal.
  final Money principal;
  final InterestRate rate;

  /// Disbursement date.
  final DateTime startDate;

  /// Due date of the first instalment / interest period.
  final DateTime firstDueDate;
  final Frequency frequency;

  /// Number of instalments (amortizing loans only).
  final int? tenureInstallments;

  /// Optional date the principal is due (interest-only loans).
  final DateTime? maturityDate;
  final PrepaymentStrategy prepaymentStrategy;
  final LoanStatus status;

  /// Set when the disbursement was recorded as a cash movement.
  final String? disbursementTransactionId;
  final String? note;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int version;

  bool get isBorrowed => direction == LoanDirection.borrowed;
  bool get isAmortizing => structure == LoanStructure.amortizing;

  Loan copyWith({
    String? name,
    String? counterparty,
    InterestRate? rate,
    DateTime? firstDueDate,
    int? Function()? tenureInstallments,
    DateTime? Function()? maturityDate,
    PrepaymentStrategy? prepaymentStrategy,
    LoanStatus? status,
    String? Function()? note,
    DateTime? updatedAt,
    int? version,
  }) =>
      Loan(
        id: id,
        name: name ?? this.name,
        counterparty: counterparty ?? this.counterparty,
        direction: direction,
        structure: structure,
        principal: principal,
        rate: rate ?? this.rate,
        startDate: startDate,
        firstDueDate: firstDueDate ?? this.firstDueDate,
        frequency: frequency,
        tenureInstallments: tenureInstallments != null ? tenureInstallments() : this.tenureInstallments,
        maturityDate: maturityDate != null ? maturityDate() : this.maturityDate,
        prepaymentStrategy: prepaymentStrategy ?? this.prepaymentStrategy,
        status: status ?? this.status,
        disbursementTransactionId: disbursementTransactionId,
        note: note != null ? note() : this.note,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        version: version ?? this.version,
      );

  @override
  bool operator ==(Object other) => other is Loan && other.id == id && other.version == version;

  @override
  int get hashCode => Object.hash(id, version);
}

enum LoanPaymentKind {
  /// A scheduled EMI (amortizing loans).
  installment('EMI instalment'),

  /// A periodic interest payment (interest-only loans).
  interest('Interest payment'),

  /// Extra principal repayment / part-prepayment.
  principal('Principal repayment');

  const LoanPaymentKind(this.label);
  final String label;
}

/// A recorded repayment (or, for lent loans, a received repayment).
@immutable
class LoanPayment {
  const LoanPayment({
    required this.id,
    required this.loanId,
    required this.kind,
    required this.date,
    required this.interestComponent,
    required this.principalComponent,
    required this.createdAt,
    this.periodNumber,
    this.transactionId,
    this.note,
  });

  final String id;
  final String loanId;
  final LoanPaymentKind kind;
  final DateTime date;
  final Money interestComponent;
  final Money principalComponent;

  /// Instalment / interest period number this payment settled (1-based).
  final int? periodNumber;

  /// Linked cash transaction, when recorded as a cash movement.
  final String? transactionId;
  final String? note;
  final DateTime createdAt;

  Money get total => interestComponent + principalComponent;

  @override
  bool operator ==(Object other) => other is LoanPayment && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
