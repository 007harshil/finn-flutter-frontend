import 'package:finn/data/local/local_data_store.dart';
import 'package:finn/features/home/presentation/widgets/accounts_section.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/test_app.dart';

void main() {
  testWidgets('home accounts section lists accounts with owed on credit cards', (tester) async {
    final env = await TestEnv.create();
    await env.pumpWidget(tester, const HomeAccountsSection());
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
    await env.pumpWidget(tester, const HomeAccountsSection());
    await tester.pumpAndSettle();
    expect(find.text('Cash'), findsOneWidget);
  });
}
