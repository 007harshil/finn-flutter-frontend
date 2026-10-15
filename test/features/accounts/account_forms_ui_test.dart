import 'package:finn/app/di/data_providers.dart';
import 'package:finn/core/money/money.dart';
import 'package:finn/data/mock/seed_data.dart';
import 'package:finn/features/accounts/presentation/transfer_form_sheet.dart';
import 'package:finn/features/accounts/presentation/widgets/account_picker_field.dart';
import 'package:finn/features/loans/presentation/loan_payment_sheet.dart';
import 'package:finn/features/pending/domain/pending_payment.dart';
import 'package:finn/features/pending/presentation/settle_pending_sheet.dart';
import 'package:finn/features/transactions/application/transaction_filter.dart';
import 'package:finn/features/transactions/domain/transaction.dart';
import 'package:finn/features/transactions/presentation/transaction_form_sheet.dart';
import 'package:finn/features/transactions/presentation/transactions_screen.dart';
import 'package:finn/kit/kit.dart' show LedgerAmountField;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/test_app.dart';

Future<void> _sized(WidgetTester tester, {double h = 1800}) async {
  tester.view.physicalSize = Size(400, h) * tester.view.devicePixelRatio;
  addTearDown(tester.view.resetPhysicalSize);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 500));
  }
}

Finder _button(String label) => find.ancestor(of: find.text(label), matching: find.byType(InkWell)).last;

Future<void> _enterAmount(WidgetTester tester, String text) async {
  await tester.enterText(
    find.descendant(of: find.byType(LedgerAmountField).first, matching: find.byType(EditableText)),
    text,
  );
  await tester.pump();
}

Finder _pickerField(String label) => find.descendant(
  of: find.byWidgetPredicate((w) => w is AccountPickerField && w.label == label, description: 'picker "$label"'),
  matching: find.byType(InkWell),
);

Future<void> _openPicker(WidgetTester tester, String label) async {
  await tester.ensureVisible(_pickerField(label));
  await tester.tap(_pickerField(label));
  await tester.pumpAndSettle();
}

Future<void> _pickAccount(WidgetTester tester, String fieldLabel, String accountId) async {
  await _openPicker(tester, fieldLabel);
  await tester.tap(find.byKey(ValueKey('account-$accountId')));
  await tester.pumpAndSettle();
}

/// Taps the primary button, then approves the review sheet when one shows.
Future<void> _submitAndConfirm(WidgetTester tester, String label) async {
  await tester.tap(_button(label));
  await tester.pump(const Duration(milliseconds: 600));
  final confirm = find.text('Confirm');
  for (var i = 0; i < 20 && confirm.evaluate().isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  if (confirm.evaluate().isNotEmpty) {
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(confirm.last);
  }
  await _settle(tester);
}

void main() {
  late TestEnv env;

  setUp(() async => env = await TestEnv.create());

  group('transaction form', () {
    testWidgets('preselects the default account; another account and a channel are saved', (tester) async {
      await _sized(tester);
      await env.pumpWidget(tester, const TransactionFormSheet());
      await tester.pumpAndSettle();

      expect(find.text('Paid from'), findsOneWidget);
      expect(find.text('SBI'), findsWidgets);

      await _enterAmount(tester, '640');
      await tester.tap(find.text('Choose a category'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey(SeedCategoryIds.food)));
      await tester.pumpAndSettle();

      await _pickAccount(tester, 'Paid from', SeedAccountIds.cash);
      await tester.ensureVisible(find.byKey(const ValueKey('channel-Tap / swipe')));
      await tester.tap(find.byKey(const ValueKey('channel-Tap / swipe')));
      await tester.pumpAndSettle();

      await _submitAndConfirm(tester, 'Record expense');

      final tx = (await env.snapshot()).transactions.firstWhere((t) => t.amount == const Money.rupees(640));
      expect(tx.accountId, SeedAccountIds.cash);
      expect(tx.channel, 'Tap / swipe');
      expect(tester.takeException(), isNull);
    });

    testWidgets('a custom channel is trimmed and saved; an untouched account is the default', (tester) async {
      await _sized(tester);
      await env.pumpWidget(tester, const TransactionFormSheet());
      await tester.pumpAndSettle();
      await _enterAmount(tester, '77');
      await tester.tap(find.text('Choose a category'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey(SeedCategoryIds.food)));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const ValueKey('channel-other')));
      await tester.tap(find.byKey(const ValueKey('channel-other')));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'e.g. Wallet, DD'), '  Wallet ');
      await tester.pump();
      await _submitAndConfirm(tester, 'Record expense');

      final tx = (await env.snapshot()).transactions.firstWhere((t) => t.amount == const Money.rupees(77));
      expect(tx.accountId, SeedAccountIds.sbi);
      expect(tx.channel, 'Wallet');
    });

    testWidgets('a channel over 30 characters is flagged', (tester) async {
      await _sized(tester);
      await env.pumpWidget(tester, const TransactionFormSheet());
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('channel-other')));
      await tester.tap(find.byKey(const ValueKey('channel-other')));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'e.g. Wallet, DD'), 'x' * 31);
      await tester.pump();
      expect(find.textContaining('under 30 characters'), findsOneWidget);
    });
  });

  group('account picker', () {
    testWidgets('lists kind, last4 and balance; credit card shows owed; exclude hides an account', (tester) async {
      await _sized(tester);
      await env.pumpWidget(
        tester,
        AccountPickerField(value: SeedAccountIds.sbi, exclude: SeedAccountIds.cash, onChanged: (_) {}),
      );
      await tester.pumpAndSettle();
      await _openPicker(tester, 'Account');
      expect(find.byKey(ValueKey('account-${SeedAccountIds.cash}')), findsNothing);
      expect(find.textContaining('····4821'), findsOneWidget);
      expect(find.textContaining('owed'), findsOneWidget);
    });
  });

  group('transfer sheet', () {
    Future<void> open(WidgetTester tester, {String? from, String? to}) async {
      await _sized(tester);
      await env.pumpWidget(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showTransferSheet(context, fromAccountId: from, toAccountId: to),
            child: const Text('open'),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('requires a destination and an amount', (tester) async {
      final before = await env.snapshot();
      await open(tester);
      await tester.tap(_button('Record transfer'));
      await tester.pumpAndSettle();
      expect(find.text('Enter an amount greater than zero.'), findsOneWidget);
      expect(find.text('Choose the account the money goes to.'), findsOneWidget);
      expect((await env.snapshot()).transfers.length, before.transfers.length);
    });

    testWidgets('the destination picker leaves out the source', (tester) async {
      await open(tester, from: SeedAccountIds.sbi);
      await _openPicker(tester, 'To');
      expect(find.byKey(ValueKey('account-${SeedAccountIds.sbi}')), findsNothing);
      expect(find.byKey(ValueKey('account-${SeedAccountIds.cash}')), findsOneWidget);
    });

    testWidgets('changing the source to the chosen destination clears the destination', (tester) async {
      await open(tester, from: SeedAccountIds.sbi, to: SeedAccountIds.cash);
      await _pickAccount(tester, 'From', SeedAccountIds.cash);
      await _enterAmount(tester, '100');
      await tester.tap(_button('Record transfer'));
      await tester.pumpAndSettle();
      expect(find.text('Choose the account the money goes to.'), findsOneWidget);
    });

    testWidgets('records a transfer with a channel and creates no transaction', (tester) async {
      final before = await env.snapshot();
      await open(tester, from: SeedAccountIds.sbi, to: SeedAccountIds.cash);
      await _enterAmount(tester, '2000');
      await tester.ensureVisible(find.byKey(const ValueKey('channel-ATM')));
      await tester.tap(find.byKey(const ValueKey('channel-ATM')));
      await tester.pumpAndSettle();
      await _submitAndConfirm(tester, 'Record transfer');

      final after = await env.snapshot();
      expect(after.transfers.length, before.transfers.length + 1);
      final t = after.transfers.firstWhere((t) => t.amount == const Money.rupees(2000));
      expect([t.fromAccountId, t.toAccountId, t.channel], [SeedAccountIds.sbi, SeedAccountIds.cash, 'ATM']);
      expect(after.transactions.length, before.transactions.length);
    });
  });

  group('activity', () {
    Future<ProviderContainer> pumpActivity(WidgetTester tester) async {
      await _sized(tester, h: 2400);
      await env.pumpWidget(tester, const TransactionsScreen());
      await tester.pumpAndSettle();
      return ProviderScope.containerOf(tester.element(find.byType(TransactionsScreen)));
    }

    testWidgets('transfers are neutral rows, stay out of totals, and tap opens the edit sheet', (tester) async {
      final container = await pumpActivity(tester);
      final feed = container.read(transactionFeedProvider).requireValue;
      expect(feed.transfers, isNotEmpty);

      final snapshot = await env.snapshot();
      final cats = container.read(categoriesByIdProvider).requireValue;
      final plain = TransactionQuery.build(
        container.read(sortedTransactionsProvider).requireValue,
        feed.filter,
        cats,
        today: snapshot.today,
      );
      expect(feed.income, plain.income);
      expect(feed.expense, plain.expense);
      expect(feed.count, plain.count);
      expect(feed.rowCount, plain.count + feed.transfers.length);

      final rowText = find.textContaining('→');
      expect(rowText, findsWidgets);
      await tester.tap(rowText.first);
      await tester.pumpAndSettle();
      expect(find.text('Edit transfer'), findsOneWidget);
      expect(find.text('Delete transfer'), findsOneWidget);
    });

    testWidgets('account filter keeps transactions and transfers of the chosen accounts', (tester) async {
      final container = await pumpActivity(tester);
      final notifier = container.read(transactionFilterProvider.notifier);
      notifier.setAccounts({SeedAccountIds.cash});
      await tester.pumpAndSettle();
      final feed = container.read(transactionFeedProvider).requireValue;
      expect(feed.transactions.every((t) => t.accountId == SeedAccountIds.cash), isTrue);
      expect(
        feed.transfers.every((t) => t.fromAccountId == SeedAccountIds.cash || t.toAccountId == SeedAccountIds.cash),
        isTrue,
      );
      notifier.setAccounts(const {});
      notifier.setType(TransactionType.expense);
      await tester.pumpAndSettle();
      expect(container.read(transactionFeedProvider).requireValue.transfers, isEmpty);
    });

    testWidgets('filter sheet multi-selects accounts and channels', (tester) async {
      final container = await pumpActivity(tester);
      await tester.tap(find.byKey(const ValueKey('activity-filters')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('filter-account:${SeedAccountIds.cash}')));
      await tester.tap(find.byKey(ValueKey('filter-account:${SeedAccountIds.sbi}')));
      await tester.pump();
      final channel = find.byKey(const ValueKey('filter-channel:ATM'));
      await tester.ensureVisible(channel);
      await tester.tap(channel);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('activity-filter-apply')));
      await tester.pumpAndSettle();
      final f = container.read(transactionFilterProvider);
      expect(f.accountIds, {SeedAccountIds.cash, SeedAccountIds.sbi});
      expect(f.channels, {'ATM'});
      expect(find.byKey(const ValueKey('active-filter:channels')), findsOneWidget);
    });
  });

  group('settle and loan sheets', () {
    testWidgets('settle sheet sends the chosen account', (tester) async {
      await _sized(tester);
      final before = await env.snapshot();
      final v = before.pendingViews.firstWhere((v) => v.payment.purpose == 'Goa trip hotel share');
      expect(v.payment.direction, PendingDirection.owedToMe);
      await env.pumpWidget(tester, SettlePendingSheet(pendingId: v.payment.id));
      await tester.pumpAndSettle();
      expect(find.text('Received in'), findsOneWidget);
      await _pickAccount(tester, 'Received in', SeedAccountIds.axis);
      await _submitAndConfirm(tester, 'Record receipt');
      final linked = (await env.snapshot()).linkedTransactions(v.payment.id);
      expect(linked.single.accountId, SeedAccountIds.axis);
    });

    testWidgets('loan payment sheet sends the default account when none is picked', (tester) async {
      await _sized(tester);
      final before = await env.snapshot();
      await env.pumpWidget(tester, const LoanPaymentSheet(loanId: 'loan_seed_car'));
      await tester.pumpAndSettle();
      expect(find.text('Paid from'), findsOneWidget);
      expect(find.text('SBI'), findsWidgets);
      await _submitAndConfirm(tester, 'Record payment');
      final after = await env.snapshot();
      final created = after.transactions.where((t) => !before.transactions.any((b) => b.id == t.id)).toList();
      expect(created, hasLength(1));
      expect(created.single.accountId, SeedAccountIds.sbi);
    });
  });
}
