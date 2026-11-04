// Screenshot capture for design review (not part of the normal test suite).
//
// Pumps the real app on seeded demo data, routes to every screen and writes
// one PNG per screen. Run from the repo root:
//
//   flutter test tool/screenshots/capture_test.dart \
//     --dart-define=SHOT_DIR=docs/redesign/screens/before --dart-define=SHOT_THEME=light
//
// SHOT_THEME is `light` or `dark`. Layout errors are logged, not fatal, so a
// broken screen still gets captured and reported.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:finn/app/app.dart';
import 'package:finn/app/router/app_router.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test/helpers/test_app.dart';

const _dir = String.fromEnvironment('SHOT_DIR', defaultValue: 'docs/redesign/screens/before');
const _theme = String.fromEnvironment('SHOT_THEME', defaultValue: 'light');
const _size = Size(412, 915);
const _ratio = 2.0;

final _root = GlobalKey();

Future<void> _loadFonts() async {
  final manifest = json.decode(await rootBundle.loadString('FontManifest.json')) as List<dynamic>;
  for (final entry in manifest.cast<Map<String, dynamic>>()) {
    final family = entry['family'] as String;
    final loader = FontLoader(family);
    for (final font in (entry['fonts'] as List).cast<Map<String, dynamic>>()) {
      loader.addFont(rootBundle.load(font['asset'] as String));
    }
    await loader.load();
  }
  // Material widgets without an explicit family fall back to Roboto, which
  // flutter_test does not ship; render them in the app font instead.
  final roboto = FontLoader('Roboto')..addFont(rootBundle.load('assets/fonts/Manrope.ttf'));
  await roboto.load();
}

String _settings({bool onboarded = true}) =>
    '{"onboardingComplete":$onboarded,"motion":"reduced","agentConsent":true,"theme":"$_theme"}';

Future<void> _pump(WidgetTester tester, TestEnv env) async {
  tester.view.physicalSize = _size * _ratio;
  tester.view.devicePixelRatio = _ratio;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: env.overrides,
    child: RepaintBoundary(key: _root, child: const FinnApp()),
  ));
  await _settle(tester);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

Future<void> _shot(WidgetTester tester, String name) async {
  final error = tester.takeException();
  if (error != null) {
    // ignore: avoid_print
    print('LAYOUT-ISSUE [$name]: ${error.toString().split('\n').first}');
  }
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(_root));
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: _ratio);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('$_dir/$_theme/$name.png')..createSync(recursive: true);
    file.writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

Future<void> _visit(WidgetTester tester, String route, String name) async {
  final container = ProviderScope.containerOf(tester.element(find.byType(FinnApp)));
  container.read(routerProvider).go(route);
  await _settle(tester);
  await _shot(tester, name);
}

void main() {
  setUpAll(_loadFonts);

  testWidgets('signed-out and first-run screens', (tester) async {
    final out = await TestEnv.create(signedIn: false, prefsValues: {'finn.settings.v1': _settings()});
    await _pump(tester, out);
    await _shot(tester, '00_login');
    await _visit(tester, '/login/verify?email=aarav%40example.com', '01_verify_otp');
  });

  testWidgets('onboarding', (tester) async {
    final env = await TestEnv.create(prefsValues: {'finn.settings.v1': _settings(onboarded: false)});
    await _pump(tester, env);
    await _shot(tester, '02_onboarding');
  });

  testWidgets('signed-in screens', (tester) async {
    final env = await TestEnv.create(prefsValues: {'finn.settings.v1': _settings()});
    final repos = env.repos;
    late final String tx, budget, goal, sub, pending, account;
    await tester.runAsync(() async {
      tx = (await repos.transactions.getAll()).first.id;
      budget = (await repos.budgets.getAll()).first.id;
      goal = (await repos.goals.getAll()).first.id;
      sub = (await repos.subscriptions.getAll()).first.id;
      pending = (await repos.pending.getAll()).first.id;
      account = (await repos.moneyAccounts.getAll()).first.id;
    });
    await _pump(tester, env);

    final routes = <String, String>{
      '10_home': '/home',
      '11_alerts': '/home/alerts',
      '12_timeline': '/home/timeline',
      '20_transactions': '/transactions',
      '21_transaction_detail': '/transactions/$tx',
      '22_add_expense': '/transactions/new?type=expense',
      '23_add_income': '/transactions/new?type=income',
      '30_budgets': '/budgets',
      '31_budget_detail': '/budgets/$budget',
      '32_new_budget': '/budgets/new',
      '40_goals': '/goals',
      '41_goal_detail': '/goals/$goal',
      '42_goal_contribute': '/goals/$goal/move?kind=contribute',
      '43_emergency_fund': '/goals/emergency-fund',
      '44_emergency_plan': '/goals/emergency-fund/plan',
      '50_more': '/more',
      '51_account': '/more/account',
      '52_friends': '/more/friends',
      '53_loans': '/more/loans',
      '54_loan_detail': '/more/loans/loan_seed_car',
      '55_loan_pay': '/more/loans/loan_seed_car/pay',
      '56_subscriptions': '/more/subscriptions',
      '57_subscription_detail': '/more/subscriptions/$sub',
      '58_pending': '/more/pending',
      '59_pending_detail': '/more/pending/$pending',
      '60_new_pending': '/more/pending/new',
      '61_accounts': '/more/accounts',
      '62_account_detail': '/more/accounts/$account',
      '63_analytics': '/more/analytics',
      '64_net_worth': '/more/net-worth',
      '70_settings': '/more/settings',
      '71_profile': '/more/settings/profile',
      '72_categories': '/more/settings/categories',
      '73_export': '/more/settings/export',
      '74_notifications': '/more/settings/notifications',
      '75_activity_log': '/more/settings/activity',
      '80_assistant': '/assistant',
    };
    for (final MapEntry(key: name, value: route) in routes.entries) {
      await _visit(tester, route, name);
    }

    // Insights, daily spend topic (the scrub-able running-spend chart).
    final container = ProviderScope.containerOf(tester.element(find.byType(FinnApp)));
    container.read(routerProvider).go('/more/analytics');
    await _settle(tester);
    await tester.tap(find.byKey(const Key('insights-chip:spending')));
    await _settle(tester);
    await _shot(tester, '63b_insights_spending');
  });
}
