import 'dart:convert';

import 'package:finn/core/money/money.dart';
import 'package:finn/core/persistence/persistence_driver.dart';
import 'package:finn/core/result/result.dart';
import 'package:finn/data/local/local_data_store.dart';
import 'package:finn/data/mock/seed_data.dart';
import 'package:finn/features/accounts/application/account_actions.dart';
import 'package:finn/features/accounts/application/transfer_actions.dart';
import 'package:finn/features/accounts/domain/money_account.dart';
import 'package:finn/features/accounts/domain/transfer.dart';
import 'package:finn/features/transactions/application/transaction_actions.dart';
import 'package:finn/features/transactions/domain/transaction.dart';
import 'package:finn/finance/ledger.dart';
import 'package:flutter_test/flutter_test.dart';

import 'action_harness.dart';

AccountInput newAccount(
  String name,
  MoneyAccountKind kind, {
  int opening = 0,
  String? last4,
  int? limit,
  bool? isDefault,
  DateTime? openingDate,
}) =>
    AccountInput(
      name: name,
      kind: kind,
      openingBalance: Money.rupees(opening),
      last4: last4,
      creditLimit: limit == null ? null : Money.rupees(limit),
      isDefault: isDefault,
      openingDate: openingDate,
    );

TransactionInput spend(int rupees, {String? accountId, DateTime? date, String? channel}) => TransactionInput(
      type: TransactionType.expense,
      amount: Money.rupees(rupees),
      categoryId: SeedCategoryIds.food,
      date: date ?? DateTime(2026, 10, 9),
      accountId: accountId,
      channel: channel,
    );

void main() {
  late ActionHarness h;
  setUp(() async => h = await ActionHarness.create());

  group('accounts.create', () {
    test('bootstrap has a default Cash account holding the opening balance', () async {
      final s = await h.snapshot();
      expect(s.accounts.single.id, cashAccountId);
      expect(s.defaultAccount!.id, cashAccountId);
      expect(s.balance.cash, harnessOpening);
    });

    test('adds an account that contributes to cash; the first default stays', () async {
      final sbi = await h.run(const CreateAccountAction(),
          newAccount('SBI', MoneyAccountKind.debitCard, opening: 10000, last4: '4821'));
      expect(sbi.id, 'acc_1');
      expect(sbi.isDefault, isFalse);
      expect(sbi.openingDate, DateTime(2026, 10, 10));
      expect(sbi.sortOrder, 1);
      final s = await h.snapshot();
      expect(s.defaultAccount!.id, cashAccountId);
      expect(s.balance.cash, harnessOpening + const Money.rupees(10000));
    });

    test('isDefault moves the default; credit cards never count as cash', () async {
      await h.run(const CreateAccountAction(), newAccount('HDFC', MoneyAccountKind.creditCard, opening: 3000, limit: 100000, isDefault: true));
      final s = await h.snapshot();
      expect(s.defaultAccount!.name, 'HDFC');
      expect(s.accounts.where((a) => a.isDefault), hasLength(1));
      expect(s.balance.cash, harnessOpening);
      expect(s.balance.creditOwed, const Money.rupees(3000));
      expect(s.netWorth.netWorth, harnessOpening - const Money.rupees(3000));
    });

    test('validation', () async {
      Future<Iterable<String>> fields(AccountInput i) async => (await h.reject(const CreateAccountAction(), i)).fieldErrors.keys;
      expect(await fields(newAccount('  ', MoneyAccountKind.bank)), ['name']);
      expect(await fields(newAccount('x' * 41, MoneyAccountKind.bank)), ['name']);
      expect(await fields(newAccount('A', MoneyAccountKind.bank, last4: '1234')), ['last4']);
      expect(await fields(newAccount('A', MoneyAccountKind.debitCard, last4: '12')), ['last4']);
      expect(await fields(newAccount('A', MoneyAccountKind.debitCard, limit: 5)), ['creditLimit']);
      expect(await fields(newAccount('A', MoneyAccountKind.bank, opening: -1)), ['openingBalance']);
      expect(await fields(newAccount('A', MoneyAccountKind.bank, openingDate: DateTime(2026, 10, 11))), ['openingDate']);
    });

    test('a duplicate name and kind only warns', () async {
      final p = await h.dispatcher.preview(const CreateAccountAction(), newAccount('cash', MoneyAccountKind.cash));
      expect(p.valueOrNull!.warnings, isNotEmpty);
    });
  });

  group('accounts.update / setBalance', () {
    late MoneyAccount sbi;
    setUp(() async => sbi = await h.run(const CreateAccountAction(), newAccount('SBI', MoneyAccountKind.bank, opening: 10000)));

    test('update changes fields and version; stale versions are rejected', () async {
      final input = UpdateAccountInput(
          id: sbi.id, version: 1, data: newAccount('SBI Savings', MoneyAccountKind.bank, opening: 12000));
      final u = await h.run(const UpdateAccountAction(), input);
      expect(u.name, 'SBI Savings');
      expect(u.version, 2);
      final f = await h.reject(const UpdateAccountAction(), input);
      expect(f.code, FailureCode.staleData);
    });

    test('kind may switch to a credit card only while it has no movements', () async {
      await h.run(const CreateAccountAction(), newAccount('Spare', MoneyAccountKind.bank));
      await h.run(const UpdateAccountAction(),
          UpdateAccountInput(id: 'acc_2', data: newAccount('Spare', MoneyAccountKind.creditCard)));
      await h.run(const CreateTransactionAction(), spend(100, accountId: sbi.id));
      final f = await h.reject(const UpdateAccountAction(),
          UpdateAccountInput(id: sbi.id, data: newAccount('SBI', MoneyAccountKind.creditCard)));
      expect(f.fieldErrors.keys, ['kind']);
    });

    test('setBalance corrects the balance shown today and keeps transactions', () async {
      await h.run(const CreateTransactionAction(), spend(1000, accountId: sbi.id, date: DateTime(2026, 10, 10)));
      expect((await h.snapshot()).balance.balanceOf(sbi.id), const Money.rupees(9000));
      final out = await h.run(const SetAccountBalanceAction(), SetAccountBalanceInput(id: sbi.id, balance: const Money.rupees(7500)));
      expect(out.version, 2);
      final s = await h.snapshot();
      expect(s.balance.balanceOf(sbi.id), const Money.rupees(7500));
      expect(s.transactions, hasLength(1));
    });

    test('setBalance on a credit card sets the amount owed', () async {
      final card = await h.run(const CreateAccountAction(), newAccount('Card', MoneyAccountKind.creditCard));
      await h.run(const CreateTransactionAction(), spend(400, accountId: card.id, date: DateTime(2026, 10, 10)));
      await h.run(const SetAccountBalanceAction(), SetAccountBalanceInput(id: card.id, balance: const Money.rupees(1000)));
      expect((await h.snapshot()).balance.balanceOf(card.id), const Money.rupees(1000));
    });
  });

  group('accounts.setDefault / archive / delete', () {
    late MoneyAccount sbi;
    setUp(() async => sbi = await h.run(const CreateAccountAction(), newAccount('SBI', MoneyAccountKind.bank)));

    test('setDefault unsets the previous default', () async {
      await h.run(const SetDefaultAccountAction(), AccountIdInput(id: sbi.id));
      final s = await h.snapshot();
      expect(s.accounts.where((a) => a.isDefault).map((a) => a.id), [sbi.id]);
    });

    test('cannot archive the default or the last active account', () async {
      final f = await h.reject(const ArchiveAccountAction(), const ArchiveAccountInput(id: cashAccountId, archived: true));
      expect(f.code, FailureCode.validation);
      await h.run(const SetDefaultAccountAction(), AccountIdInput(id: sbi.id));
      await h.run(const ArchiveAccountAction(), const ArchiveAccountInput(id: cashAccountId, archived: true));
      final last = await h.reject(const ArchiveAccountAction(), ArchiveAccountInput(id: sbi.id, archived: true));
      expect(last.code, FailureCode.validation);
      // Archived accounts keep counting towards cash and can be restored.
      expect((await h.snapshot()).balance.cash, harnessOpening);
      await h.run(const ArchiveAccountAction(), const ArchiveAccountInput(id: cashAccountId, archived: false));
      expect((await h.snapshot()).activeAccounts, hasLength(2));
    });

    test('delete is blocked while anything references the account, then allowed', () async {
      await h.run(const CreateTransactionAction(), spend(50, accountId: sbi.id));
      final blocked = await h.reject(const DeleteAccountAction(), AccountIdInput(id: sbi.id));
      expect(blocked.message, contains('Archive'));

      final spare = await h.run(const CreateAccountAction(), newAccount('Spare', MoneyAccountKind.bank));
      await h.run(const CreateTransferAction(),
          TransferInput(fromAccountId: sbi.id, toAccountId: spare.id, amount: const Money.rupees(1), date: DateTime(2026, 10, 9)));
      final viaTransfer = await h.reject(const DeleteAccountAction(), AccountIdInput(id: spare.id));
      expect(viaTransfer.code, FailureCode.validation);

      final other = await h.run(const CreateAccountAction(), newAccount('Unused', MoneyAccountKind.bank));
      await h.run(const DeleteAccountAction(), AccountIdInput(id: other.id));
      expect((await h.snapshot()).account(other.id), isNull);
    });

    test('the last account cannot be deleted; deleting the default hands the default on', () async {
      await h.run(const DeleteAccountAction(), AccountIdInput(id: sbi.id));
      final f = await h.reject(const DeleteAccountAction(), const AccountIdInput(id: cashAccountId));
      expect(f.code, FailureCode.validation);
      // Cash is the default and unreferenced: deleting it hands the default on.
      final extra = await h.run(const CreateAccountAction(), newAccount('Extra', MoneyAccountKind.bank));
      await h.run(const DeleteAccountAction(), const AccountIdInput(id: cashAccountId));
      final s = await h.snapshot();
      expect(s.accounts.single.id, extra.id);
      expect(s.defaultAccount!.id, extra.id);
    });
  });

  group('transactions on accounts', () {
    late MoneyAccount sbi;
    setUp(() async => sbi = await h.run(const CreateAccountAction(), newAccount('SBI', MoneyAccountKind.bank, opening: 10000)));

    test('an omitted account resolves to the default; channel is trimmed', () async {
      final t = await h.run(const CreateTransactionAction(), spend(100, channel: '  UPI '));
      expect(t.accountId, cashAccountId);
      expect(t.channel, 'UPI');
      final blank = await h.run(const CreateTransactionAction(), spend(100, channel: '   '));
      expect(blank.channel, isNull);
    });

    test('the account must exist and not be archived; channel is capped at 30', () async {
      final unknown = await h.reject(const CreateTransactionAction(), spend(100, accountId: 'acc_nope'));
      expect(unknown.fieldErrors.keys, ['accountId']);
      await h.run(const ArchiveAccountAction(), ArchiveAccountInput(id: sbi.id, archived: true));
      final archived = await h.reject(const CreateTransactionAction(), spend(100, accountId: sbi.id));
      expect(archived.fieldErrors.keys, ['accountId']);
      final long = await h.reject(const CreateTransactionAction(), spend(100, channel: 'x' * 31));
      expect(long.fieldErrors.keys, ['channel']);
    });

    test('editing keeps an archived account on an old transaction', () async {
      final t = await h.run(const CreateTransactionAction(), spend(100, accountId: sbi.id));
      await h.run(const ArchiveAccountAction(), ArchiveAccountInput(id: sbi.id, archived: true));
      final u = await h.run(const UpdateTransactionAction(),
          UpdateTransactionInput(id: t.id, expectedVersion: 1, data: spend(120, accountId: sbi.id)));
      expect(u.amount, const Money.rupees(120));
      expect(u.accountId, sbi.id);
    });

    test('a transaction dated before an account opened moves that account\'s opening date back', () async {
      await h.run(const CreateTransactionAction(), spend(100, accountId: sbi.id, date: DateTime(2026, 9, 1)));
      final s = await h.snapshot();
      expect(s.account(sbi.id)!.openingDate, DateTime(2026, 9, 1));
      expect(s.account(cashAccountId)!.openingDate, DateTime(2026, 1, 1), reason: 'other accounts untouched');
      expect(s.balance.balanceOf(sbi.id), const Money.rupees(9900));
    });
  });

  group('transfers', () {
    late MoneyAccount sbi;
    setUp(() async => sbi = await h.run(const CreateAccountAction(), newAccount('SBI', MoneyAccountKind.bank, opening: 10000)));

    TransferInput atm(int rupees, {String? to, DateTime? date}) => TransferInput(
          fromAccountId: sbi.id,
          toAccountId: to ?? cashAccountId,
          amount: Money.rupees(rupees),
          date: date ?? DateTime(2026, 10, 9),
          channel: 'ATM',
        );

    test('SBI to Cash moves money without changing cash, income or spending', () async {
      final t = await h.run(const CreateTransferAction(), atm(2000));
      expect(t.id, 'trf_1');
      final s = await h.snapshot();
      expect(s.balance.balanceOf(sbi.id), const Money.rupees(8000));
      expect(s.balance.balanceOf(cashAccountId), harnessOpening + const Money.rupees(2000));
      expect(s.balance.cash, harnessOpening + const Money.rupees(10000));
      expect(s.transactions, isEmpty);
    });

    test('paying a card bill lowers the card\'s owed amount', () async {
      final card = await h.run(const CreateAccountAction(), newAccount('Card', MoneyAccountKind.creditCard, opening: 5000));
      await h.run(const CreateTransferAction(), atm(2000, to: card.id));
      final s = await h.snapshot();
      expect(s.balance.balanceOf(card.id), const Money.rupees(3000));
      expect(s.balance.creditOwed, const Money.rupees(3000));
      expect(s.balance.cash, harnessOpening + const Money.rupees(8000));
    });

    test('validation: different accounts, active accounts, amount, date', () async {
      Future<Iterable<String>> fields(TransferInput i) async => (await h.reject(const CreateTransferAction(), i)).fieldErrors.keys;
      expect(await fields(atm(100, to: sbi.id)), ['toAccountId']);
      expect(await fields(atm(100, to: 'acc_nope')), ['toAccountId']);
      expect(await fields(atm(0)), ['amount']);
      expect(await fields(atm(100, date: DateTime(2026, 10, 11))), ['date']);
      await h.run(const ArchiveAccountAction(), ArchiveAccountInput(id: sbi.id, archived: true));
      expect(await fields(atm(100)), ['fromAccountId']);
    });

    test('overdrawing only warns', () async {
      final p = await h.dispatcher.preview(const CreateTransferAction(), atm(50000));
      expect(p.valueOrNull!.warnings, isNotEmpty);
    });

    test('update and delete reverse the effect; stale versions are rejected', () async {
      final t = await h.run(const CreateTransferAction(), atm(2000));
      final u = await h.run(const UpdateTransferAction(), UpdateTransferInput(id: t.id, version: 1, data: atm(500)));
      expect(u.version, 2);
      expect((await h.snapshot()).balance.balanceOf(sbi.id), const Money.rupees(9500));
      final stale = await h.reject(const UpdateTransferAction(), UpdateTransferInput(id: t.id, version: 1, data: atm(900)));
      expect(stale.code, FailureCode.staleData);
      await h.run(const DeleteTransferAction(), DeleteTransferInput(id: t.id));
      final s = await h.snapshot();
      expect(s.transfers, isEmpty);
      expect(s.balance.balanceOf(sbi.id), const Money.rupees(10000));
    });

    test('a transfer dated before an account opened moves its opening date back', () async {
      await h.run(const CreateTransferAction(), atm(100, date: DateTime(2026, 8, 1)));
      final s = await h.snapshot();
      expect(s.account(sbi.id)!.openingDate, DateTime(2026, 8, 1));
      expect(s.account(cashAccountId)!.openingDate, DateTime(2026, 1, 1));
      final a = Transfer(
        id: 'x', fromAccountId: 'a', toAccountId: 'b', amount: Money.zero, date: DateTime(2026),
        createdAt: DateTime(2026), updatedAt: DateTime(2026),
      );
      expect(a.copyWith(channel: () => 'ATM').channel, 'ATM');
    });
  });

  group('profile.update keeps the Cash account in step', () {
    test('onboarding opening balance becomes the acc_cash opening', () async {
      final s = await h.snapshot();
      expect(s.account(cashAccountId)!.opening, harnessOpening);
      expect(s.account(cashAccountId)!.openingDate, DateTime(2026, 1, 1));
    });
  });

  group('local migration (no moneyAccounts key)', () {
    Map<String, Object?> legacyTx(String id, int paise, String type, String? method) => {
          'id': id,
          'type': type,
          'amountPaise': paise,
          'categoryId': 'cat_food',
          'date': '2026-10-05',
          'paymentMethod': method,
          'counterparty': null,
          'note': null,
          'origin': 'manual',
          'originRefId': null,
          'createdAt': '2026-10-05T10:00:00.000',
          'updatedAt': '2026-10-05T10:00:00.000',
          'version': 1,
        };

    test('old data moves into one Cash account, totals do not change, methods become channels', () async {
      final driver = MemoryDriver();
      driver.store['transactions'] = jsonEncode([
        legacyTx('t1', 100000, 'expense', 'upi'),
        legacyTx('t2', 50000, 'income', 'bankTransfer'),
        legacyTx('t3', 20000, 'expense', 'cash'),
        legacyTx('t4', 10000, 'expense', null),
      ]);
      driver.store['profile'] = jsonEncode({
        'exists': true,
        'displayName': 'Old',
        'openingPaise': 2500000,
        'openingDate': '2026-09-01',
        'monthlyIncomeEstimatePaise': null,
      });
      driver.store['subscriptions'] = jsonEncode([
        {
          'id': 's1', 'name': 'Netflix', 'amountPaise': 64900, 'categoryId': 'cat_subscriptions',
          'frequency': 'monthly', 'nextDueDate': '2026-10-20', 'startDate': null, 'status': 'active',
          'autoRenews': true, 'paymentMethod': 'card', 'note': null,
          'createdAt': '2026-09-01T10:00:00.000', 'updatedAt': '2026-09-01T10:00:00.000', 'version': 1,
        },
        {
          'id': 's2', 'name': 'Gym', 'amountPaise': 100000, 'categoryId': 'cat_fitness',
          'frequency': 'monthly', 'nextDueDate': '2026-10-21', 'startDate': null, 'status': 'active',
          'autoRenews': true, 'paymentMethod': null, 'note': null,
          'createdAt': '2026-09-01T10:00:00.000', 'updatedAt': '2026-09-01T10:00:00.000', 'version': 1,
        },
      ]);

      final store = LocalDataStore(driver: driver);
      expect(await store.loadExisting(), isTrue);

      final cash = store.moneyAccounts.current.single;
      expect(cash.id, cashAccountId);
      expect(cash.kind, MoneyAccountKind.cash);
      expect(cash.isDefault, isTrue);
      expect(cash.opening, const Money.rupees(25000));
      expect(cash.openingDate, DateTime(2026, 9, 1));

      final byId = {for (final t in store.transactions.current) t.id: t};
      expect(byId.values.every((t) => t.accountId == cashAccountId), isTrue);
      expect([for (final id in ['t1', 't2', 't3', 't4']) byId[id]!.channel], ['UPI', 'Bank transfer', null, null]);
      final subs = {for (final s in store.subscriptions.current) s.id: s};
      expect(subs['s1']!.accountId, cashAccountId);
      expect(subs['s2']!.accountId, isNull);

      // Totals are unchanged: 25,000 - 1,000 + 500 - 200 - 100.
      final b = const LedgerCalculator().balance(
        profile: store.profile.current,
        accounts: store.moneyAccounts.current,
        transfers: store.transfers.current,
        transactions: store.transactions.current,
        movements: const [],
        asOf: DateTime(2026, 10, 10),
      );
      expect(b.cash, const Money.rupees(24200));

      // Persisted: a second load keeps the single account and does not migrate again.
      final again = LocalDataStore(driver: driver);
      expect(await again.loadExisting(), isTrue);
      expect(again.moneyAccounts.current.single.id, cashAccountId);
    });
  });
}
