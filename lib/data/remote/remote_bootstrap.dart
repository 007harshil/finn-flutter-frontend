import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/di/core_providers.dart';
import '../../core/persistence/persistence_driver.dart';
import '../../core/time/clock.dart';
import '../../features/auth/application/auth_controller.dart';
import '../../features/auth/data/backend_auth_service.dart';
import '../../features/auth/data/session_store.dart';
import '../../features/auth/domain/auth_session.dart';
import '../local/local_data_store.dart';
import 'api_client.dart';
import 'api_config.dart';
import 'remote_import.dart';
import 'remote_providers.dart';
import 'remote_repositories.dart';
import 'remote_session_scope.dart';
import 'sync_engine.dart';

/// Starts the app connected to the FiNN API: restores the stored FiNN
/// session and the signed-in user's offline cache (so repositories are hydrated before
/// the first frame) and wraps [app] with the remote overrides.
Future<Widget> bootstrapRemoteApp({
  required ApiConfig config,
  required SharedPreferences prefs,
  required Widget app,
}) async {
  final apiAuth = BackendApiAuth(config: config, prefs: prefs, store: const SecureSessionStore());
  await apiAuth.restore();
  final api = ApiClient(config: config, auth: apiAuth);
  final engine = SyncEngine(api: api, prefs: prefs);

  // Data created on this device in local mode, offered for upload once.
  final local = LocalDataStore(driver: SharedPreferencesDriver(prefs));
  final hasLocal = await local.loadExisting();

  // The app's sign-in state follows the stored FiNN session.
  final userId = apiAuth.userId;
  if (apiAuth.session == null || userId == null) {
    await prefs.remove(AuthController.storageKey);
    // The session ended while the app was closed: drop its offline cache
    // (kept when the keystore was only unreadable this launch).
    if (!apiAuth.restoreFailed) await engine.close();
  } else {
    if (prefs.getString(AuthController.storageKey) == null) {
      final session = AuthSession(email: apiAuth.email ?? '', signedInAt: const SystemClock().now());
      await prefs.setString(AuthController.storageKey, jsonEncode(session.toJson()));
    }
    await engine.open(userId);
  }

  final backend = RemoteBackend(
    config: config,
    prefs: prefs,
    auth: apiAuth,
    authService: BackendAuthService(auth: apiAuth, clock: const SystemClock(), api: api),
    api: api,
    engine: engine,
    repositories: buildRemoteRepositories(engine, api),
    importer: RemoteImporter(api: api, engine: engine, local: hasLocal ? local : null),
  );
  debugPrint('FiNN connected to ${config.baseUrl}');

  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      localDataStoreProvider.overrideWithValue(local),
      ...remoteOverrides(backend),
    ],
    child: RemoteSessionScope(child: app),
  );
}
