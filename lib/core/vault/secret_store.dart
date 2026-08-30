import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// A narrow key/value interface over OS-native secure storage.
///
/// The app depends on this rather than on `FlutterSecureStorage` directly so
/// that vault logic — key derivation, credential verification and the v1→v2
/// migration — can be tested against an in-memory double instead of a
/// platform plugin.
abstract class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// Production [SecretStore] backed by the platform credential store
/// (Windows Credential Manager, Android Keystore, iOS/macOS Keychain,
/// libsecret on Linux — see ADR-0004).
class FlutterSecretStore implements SecretStore {
  final FlutterSecureStorage _storage;

  const FlutterSecretStore([
    this._storage = const FlutterSecureStorage(),
  ]);

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// In-memory [SecretStore] for tests.
///
/// [failWritesTo] simulates a storage failure mid-migration, which the vault
/// must survive without corrupting or half-upgrading the user's data.
class InMemorySecretStore implements SecretStore {
  final Map<String, String> _values;
  final Set<String> _failingKeys = <String>{};

  InMemorySecretStore([Map<String, String>? initial])
      : _values = {...?initial};

  void failWritesTo(String key) => _failingKeys.add(key);

  Map<String, String> dump() => Map.unmodifiable(_values);

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    if (_failingKeys.contains(key)) {
      throw StateError('simulated secure-storage failure for "$key"');
    }
    _values[key] = value;
  }

  @override
  Future<void> delete(String key) async => _values.remove(key);
}
