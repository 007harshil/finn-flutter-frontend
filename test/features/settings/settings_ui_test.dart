import 'package:finn/actions/dispatcher.dart';
import 'package:finn/app/di/action_providers.dart';
import 'package:finn/app/di/core_providers.dart';
import 'package:finn/core/money/money.dart';
import 'package:finn/kit/kit.dart';
import 'package:finn/features/alerts/domain/alert.dart';
import 'package:finn/features/net_worth/application/asset_actions.dart';
import 'package:finn/features/net_worth/domain/asset.dart';
import 'package:finn/features/settings/presentation/activity_log_screen.dart';
import 'package:finn/features/settings/presentation/notification_settings_screen.dart';
import 'package:finn/features/settings/presentation/profile_sheet.dart';
import 'package:finn/features/settings/presentation/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/test_app.dart';

ProviderContainer _container(WidgetTester tester, Type screen) =>
    ProviderScope.containerOf(tester.element(find.byType(screen)));

void main() {
  testWidgets('settings shows the profile and toggles preferences', (tester) async {
    final env = await TestEnv.create();
    await env.pumpWidget(tester, const SettingsScreen());
    await tester.pumpAndSettle();

    expect(find.text('Aarav'), findsOneWidget);
    final container = _container(tester, SettingsScreen);
    expect(container.read(settingsProvider).hideBalances, isFalse);

    await tester.tap(find.byKey(const ValueKey('hide-balances')));
    await tester.pumpAndSettle();
    expect(container.read(settingsProvider).hideBalances, isTrue);

    final increase = find.byTooltip('Increase Budget month starts');
    await tester.scrollUntilVisible(increase, 200);
    await tester.tap(increase);
    await tester.pumpAndSettle();
    expect(container.read(settingsProvider).monthStartDay, 2);
    expect(find.text('2nd'), findsOneWidget);
  });

  testWidgets('profile sheet saves a new name', (tester) async {
    final env = await TestEnv.create();
    await env.pumpWidget(tester, const ProfileSheet());
    await tester.pumpAndSettle();

    final name = find.widgetWithText(LedgerTextField, 'Name');
    expect(find.text('Aarav'), findsOneWidget);
    await tester.enterText(name, '');
    await tester.tap(find.widgetWithText(LedgerButton, 'Save profile'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a name.'), findsOneWidget);

    await tester.enterText(name, 'Aarav Sharma');
    await tester.tap(find.widgetWithText(LedgerButton, 'Save profile'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    final profile = (await env.snapshot()).profile;
    expect(profile?.displayName, 'Aarav Sharma');
  });

  testWidgets('alert types can be switched off', (tester) async {
    final env = await TestEnv.create();
    await env.pumpWidget(tester, const NotificationSettingsScreen());
    await tester.pumpAndSettle();

    final row = find.byKey(const ValueKey('alert-emiDue'));
    await tester.scrollUntilVisible(row, 200);
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    await tester.tap(row);
    await tester.pumpAndSettle();
    final settings = _container(tester, NotificationSettingsScreen).read(settingsProvider);
    expect(settings.disabledAlertTypes, contains(AlertType.emiDue));
    expect(settings.isAlertEnabled(AlertType.emiOverdue), isTrue);
  });

  testWidgets('activity log lists dispatched actions', (tester) async {
    final env = await TestEnv.create();
    await env.pumpWidget(tester, const ActivityLogScreen());
    await tester.pumpAndSettle();
    expect(find.text('No activity yet'), findsOneWidget);

    final container = _container(tester, ActivityLogScreen);
    final outcome = await tester.runAsync(() => container.read(actionDispatcherProvider).dispatch(
          const CreateAssetAction(),
          AssetInput(name: 'PPF account', type: AssetType.retirement, value: const Money.rupees(90000), valuedOn: testNow),
          idempotencyKey: 'activity-test',
        ));
    expect(outcome, isA<ActionCompleted<Asset>>());
    await tester.pumpAndSettle();

    expect(find.text('No activity yet'), findsNothing);
    expect(find.textContaining('PPF account'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
  });
}
