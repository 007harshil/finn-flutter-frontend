import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/action_providers.dart';
import '../../../app/di/core_providers.dart';
import '../../../core/result/result.dart';
import '../../../core/time/clock.dart';
import '../../../data/local/local_data_store.dart';

/// Device-level data management for the local (mock) backend. These are
/// whole-dataset operations, not individual financial actions, so they do
/// not go through the action dispatcher (onboarding uses the same path).
class DataResetService {
  DataResetService(this._ref);
  final Ref _ref;

  /// Replaces everything on this device with the sample dataset.
  Future<void> loadSampleData() async {
    _ensureLocal('Sample data is only available when FiNN runs without an account connection.');
    final today = _ref.read(clockProvider).today();
    await _ref.read(localDataStoreProvider).reseed(DataScenario.demo, today);
  }

  /// Deletes every record and returns the app to first-run setup.
  Future<void> eraseEverything() async {
    _ensureLocal('Your records are stored in your FiNN account. Delete them individually while connected.');
    final today = _ref.read(clockProvider).today();
    await _ref.read(localDataStoreProvider).reseed(DataScenario.empty, today);
    await _ref.read(settingsProvider.notifier).update((s) => s.copyWith(onboardingComplete: false));
  }

  /// Forgets everything FiNN keeps on this device (records, settings,
  /// sessions, sync caches) and returns the app to first-run setup. Runs
  /// after the account is deleted, in both modes.
  Future<void> wipeDevice() async {
    final prefs = _ref.read(sharedPreferencesProvider);
    for (final key in prefs.getKeys().where((k) => k.startsWith('finn.')).toList()) {
      await prefs.remove(key);
    }
    // Empty records, persisted, so a restart does not seed the sample data.
    final today = _ref.read(clockProvider).today();
    await _ref.read(localDataStoreProvider).reseed(DataScenario.empty, today);
    _ref.invalidate(settingsProvider);
    _ref.invalidate(auditLogProvider);
  }

  /// Whole-dataset resets apply to the local mock only; a connected account
  /// is changed through actions.
  void _ensureLocal(String message) {
    if (_ref.read(remoteModeProvider)) throw AppFailure(FailureCode.notPermitted, message);
  }
}

final dataResetServiceProvider = Provider<DataResetService>((ref) => DataResetService(ref));
