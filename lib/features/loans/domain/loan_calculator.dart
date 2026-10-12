import 'package:flutter/foundation.dart';

import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/result/result.dart';
import '../../../core/time/dates.dart';
import 'loan.dart';

/// One row of a repayment schedule (projected, not yet paid).
@immutable
class ScheduleRow {
  const ScheduleRow({
    required this.number,
    required this.dueDate,
    required this.payment,
    required this.interest,
    required this.principal,
    required this.balanceAfter,
    this.isFinal = false,
  });

  final int number;
  final DateTime dueDate;
  final Money payment;
  final Money interest;
  final Money principal;
  final Money balanceAfter;
  final bool isFinal;
}

/// Complete derived state of a loan at a given date.
@immutable
class LoanState {
  const LoanState({
    required this.loan,
    required this.payments,
    required this.outstanding,
    required this.principalRepaid,
    required this.interestPaid,
    required this.periodsPaid,
    required this.currentInstallment,
    required this.schedule,
    required this.projectedInterest,
    required this.today,
    this.warning,
  });

  final Loan loan;

  /// Recorded payments, newest first.
  final List<LoanPayment> payments;
  final Money outstanding;
  final Money principalRepaid;
  final Money interestPaid;

  /// Instalments (amortizing) or interest periods (interest-only) paid.
  final int periodsPaid;

  /// Current EMI (amortizing) or per-period interest (interest-only).
  final Money currentInstallment;

  /// Remaining projected schedule (interest-only: next 12 periods).
  final List<ScheduleRow> schedule;

  /// Interest still expected over [schedule].
  final Money projectedInterest;
  final DateTime today;

  /// Explains a condition such as negative amortisation.
  final String? warning;

  bool get isClosed => outstanding.isZero || loan.status == LoanStatus.closed;

  ScheduleRow? get nextDue => isClosed || schedule.isEmpty ? null : schedule.first;

  /// Unpaid rows whose due date is before today.
  int get overdueCount => isClosed ? 0 : schedule.where((r) => r.dueDate.isBefore(today)).length;

  bool get isOverdue => overdueCount > 0;

  int? get daysUntilNextDue => nextDue == null ? null : daysBetween(today, nextDue!.dueDate);

  /// Interest paid plus interest still expected.
  Money get totalInterestCost => interestPaid + projectedInterest;

  int get repaidBps => (principalRepaid.ratioBps(loan.principal) ?? 0).clamp(0, 10000);

  int? get remainingInstallments => loan.isAmortizing ? schedule.length : null;

  DateTime? get projectedEndDate =>
      loan.isAmortizing ? (schedule.isEmpty ? null : schedule.last.dueDate) : loan.maturityDate;

  @override
  bool operator ==(Object other) =>
      other is LoanState &&
      other.loan == loan &&
      other.payments.length == payments.length &&
      other.outstanding == outstanding &&
      other.today == today;

  @override
  int get hashCode => Object.hash(loan, payments.length, outstanding, today);
}

/// How a proposed payment will be applied.
@immutable
class LoanPaymentPreview {
  const LoanPaymentPreview({
    required this.kind,
    required this.amount,
    required this.interestPortion,
    required this.principalPortion,
    required this.outstandingBefore,
    required this.outstandingAfter,
    required this.periodNumber,
    required this.dueDate,
    required this.closesLoan,
    required this.includesPrepayment,
  });

  final LoanPaymentKind kind;
  final Money amount;
  final Money interestPortion;
  final Money principalPortion;
  final Money outstandingBefore;
  final Money outstandingAfter;
  final int? periodNumber;
  final DateTime? dueDate;
  final bool closesLoan;

  /// The amount exceeds the scheduled instalment; the excess reduces principal.
  final bool includesPrepayment;
}

/// Pure loan mathematics. Deterministic, integer-only (paise), unit-tested.
///
/// Policies (see docs/FINANCIAL_MODEL.md):
/// * Periodic interest = outstanding × annual rate ÷ periods per year,
///   rounded half-up to the paisa. No daily accrual.
/// * EMI = standard annuity formula computed exactly with integers, then
///   rounded **up** to the next whole rupee. The final instalment absorbs
///   the difference so the balance reaches exactly zero.
/// * Payments apply to interest due first, then principal.
class LoanCalculator {
  const LoanCalculator();

  static const int _maxRows = 1200;

  /// Interest for one period on [balance].
  Money periodInterest(Money balance, InterestRate rate, int periodsPerYear) {
    if (rate.bps == 0 || balance.paise <= 0) return Money.zero;
    return Money.fromPaise(
      roundDivBig(
        BigInt.from(balance.paise) * BigInt.from(rate.bps),
        BigInt.from(10000 * periodsPerYear),
        RoundingMode.halfUp,
      ).toInt(),
    );
  }

  /// Equated instalment for [principal] over [installments] periods.
  Money emi(Money principal, InterestRate rate, int installments, int periodsPerYear) {
    if (installments <= 0) throw ArgumentError.value(installments, 'installments');
    if (principal.paise <= 0) return Money.zero;
    if (rate.bps == 0) {
      return Money.fromPaise(roundDiv(principal.paise, installments, RoundingMode.up))
          .roundToRupee(mode: RoundingMode.up);
    }
    final d = BigInt.from(10000 * periodsPerYear);
    final r = BigInt.from(rate.bps);
    final growth = (d + r).pow(installments);
    final base = d.pow(installments);
    final numerator = BigInt.from(principal.paise) * r * growth;
    final denominator = d * (growth - base);
    final exactPaise = roundDivBig(numerator, denominator, RoundingMode.up);
    return Money.fromPaise(exactPaise.toInt()).roundToRupee(mode: RoundingMode.up);
  }

  /// Projects instalments from [balance] using a fixed [installment].
  List<ScheduleRow> projectAmortizing({
    required Money balance,
    required InterestRate rate,
    required Money installment,
    required int periodsPerYear,
    required int firstNumber,
    required DateTime Function(int number) dueDateOf,
    int? maxRows,
  }) {
    final rows = <ScheduleRow>[];
    var b = balance;
    var n = firstNumber;
    final limit = maxRows ?? _maxRows;
    while (b.isPositive && rows.length < limit) {
      final interest = periodInterest(b, rate, periodsPerYear);
      var principalPart = installment - interest;
      if (!principalPart.isPositive) break; // negative amortisation guard
      var payment = installment;
      var isFinal = false;
      if (principalPart >= b) {
        principalPart = b;
        payment = b + interest;
        isFinal = true;
      }
      b = b - principalPart;
      rows.add(
        ScheduleRow(
          number: n,
          dueDate: dueDateOf(n),
          payment: payment,
          interest: interest,
          principal: principalPart,
          balanceAfter: b,
          isFinal: isFinal || b.isZero,
        ),
      );
      n++;
    }
    return rows;
  }

  /// Full original schedule for a new amortizing loan (no payments yet).
  List<ScheduleRow> originalSchedule(Loan loan) {
    assert(loan.isAmortizing, 'amortizing only');
    final n = loan.tenureInstallments ?? 1;
    final ppy = loan.frequency.periodsPerYear;
    return projectAmortizing(
      balance: loan.principal,
      rate: loan.rate,
      installment: emi(loan.principal, loan.rate, n, ppy),
      periodsPerYear: ppy,
      firstNumber: 1,
      dueDateOf: (k) => loan.frequency.nth(loan.firstDueDate, k - 1),
    );
  }

  LoanState state(Loan loan, List<LoanPayment> allPayments, DateTime today) {
    final payments = allPayments.where((p) => p.loanId == loan.id).toList()
      ..sort((a, b) {
        final c = b.date.compareTo(a.date);
        return c != 0 ? c : b.createdAt.compareTo(a.createdAt);
      });
    final principalRepaid = Money.sum(payments.map((p) => p.principalComponent));
    final interestPaid = Money.sum(payments.map((p) => p.interestComponent));
    final outstanding = Money.max(loan.principal - principalRepaid, Money.zero);
    final ppy = loan.frequency.periodsPerYear;
    final t = today.dateOnly;

    if (loan.isAmortizing) {
      final tenure = loan.tenureInstallments ?? 1;
      final paid = payments.where((p) => p.kind == LoanPaymentKind.installment).length;
      final originalEmi = emi(loan.principal, loan.rate, tenure, ppy);
      // A prepayment happened if more principal was repaid than the original
      // schedule would have repaid after the same number of instalments.
      final scheduledPrincipal = Money.sum(
        projectAmortizing(
          balance: loan.principal,
          rate: loan.rate,
          installment: originalEmi,
          periodsPerYear: ppy,
          firstNumber: 1,
          dueDateOf: (k) => loan.firstDueDate,
          maxRows: paid,
        ).map((r) => r.principal),
      );
      final hasPrepayment = principalRepaid > scheduledPrincipal;
      var installment = originalEmi;
      if (hasPrepayment && loan.prepaymentStrategy == PrepaymentStrategy.reduceEmi) {
        final remaining = (tenure - paid).clamp(1, tenure);
        installment = emi(outstanding, loan.rate, remaining, ppy);
      }
      final schedule = projectAmortizing(
        balance: outstanding,
        rate: loan.rate,
        installment: installment,
        periodsPerYear: ppy,
        firstNumber: paid + 1,
        dueDateOf: (k) => loan.frequency.nth(loan.firstDueDate, k - 1),
      );
      String? warning;
      if (outstanding.isPositive && schedule.isEmpty) {
        warning = 'The instalment does not cover the interest due. Review the rate and tenure.';
      }
      return LoanState(
        loan: loan,
        payments: payments,
        outstanding: outstanding,
        principalRepaid: principalRepaid,
        interestPaid: interestPaid,
        periodsPaid: paid,
        currentInstallment: installment,
        schedule: schedule,
        projectedInterest: Money.sum(schedule.map((r) => r.interest)),
        today: t,
        warning: warning,
      );
    }

    // Interest-only.
    final paid = payments.where((p) => p.kind == LoanPaymentKind.interest).length;
    final interest = periodInterest(outstanding, loan.rate, ppy);
    final schedule = <ScheduleRow>[];
    if (outstanding.isPositive) {
      for (var i = 0; i < (interest.isZero ? 600 : 12) && schedule.length < 12; i++) {
        final number = paid + 1 + i;
        final due = loan.frequency.nth(loan.firstDueDate, number - 1);
        final atMaturity = loan.maturityDate != null && !due.isBefore(loan.maturityDate!.dateOnly);
        // Interest-free loans have nothing due until maturity.
        if (interest.isZero && !atMaturity) continue;
        schedule.add(
          ScheduleRow(
            number: number,
            dueDate: due,
            payment: atMaturity ? interest + outstanding : interest,
            interest: interest,
            principal: atMaturity ? outstanding : Money.zero,
            balanceAfter: atMaturity ? Money.zero : outstanding,
            isFinal: atMaturity,
          ),
        );
        if (atMaturity) break;
      }
    }
    return LoanState(
      loan: loan,
      payments: payments,
      outstanding: outstanding,
      principalRepaid: principalRepaid,
      interestPaid: interestPaid,
      periodsPaid: paid,
      currentInstallment: interest,
      schedule: schedule,
      projectedInterest: Money.sum(schedule.map((r) => r.interest)),
      today: t,
    );
  }

  /// Validates and splits a proposed payment.
  Result<LoanPaymentPreview> previewPayment({
    required LoanState state,
    required LoanPaymentKind kind,
    required Money amount,
  }) {
    if (!amount.isPositive) {
      return const Result.err(
        AppFailure.validation(
          'Enter an amount greater than zero.',
          fields: {'amount': 'Enter an amount greater than zero.'},
        ),
      );
    }
    if (state.isClosed) {
      return const Result.err(AppFailure(FailureCode.validation, 'This loan is already fully repaid.'));
    }
    final loan = state.loan;
    final outstanding = state.outstanding;

    if (kind == LoanPaymentKind.principal) {
      if (amount > outstanding) {
        return Result.err(
          AppFailure.validation(
            'Principal repayment cannot exceed the outstanding ${_fmt(outstanding)}.',
            fields: {'amount': 'Maximum ${_fmt(outstanding)}'},
          ),
        );
      }
      final after = outstanding - amount;
      return Result.ok(
        LoanPaymentPreview(
          kind: kind,
          amount: amount,
          interestPortion: Money.zero,
          principalPortion: amount,
          outstandingBefore: outstanding,
          outstandingAfter: after,
          periodNumber: null,
          dueDate: null,
          closesLoan: after.isZero,
          includesPrepayment: true,
        ),
      );
    }

    final expectedKind = loan.isAmortizing ? LoanPaymentKind.installment : LoanPaymentKind.interest;
    if (kind != expectedKind) {
      return Result.err(
        AppFailure.validation('${kind.label} is not applicable to a ${loan.structure.label.toLowerCase()}.'),
      );
    }
    final row = state.nextDue;
    if (row == null) {
      // E.g. an interest-free loan with no maturity date, or an instalment
      // that no longer covers the interest: nothing is scheduled.
      return const Result.err(
        AppFailure.validation('Nothing is scheduled on this loan right now. Record a principal repayment instead.'),
      );
    }
    final interestDue = row.interest;
    if (amount < interestDue) {
      return Result.err(
        AppFailure.validation(
          'The payment must at least cover the interest due of ${_fmt(interestDue)}.',
          fields: {'amount': 'Minimum ${_fmt(interestDue)}'},
        ),
      );
    }
    final payoff = interestDue + outstanding;
    if (amount > payoff) {
      return Result.err(
        AppFailure.validation(
          'This is more than the full payoff amount of ${_fmt(payoff)}.',
          fields: {'amount': 'Maximum ${_fmt(payoff)}'},
        ),
      );
    }
    final principalPortion = amount - interestDue;
    final after = outstanding - principalPortion;
    return Result.ok(
      LoanPaymentPreview(
        kind: kind,
        amount: amount,
        interestPortion: interestDue,
        principalPortion: principalPortion,
        outstandingBefore: outstanding,
        outstandingAfter: after,
        periodNumber: row.number,
        dueDate: row.dueDate,
        closesLoan: after.isZero,
        includesPrepayment: amount > row.payment,
      ),
    );
  }

  /// Outstanding principal (signed by direction is the caller's concern) at
  /// the end of [date], from recorded payments.
  Money outstandingOn(Loan loan, List<LoanPayment> payments, DateTime date) {
    if (date.isBefore(loan.startDate.dateOnly)) return Money.zero;
    final repaid = Money.sum(
      payments
          .where((p) => p.loanId == loan.id && !p.date.dateOnly.isAfter(date.dateOnly))
          .map((p) => p.principalComponent),
    );
    return Money.max(loan.principal - repaid, Money.zero);
  }

  static String _fmt(Money m) => MoneyFormatter.format(m);
}
