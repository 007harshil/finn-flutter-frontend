import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'app/di/core_providers.dart';
import 'core/persistence/persistence_driver.dart';
import 'core/time/clock.dart';
import 'data/local/local_data_store.dart';
import 'data/remote/api_config.dart';
import 'data/remote/remote_bootstrap.dart';
import 'features/export/application/export_file_sink.dart';

/// Dataset used on first launch: `--dart-define=FINN_SCENARIO=empty|demo|stressed`.
const _scenarioName = String.fromEnvironment('FINN_SCENARIO', defaultValue: 'demo');

/// Simulated repository latency in ms: `--dart-define=FINN_LATENCY_MS=600`.
const _latencyMs = int.fromEnvironment('FINN_LATENCY_MS', defaultValue: 250);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Diagnostics can include amounts, names and API errors: keep them out of
  // logcat in store builds.
  if (kReleaseMode) debugPrint = (String? message, {int? wrapWidth}) {};
  final prefs = await SharedPreferences.getInstance();
  // Exports from an earlier session (e.g. the app was closed mid-share).
  unawaited(ShareExportFileSink.purge());

  // Connected mode by default (https://finn-backend.vercel.app); override with
  // `--dart-define=FINN_API_URL=https://...`, or empty for the local mock.
  const api = ApiConfig.fromEnvironment();
  if (api.enabled) {
    runApp(await bootstrapRemoteApp(config: api, prefs: prefs, app: const FinnApp()));
    return;
  }

  final scenario = DataScenario.values.firstWhere((s) => s.name == _scenarioName, orElse: () => DataScenario.demo);
  final store = LocalDataStore(
    driver: SharedPreferencesDriver(prefs),
    behavior: MockBehavior(latency: const Duration(milliseconds: _latencyMs)),
  );
  await store.open(scenario: scenario, today: const SystemClock().today());

  runApp(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs), localDataStoreProvider.overrideWithValue(store)],
      child: const FinnApp(),
    ),
  );
}
