import 'package:finn/core/money/money.dart';
import 'package:finn/features/loans/domain/loan.dart';
import 'package:finn/features/loans/domain/loan_calculator.dart';
import 'package:finn/features/net_worth/domain/net_worth.dart';
import 'package:finn/features/pending/domain/pending_payment.dart';
import 'package:finn/finance/ledger.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

const calc = NetWorthCalculator();
const loans = LoanCalculator();
const pendingCalc = PendingCalculator();

BalanceSnapshot balance({int opening = 200000, int goals = 0, int ef = 0}) => BalanceSnapshot(
      openingBalance: rs(opening),
      totalInflow: Money.zero,
      totalOutflow: Money.zero,
      earmarkedGoals: rs(goals),
      earmarkedEmergency: rs(ef),
    );

void main() {
  test('cash is counted once: earmarked savings are part of cash, not added again', () {
    final plain = calc.compute(balance: balance(), assets: const [], loans: const [], pending: const []);
    final earmarked = calc.compute(balance: balance(goals: 50000, ef: 30000), assets: const [], loans: const [], pending: const []);
    expect(plain.netWorth, rs(200000));
    expect(earmarked.netWorth, rs(200000));
    expect(earmarked.cash, rs(200000));
    expect(earmarked.lines.first.detail, 'Includes earmarked savings');
    expect(plain.lines.first.detail, isNull);
  });

  test('assets add; borrowed loans are liabilities; lent loans are receivables', () {
    final borrowed = loans.state(emiLoan(id: 'b', principal: 300000), const [], fxToday);
    final lent = loans.state(emiLoan(id: 'l', principal: 40000, direction: LoanDirection.lent), const [], fxToday);
    final nw = calc.compute(
      balance: balance(),
      assets: [asset('Mutual funds', 150000), asset('Gold', 50000)],
      loans: [borrowed, lent],
      pending: const [],
    );
    expect(nw.assets, rs(200000));
    expect(nw.liabilities, rs(300000));
    expect(nw.receivables, rs(40000));
    expect(nw.totalAssets, rs(200000 + 200000 + 40000));
    expect(nw.netWorth, rs(140000));
    final liability = nw.lines.singleWhere((l) => l.group == NetWorthGroup.liabilities);
    expect(liability.recordId, 'b');
    expect(liability.label, 'Car loan · HDFC Bank');
  });

  test('loans use outstanding principal after repayments; repaid loans disappear', () {
    final partly = loans.state(
      emiLoan(id: 'p', principal: 100000),
      [loanPayment('p', d(2026, 5, 1), interestPaise: 0, principalPaise: 2500000)],
      fxToday,
    );
    final repaid = loans.state(
      emiLoan(id: 'r', principal: 10000),
      [loanPayment('r', d(2026, 5, 1), interestPaise: 0, principalPaise: 1000000)],
      fxToday,
    );
    final nw = calc.compute(balance: balance(opening: 0), assets: const [], loans: [partly, repaid], pending: const []);
    expect(nw.liabilities, rs(75000));
    expect(nw.lines.where((l) => l.recordId == 'r'), isEmpty);
  });

  test('pending obligations are summarised per direction on their outstanding amount', () {
    final owe = pendingPayment(id: 'o', amount: 5000);
    final owePartly = pendingPayment(id: 'op', amount: 3000);
    final collect = pendingPayment(id: 'c', amount: 8000, direction: PendingDirection.owedToMe);
    final cancelled = pendingPayment(id: 'x', amount: 9999, cancelled: true);
    final settlements = [settlement('op', 1000, d(2026, 9, 10))];
    final views = [for (final p in [owe, owePartly, collect, cancelled]) pendingCalc.view(p, settlements, fxToday)];
    final nw = calc.compute(balance: balance(opening: 10000), assets: const [], loans: const [], pending: views);
    expect(nw.liabilities, rs(7000));
    expect(nw.receivables, rs(8000));
    expect(nw.lines.where((l) => l.label == 'Pending to pay').single.amount, rs(7000));
    expect(nw.lines.where((l) => l.label == 'Pending to collect').single.amount, rs(8000));
    expect(nw.netWorth, rs(11000));
  });

  test('no pending lines when nothing is outstanding', () {
    final settled = pendingPayment(id: 's', amount: 1000);
    final view = pendingCalc.view(settled, [settlement('s', 1000, d(2026, 9, 10))], fxToday);
    final nw = calc.compute(balance: balance(), assets: const [], loans: const [], pending: [view]);
    expect(nw.lines.length, 1);
  });

  test('negative net worth when debt exceeds everything else', () {
    final nw = calc.compute(
      balance: balance(opening: 10000),
      assets: const [],
      loans: [loans.state(emiLoan(principal: 600000), const [], fxToday)],
      pending: const [],
    );
    expect(nw.netWorth, rs(-590000));
    expect(nw.netWorth.isNegative, isTrue);
  });
}
