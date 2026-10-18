import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/ids/id_generator.dart';
import '../../core/time/clock.dart';
import '../../core/time/dates.dart';
import '../../data/local/local_data_store.dart';
import '../../domain/finance_repositories.dart';
import '../../features/settings/domain/app_settings.dart';

/// Overridden at startup (see bootstrap.dart).
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('sharedPreferencesProvider must be overridden'),
);

/// The local mock backend. Overridden at startup and in tests.
final localDataStoreProvider = Provider<LocalDataStore>(
  (ref) => throw UnimplementedError('localDataStoreProvider must be overridden'),
);

/// Whether the app is connected to the FiNN API (`--dart-define=FINN_API_URL`,
/// see `lib/data/remote/`). False in local (mock) mode and in tests.
final remoteModeProvider = Provider<bool>((ref) => false);

final clockProvider = Provider<Clock>((ref) => const SystemClock());

final idGeneratorProvider = Provider<IdGenerator>((ref) => RandomIdGenerator());

/// Today's date; refreshes itself just after midnight so due dates and
/// "today" projections roll over without an app restart.
final todayProvider = NotifierProvider<TodayNotifier, DateTime>(TodayNotifier.new);

class TodayNotifier extends Notifier<DateTime> {
  Timer? _timer;

  @override
  DateTime build() {
    final clock = ref.watch(clockProvider);
    final now = clock.now();
    _timer?.cancel();
    final nextMidnight = DateTime(now.year, now.month, now.day + 1, 0, 0, 5);
    _timer = Timer(nextMidnight.difference(now), () => state = clock.today());
    ref.onDispose(() => _timer?.cancel());
    return now.dateOnly;
  }
}

/// Repository bundle. Replace the implementations here to connect a real
/// backend; nothing else in the app needs to change.
final financeRepositoriesProvider = Provider<FinanceRepositories>((ref) {
  final store = ref.watch(localDataStoreProvider);
  return FinanceRepositories(
    transactions: store.transactions,
    categories: store.categories,
    budgets: store.budgets,
    goals: store.goals,
    savingsMovements: store.savingsMovements,
    loans: store.loans,
    loanPayments: store.loanPayments,
    subscriptions: store.subscriptions,
    pending: store.pending,
    settlements: store.settlements,
    assets: store.assets,
    moneyAccounts: store.moneyAccounts,
    transfers: store.transfers,
    profile: store.profile,
    emergencyPlan: store.emergencyPlan,
    alertInbox: store.alertInbox,
    users: store.users,
    friends: store.friends,
    sharedLedger: store.sharedLedger,
  );
});

/// User preferences, persisted in SharedPreferences.
final settingsProvider = NotifierProvider<SettingsController, AppSettings>(SettingsController.new);

class SettingsController extends Notifier<AppSettings> {
  static const _key = 'finn.settings.v1';

  @override
  AppSettings build() {
    final raw = ref.watch(sharedPreferencesProvider).getString(_key);
    if (raw == null) return const AppSettings();
    try {
      return AppSettings.fromJson(Map<String, Object?>.from(jsonDecode(raw) as Map));
    } catch (_) {
      return const AppSettings();
    }
  }

  Future<void> update(AppSettings Function(AppSettings current) change) async {
    final next = change(state);
    if (next == state) return;
    state = next;
    await ref.read(sharedPreferencesProvider).setString(_key, jsonEncode(next.toJson()));
  }
}
