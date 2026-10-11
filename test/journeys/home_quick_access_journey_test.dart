import 'package:finn/app/router/routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../helpers/test_app.dart';
import 'journey_helpers.dart';

String _location(WidgetTester tester) => GoRouter.of(tester.element(find.byType(Navigator).first)).state.uri.path;

void main() {
  testWidgets('home quick-access tiles sit in bento order and open their module', (tester) async {
    final env = await TestEnv.create();
    await env.pumpApp(tester);
    await tester.pumpAndSettle();

    await scrollTo(tester, find.byKey(const ValueKey('quick-tile:Timeline')));
    final pos = {
      for (final name in ['Loans & EMIs', 'Pending payments', 'Emergency fund', 'Goals', 'Timeline'])
        name: tester.getCenter(find.byKey(ValueKey('quick-tile:$name'))),
    };
    // Tall loans tile on the left, pending above emergency fund on the right,
    // goals and timeline sharing the bottom row.
    expect(pos['Loans & EMIs']!.dx, lessThan(pos['Pending payments']!.dx));
    expect(pos['Pending payments']!.dy, lessThan(pos['Emergency fund']!.dy));
    expect(pos['Goals']!.dy, greaterThan(pos['Emergency fund']!.dy));
    expect(pos['Goals']!.dx, lessThan(pos['Timeline']!.dx));
    expect((pos['Goals']!.dy - pos['Timeline']!.dy).abs(), lessThan(1));

    final routes = {
      'Loans & EMIs': AppRoutes.loans,
      'Pending payments': AppRoutes.pending,
      'Emergency fund': AppRoutes.emergencyFund,
      'Timeline': AppRoutes.timeline,
    };
    for (final MapEntry(key: name, value: route) in routes.entries) {
      await scrollAndTap(tester, find.byKey(ValueKey('quick-tile:$name')));
      expect(_location(tester), route, reason: '$name tile');
      tester.state<NavigatorState>(find.byType(Navigator).last).pop();
      await tester.pumpAndSettle();
    }

    await scrollAndTap(tester, find.byKey(const ValueKey('quick-tile:Goals')));
    expect(_location(tester), AppRoutes.goals);
  });
}
