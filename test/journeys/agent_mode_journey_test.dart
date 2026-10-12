import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_app.dart';
import 'journey_helpers.dart';

void main() {
  testWidgets('the agent orb sits centred after Budgets and agent mode locks the app', (tester) async {
    final env = await TestEnv.create();
    await env.pumpApp(tester);
    await tester.pumpAndSettle();

    // Orb between Budgets and Goals, at the bar's centre.
    final orb = find.byTooltip('FiNN Agent');
    expect(orb, findsOneWidget);
    final orbX = tester.getCenter(orb).dx;
    expect(tester.getCenter(navTab('Budgets')).dx, lessThan(orbX));
    expect(tester.getCenter(navTab('Goals')).dx, greaterThan(orbX));
    expect(orbX, closeTo(tester.view.physicalSize.width / tester.view.devicePixelRatio / 2, 1));
    expect(find.byTooltip('Add transaction'), findsOneWidget);

    // Agent mode on: the panel opens, the FAB goes and tabs stop responding.
    await tester.tap(orb);
    await tester.pumpAndSettle();
    expect(find.text('FiNN Agent'), findsOneWidget);
    expect(find.text('Agent mode on · the app is paused'), findsOneWidget);
    expect(find.byTooltip('Add transaction'), findsNothing);

    await tester.tap(navTab('Goals'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('Agent mode on · the app is paused'), findsOneWidget, reason: 'tabs are disabled');

    // Close from the panel: everything works again.
    await tester.tap(find.byTooltip('Close agent mode'));
    await tester.pumpAndSettle();
    expect(find.text('Agent mode on · the app is paused'), findsNothing);
    expect(find.byTooltip('Add transaction'), findsOneWidget);
    await tapTab(tester, 'Goals');
    expect(tester.takeException(), isNull);
  });
}
