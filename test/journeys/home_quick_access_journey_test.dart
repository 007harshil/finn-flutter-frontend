import 'package:finn/app/router/routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../helpers/test_app.dart';
import 'journey_helpers.dart';

String _location(WidgetTester tester) => GoRouter.of(tester.element(find.byType(Navigator).first)).state.uri.path;

void main() {
  testWidgets('home shortcuts sit in a 3-column grid and open their module', (tester) async {
    final env = await TestEnv.create();
    await env.pumpApp(tester);
    await tester.pumpAndSettle();

    const names = ['Loans', 'Pending', 'Subscriptions', 'Emergency fund', 'Insights', 'Timeline'];
    await scrollTo(tester, find.byKey(const ValueKey('quick-tile:Timeline')));
    final pos = {for (final name in names) name: tester.getCenter(find.byKey(ValueKey('quick-tile:$name')))};
    // Two rows of three, left to right.
    for (final (a, b) in [('Loans', 'Pending'), ('Pending', 'Subscriptions'), ('Emergency fund', 'Insights')]) {
      expect(pos[a]!.dx, lessThan(pos[b]!.dx), reason: '$a before $b');
      expect((pos[a]!.dy - pos[b]!.dy).abs(), lessThan(1), reason: '$a and $b share a row');
    }
    expect(pos['Emergency fund']!.dy, greaterThan(pos['Loans']!.dy));

    final routes = {
      'Loans': AppRoutes.loans,
      'Pending': AppRoutes.pending,
      'Subscriptions': AppRoutes.subscriptions,
      'Emergency fund': AppRoutes.emergencyFund,
      'Insights': AppRoutes.analytics,
      'Timeline': AppRoutes.timeline,
    };
    for (final MapEntry(key: name, value: route) in routes.entries) {
      await scrollAndTap(tester, find.byKey(ValueKey('quick-tile:$name')));
      expect(_location(tester), route, reason: '$name tile');
      tester.state<NavigatorState>(find.byType(Navigator).last).pop();
      await tester.pumpAndSettle();
    }
  });
}
