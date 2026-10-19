import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Where the serialised FiNN API session (access + refresh token) lives.
abstract interface class SessionStore {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> delete();
}

/// The platform keystore: Android Keystore-backed ciphers, the iOS/macOS
/// Keychain (this device only), and encrypted storage elsewhere.
class SecureSessionStore implements SessionStore {
  const SecureSessionStore([this._storage = const FlutterSecureStorage()]);

  static const key = 'finn.auth.session.v1';

  final FlutterSecureStorage _storage;

  static const _ios = IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device);
  static const _mac = MacOsOptions(accessibility: KeychainAccessibility.first_unlock_this_device);

  @override
  Future<String?> read() => _storage.read(key: key, iOptions: _ios, mOptions: _mac);

  @override
  Future<void> write(String value) => _storage.write(key: key, value: value, iOptions: _ios, mOptions: _mac);

  @override
  Future<void> delete() => _storage.delete(key: key, iOptions: _ios, mOptions: _mac);
}

/// In-memory store for tests.
class MemorySessionStore implements SessionStore {
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String value) async => this.value = value;

  @override
  Future<void> delete() async => value = null;
}
