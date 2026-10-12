import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/di/action_providers.dart';
import '../../app/di/core_providers.dart';
import '../../domain/finance_repositories.dart';
import '../../features/auth/application/auth_controller.dart';
import '../../features/auth/data/supabase_auth_service.dart';
import 'api_client.dart';
import 'api_config.dart';
import 'remote_dispatcher.dart';
import 'remote_import.dart';
import 'sync_engine.dart';

/// Everything the remote mode is built from. Null in local mode.
final remoteBackendProvider = Provider<RemoteBackend?>((ref) => null);

/// The connected backend: API client, sync engine and repositories.
class RemoteBackend {
  RemoteBackend({
    required this.config,
    required this.prefs,
    required this.auth,
    required this.authService,
    required this.api,
    required this.engine,
    required this.repositories,
    required this.importer,
  });

  final ApiConfig config;
  final SharedPreferences prefs;
  final SupabaseApiAuth auth;
  final SupabaseAuthService authService;
  final ApiClient api;
  final SyncEngine engine;
  final FinanceRepositories repositories;
  final RemoteImporter importer;
}

/// Provider overrides that switch the app to [backend].
List<Override> remoteOverrides(RemoteBackend backend) => [
      remoteModeProvider.overrideWithValue(true),
      remoteBackendProvider.overrideWithValue(backend),
      financeRepositoriesProvider.overrideWithValue(backend.repositories),
      authServiceProvider.overrideWithValue(backend.authService),
      actionDispatcherProvider.overrideWith((ref) => RemoteOperationDispatcher(
            environment: ref.watch(actionEnvironmentProvider),
            audit: ref.watch(auditLogProvider),
            api: backend.api,
            engine: backend.engine,
          )),
      auditEntriesProvider.overrideWith((ref) => watchRemoteAudit(backend.api, backend.engine)),
    ];
