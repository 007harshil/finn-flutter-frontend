import 'package:finn/app/app.dart';
import 'package:finn/app/di/core_providers.dart';
import 'package:finn/core/ids/id_generator.dart';
import 'package:finn/core/persistence/persistence_driver.dart';
import 'package:finn/core/time/clock.dart';
import 'package:finn/data/local/local_data_store.dart';
import 'package:finn/design_system/design_system.dart';
import 'package:finn/domain/finance_repositories.dart';
import 'package:finn/finance/finance_snapshot.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Fixed "today" used by all tests: Saturday 10 Oct 2026, 09:00.
final testNow = DateTime(2026, 10, 10, 9);

/// A fully wired, in-memory test environment (no latency, deterministic).
class TestEnv {
  TestEnv._(this.store, this.prefs, this.clock, this.ids);

  final LocalDataStore store;
  final SharedPreferences prefs;
  final FixedClock clock;
  final SequentialIdGenerator ids;

  static Future<TestEnv> create({
    DataScenario scenario = DataScenario.demo,
    bool onboarded = true,
    bool signedIn = true,
    Map<String, Object> prefsValues = const {},
  }) async {
    SharedPreferences.setMockInitialValues({
      if (onboarded) 'finn.settings.v1': '{"onboardingComplete":true,"motion":"reduced"}',
      if (signedIn) 'finn.auth.v1': '{"email":"aarav@example.com","signedInAt":"2026-10-01T09:00:00.000"}',
      ...prefsValues,
    });
    final prefs = await SharedPreferences.getInstance();
    final clock = FixedClock(testNow);
    final store = LocalDataStore(driver: MemoryDriver());
    await store.open(scenario: scenario, today: clock.today(), forceSeed: true);
    return TestEnv._(store, prefs, clock, SequentialIdGenerator());
  }

  List<Override> get overrides => [
        sharedPreferencesProvider.overrideWithValue(prefs),
        localDataStoreProvider.overrideWithValue(store),
        clockProvider.overrideWithValue(clock),
        idGeneratorProvider.overrideWithValue(ids),
      ];

  ProviderContainer container() => ProviderContainer(overrides: overrides);

  FinanceRepositories get repos => FinanceRepositories(
        transactions: store.transactions, categories: store.categories, budgets: store.budgets,
        goals: store.goals, savingsMovements: store.savingsMovements, loans: store.loans,
        loanPayments: store.loanPayments, subscriptions: store.subscriptions, pending: store.pending,
        settlements: store.settlements, assets: store.assets, moneyAccounts: store.moneyAccounts, transfers: store.transfers, profile: store.profile,
        emergencyPlan: store.emergencyPlan, alertInbox: store.alertInbox,
        users: store.users, friends: store.friends, sharedLedger: store.sharedLedger,
      );

  Future<FinanceSnapshot> snapshot() => repos.loadSnapshot(clock, monthStartDay: 1);

  /// Pumps a single widget inside theme + providers (no router).
  Future<void> pumpWidget(WidgetTester tester, Widget child, {ThemeData? theme}) async {
    await tester.pumpWidget(ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: theme ?? FinnTheme.light(),
        home: MotionScope(reduceMotion: true, child: Scaffold(body: child)),
      ),
    ));
    await tester.pump();
  }

  /// Pumps the full application (router, shell, onboarding redirect).
  Future<void> pumpApp(WidgetTester tester, {Size size = const Size(400, 860)}) async {
    tester.view.physicalSize = size * tester.view.devicePixelRatio;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(ProviderScope(overrides: overrides, child: const FinnApp()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }
}
