import 'package:finn/data/local/local_data_store.dart';
import 'package:finn/features/home/presentation/widgets/hero_balance_card.dart';
import 'package:finn/features/home/presentation/widgets/accounts_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/test_app.dart';

void main() {
  testWidgets('hero card lists accounts with owed on credit cards', (tester) async {
    final env = await TestEnv.create();
    await env.pumpWidget(tester, const HeroBalanceCard());
    await tester.pumpAndSettle();

    expect(find.textContaining('Accounts'), findsOneWidget);
    expect(find.text('Manage'), findsOneWidget);
    expect(find.text('SBI'), findsOneWidget);
    expect(find.text('HDFC Millennia'), findsOneWidget);
    expect(find.textContaining('····4821'), findsOneWidget);
    expect(find.textContaining('owed'), findsWidgets);
  });

  testWidgets('a fresh install shows its single Cash account', (tester) async {
    final env = await TestEnv.create(scenario: DataScenario.empty);
    await env.pumpWidget(tester, const HeroBalanceCard());
    await tester.pumpAndSettle();
    // "Cash" is also the hero legend; look inside the accounts strip.
    expect(find.descendant(of: find.byType(HeroAccountsStrip), matching: find.text('Cash')), findsOneWidget);
  });

  testWidgets('an account with money set aside shows a quiet set aside line', (tester) async {
    final env = await TestEnv.create();
    await env.pumpWidget(tester, const HeroBalanceCard());
    await tester.pumpAndSettle();
    // The demo data sets savings aside on the Cash account.
    expect(find.textContaining(RegExp('set aside|Over-reserved')), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('more than two accounts scroll sideways', (tester) async {
    final env = await TestEnv.create();
    await env.pumpWidget(tester, const HeroBalanceCard());
    await tester.pumpAndSettle();
    final strip = find.descendant(
      of: find.byType(HeroAccountsStrip),
      matching: find.byWidgetPredicate((w) => w is SingleChildScrollView && w.scrollDirection == Axis.horizontal),
    );
    expect(strip, findsOneWidget);
  });
}
