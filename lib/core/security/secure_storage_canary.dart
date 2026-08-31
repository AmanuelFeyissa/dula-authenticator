import 'package:flutter/material.dart' show TargetPlatform;

import 'package:dula_auth/core/vault/secret_store.dart';

/// Whether the Linux-keyring gap this canary exists for (ADR-0004) applies to
/// [platform]. Every other platform's secret store (Keystore, Keychain,
/// DPAPI) does not depend on an optional, separately-running daemon the way
/// libsecret does, so the extra startup check would only add latency there.
bool secureStorageCanaryAppliesOn(TargetPlatform platform) =>
    platform == TargetPlatform.linux;

/// Verifies the platform secret store can actually persist data.
///
/// A missing Linux keyring daemon (GNOME Keyring, KWallet) makes
/// `flutter_secure_storage` fail outright or silently accept writes that
/// never land, which would otherwise surface as an inexplicable lockout or
/// data loss much later. This performs a real write/read/delete round trip
/// during startup so that failure is caught immediately, before the app
/// lets the user set a credential it cannot durably store (ADR-0004).
class SecureStorageCanary {
  static const _key = '_secure_storage_canary_probe';

  static Future<bool> check(SecretStore store) async {
    try {
      const probe = 'ok';
      await store.write(_key, probe);
      final readBack = await store.read(_key);
      await store.delete(_key);
      return readBack == probe;
    } catch (_) {
      return false;
    }
  }
}
