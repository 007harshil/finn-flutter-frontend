import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/core_providers.dart';
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
    final today = _ref.read(clockProvider).today();
    await _ref.read(localDataStoreProvider).reseed(DataScenario.demo, today);
  }

  /// Deletes every record and returns the app to first-run setup.
  Future<void> eraseEverything() async {
    final today = _ref.read(clockProvider).today();
    await _ref.read(localDataStoreProvider).reseed(DataScenario.empty, today);
    await _ref.read(settingsProvider.notifier).update((s) => s.copyWith(onboardingComplete: false));
  }
}

final dataResetServiceProvider = Provider<DataResetService>((ref) => DataResetService(ref));
