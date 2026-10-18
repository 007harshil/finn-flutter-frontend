import 'package:finn/core/money/money.dart';
import 'package:finn/features/accounts/domain/money_account.dart';
import 'package:finn/features/accounts/domain/transfer.dart';
import 'package:finn/features/goals/domain/goal.dart';
import 'package:finn/features/net_worth/domain/net_worth.dart';
import 'package:finn/finance/ledger.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

MoneyAccount acct(
  String id,
  MoneyAccountKind kind,
  int opening, {
  DateTime? openingDate,
  int order = 0,
  int? limit,
}) =>
    MoneyAccount(
      id: id,
      name: id,
      kind: kind,
      opening: rs(opening),
      openingDate: openingDate ?? d(2026, 1, 1),
      creditLimit: limit == null ? null : rs(limit),
      sortOrder: order,
      createdAt: fxStamp,
      updatedAt: fxStamp,
    );

Transfer xfer(String from, String to, int rupees, DateTime date) => Transfer(
      id: 'trf_${from}_${to}_$rupees',
      fromAccountId: from,
      toAccountId: to,
      amount: rs(rupees),
      date: date,
      createdAt: fxStamp,
      updatedAt: fxStamp,
    );

BalanceSnapshot balanceOf(
  List<MoneyAccount> accounts, {
  List<dynamic> txs = const [],
  List<Transfer> transfers = const [],
}) =>
    const LedgerCalculator().balance(
      profile: null,
      accounts: accounts,
      transfers: transfers,
      transactions: [for (final t in txs) t],
      movements: const [],
      asOf: fxToday,
    );

void main() {
  final sbi = acct('sbi', MoneyAccountKind.debitCard, 10000, order: 1);
  final axis = acct('axis', MoneyAccountKind.bank, 4000, order: 2);
  final cash = acct('cash', MoneyAccountKind.cash, 0, order: 0);
  final card = acct('card', MoneyAccountKind.creditCard, 0, order: 3, limit: 50000);

  test('spec example: SBI 10,000 + Axis 4,000 = 14,000; Rs 1,000 on SBI leaves SBI 9,000 and cash 13,000', () {
    expect(balanceOf([sbi, axis]).cash, rs(14000));
    final b = balanceOf([sbi, axis], txs: [tx(1000, d(2026, 10, 5), accountId: 'sbi')]);
    expect(b.balanceOf('sbi'), rs(9000));
    expect(b.balanceOf('axis'), rs(4000));
    expect(b.cash, rs(13000));
    expect(b.totalOutflow, rs(1000));
  });

  test('credit card spend raises owed and does not change cash', () {
    final b = balanceOf([sbi, card], txs: [tx(2500, d(2026, 10, 5), accountId: 'card')]);
    expect(b.cash, rs(10000));
    expect(b.creditOwed, rs(2500));
    expect(b.balanceOf('card'), rs(2500));
    expect(b.accounts.firstWhere((a) => a.account.id == 'card').limitLeft, rs(47500));
    // A refund lowers what is owed.
    final refunded = balanceOf([sbi, card],
        txs: [tx(2500, d(2026, 10, 5), accountId: 'card'), tx(500, d(2026, 10, 6), accountId: 'card', income: true)]);
    expect(refunded.creditOwed, rs(2000));
  });

  test('transfer between asset accounts leaves cash unchanged', () {
    final b = balanceOf([sbi, cash], transfers: [xfer('sbi', 'cash', 2000, d(2026, 10, 2))]);
    expect(b.balanceOf('sbi'), rs(8000));
    expect(b.balanceOf('cash'), rs(2000));
    expect(b.cash, rs(10000));
    expect(b.totalInflow, Money.zero);
    expect(b.totalOutflow, Money.zero);
  });

  test('paying a card bill lowers cash and owed by the same amount', () {
    final b = balanceOf([sbi, card],
        txs: [tx(3000, d(2026, 10, 1), accountId: 'card')], transfers: [xfer('sbi', 'card', 1000, d(2026, 10, 3))]);
    expect(b.cash, rs(9000));
    expect(b.creditOwed, rs(2000));
  });

  test('income and expenses never leak across accounts', () {
    final b = balanceOf([sbi, axis], txs: [tx(700, d(2026, 10, 1), accountId: 'axis', income: true)]);
    expect(b.balanceOf('sbi'), rs(10000));
    expect(b.balanceOf('axis'), rs(4700));
  });

  test('each account ignores movements before its own opening date', () {
    final late = acct('late', MoneyAccountKind.bank, 5000, openingDate: d(2026, 10, 1));
    final b = balanceOf([sbi, late], txs: [
      tx(100, d(2026, 9, 20), accountId: 'late'), // before its opening: ignored
      tx(100, d(2026, 10, 1), accountId: 'late'), // opening day counts
      tx(100, d(2026, 9, 20), accountId: 'sbi'), // sbi opened in January: counts
    ]);
    expect(b.balanceOf('late'), rs(4900));
    expect(b.balanceOf('sbi'), rs(9900));
  });

  test('future movements are excluded and an overdrawn account goes negative', () {
    final b = balanceOf([axis], txs: [tx(5000, d(2026, 10, 9), accountId: 'axis'), tx(9, d(2026, 10, 11), accountId: 'axis')]);
    expect(b.balanceOf('axis'), rs(-1000));
  });

  test('accounts come back sorted by sortOrder, archived ones still count', () {
    final archived = acct('old', MoneyAccountKind.bank, 300, order: 0).copyWith(isArchived: true);
    final b = balanceOf([card, axis, archived, sbi]);
    expect(b.accounts.map((a) => a.account.id), ['old', 'sbi', 'axis', 'card']);
    expect(b.cash, rs(14300));
  });

  test('net worth subtracts credit card owed', () {
    final b = balanceOf([sbi, card], txs: [tx(2500, d(2026, 10, 5), accountId: 'card')]);
    final nw = const NetWorthCalculator().compute(balance: b, assets: const [], loans: const [], pending: const []);
    expect(nw.cash, rs(10000));
    expect(nw.liabilities, rs(2500));
    expect(nw.netWorth, rs(7500));
  });

  test('without accounts a synthetic Cash account is built from the profile', () {
    final b = const LedgerCalculator().balance(
      profile: fxProfile(opening: 5000),
      transactions: [tx(1000, d(2026, 10, 5))],
      movements: const [],
      asOf: fxToday,
    );
    expect(b.cash, rs(4000));
    expect(b.accounts.single.account.id, cashAccountId);
  });

  group('set aside per account', () {
    BalanceSnapshot snap(List<SavingsMovement> movements, {DateTime? asOf}) => const LedgerCalculator().balance(
          profile: null,
          accounts: [
            acct('sbi', MoneyAccountKind.bank, 10000),
            acct('hdfc', MoneyAccountKind.bank, 4000, order: 1),
            acct('visa', MoneyAccountKind.creditCard, 0, order: 2),
          ],
          transactions: const [],
          movements: movements,
          asOf: asOf ?? fxToday,
        );

    test('earmarked and available per account; the balance never changes', () {
      final b = snap([
        goalMove(3000, d(2026, 10, 5), accountId: 'sbi'),
        efMove(1000, d(2026, 10, 5), accountId: 'sbi'),
        goalMove(500, d(2026, 10, 6), accountId: 'sbi', withdraw: true),
      ]);
      final sbi = b.accounts.firstWhere((a) => a.account.id == 'sbi');
      final hdfc = b.accounts.firstWhere((a) => a.account.id == 'hdfc');
      expect(sbi.balance, rs(10000));
      expect(sbi.earmarked, rs(3500));
      expect(sbi.available, rs(6500));
      expect(hdfc.earmarked, Money.zero);
      expect(hdfc.available, rs(4000));
      expect(b.cash, rs(14000));
      expect(b.earmarked, rs(3500));
      expect(b.available, rs(10500));
      expect(b.earmarkedUnassigned, Money.zero);
    });

    test('movements on no account count overall only; future movements are ignored', () {
      final b = snap([
        efMove(700, d(2026, 10, 5)),
        efMove(900, d(2026, 10, 20), accountId: 'sbi'),
      ]);
      expect(b.earmarkedUnassigned, rs(700));
      expect(b.earmarked, rs(700));
      expect(b.accounts.every((a) => a.earmarked == Money.zero), isTrue);
      expect(b.available, rs(13300));
    });

    test('credit cards hold nothing: available is the amount owed', () {
      final b = snap([goalMove(100, d(2026, 10, 5), accountId: 'visa')]);
      final visa = b.accounts.firstWhere((a) => a.account.id == 'visa');
      expect(visa.earmarked, Money.zero);
      expect(visa.available, visa.balance);
    });

    test('over-reserved: spending can push available below zero', () {
      final b = const LedgerCalculator().balance(
        profile: null,
        accounts: [acct('sbi', MoneyAccountKind.bank, 1000)],
        transactions: [tx(900, d(2026, 10, 6), accountId: 'sbi')],
        movements: [efMove(500, d(2026, 10, 5), accountId: 'sbi')],
        asOf: fxToday,
      );
      expect(b.accounts.single.available, rs(-400));
    });
  });
}
