import 'dart:async';

import 'package:dula_auth/core/vault/secret_store.dart';

/// A memoised "is the credential store reachable?" verdict.
///
/// Callers: [GatedSecretStore] consults it before every call;
/// `lib/core/widgets/app_lifecycle_wrapper.dart` calls [reset] from the
/// error screen's RETRY and on app resume so a keyring started since is
/// picked up. No data of its own.
///
/// Why this exists (ADR-0018): on Linux, `flutter_secure_storage` makes
/// *synchronous* libsecret calls on the GTK platform thread — the same thread
/// the Dart UI isolate runs on for desktop embedders. With no Secret Service
/// on the session bus that call blocks the whole app, and nothing on the Dart
/// side (timeouts, background isolates) can interrupt it, because the thread
/// that would run the timeout is the one that is stuck. The only safe move is
/// to never make the call unless the service is known to be there, which is
/// what this gate decides — cheaply, and asynchronously — up front.
class SecretStoreGate {
  final Future<bool> Function() _check;
  Future<bool>? _verdict;

  SecretStoreGate(this._check);

  /// For platforms whose credential store has no such failure mode.
  static final SecretStoreGate alwaysOpen = SecretStoreGate(() async => true);

  /// Whether the store may be entered. The first call runs the check and
  /// every later call (including ones that overlap the first) reuses its
  /// result until [reset]. A check that throws is a closed gate: an error
  /// from the probe is not evidence the backend is safe to enter.
  Future<bool> isOpen() {
    return _verdict ??= _check().then((ok) => ok, onError: (_) => false);
  }

  /// Forgets the verdict so the next call re-runs the check.
  void reset() => _verdict = null;
}

/// A [SecretStore] that refuses to enter its backend while the gate is closed.
///
/// Every operation throws [SecretStoreUnavailableException] instead of
/// touching [_inner] when the gate reports the store unreachable, so the
/// freezing call is never issued. Callers: constructed in
/// `lib/core/vault/secret_store_provider.dart` on Linux only.
class GatedSecretStore implements SecretStore {
  final SecretStore _inner;
  final SecretStoreGate _gate;

  GatedSecretStore(this._inner, this._gate);

  Future<void> _ensureOpen() async {
    if (!await _gate.isOpen()) {
      throw const SecretStoreUnavailableException(
        'No Secret Service (org.freedesktop.secrets) is reachable on the '
        'session bus; refusing to call libsecret, which would block.',
      );
    }
  }

  @override
  Future<String?> read(String key) async {
    await _ensureOpen();
    return _inner.read(key);
  }

  @override
  Future<void> write(String key, String value) async {
    await _ensureOpen();
    return _inner.write(key, value);
  }

  @override
  Future<void> delete(String key) async {
    await _ensureOpen();
    return _inner.delete(key);
  }
}
