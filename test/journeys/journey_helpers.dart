import 'package:finn/core/money/money.dart';
import 'package:finn/core/money/money_format.dart';
import 'package:finn/design_system/design_system.dart';
import 'package:finn/features/home/presentation/widgets/hero_balance_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Shared steps for the end-to-end journeys in this folder. Every journey
/// drives the full app (router, shell, sheets) built by `TestEnv.pumpApp`.

/// Pumps long enough for toasts, success overlays and debounced writes to
/// finish, so no timer is left pending and the next screen is settled.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 500));
  }
  await tester.pumpAndSettle();
}

/// The bottom-navigation item labelled [label] ("Home" may carry an alert
/// count, e.g. "Home, 3 alerts").
Finder navTab(String label) => find.byWidgetPredicate(
  (w) =>
      w is Semantics &&
      w.properties.button == true &&
      w.properties.selected != null &&
      (w.properties.label == label || (w.properties.label?.startsWith('$label,') ?? false)),
  description: 'bottom nav tab "$label"',
);

/// Switches branch through the real bottom navigation bar.
Future<void> tapTab(WidgetTester tester, String label) async {
  final tab = navTab(label);
  expect(tab, findsOneWidget, reason: 'bottom nav should show "$label"');
  // After scrolling down the bar is compact: the first tap only expands it.
  final item = tester.renderObject(tab);
  final hits = tester.hitTestOnBinding(tester.getCenter(tab)).path;
  if (!hits.any((e) => e.target == item)) {
    await tester.tap(tab, warnIfMissed: false);
    await tester.pumpAndSettle();
  }
  await tester.tap(tab);
  await tester.pumpAndSettle();
}

/// Opens the side drawer (profile, net worth, money modules, settings) from
/// the current tab's header menu button.
Future<void> openMenu(WidgetTester tester) async {
  final menu = find.byTooltip('Menu');
  expect(menu, findsWidgets, reason: 'the tab header should show a menu button');
  await tester.tap(menu.first);
  await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey('app-drawer')), findsOneWidget);
}

/// [finder] limited to the open side drawer.
Finder inDrawer(Finder finder) => find.descendant(of: find.byKey(const ValueKey('app-drawer')), matching: finder);

final _verticalScrollable = find.byWidgetPredicate(
  (w) =>
      w is Scrollable &&
      (w.axisDirection == AxisDirection.down || w.axisDirection == AxisDirection.up) &&
      // Fixed-height lists nested inside a page (e.g. home "Coming up").
      !(w.restorationId?.startsWith('nested_') ?? false),
  description: 'vertical Scrollable',
);

/// Scrolls the top-most vertical list (towards the top when [up]) until
/// [finder] is built and visible.
Future<void> scrollTo(WidgetTester tester, Finder finder, {bool up = false}) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(finder, up ? -250 : 250, scrollable: _verticalScrollable.last);
  }
  await tester.ensureVisible(finder.first);
  await tester.pumpAndSettle();
}

/// Scrolls to [finder] and taps it.
Future<void> scrollAndTap(WidgetTester tester, Finder finder) async {
  await scrollTo(tester, finder);
  await tester.tap(finder.first);
  await tester.pumpAndSettle();
}

/// Types [text] into the [index]-th visible [AmountField].
Future<void> enterAmount(WidgetTester tester, String text, {int index = 0}) async {
  final field = find.descendant(of: find.byType(AmountField).at(index), matching: find.byType(EditableText));
  await tester.enterText(field, text);
  await tester.pump();
}

/// Types [text] into the [FinnTextField] labelled [label].
Future<void> enterField(WidgetTester tester, String label, String text) async {
  final field = find.descendant(of: find.widgetWithText(FinnTextField, label), matching: find.byType(EditableText));
  await scrollTo(tester, field);
  await tester.enterText(field, text);
  await tester.pump();
}

/// Approves the action review sheet ("Confirm") shown for consequential
/// actions, after checking it is really there.
Future<void> confirmReview(WidgetTester tester) async {
  // The submitting form shows a spinner underneath, so the tree never
  // "settles" while the review is open: pump frames instead.
  final confirm = find.widgetWithText(FinnButton, 'Confirm');
  for (var i = 0; i < 20 && confirm.evaluate().isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pump(const Duration(milliseconds: 500));
  expect(confirm, findsOneWidget, reason: 'the review sheet should ask for confirmation');
  await tester.tap(confirm);
  await settle(tester);
}

/// Taps the [FinnButton] labelled [label]; when several match (a sheet over
/// its screen), the top-most (last built) one.
Future<void> tapButton(WidgetTester tester, String label) async {
  final button = find.widgetWithText(FinnButton, label);
  expect(button, findsWidgets, reason: 'button "$label"');
  await tester.ensureVisible(button.last);
  await tester.pumpAndSettle();
  await tester.tap(button.last);
  await tester.pump();
}

/// Hero amounts are shown without paise.
String rupees(Money m) => MoneyFormatter.format(m, decimals: DecimalDisplay.none);

/// Finds [text] inside the home hero balance card.
Finder inHero(String text) => find.descendant(of: find.byType(HeroBalanceCard), matching: find.text(text));
