import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/helpers/test_app.dart';
import '../test/journeys/journey_helpers.dart';

/// A page title (a header-semantics text), not the bottom-nav label.
Finder pageHeader(String title) => find.descendant(
  of: find.byWidgetPredicate((w) => w is Semantics && w.properties.header == true),
  matching: find.text(title),
);

/// Smoke journey on a device / desktop: launch the full app with the demo
/// data, visit every bottom-navigation tab, then open the side drawer.
///
/// Run with `flutter test integration_test/app_journey_test.dart -d <device>`.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('launches and every tab renders', (tester) async {
    final env = await TestEnv.create();
    await env.pumpApp(tester);
    await tester.pumpAndSettle();

    expect(find.text('AVAILABLE TO SPEND'), findsOneWidget);

    final tabs = <String, Finder>{
      'Activity': pageHeader('Activity'),
      'Budgets': pageHeader('Budgets'),
      'Goals': find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.header == true && w.properties.label == 'Your vision',
      ),
      'Home': find.text('AVAILABLE TO SPEND'),
    };
    for (final MapEntry(key: tab, value: title) in tabs.entries) {
      await tapTab(tester, tab);
      expect(title, findsOneWidget, reason: '$tab tab should show its page');
      expect(tester.takeException(), isNull, reason: 'no errors on $tab');
    }

    // The side drawer replaced the old "More" tab.
    await openMenu(tester);
    expect(pageHeader('Financial overview'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
