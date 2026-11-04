import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_app.dart';
import 'journey_helpers.dart';

void main() {
  testWidgets('five equal slots with "add" at the centre; the header agent mark locks the app', (tester) async {
    final env = await TestEnv.create();
    await env.pumpApp(tester);
    await tester.pumpAndSettle();

    // Home, Activity, Add, Budgets, Goals: no "More" tab, equal spacing.
    expect(navTab('More'), findsNothing);
    final add = find.byTooltip('Add transaction');
    expect(add, findsOneWidget);
    final xs = [
      tester.getCenter(navTab('Home')).dx,
      tester.getCenter(navTab('Activity')).dx,
      tester.getCenter(add).dx,
      tester.getCenter(navTab('Budgets')).dx,
      tester.getCenter(navTab('Goals')).dx,
    ];
    final step = xs[1] - xs[0];
    for (var i = 1; i < xs.length; i++) {
      expect(xs[i] - xs[i - 1], closeTo(step, 1), reason: 'slot $i is evenly spaced');
    }
    expect(xs[2], closeTo(tester.view.physicalSize.width / tester.view.devicePixelRatio / 2, 1));

    // The agent lives on the FiNN mark in the tab header.
    final orb = find.byTooltip('FiNN Agent');
    expect(orb, findsOneWidget);

    // Agent mode on: the full-screen agent opens; add and tabs stop responding.
    await tester.tap(orb);
    await tester.pumpAndSettle();
    expect(find.text('FiNN Agent'), findsOneWidget);
    expect(find.text('Agent mode · app paused'), findsOneWidget);

    await tester.tap(add, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('Agent mode · app paused'), findsOneWidget, reason: 'add is disabled');

    await tester.tap(navTab('Goals'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('Agent mode · app paused'), findsOneWidget, reason: 'tabs are disabled');

    // Close from the top bar: everything works again.
    await tester.tap(find.byTooltip('Close agent mode'));
    await tester.pumpAndSettle();
    expect(find.text('Agent mode · app paused'), findsNothing);
    expect(find.byTooltip('Add transaction'), findsOneWidget);
    await tapTab(tester, 'Goals');
    expect(tester.takeException(), isNull);
  });

  testWidgets('the side drawer replaces the More tab and opens its pages', (tester) async {
    final env = await TestEnv.create();
    await env.pumpApp(tester);
    await tester.pumpAndSettle();

    await openMenu(tester);
    expect(inDrawer(find.text('Money')), findsOneWidget);
    await scrollAndTap(tester, inDrawer(find.text('Settings')));
    expect(find.byKey(const ValueKey('app-drawer')), findsNothing, reason: 'the drawer closes before navigating');
    expect(find.byKey(const ValueKey('hide-balances')), findsWidgets);

    // A drawer page highlights no tab; Home is one tap away.
    await tapTab(tester, 'Home');
    expect(find.text('Available to spend'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
