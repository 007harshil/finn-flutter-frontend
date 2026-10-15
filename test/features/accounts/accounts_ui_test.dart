import 'package:finn/core/money/money.dart';
import 'package:finn/data/mock/seed_data.dart';
import 'package:finn/features/accounts/domain/money_account.dart';
import 'package:finn/features/accounts/presentation/account_detail_screen.dart';
import 'package:finn/features/accounts/presentation/account_form_sheet.dart';
import 'package:finn/features/accounts/presentation/accounts_screen.dart';
import 'package:finn/features/accounts/presentation/set_balance_sheet.dart';
import 'package:finn/kit/kit.dart' show LedgerAmountField, LedgerButton, LedgerChip, LedgerTextField;
import 'package:flutter/widgets.dart' show Size;
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/test_app.dart';

Future<void> _settle(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();
}

void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(400, 2400) * tester.view.devicePixelRatio;
  addTearDown(tester.view.resetPhysicalSize);
}

void main() {
  testWidgets('accounts screen groups accounts and marks the default', (tester) async {
    _tall(tester);
    final env = await TestEnv.create();
    await env.pumpWidget(tester, const AccountsScreen());
    await tester.pumpAndSettle();

    expect(find.text('Total money'), findsOneWidget);
    expect(find.textContaining('Cards'), findsOneWidget);
    expect(find.textContaining('Credit cards'), findsOneWidget);
    expect(find.text('HDFC Millennia'), findsOneWidget);
    expect(find.textContaining('left'), findsOneWidget);
    // SBI is the default account.
    expect(find.textContaining('····4821 · Default'), findsOneWidget);
  });

  testWidgets('archived accounts are collapsed until shown', (tester) async {
    final env = await TestEnv.create();
    _tall(tester);
    final axis = (await env.snapshot()).account(SeedAccountIds.axis)!;
    await env.repos.moneyAccounts.save(axis.copyWith(isArchived: true, version: axis.version + 1));
    await env.pumpWidget(tester, const AccountsScreen());
    await tester.pumpAndSettle();

    expect(find.textContaining('Archived'), findsWidgets);
    expect(find.text('Axis'), findsNothing);
    await tester.tap(find.widgetWithText(LedgerButton, 'Show'));
    await tester.pumpAndSettle();
    expect(find.text('Axis'), findsOneWidget);
  });

  testWidgets('account detail lists movements with neutral transfer rows', (tester) async {
    _tall(tester);
    final env = await TestEnv.create();
    await env.pumpWidget(tester, const AccountDetailScreen(id: SeedAccountIds.cash));
    await tester.pumpAndSettle();

    expect(find.text('Balance'), findsOneWidget);
    expect(find.textContaining('Movements'), findsOneWidget);
    // ATM withdrawals land in Cash from SBI.
    expect(find.text('From SBI'), findsWidgets);
  });

  testWidgets('credit card detail shows owed and limit left', (tester) async {
    _tall(tester);
    final env = await TestEnv.create();
    await env.pumpWidget(tester, const AccountDetailScreen(id: SeedAccountIds.hdfcCard));
    await tester.pumpAndSettle();
    expect(find.text('Amount owed'), findsOneWidget);
    expect(find.textContaining('left'), findsOneWidget);
  });

  testWidgets('deleting an account that has movements is blocked with an archive hint', (tester) async {
    _tall(tester);
    final env = await TestEnv.create();
    await env.pumpWidget(tester, const AccountDetailScreen(id: SeedAccountIds.sbi));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('More actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Archive it instead'), findsOneWidget);
    expect((await env.snapshot()).account(SeedAccountIds.sbi), isNotNull);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('account form validates, shows card-only fields and creates an account', (tester) async {
    final env = await TestEnv.create();
    await env.pumpWidget(tester, const AccountFormSheet());
    await tester.pumpAndSettle();

    final save = find.widgetWithText(LedgerButton, 'Add account');
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.text('Enter a name.'), findsOneWidget);

    // Bank kind: no last 4, no limit.
    expect(find.text('Last 4 digits (optional)'), findsNothing);
    expect(find.text('Credit limit (optional)'), findsNothing);
    expect(find.text('Opening balance'), findsOneWidget);

    await tester.tap(find.widgetWithText(LedgerChip, 'Credit card'));
    await tester.pumpAndSettle();
    expect(find.text('Amount owed'), findsOneWidget);
    expect(find.text('Credit limit (optional)'), findsOneWidget);
    expect(find.text('Last 4 digits (optional)'), findsOneWidget);

    await tester.enterText(find.widgetWithText(LedgerTextField, 'Name'), 'ICICI Amazon');
    await tester.enterText(find.widgetWithText(LedgerTextField, 'Last 4 digits (optional)'), '12');
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.text('Enter exactly 4 digits.'), findsOneWidget);

    await tester.enterText(find.widgetWithText(LedgerTextField, 'Last 4 digits (optional)'), '9021');
    await tester.enterText(find.widgetWithText(LedgerAmountField, 'Amount owed'), '5000');
    await tester.tap(save);
    await _settle(tester);

    final a = (await env.snapshot()).accounts.firstWhere((x) => x.name == 'ICICI Amazon');
    expect(a.kind, MoneyAccountKind.creditCard);
    expect(a.last4, '9021');
    expect(a.opening, const Money.rupees(5000));
  });

  testWidgets('correct balance previews old to new and saves', (tester) async {
    final env = await TestEnv.create();
    await env.pumpWidget(tester, const SetBalanceSheet(accountId: SeedAccountIds.cash));
    await tester.pumpAndSettle();
    expect(find.text('Balance now'), findsOneWidget);
    await tester.enterText(find.byType(LedgerAmountField), '12345');
    await tester.pump();
    expect(find.text('Will be'), findsOneWidget);
    expect(find.text('Difference'), findsOneWidget);

    await tester.tap(find.widgetWithText(LedgerButton, 'Save'));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.widgetWithText(LedgerButton, 'Confirm'));
    await _settle(tester);
    final b = (await env.snapshot()).accountBalances.firstWhere((x) => x.account.id == SeedAccountIds.cash);
    expect(b.balance, const Money.rupees(12345));
  });
}
