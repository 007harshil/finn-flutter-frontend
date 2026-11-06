import 'package:finn/core/money/money.dart';
import 'package:finn/core/result/result.dart';
import 'package:finn/data/dto/dtos.dart';
import 'package:finn/data/mock/seed_data.dart';
import 'package:finn/features/accounts/application/account_actions.dart';
import 'package:finn/features/accounts/domain/money_account.dart';
import 'package:finn/features/pending/application/pending_actions.dart';
import 'package:finn/features/pending/domain/pending_payment.dart';
import 'package:finn/features/transactions/application/transaction_actions.dart';
import 'package:finn/features/transactions/domain/transaction.dart';
import 'package:flutter_test/flutter_test.dart';

import 'action_harness.dart';

TransactionInput _expense(int rupees, {List<AccountLeg> splits = const [], String? accountId}) => TransactionInput(
      type: TransactionType.expense,
      amount: Money.rupees(rupees),
      categoryId: SeedCategoryIds.food,
      date: DateTime(2026, 10, 9),
      accountId: accountId,
      splits: splits,
    );

void main() {
  late ActionHarness h;
  late MoneyAccount card;

  setUp(() async {
    h = await ActionHarness.create();
    await h.run(const SetAccountBalanceAction(), SetAccountBalanceInput(id: cashAccountId, balance: const Money.rupees(2000)));
    card = await h.run(
      const CreateAccountAction(),
      AccountInput(name: 'Debit card', kind: MoneyAccountKind.debitCard, openingBalance: const Money.rupees(4000)),
    );
  });

  Future<Money> bal(String id) async => (await h.snapshot()).balance.balanceOf(id)!;

  test('one account cannot pay more than it holds; the error suggests splitting', () async {
    final f = await h.reject(const CreateTransactionAction(), _expense(5400));
    expect(f.code, FailureCode.insufficientFunds);
    expect(f.message, contains('Split the payment across accounts.'));
  });

  test('5,400 paid as 4,000 from the debit card and 1,400 from cash is one transaction', () async {
    final tx = await h.run(
      const CreateTransactionAction(),
      _expense(5400, splits: [AccountLeg(card.id, const Money.rupees(4000)), const AccountLeg(cashAccountId, Money.rupees(1400))]),
    );
    expect(tx.isSplit, isTrue);
    expect(tx.accountId, card.id);
    expect(tx.amount, const Money.rupees(5400));
    final s = await h.snapshot();
    expect(s.transactions.where((t) => t.amount == const Money.rupees(5400)), hasLength(1));
    expect(await bal(card.id), Money.zero);
    expect(await bal(cashAccountId), const Money.rupees(600));
    expect(tx.amountOn(cashAccountId), const Money.rupees(1400));

    // Survives storage.
    final back = TransactionDto.fromJson(TransactionDto.toJson(tx));
    expect(back.splits, tx.splits);
  });

  test('parts must add up, use different accounts, and each stay within its account', () async {
    final sum = await h.reject(
      const CreateTransactionAction(),
      _expense(5400, splits: [AccountLeg(card.id, const Money.rupees(3000)), const AccountLeg(cashAccountId, Money.rupees(1400))]),
    );
    expect(sum.fieldErrors['splits'], contains('add up to'));
    final twice = await h.reject(
      const CreateTransactionAction(),
      _expense(2000, splits: [AccountLeg(card.id, const Money.rupees(1000)), AccountLeg(card.id, const Money.rupees(1000))]),
    );
    expect(twice.fieldErrors, contains('splits'));
    final over = await h.reject(
      const CreateTransactionAction(),
      _expense(5400, splits: [AccountLeg(card.id, const Money.rupees(2400)), const AccountLeg(cashAccountId, Money.rupees(3000))]),
    );
    expect(over.code, FailureCode.insufficientFunds);
  });

  test('a full settlement of 25,000 with 21,000 in cash is refused, and works when split', () async {
    await h.run(const SetAccountBalanceAction(), SetAccountBalanceInput(id: cashAccountId, balance: const Money.rupees(21000)));
    final p = await h.run(
      const CreatePendingAction(),
      PendingInput(
        counterparty: 'Ravi',
        direction: PendingDirection.iOwe,
        kind: PendingKind.borrowed,
        amount: const Money.rupees(25000),
        purpose: 'Rent',
        createdDate: DateTime(2026, 10, 1),
      ),
    );
    final f = await h.reject(
      const SettlePendingAction(),
      SettlePendingInput(pendingId: p.id, amount: const Money.rupees(25000), date: DateTime(2026, 10, 9)),
    );
    expect(f.code, FailureCode.insufficientFunds);
    expect(await bal(cashAccountId), const Money.rupees(21000));

    final st = await h.run(
      const SettlePendingAction(),
      SettlePendingInput(
        pendingId: p.id,
        amount: const Money.rupees(25000),
        date: DateTime(2026, 10, 9),
        splits: [const AccountLeg(cashAccountId, Money.rupees(21000)), AccountLeg(card.id, const Money.rupees(4000))],
      ),
    );
    final s = await h.snapshot();
    expect(s.transactionById[st.transactionId]!.isSplit, isTrue);
    expect(await bal(cashAccountId), Money.zero);
    expect(await bal(card.id), Money.zero);
    expect(s.pendingView(p.id)!.outstanding, Money.zero);
  });

  test('deleting an account that a split touches removes the whole entry', () async {
    final tx = await h.run(
      const CreateTransactionAction(),
      _expense(5400, splits: [AccountLeg(card.id, const Money.rupees(4000)), const AccountLeg(cashAccountId, Money.rupees(1400))]),
    );
    await h.run(const DeleteAccountAction(), AccountIdInput(id: card.id));
    final s = await h.snapshot();
    expect(s.transactionById[tx.id], isNull);
    expect(await bal(cashAccountId), const Money.rupees(2000));
  });
}
