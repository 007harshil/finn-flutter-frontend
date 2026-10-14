import 'package:finn/app/router/routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../helpers/test_app.dart';
import 'journey_helpers.dart';

String _location(WidgetTester tester) => GoRouter.of(tester.element(find.byType(Navigator).first)).state.uri.path;

void main() {
  testWidgets('home quick-access tiles sit in a 3 × 2 grid and open their module', (tester) async {
    final env = await TestEnv.create();
    await env.pumpApp(tester);
    await tester.pumpAndSettle();

    await scrollTo(tester, find.byKey(const ValueKey('quick-tile:Insights')));
    final pos = {
      for (final name in ['Loans & EMIs', 'Pending payments', 'Emergency fund', 'Goals', 'Timeline', 'Insights'])
        name: tester.getCenter(find.byKey(ValueKey('quick-tile:$name'))),
    };
    // Loans, pending, emergency fund on the first row; goals, timeline,
    // insights on the second, left to right.
    final names = pos.keys.toList();
    for (var i = 0; i < names.length; i++) {
      final row = i ~/ 3;
      expect((pos[names[i]]!.dy - pos[names[row * 3]]!.dy).abs(), lessThan(1), reason: '${names[i]} row');
      if (i % 3 > 0) expect(pos[names[i]]!.dx, greaterThan(pos[names[i - 1]]!.dx), reason: '${names[i]} column');
    }
    expect(pos['Goals']!.dy, greaterThan(pos['Loans & EMIs']!.dy));

    final routes = {
      'Loans & EMIs': AppRoutes.loans,
      'Pending payments': AppRoutes.pending,
      'Emergency fund': AppRoutes.emergencyFund,
      'Timeline': AppRoutes.timeline,
      'Insights': AppRoutes.analytics,
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
