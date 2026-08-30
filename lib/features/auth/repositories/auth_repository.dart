import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:dula_auth/core/crypto/vault_crypto.dart';
import 'package:dula_auth/core/security/biometric_authenticator.dart';
import 'package:dula_auth/core/security/credential_kind.dart';
import 'package:dula_auth/core/vault/secret_store.dart';
import 'package:dula_auth/core/vault/vault_service.dart';

/// Device-side state behind unlocking: the vault, the biometric gate, and the
/// throttling counters.
///
/// Callers: `lib/features/auth/providers/auth_provider.dart` only — screens go
/// through the notifier. Data schema: the secure-store keys declared below,
/// plus the vault records owned by [VaultService].
///
/// Reworked for the user instruction "go ahead on phase 3" (ADR-0011):
/// credential-kind aware, biometrics behind an interface, and the cached vault
/// key kept only while biometric unlock is switched on.
class AuthRepository {
  final VaultService _vault;
  final SecretStore _store;
  final BiometricAuthenticator _biometrics;

  /// When the current credential was set. Read by the optional rotation
  /// policy; meaningless while that policy is off.
  static const String credentialLastSetKey = 'mfa_credential_last_set';

  /// Failed-attempt counter and lockout deadline.
  ///
  /// Held in the secure store rather than shared preferences: preferences are
  /// a plain file an attacker with device access can clear, and a lockout that
  /// can be cleared from outside the app is not a lockout.
  static const String failedAttemptsKey = 'mfa_failed_attempts';
  static const String lockoutUntilKey = 'mfa_lockout_until';

  /// The derived vault key, cached so biometric unlock can restore it.
  ///
  /// Written **only** while biometric unlock is enabled. Biometrics cannot
  /// derive a key, so this cache is what makes them possible — which also
  /// means biometric security is exactly as strong as the platform's secure
  /// storage, and no stronger (ADR-0011, docs/SECURITY_MODEL.md).
  static const String masterKeyKey = 'mfa_biometric_master_key';

  AuthRepository({
    SecretStore? store,
    VaultService? vault,
    BiometricAuthenticator? biometrics,
  })  : _store = store ?? const FlutterSecretStore(),
        _vault = vault ?? VaultService(store ?? const FlutterSecretStore()),
        _biometrics = biometrics ?? LocalAuthBiometrics();

  VaultService get vault => _vault;

  /// Whether a credential has been set up.
  Future<bool> hasCredential() => _vault.isInitialized();

  /// Which credential opens the vault. Readable while locked, so the lock
  /// screen can present the matching input.
  Future<CredentialKind> credentialKind() => _vault.credentialKind();

  /// Verifies [credential] and returns the vault key, or a failed result.
  Future<UnlockResult> unlockVault(String credential) =>
      _vault.unlock(credential);

  /// Checks a candidate credential without changing any state.
  Future<bool> verifyCredential(String credential) async =>
      (await _vault.unlock(credential)).isUnlocked;

  /// Creates a new vault protected by [credential].
  Future<MasterKey> setCredential(
    String credential,
    CredentialKind kind,
  ) async {
    final key = await _vault.initialize(credential, kind: kind);
    await _markCredentialSet();
    return key;
  }

  /// Re-keys the vault, optionally switching the credential kind at the same
  /// time. Returns false when [current] is wrong or the rewrite failed, in
  /// which case the existing credential still works.
  Future<bool> changeCredential({
    required String current,
    required String next,
    required CredentialKind kind,
  }) async {
    final changed = await _vault.changeCredential(
      currentPassword: current,
      newPassword: next,
      newKind: kind,
    );
    if (changed) await _markCredentialSet();
    return changed;
  }

  Future<void> _markCredentialSet() =>
      _store.write(credentialLastSetKey, DateTime.now().toIso8601String());

  /// Date the credential was last set, used by the optional rotation policy.
  Future<DateTime?> getCredentialLastSetDate() async {
    final raw = await _store.read(credentialLastSetKey);
    if (raw == null) return null;
    return DateTime.tryParse(raw);
  }

  /// Whether this device can perform a biometric check.
  Future<bool> canUseBiometrics() => _biometrics.isAvailable();

  Future<bool> authenticateWithBiometrics(String reason) =>
      _biometrics.authenticate(reason);

  Future<void> storeMasterKey(MasterKey key) =>
      _store.write(masterKeyKey, base64.encode(key.bytes));

  /// Restores the vault key previously cached for biometric unlock.
  Future<MasterKey?> getStoredMasterKey() async {
    final raw = await _store.read(masterKeyKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final bytes = base64.decode(raw);
      if (bytes.length != VaultCrypto.keyLength) return null;
      return MasterKey(Uint8List.fromList(bytes));
    } catch (_) {
      return null;
    }
  }

  Future<void> clearStoredMasterKey() => _store.delete(masterKeyKey);

  Future<int> getFailedAttempts() async {
    final raw = await _store.read(failedAttemptsKey);
    return int.tryParse(raw ?? '') ?? 0;
  }

  Future<void> setFailedAttempts(int count) =>
      _store.write(failedAttemptsKey, '$count');

  Future<DateTime?> getLockoutUntil() async {
    final raw = await _store.read(lockoutUntilKey);
    if (raw == null) return null;
    return DateTime.tryParse(raw);
  }

  Future<void> setLockoutUntil(DateTime? until) async {
    if (until == null) {
      await _store.delete(lockoutUntilKey);
    } else {
      await _store.write(lockoutUntilKey, until.toIso8601String());
    }
  }

  /// Wipes the vault and every piece of auth state that depends on it.
  Future<void> clearAuthData() async {
    await _vault.reset();
    await _store.delete(credentialLastSetKey);
    await _store.delete(failedAttemptsKey);
    await _store.delete(lockoutUntilKey);
    await clearStoredMasterKey();
  }
}
