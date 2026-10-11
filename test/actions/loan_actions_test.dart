import 'package:finn/actions/action.dart';
import 'package:finn/actions/dispatcher.dart';
import 'package:finn/core/money/money.dart';
import 'package:finn/core/result/result.dart';
import 'package:finn/core/time/frequency.dart';
import 'package:finn/features/categories/domain/category.dart';
import 'package:finn/features/loans/application/loan_actions.dart';
import 'package:finn/features/loans/domain/loan.dart';
import 'package:finn/features/transactions/domain/transaction.dart';
import 'package:flutter_test/flutter_test.dart';

import 'action_harness.dart';

LoanInput carLoan({
  LoanDirection direction = LoanDirection.borrowed,
  bool recordDisbursement = false,
  int principal = 600000,
  int rateBps = 950,
  int? tenure = 60,
  DateTime? start,
  DateTime? firstDue,
  Frequency frequency = Frequency.monthly,
  LoanStructure structure = LoanStructure.amortizing,
  String name = 'Car loan',
}) =>
    LoanInput(
      name: name,
      counterparty: direction == LoanDirection.borrowed ? 'HDFC Bank' : 'Ravi',
      direction: direction,
      structure: structure,
      principal: Money.rupees(principal),
      rate: InterestRate(rateBps),
      startDate: start ?? DateTime(2026, 9, 1),
      firstDueDate: firstDue ?? DateTime(2026, 10, 5),
      frequency: frequency,
      tenureInstallments: tenure,
      recordDisbursement: recordDisbursement,
    );

LoanPaymentInput pay(String loanId, int rupees,
        {LoanPaymentKind kind = LoanPaymentKind.installment, DateTime? date, bool cash = true}) =>
    LoanPaymentInput(
      loanId: loanId,
      kind: kind,
      amount: Money.rupees(rupees),
      date: date ?? DateTime(2026, 10, 5),
      recordCashMovement: cash,
    );

void main() {
  late ActionHarness h;
  setUp(() async => h = await ActionHarness.create());

  group('loans.create', () {
    test('an existing loan is added without touching cash and without a review step', () async {
      final out = await h.dispatcher.dispatch(const CreateLoanAction(), carLoan(), idempotencyKey: 'k');
      final loan = (out as ActionCompleted<Loan>).value;
      final lines = {for (final l in out.preview.lines) l.label: l.value};
      expect(lines['Monthly EMI'], '₹12,602');
      expect(lines['Cash balance'], 'Unchanged (existing loan)');
      expect(loan.disbursementTransactionId, isNull);
      final s = await h.snapshot();
      expect(s.transactions, isEmpty);
      expect(s.balance.cash, harnessOpening);
      expect(s.totalDebt, const Money.rupees(600000));
      expect(s.netWorth.netWorth, harnessOpening - const Money.rupees(600000));
    });

    test('recording a borrowed disbursement adds cash (not income) and needs a review', () async {
      final out = await h.dispatcher.dispatch(const CreateLoanAction(), carLoan(recordDisbursement: true), idempotencyKey: 'k');
      expect(out, isA<ActionNeedsConfirmation<Loan>>());
      final loan = await h.run(const CreateLoanAction(), carLoan(recordDisbursement: true));
      final s = await h.snapshot();
      final tx = s.transactionById[loan.disbursementTransactionId]!;
      expect(tx.type, TransactionType.income);
      expect(tx.origin, TransactionOrigin.loanDisbursement);
      expect(tx.categoryId, SystemCategories.loanReceived);
      expect(tx.originRefId, loan.id);
      expect(s.balance.cash, harnessOpening + const Money.rupees(600000));
      expect(s.monthSummary(s.currentMonth.previous).income, Money.zero, reason: 'a loan is not income');
      expect(s.netWorth.netWorth, harnessOpening, reason: 'cash in = liability');
    });

    test('recording a lent disbursement takes cash out and creates a receivable', () async {
      final loan = await h.run(const CreateLoanAction(), carLoan(direction: LoanDirection.lent, principal: 50000, recordDisbursement: true));
      final s = await h.snapshot();
      expect(s.transactionById[loan.disbursementTransactionId]!.categoryId, SystemCategories.loanGiven);
      expect(s.balance.cash, harnessOpening - const Money.rupees(50000));
      expect(s.netWorth.receivables, const Money.rupees(50000));
      expect(s.netWorth.netWorth, harnessOpening);
    });

    test('validation', () async {
      Future<Iterable<String>> fields(LoanInput i) async => (await h.reject(const CreateLoanAction(), i)).fieldErrors.keys;
      expect(await fields(carLoan(principal: 0)), ['principal']);
      expect(await fields(carLoan(rateBps: 6001)), ['rate']);
      expect(await fields(carLoan(frequency: Frequency.weekly)), ['frequency']);
      expect(await fields(carLoan(firstDue: DateTime(2026, 8, 31))), ['firstDueDate']);
      expect(await fields(carLoan(tenure: 0)), ['tenureInstallments']);
      expect(await fields(carLoan(tenure: 481)), ['tenureInstallments']);
      expect(await fields(carLoan(tenure: null)), ['tenureInstallments']);
      expect(await fields(carLoan(name: ' ')), ['name']);
      expect(
          await fields(carLoan(recordDisbursement: true, start: DateTime(2026, 10, 20), firstDue: DateTime(2026, 11, 20))),
          ['startDate']);
    });

    test('interest-only loans need no tenure', () async {
      final loan = await h.run(const CreateLoanAction(),
          carLoan(structure: LoanStructure.interestOnly, tenure: null, principal: 100000, rateBps: 1200));
      expect(loan.tenureInstallments, isNull);
      expect((await h.snapshot()).loan(loan.id)!.nextDue!.payment, const Money.rupees(1000));
    });
  });

  group('loans.recordPayment', () {
    late Loan loan;
    setUp(() async => loan = await h.run(const CreateLoanAction(), carLoan()));

    test('an EMI pays interest due first, the rest reduces principal, with a linked expense', () async {
      final out = await h.dispatcher.dispatch(const RecordLoanPaymentAction(), pay(loan.id, 12602), idempotencyKey: 'p');
      final preview = (out as ActionNeedsConfirmation).preview;
      final lines = {for (final l in preview.lines) l.label: l.value};
      expect(lines['Towards interest'], '₹4,750');
      expect(lines['Towards principal'], '₹7,852');

      final p = await h.run(const RecordLoanPaymentAction(), pay(loan.id, 12602));
      expect(p.interestComponent, const Money.rupees(4750));
      expect(p.principalComponent, const Money.rupees(7852));
      expect(p.periodNumber, 1);
      final s = await h.snapshot();
      final tx = s.transactionById[p.transactionId]!;
      expect(tx.origin, TransactionOrigin.loanRepayment);
      expect(tx.categoryId, SystemCategories.loanEmi);
      expect(tx.amount, const Money.rupees(12602));
      expect(s.loan(loan.id)!.outstanding, const Money.rupees(600000 - 7852));
      expect(s.loan(loan.id)!.nextDue!.number, 2);
      expect(s.balance.cash, harnessOpening - const Money.rupees(12602));
    });

    test('without a cash movement only the loan changes', () async {
      final p = await h.run(const RecordLoanPaymentAction(), pay(loan.id, 12602, cash: false));
      expect(p.transactionId, isNull);
      final s = await h.snapshot();
      expect(s.transactions, isEmpty);
      expect(s.loan(loan.id)!.outstanding, const Money.rupees(592148));
    });

    test('a repayment received on a lent loan is income-like cash in', () async {
      final lent = await h.run(const CreateLoanAction(), carLoan(direction: LoanDirection.lent, principal: 12000, rateBps: 0, tenure: 12));
      final p = await h.run(const RecordLoanPaymentAction(), pay(lent.id, 1000));
      final tx = (await h.snapshot()).transactionById[p.transactionId]!;
      expect(tx.type, TransactionType.income);
      expect(tx.categoryId, SystemCategories.loanRepaymentReceived);
    });

    test('paying off the outstanding principal closes the loan', () async {
      final small = await h.run(const CreateLoanAction(), carLoan(principal: 10000, rateBps: 0, tenure: 2));
      final out = await h.dispatcher.dispatch(const RecordLoanPaymentAction(),
          pay(small.id, 10000, kind: LoanPaymentKind.principal), idempotencyKey: 'x');
      expect((out as ActionNeedsConfirmation).preview.warnings, contains('This payment closes the loan.'));
      await h.run(const RecordLoanPaymentAction(), pay(small.id, 10000, kind: LoanPaymentKind.principal));
      final st = (await h.snapshot()).loan(small.id)!;
      expect(st.loan.status, LoanStatus.closed);
      expect(st.loan.version, 2);
      expect(st.isClosed, isTrue);
      final again = await h.reject(const RecordLoanPaymentAction(), pay(small.id, 1, kind: LoanPaymentKind.principal));
      expect(again.code, FailureCode.validation);
    });

    test('rejects future dates, dates before the start, too little and too much', () async {
      Future<AppFailure> r(LoanPaymentInput i) => h.reject(const RecordLoanPaymentAction(), i);
      expect((await r(pay(loan.id, 12602, date: DateTime(2026, 10, 11)))).fieldErrors.keys, ['date']);
      expect((await r(pay(loan.id, 12602, date: DateTime(2026, 8, 31)))).fieldErrors.keys, ['date']);
      expect((await r(pay(loan.id, 4000))).message, contains('interest due'));
      expect((await r(pay(loan.id, 700000))).message, contains('payoff'));
      expect((await r(pay(loan.id, 1, kind: LoanPaymentKind.interest))).code, FailureCode.validation);
      expect((await r(pay('nope', 1))).code, FailureCode.notFound);
      expect((await h.snapshot()).loanPayments, isEmpty);
    });

    test('an approval is stale once another payment was recorded', () async {
      final asked = await h.dispatcher.dispatch(const RecordLoanPaymentAction(),
          pay(loan.id, 20000, kind: LoanPaymentKind.principal), idempotencyKey: 'p');
      final fp = (asked as ActionNeedsConfirmation).preview.fingerprint;
      await h.run(const RecordLoanPaymentAction(), pay(loan.id, 12602));
      final out = await h.dispatcher.dispatch(const RecordLoanPaymentAction(),
          pay(loan.id, 20000, kind: LoanPaymentKind.principal),
          idempotencyKey: 'p', confirmation: ActionConfirmation(fp));
      expect(out, isA<ActionNeedsConfirmation>());
      expect((await h.snapshot()).loanPayments.length, 1);
    });
  });

  group('loans.update and loans.delete', () {
    late Loan loan;
    setUp(() async => loan = await h.run(const CreateLoanAction(), carLoan(recordDisbursement: true)));

    test('terms can change until the first payment; then only descriptive fields', () async {
      final changed = await h.run(const UpdateLoanAction(),
          UpdateLoanInput(id: loan.id, expectedVersion: 1, data: carLoan(rateBps: 900, recordDisbursement: true)));
      expect(changed.version, 2);
      expect(changed.rate, const InterestRate(900));
      expect(changed.disbursementTransactionId, loan.disbursementTransactionId);
      await h.run(const RecordLoanPaymentAction(), pay(loan.id, (await h.snapshot()).loan(loan.id)!.nextDue!.payment.rupeePart));

      final locked = await h.reject(const UpdateLoanAction(),
          UpdateLoanInput(id: loan.id, expectedVersion: 2, data: carLoan(rateBps: 800)));
      expect(locked.code, FailureCode.notPermitted);
      final renamed = await h.run(const UpdateLoanAction(),
          UpdateLoanInput(id: loan.id, expectedVersion: 2, data: carLoan(rateBps: 900, name: 'Swift loan')));
      expect(renamed.name, 'Swift loan');
      final stale = await h.reject(const UpdateLoanAction(),
          UpdateLoanInput(id: loan.id, expectedVersion: 2, data: carLoan(rateBps: 900, name: 'Again')));
      expect(stale.code, FailureCode.staleData);
    });

    test('deleting a loan without payments also removes its disbursement', () async {
      await h.run(const DeleteLoanAction(), LoanIdInput(id: loan.id));
      final s = await h.snapshot();
      expect(s.loans, isEmpty);
      expect(s.transactions, isEmpty);
      expect(s.balance.cash, harnessOpening);
    });

    test('a loan with payments is kept for history', () async {
      await h.run(const RecordLoanPaymentAction(), pay(loan.id, 12602));
      expect((await h.reject(const DeleteLoanAction(), LoanIdInput(id: loan.id))).code, FailureCode.notPermitted);
    });
  });
}
