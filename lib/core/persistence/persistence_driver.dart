import 'package:shared_preferences/shared_preferences.dart';

/// Key-value byte sink used by local repositories. A future backend
/// integration replaces repositories, not this driver.
abstract interface class PersistenceDriver {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class SharedPreferencesDriver implements PersistenceDriver {
  SharedPreferencesDriver(this._prefs);

  final SharedPreferences _prefs;
  static const _prefix = 'finn.data.';

  @override
  Future<String?> read(String key) async => _prefs.getString('$_prefix$key');

  @override
  Future<void> write(String key, String value) => _prefs.setString('$_prefix$key', value);

  @override
  Future<void> delete(String key) => _prefs.remove('$_prefix$key');
}

/// Volatile driver for tests and demo scenarios.
class MemoryDriver implements PersistenceDriver {
  final Map<String, String> store = {};

  @override
  Future<String?> read(String key) async => store[key];

  @override
  Future<void> write(String key, String value) async => store[key] = value;

  @override
  Future<void> delete(String key) async => store.remove(key);
}

/// Simulated network characteristics for mock repositories, so loading and
/// error states can be exercised deterministically.
class MockBehavior {
  MockBehavior({this.latency = Duration.zero, this.failReads = false, this.failWrites = false});

  Duration latency;
  bool failReads;
  bool failWrites;
}
