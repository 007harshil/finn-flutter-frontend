import 'dart:math';

import 'package:finn/core/money/money.dart';
import 'package:finn/core/result/result.dart';
import 'package:finn/core/time/frequency.dart';
import 'package:finn/features/loans/domain/loan.dart';
import 'package:finn/features/loans/domain/loan_calculator.dart';
import 'package:flutter_test/flutter_test.dart';

const calc = LoanCalculator();
final today = DateTime(2026, 10, 10);
final stamp = DateTime(2026, 1, 1, 9);

Money rs(int rupees) => Money.rupees(rupees);
Money ps(int paise) => Money.fromPaise(paise);

Loan amortizing({
  String id = 'loan_a',
  Money principal = const Money.rupees(600000),
  int bps = 950,
  int n = 60,
  DateTime? firstDue,
  Frequency frequency = Frequency.monthly,
  PrepaymentStrategy strategy = PrepaymentStrategy.reduceTenure,
  LoanStatus status = LoanStatus.active,
  LoanDirection direction = LoanDirection.borrowed,
}) => Loan(
  id: id,
  name: 'Car loan',
  counterparty: 'HDFC Bank',
  direction: direction,
  structure: LoanStructure.amortizing,
  principal: principal,
  rate: InterestRate(bps),
  startDate: DateTime(2025, 12, 5),
  firstDueDate: firstDue ?? DateTime(2026, 11, 5),
  frequency: frequency,
  tenureInstallments: n,
  prepaymentStrategy: strategy,
  status: status,
  createdAt: stamp,
  updatedAt: stamp,
);

Loan interestOnly({
  String id = 'loan_i',
  Money principal = const Money.rupees(200000),
  int bps = 1200,
  DateTime? firstDue,
  DateTime? maturity,
}) => Loan(
  id: id,
  name: 'Family loan',
  counterparty: 'Ramesh Uncle',
  direction: LoanDirection.borrowed,
  structure: LoanStructure.interestOnly,
  principal: principal,
  rate: InterestRate(bps),
  startDate: DateTime(2026, 10, 1),
  firstDueDate: firstDue ?? DateTime(2026, 11, 1),
  frequency: Frequency.monthly,
  maturityDate: maturity,
  createdAt: stamp,
  updatedAt: stamp,
);

int _pid = 0;
LoanPayment payment(Loan loan, LoanPaymentKind kind, DateTime date, Money interest, Money principal, {int? period}) =>
    LoanPayment(
      id: 'lp_${_pid++}',
      loanId: loan.id,
      kind: kind,
      date: date,
      interestComponent: interest,
      principalComponent: principal,
      periodNumber: period,
      createdAt: date,
    );

/// Payments for the first [count] rows of the original schedule.
List<LoanPayment> payInstallments(Loan loan, int count) {
  final rows = calc.originalSchedule(loan).take(count);
  return [
    for (final r in rows)
      payment(loan, LoanPaymentKind.installment, r.dueDate, r.interest, r.principal, period: r.number),
  ];
}

T ok<T>(Result<T> r) {
  if (r case Err(:final failure)) fail('Expected Ok, got $failure');
  return (r as Ok<T>).value;
}

AppFailure err<T>(Result<T> r) {
  if (r case Ok(:final value)) fail('Expected Err, got $value');
  return (r as Err<T>).failure;
}

void main() {
  group('EMI', () {
    test('₹6,00,000 @ 9.5% p.a. for 60 months = exact annuity rounded UP to the rupee (₹12,602)', () {
      // Exact annuity E = P·r·(1+r)^n / ((1+r)^n − 1), r = 9.5% / 12 = 19/2400,
      // evaluated as an exact rational with BigInt.
      final p = BigInt.from(600000);
      final num = BigInt.from(19);
      final den = BigInt.from(2400);
      final growthNum = (den + num).pow(60);
      final growthDen = den.pow(60);
      // E = P·(num/den)·(gN/gD) / ((gN − gD)/gD) = P·num·gN / (den·(gN − gD))
      final eNum = p * num * growthNum;
      final eDen = den * (growthNum - growthDen);
      final floorRupees = eNum ~/ eDen;
      final isExact = eNum % eDen == BigInt.zero;
      expect(floorRupees, BigInt.from(12601));
      expect(isExact, isFalse);
      final ceilRupees = floorRupees + BigInt.one;

      // Cross-check in floating point.
      const r = 0.095 / 12;
      final g = pow(1 + r, 60);
      expect(600000 * r * g / (g - 1), closeTo(12601.1168, 1e-3));

      final emi = calc.emi(rs(600000), const InterestRate(950), 60, 12);
      expect(emi, Money.rupees(ceilRupees.toInt()));
      expect(emi, rs(12602));
    });

    test('rounded-up EMI repays the loan within the tenure; one rupee less does not', () {
      // Independent characterisation: iterate the exact (unrounded) balance
      // b ← b·(1 + r) − E for 60 periods using rationals with denominator 2400^k.
      BigInt finalBalanceNumerator(int emiRupees) {
        var n = BigInt.from(600000);
        var scale = BigInt.one;
        for (var k = 0; k < 60; k++) {
          scale *= BigInt.from(2400);
          n = n * BigInt.from(2419) - BigInt.from(emiRupees) * scale;
        }
        return n;
      }

      expect(finalBalanceNumerator(12602).isNegative, isTrue);
      expect(finalBalanceNumerator(12601).isNegative, isFalse);
    });

    test('zero-rate EMI is principal / n rounded up to the rupee', () {
      expect(calc.emi(rs(100000), const InterestRate(0), 12, 12), rs(8334));
      expect(calc.emi(rs(120000), const InterestRate(0), 12, 12), rs(10000));
      expect(calc.emi(Money.zero, const InterestRate(950), 12, 12), Money.zero);
      expect(() => calc.emi(rs(1000), const InterestRate(950), 0, 12), throwsArgumentError);
    });

    test('periodic interest = balance × rate ÷ periods, half-up to the paisa', () {
      expect(calc.periodInterest(rs(600000), const InterestRate(950), 12), rs(4750));
      expect(calc.periodInterest(ps(12345), const InterestRate(1000), 12), ps(103)); // 102.875
      expect(calc.periodInterest(ps(12300), const InterestRate(1000), 12), ps(103)); // 102.5 → 103
      expect(calc.periodInterest(rs(100000), const InterestRate(1200), 4), rs(3000));
      expect(calc.periodInterest(rs(100000), const InterestRate(0), 12), Money.zero);
      expect(calc.periodInterest(Money.zero, const InterestRate(950), 12), Money.zero);
    });
  });

  group('amortization schedule', () {
    test('₹6L @ 9.5% × 60: principal sums exactly, ends at zero, final payment ≤ EMI', () {
      final loan = amortizing();
      final rows = calc.originalSchedule(loan);
      final emi = rs(12602);
      expect(rows.length, 60);
      expect(Money.sum(rows.map((r) => r.principal)), loan.principal);
      expect(rows.last.balanceAfter, Money.zero);
      expect(rows.last.isFinal, isTrue);
      expect(rows.where((r) => r.isFinal).length, 1);
      expect(rows.last.payment <= emi, isTrue);
      expect(rows.take(59).every((r) => r.payment == emi), isTrue);

      var balance = loan.principal;
      for (final r in rows) {
        // Interest is computed independently: half-up of balance·950/120000.
        final expected = roundDivBig(
          BigInt.from(balance.paise) * BigInt.from(950),
          BigInt.from(120000),
          RoundingMode.halfUp,
        );
        expect(r.interest.paise, expected.toInt(), reason: 'row ${r.number}');
        expect(r.interest + r.principal, r.payment);
        balance -= r.principal;
        expect(r.balanceAfter, balance);
      }
      expect(rows.first.interest, rs(4750));
      expect(rows.first.principal, rs(7852));
      expect(rows.map((r) => r.number), List.generate(60, (i) => i + 1));
      expect(rows.first.dueDate, DateTime(2026, 11, 5));
      expect(rows[3].dueDate, DateTime(2027, 2, 5));
      expect(rows.last.dueDate, DateTime(2031, 10, 5));
    });

    test('due dates stay anchored to the 31st', () {
      final rows = calc.originalSchedule(amortizing(firstDue: DateTime(2027, 1, 31), n: 4));
      expect(rows.map((r) => r.dueDate), [
        DateTime(2027, 1, 31),
        DateTime(2027, 2, 28),
        DateTime(2027, 3, 31),
        DateTime(2027, 4, 30),
      ]);
    });

    test('invariants hold across many loans', () {
      final rnd = Random(2026);
      for (var i = 0; i < 150; i++) {
        final principal = ps((rnd.nextInt(5000000) + 1000) * 100 + rnd.nextInt(100));
        final bps = rnd.nextInt(2400);
        final n = rnd.nextInt(240) + 1;
        final freq = [Frequency.monthly, Frequency.quarterly, Frequency.yearly][rnd.nextInt(3)];
        final loan = amortizing(principal: principal, bps: bps, n: n, frequency: freq);
        final emi = calc.emi(principal, InterestRate(bps), n, freq.periodsPerYear);
        // Loans whose EMI never repays principal are rejected by validateLoan.
        if (emi <= calc.periodInterest(principal, InterestRate(bps), freq.periodsPerYear)) continue;
        final rows = calc.originalSchedule(loan);
        final label = '$principal @ $bps bps × $n ${freq.name}';
        expect(emi.paise % 100, 0, reason: label);
        expect(Money.sum(rows.map((r) => r.principal)), principal, reason: label);
        expect(rows.last.balanceAfter, Money.zero, reason: label);
        expect(rows.last.payment <= emi, isTrue, reason: label);
        expect(rows.length, lessThanOrEqualTo(n), reason: label);
        expect(rows.every((r) => !r.principal.isNegative && !r.interest.isNegative), isTrue, reason: label);
      }
    });

    test('zero-rate loan: no interest, equal instalments, final instalment absorbs the remainder', () {
      final loan = amortizing(principal: rs(100000), bps: 0, n: 12);
      final rows = calc.originalSchedule(loan);
      expect(rows.length, 12);
      expect(rows.every((r) => r.interest.isZero), isTrue);
      expect(rows.take(11).every((r) => r.payment == rs(8334)), isTrue);
      expect(rows.last.payment, rs(8326));
      expect(Money.sum(rows.map((r) => r.principal)), rs(100000));
      final st = calc.state(loan, const [], today);
      expect(st.projectedInterest, Money.zero);
      expect(st.currentInstallment, rs(8334));
    });
  });

  group('loan state', () {
    test('fresh amortizing loan', () {
      final loan = amortizing();
      final st = calc.state(loan, const [], DateTime(2026, 10, 10, 15));
      expect(st.today, today);
      expect(st.outstanding, loan.principal);
      expect(st.periodsPaid, 0);
      expect(st.currentInstallment, rs(12602));
      expect(st.schedule.length, 60);
      expect(st.remainingInstallments, 60);
      expect(st.nextDue!.number, 1);
      expect(st.daysUntilNextDue, 26);
      expect(st.overdueCount, 0);
      expect(st.projectedEndDate, DateTime(2031, 10, 5));
      expect(st.totalInterestCost, Money.sum(calc.originalSchedule(loan).map((r) => r.interest)));
      expect(st.repaidBps, 0);
      expect(st.warning, isNull);
    });

    test('payments reduce outstanding and advance the schedule', () {
      final loan = amortizing();
      final pays = payInstallments(loan, 3);
      final st = calc.state(loan, pays, today);
      final original = calc.originalSchedule(loan);
      expect(st.periodsPaid, 3);
      expect(st.outstanding, original[2].balanceAfter);
      expect(st.principalRepaid, Money.sum(original.take(3).map((r) => r.principal)));
      expect(st.interestPaid, Money.sum(original.take(3).map((r) => r.interest)));
      expect(st.schedule.length, 57);
      expect(st.schedule.first.number, 4);
      expect(st.schedule.first.dueDate, original[3].dueDate);
      expect(st.currentInstallment, rs(12602));
      // Remaining schedule repays exactly what is outstanding.
      expect(Money.sum(st.schedule.map((r) => r.principal)), st.outstanding);
      expect(st.payments.first.date.isAfter(st.payments.last.date), isTrue, reason: 'newest first');
      // Payments for other loans are ignored.
      final other = calc.state(amortizing(id: 'other'), pays, today);
      expect(other.outstanding, rs(600000));
    });

    test('overdueCount counts unpaid rows due before today (FixedClock)', () {
      final loan = amortizing(firstDue: DateTime(2026, 8, 5));
      final st = calc.state(loan, const [], today);
      // 5 Aug, 5 Sep and 5 Oct are before 10 Oct.
      expect(st.overdueCount, 3);
      expect(st.isOverdue, isTrue);
      expect(st.daysUntilNextDue, -66);
      final paidOne = calc.state(loan, payInstallments(loan, 1), today);
      expect(paidOne.overdueCount, 2);
      final paidAll = calc.state(loan, payInstallments(loan, 3), today);
      expect(paidAll.overdueCount, 0);
      expect(paidAll.nextDue!.dueDate, DateTime(2026, 11, 5));
      // A row due today is not overdue.
      expect(calc.state(loan, payInstallments(loan, 2), DateTime(2026, 10, 5)).overdueCount, 0);
      final closed = calc.state(amortizing(firstDue: DateTime(2026, 8, 5), status: LoanStatus.closed), const [], today);
      expect(closed.overdueCount, 0);
      expect(closed.nextDue, isNull);
    });

    group('prepayment strategies', () {
      Loan withStrategy(PrepaymentStrategy s) => amortizing(firstDue: DateTime(2026, 1, 5), strategy: s);
      List<LoanPayment> history(Loan loan) => [
        ...payInstallments(loan, 3),
        payment(loan, LoanPaymentKind.principal, DateTime(2026, 4, 10), Money.zero, rs(100000)),
      ];

      test('reduceTenure keeps the EMI and finishes earlier', () {
        final loan = withStrategy(PrepaymentStrategy.reduceTenure);
        final st = calc.state(loan, history(loan), today);
        final original = calc.originalSchedule(loan);
        expect(st.outstanding, original[2].balanceAfter - rs(100000));
        expect(st.currentInstallment, rs(12602));
        expect(st.schedule.length, lessThan(57));
        expect(st.schedule.first.number, 4);
        expect(st.schedule.take(st.schedule.length - 1).every((r) => r.payment == rs(12602)), isTrue);
        expect(Money.sum(st.schedule.map((r) => r.principal)), st.outstanding);
        expect(st.schedule.last.balanceAfter, Money.zero);
      });

      test('reduceEmi lowers the EMI and keeps the remaining instalment count', () {
        final loan = withStrategy(PrepaymentStrategy.reduceEmi);
        final st = calc.state(loan, history(loan), today);
        final expectedEmi = calc.emi(st.outstanding, loan.rate, 57, 12);
        expect(st.currentInstallment, expectedEmi);
        expect(st.currentInstallment < rs(12602), isTrue);
        expect(st.schedule.length, 57);
        expect(st.schedule.last.dueDate, DateTime(2030, 12, 5));
        expect(Money.sum(st.schedule.map((r) => r.principal)), st.outstanding);
        expect(st.schedule.last.balanceAfter, Money.zero);
      });

      test('reduceEmi without a prepayment keeps the original EMI', () {
        final loan = withStrategy(PrepaymentStrategy.reduceEmi);
        final st = calc.state(loan, payInstallments(loan, 3), today);
        expect(st.currentInstallment, rs(12602));
        expect(st.schedule.length, 57);
      });

      test('reduceTenure costs less total interest than reduceEmi', () {
        final a = withStrategy(PrepaymentStrategy.reduceTenure);
        final b = withStrategy(PrepaymentStrategy.reduceEmi);
        final sa = calc.state(a, history(a), today);
        final sb = calc.state(b, history(b), today);
        expect(sa.projectedInterest < sb.projectedInterest, isTrue);
      });
    });

    group('interest-only', () {
      test('periodic interest on the outstanding principal, no maturity: next 12 periods', () {
        final loan = interestOnly();
        final st = calc.state(loan, const [], today);
        expect(st.currentInstallment, rs(2000));
        expect(st.schedule.length, 12);
        expect(
          st.schedule.every((r) => r.interest == rs(2000) && r.principal.isZero && r.balanceAfter == rs(200000)),
          isTrue,
        );
        expect(st.schedule.first.dueDate, DateTime(2026, 11, 1));
        expect(st.schedule.last.dueDate, DateTime(2027, 10, 1));
        expect(st.projectedInterest, rs(24000));
        expect(st.remainingInstallments, isNull);
        expect(st.projectedEndDate, isNull);
      });

      test('interest recalculates after a principal prepayment', () {
        final loan = interestOnly();
        final pays = [
          payment(loan, LoanPaymentKind.interest, DateTime(2026, 10, 1), rs(2000), Money.zero, period: 1),
          payment(loan, LoanPaymentKind.principal, DateTime(2026, 10, 5), Money.zero, rs(50000)),
        ];
        final st = calc.state(loan, pays, today);
        expect(st.outstanding, rs(150000));
        expect(st.currentInstallment, rs(1500));
        expect(st.schedule.every((r) => r.interest == rs(1500)), isTrue);
        expect(st.periodsPaid, 1);
        expect(st.schedule.first.number, 2);
        expect(st.schedule.first.dueDate, DateTime(2026, 12, 1));
      });

      test('principal is due with the period that reaches maturity', () {
        final loan = interestOnly(maturity: DateTime(2027, 2, 1));
        final st = calc.state(loan, const [], today);
        expect(st.schedule.length, 4);
        final last = st.schedule.last;
        expect(last.dueDate, DateTime(2027, 2, 1));
        expect(last.isFinal, isTrue);
        expect(last.principal, rs(200000));
        expect(last.payment, rs(202000));
        expect(last.balanceAfter, Money.zero);
        expect(st.projectedEndDate, DateTime(2027, 2, 1));
      });

      test('zero-interest loan has no periodic rows, only the maturity payoff', () {
        final loan = interestOnly(bps: 0, maturity: DateTime(2027, 3, 1));
        final st = calc.state(loan, const [], today);
        expect(st.currentInstallment, Money.zero);
        expect(st.schedule.length, 1);
        expect(st.schedule.single.dueDate, DateTime(2027, 3, 1));
        expect(st.schedule.single.interest, Money.zero);
        expect(st.schedule.single.payment, rs(200000));
        expect(st.schedule.single.number, 5);
        expect(st.projectedInterest, Money.zero);
      });

      test('zero-interest loan without maturity has nothing scheduled', () {
        final loan = interestOnly(bps: 0);
        final st = calc.state(loan, const [], today);
        expect(st.schedule, isEmpty);
        expect(st.nextDue, isNull);
        expect(st.overdueCount, 0);
        // Regression: previewing an interest payment used to throw on nextDue!.
        final f = err(calc.previewPayment(state: st, kind: LoanPaymentKind.interest, amount: rs(100)));
        expect(f.code, FailureCode.validation);
        final p = ok(calc.previewPayment(state: st, kind: LoanPaymentKind.principal, amount: rs(200000)));
        expect(p.closesLoan, isTrue);
      });
    });
  });

  group('previewPayment', () {
    final loan = amortizing();
    final st = calc.state(loan, const [], today);

    test('EMI splits into interest due then principal', () {
      final p = ok(calc.previewPayment(state: st, kind: LoanPaymentKind.installment, amount: rs(12602)));
      expect(p.interestPortion, rs(4750));
      expect(p.principalPortion, rs(7852));
      expect(p.outstandingAfter, rs(600000 - 7852));
      expect(p.periodNumber, 1);
      expect(p.dueDate, DateTime(2026, 11, 5));
      expect(p.includesPrepayment, isFalse);
      expect(p.closesLoan, isFalse);
    });

    test('more than the EMI is flagged as a prepayment', () {
      final p = ok(calc.previewPayment(state: st, kind: LoanPaymentKind.installment, amount: rs(20000)));
      expect(p.principalPortion, rs(15250));
      expect(p.includesPrepayment, isTrue);
    });

    test('exact payoff closes the loan', () {
      final p = ok(calc.previewPayment(state: st, kind: LoanPaymentKind.installment, amount: rs(604750)));
      expect(p.closesLoan, isTrue);
      expect(p.outstandingAfter, Money.zero);
      final principalOnly = ok(calc.previewPayment(state: st, kind: LoanPaymentKind.principal, amount: rs(600000)));
      expect(principalOnly.closesLoan, isTrue);
      expect(principalOnly.interestPortion, Money.zero);
    });

    test('rejects less than the interest due', () {
      final f = err(calc.previewPayment(state: st, kind: LoanPaymentKind.installment, amount: rs(4750) - ps(1)));
      expect(f.code, FailureCode.validation);
      expect(f.fieldErrors.keys, contains('amount'));
      ok(calc.previewPayment(state: st, kind: LoanPaymentKind.installment, amount: rs(4750)));
    });

    test('rejects more than the payoff amount', () {
      final f = err(calc.previewPayment(state: st, kind: LoanPaymentKind.installment, amount: rs(604750) + ps(1)));
      expect(f.fieldErrors.keys, contains('amount'));
      final g = err(calc.previewPayment(state: st, kind: LoanPaymentKind.principal, amount: rs(600000) + ps(1)));
      expect(g.fieldErrors.keys, contains('amount'));
    });

    test('rejects zero, wrong kind and closed loans', () {
      expect(
        err(calc.previewPayment(state: st, kind: LoanPaymentKind.installment, amount: Money.zero)).fieldErrors.keys,
        contains('amount'),
      );
      expect(
        err(calc.previewPayment(state: st, kind: LoanPaymentKind.interest, amount: rs(5000))).code,
        FailureCode.validation,
      );
      final closed = calc.state(amortizing(status: LoanStatus.closed), const [], today);
      expect(closed.isClosed, isTrue);
      expect(
        err(calc.previewPayment(state: closed, kind: LoanPaymentKind.installment, amount: rs(12602))).code,
        FailureCode.validation,
      );
      final repaid = calc.state(loan, [payment(loan, LoanPaymentKind.principal, today, Money.zero, rs(600000))], today);
      expect(repaid.isClosed, isTrue);
      expect(repaid.schedule, isEmpty);
      expect(
        err(calc.previewPayment(state: repaid, kind: LoanPaymentKind.principal, amount: rs(1))).code,
        FailureCode.validation,
      );
    });

    test('interest-only: minimum is the period interest, maximum the payoff', () {
      final io = calc.state(interestOnly(), const [], today);
      expect(
        err(calc.previewPayment(state: io, kind: LoanPaymentKind.interest, amount: rs(1999))).fieldErrors.keys,
        contains('amount'),
      );
      final exact = ok(calc.previewPayment(state: io, kind: LoanPaymentKind.interest, amount: rs(2000)));
      expect(exact.principalPortion, Money.zero);
      expect(exact.includesPrepayment, isFalse);
      final extra = ok(calc.previewPayment(state: io, kind: LoanPaymentKind.interest, amount: rs(52000)));
      expect(extra.principalPortion, rs(50000));
      expect(extra.includesPrepayment, isTrue);
      expect(ok(calc.previewPayment(state: io, kind: LoanPaymentKind.interest, amount: rs(202000))).closesLoan, isTrue);
      expect(
        err(calc.previewPayment(state: io, kind: LoanPaymentKind.interest, amount: rs(202000) + ps(1))).code,
        FailureCode.validation,
      );
      expect(
        err(calc.previewPayment(state: io, kind: LoanPaymentKind.installment, amount: rs(2000))).code,
        FailureCode.validation,
      );
    });
  });

  test('outstandingOn uses payments up to the date', () {
    final loan = amortizing(firstDue: DateTime(2026, 1, 5));
    final pays = payInstallments(loan, 3);
    final rows = calc.originalSchedule(loan);
    expect(calc.outstandingOn(loan, pays, DateTime(2025, 12, 1)), Money.zero);
    expect(calc.outstandingOn(loan, pays, DateTime(2026, 1, 4)), rs(600000));
    expect(calc.outstandingOn(loan, pays, DateTime(2026, 2, 5)), rows[1].balanceAfter);
    expect(calc.outstandingOn(loan, pays, today), rows[2].balanceAfter);
  });

  test('InterestRate parse and label', () {
    expect(InterestRate.tryParse('10.5'), const InterestRate(1050));
    expect(InterestRate.tryParse('9.25%'), const InterestRate(925));
    expect(InterestRate.tryParse('9'), const InterestRate(900));
    expect(InterestRate.tryParse('abc'), isNull);
    expect(InterestRate.tryParse('9.125'), isNull);
    expect(const InterestRate(1050).label, '10.5%');
    expect(const InterestRate(925).label, '9.25%');
    expect(const InterestRate(900).label, '9%');
  });
}
