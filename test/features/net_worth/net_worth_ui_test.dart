import 'package:finn/core/money/money.dart';
import 'package:finn/data/local/local_data_store.dart';
import 'package:finn/features/net_worth/domain/asset.dart';
import 'package:finn/features/net_worth/presentation/asset_form_sheet.dart';
import 'package:finn/features/net_worth/presentation/net_worth_screen.dart';
import 'package:finn/kit/kit.dart'
    show LedgerAmountField, LedgerButton, LedgerTextField;
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/test_app.dart';

Future<void> _settle(WidgetTester tester) async {
  await tester.pumpAndSettle();
  // Let toast timers run out.
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('net worth screen shows the hero, breakdown and assets', (
    tester,
  ) async {
    final env = await TestEnv.create();
    await env.pumpWidget(tester, const NetWorthScreen());
    await tester.pumpAndSettle();

    expect(find.text('What you own minus what you owe'), findsOneWidget);
    expect(find.text('What you own'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Hyundai i20'), 200);
    expect(find.text('Hyundai i20'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('What you owe'), 200);
    expect(find.text('What you owe'), findsOneWidget);
  });

  testWidgets('empty data shows the add-asset empty state', (tester) async {
    final env = await TestEnv.create(scenario: DataScenario.empty);
    await env.pumpWidget(tester, const NetWorthScreen());
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('No assets added yet'), 200);
    expect(find.text('No assets added yet'), findsOneWidget);
  });

  testWidgets('asset form validates and creates an asset', (tester) async {
    final env = await TestEnv.create();
    await env.pumpWidget(tester, const AssetFormSheet());
    await tester.pumpAndSettle();
    final save = find.widgetWithText(LedgerButton, 'Add asset');

    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.text('Use at least 2 characters.'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(LedgerTextField, 'Name'),
      'Sovereign gold bonds',
    );
    await tester.enterText(find.byType(LedgerAmountField), '75000');
    await tester.tap(save);
    await _settle(tester);

    final assets = (await env.snapshot()).assets;
    final created = assets.firstWhere((a) => a.name == 'Sovereign gold bonds');
    expect(created.value, const Money.rupees(75000));
    expect(created.type, AssetType.investment);
  });

  testWidgets('edit sheet loads an asset and deletes it after review', (
    tester,
  ) async {
    final env = await TestEnv.create();
    final target = (await env.snapshot()).assets.firstWhere(
      (a) => a.name == 'Gold jewellery',
    );
    await env.pumpWidget(tester, AssetFormSheet(assetId: target.id));
    await tester.pumpAndSettle();

    expect(find.text('Edit asset'), findsOneWidget);
    expect(find.text('Gold jewellery'), findsOneWidget);

    final delete = find.widgetWithText(LedgerButton, 'Delete asset');
    await tester.ensureVisible(delete);
    await tester.tap(delete);
    // The form shows a spinner while the review sheet is open.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Delete asset?'), findsOneWidget);
    await tester.tap(find.widgetWithText(LedgerButton, 'Confirm'));
    await _settle(tester);

    final assets = (await env.snapshot()).assets;
    expect(assets.any((a) => a.id == target.id), isFalse);
  });
}
