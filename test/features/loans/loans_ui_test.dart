import 'package:finn/actions/action.dart';
import 'package:finn/actions/dispatcher.dart';
import 'package:finn/app/di/action_providers.dart';
import 'package:finn/core/money/money.dart';
import 'package:finn/core/time/frequency.dart';
import 'package:finn/features/loans/application/loan_actions.dart';
import 'package:finn/features/loans/application/loan_quote.dart';
import 'package:finn/features/loans/domain/loan.dart';
import 'package:finn/features/loans/presentation/loan_detail_screen.dart';
import 'package:finn/features/loans/presentation/loan_form_sheet.dart';
import 'package:finn/features/loans/presentation/loan_payment_sheet.dart';
import 'package:finn/features/loans/presentation/loan_ui.dart';
import 'package:finn/features/loans/presentation/loans_screen.dart';
import 'package:finn/features/transactions/domain/transaction.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/test_app.dart';

Future<ActionOutcome<O>> _run<I extends ActionInput, O>(
  ProviderContainer container,
  FinancialAction<I, O> action,
  I input, {
  required String key,
}) async {
  final dispatcher = container.read(actionDispatcherProvider);
  var outcome = await dispatcher.dispatch(action, input, idempotencyKey: key);
  if (outcome is ActionNeedsConfirmation<O>) {
    outcome = await dispatcher.dispatch(
      action,
      input,
      idempotencyKey: key,
      confirmation: ActionConfirmation(outcome.preview.fingerprint),
    );
  }
  return outcome;
}

LoanInput _input({LoanStructure structure = LoanStructure.amortizing, int? tenure = 12}) => LoanInput(
  name: 'Test',
  counterparty: 'Bank',
  direction: LoanDirection.borrowed,
  structure: structure,
  principal: const Money.rupees(100000),
  rate: const InterestRate(1200),
  startDate: DateTime(2026, 1, 1),
  firstDueDate: DateTime(2026, 2, 1),
  frequency: Frequency.monthly,
  tenureInstallments: tenure,
);

void main() {
  late TestEnv env;
  late ProviderContainer container;

  setUp(() async {
    env = await TestEnv.create();
    container = env.container();
  });

  tearDown(() => container.dispose());

  group('LoanQuote', () {
    test('EMI of 1,00,000 at 12% over 12 months rounds up to the rupee', () {
      final q = LoanQuote.of(_input())!;
      expect(q.installment, const Money.rupees(8885));
      expect(q.installments, 12);
      expect(q.totalPayable, const Money.rupees(100000) + q.totalInterest!);
      expect(q.totalInterest!.isPositive, isTrue);
      expect(q.lastDueDate, DateTime(2027, 1, 1));
    });

    test('interest-only quotes the periodic interest', () {
      final q = LoanQuote.of(_input(structure: LoanStructure.interestOnly, tenure: null))!;
      expect(q.installment, const Money.rupees(1000));
      expect(q.totalInterest, isNull);
    });

    test('incomplete inputs give no quote', () {
      expect(LoanQuote.of(_input(tenure: null)), isNull);
      expect(LoanQuote.of(_input(tenure: 0)), isNull);
    });
  });

  test('overview splits borrowed and lent outstanding', () async {
    final o = LoansOverview.of(await env.snapshot());
    expect(o.active, hasLength(3));
    expect(o.lentOutstanding, const Money.rupees(25000)); // 40,000 lent, 15,000 repaid
    expect(o.borrowedOutstanding.isPositive, isTrue);
    expect(o.overdueCount, greaterThanOrEqualTo(1)); // family loan interest left unpaid
  });

  test('repaying the rest of a lent loan closes it and records income once', () async {
    final before = (await env.snapshot()).loan('loan_seed_lent')!;
    final txBefore = (await env.snapshot()).transactions.length;
    final repaymentsBefore = (await env.snapshot())
        .linkedTransactions(before.loan.id)
        .where((t) => t.origin == TransactionOrigin.loanRepayment)
        .length;
    final outcome = await _run(
      container,
      const RecordLoanPaymentAction(),
      LoanPaymentInput(
        loanId: before.loan.id,
        kind: LoanPaymentKind.principal,
        amount: before.outstanding,
        date: testNow,
      ),
      key: 'close-lent',
    );
    expect(outcome, isA<ActionCompleted<LoanPayment>>());
    final snap = await env.snapshot();
    final after = snap.loan('loan_seed_lent')!;
    expect(after.isClosed, isTrue);
    expect(after.loan.status, LoanStatus.closed);
    expect(snap.transactions.length, txBefore + 1);
    final repayments = snap
        .linkedTransactions(before.loan.id)
        .where((t) => t.origin == TransactionOrigin.loanRepayment);
    expect(repayments.length, repaymentsBefore + 1);
    expect(repayments.every((t) => t.type == TransactionType.income), isTrue);
  });

  group('widgets', () {
    Future<void> sized(WidgetTester tester) async {
      tester.view.physicalSize = const Size(400, 900) * tester.view.devicePixelRatio;
      addTearDown(tester.view.resetPhysicalSize);
    }

    testWidgets('loans screen shows summary and loans', (tester) async {
      await sized(tester);
      await env.pumpWidget(tester, const LoansScreen());
      await tester.pumpAndSettle();
      expect(find.text('Loans'), findsOneWidget);
      expect(find.text('You owe'), findsOneWidget);
      expect(find.text('Car loan'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('loan detail shows terms, schedule and payments', (tester) async {
      await sized(tester);
      await env.pumpWidget(tester, const LoanDetailScreen(id: 'loan_seed_car'));
      await tester.pumpAndSettle();
      expect(find.text('Upcoming'), findsOneWidget);
      expect(find.text('Record a payment'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Terms'), 300, scrollable: find.byType(Scrollable).first);
      expect(find.text('Terms'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('payment sheet previews the interest / principal split', (tester) async {
      await sized(tester);
      await env.pumpWidget(tester, const LoanPaymentSheet(loanId: 'loan_seed_car'));
      await tester.pumpAndSettle();
      expect(find.text('TOWARDS INTEREST'), findsOneWidget);
      expect(find.text('TOWARDS PRINCIPAL'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('form sheet: new loan, and terms locked when payments exist', (tester) async {
      await sized(tester);
      await env.pumpWidget(tester, const LoanFormSheet());
      await tester.pumpAndSettle();
      expect(find.text('Add a loan'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await env.pumpWidget(tester, const LoanFormSheet(loanId: 'loan_seed_car'));
      await tester.pumpAndSettle();
      expect(find.text('Edit loan'), findsOneWidget);
      expect(find.textContaining('are locked'), findsOneWidget);
      expect(find.text('ESTIMATE'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
