import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dula_auth/core/crypto/vault_crypto.dart';
import 'package:dula_auth/core/vault/secret_store.dart';
import 'package:dula_auth/core/vault/vault_service.dart';

class AuthRepository {
  final VaultService _vault;
  final SecretStore _store;
  final LocalAuthentication _localAuth;

  static const String _pinLastSetKey = 'mfa_pin_last_set';
  static const String _useBiometricsKey = 'mfa_use_biometrics';
  static const String _failedAttemptsKey = 'mfa_failed_attempts';
  static const String _lockoutUntilKey = 'mfa_lockout_until';

  /// Stores the derived vault key so biometric unlock can restore it without
  /// re-deriving from the credential. Biometric security is therefore exactly
  /// as strong as the platform's secure storage — see ADR-0011.
  static const String _masterKeyKey = 'mfa_biometric_master_key';

  AuthRepository({
    SecretStore? store,
    VaultService? vault,
    LocalAuthentication? localAuth,
  })  : _store = store ?? const FlutterSecretStore(),
        _vault = vault ?? VaultService(store ?? const FlutterSecretStore()),
        _localAuth = localAuth ?? LocalAuthentication();

  VaultService get vault => _vault;

  /// Whether a credential has been set up (in either vault version).
  Future<bool> hasPinSet() => _vault.isInitialized();

  /// Verifies [pin] and returns the vault key, migrating a legacy vault if
  /// needed. Returns a failed result when the credential is wrong.
  Future<UnlockResult> unlockVault(String pin) => _vault.unlock(pin);

  /// Creates a new vault protected by [pin].
  Future<MasterKey> setPin(String pin) async {
    final key = await _vault.initialize(pin);
    await _store.write(_pinLastSetKey, DateTime.now().toIso8601String());
    return key;
  }

  /// Checks a candidate credential without changing any state.
  Future<bool> verifyPin(String pin) async {
    final result = await _vault.unlock(pin);
    return result.isUnlocked;
  }

  /// Date the credential was last set, used by the optional rotation policy.
  Future<DateTime?> getPinLastSetDate() async {
    final raw = await _store.read(_pinLastSetKey);
    if (raw == null) return null;
    return DateTime.tryParse(raw);
  }

  Future<bool> isBiometricsEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_useBiometricsKey) ?? false;
  }

  Future<void> setBiometricsEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_useBiometricsKey, enabled);
  }

  /// Whether the device can perform biometric authentication.
  Future<bool> canUseBiometrics() async {
    // local_auth has no web implementation; treat web as unsupported.
    if (kIsWeb) return false;
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      return canCheck || await _localAuth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  Future<void> storeMasterKey(MasterKey key) =>
      _store.write(_masterKeyKey, base64.encode(key.bytes));

  /// Restores the vault key previously cached for biometric unlock.
  Future<MasterKey?> getStoredMasterKey() async {
    final raw = await _store.read(_masterKeyKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final bytes = base64.decode(raw);
      if (bytes.length != VaultCrypto.keyLength) return null;
      return MasterKey(Uint8List.fromList(bytes));
    } catch (_) {
      return null;
    }
  }

  Future<void> clearStoredMasterKey() => _store.delete(_masterKeyKey);

  Future<bool> authenticateWithBiometrics(String localizedReason) async {
    if (kIsWeb) return false;
    try {
      return await _localAuth.authenticate(
        localizedReason: localizedReason,
        options: const AuthenticationOptions(
          // Only biometrics: the app has its own credential, so falling back
          // to the device passcode would weaken the gate.
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }

  Future<int> getFailedAttempts() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_failedAttemptsKey) ?? 0;
  }

  Future<void> setFailedAttempts(int count) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_failedAttemptsKey, count);
  }

  Future<DateTime?> getLockoutUntil() async {
    final prefs = await SharedPreferences.getInstance();
    final timestamp = prefs.getInt(_lockoutUntilKey);
    if (timestamp == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(timestamp);
  }

  Future<void> setLockoutUntil(DateTime? until) async {
    final prefs = await SharedPreferences.getInstance();
    if (until == null) {
      await prefs.remove(_lockoutUntilKey);
    } else {
      await prefs.setInt(_lockoutUntilKey, until.millisecondsSinceEpoch);
    }
  }

  /// Wipes the vault and all auth state.
  Future<void> clearAuthData() async {
    await _vault.reset();
    await _store.delete(_pinLastSetKey);
    await clearStoredMasterKey();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_useBiometricsKey);
    await prefs.remove(_failedAttemptsKey);
    await prefs.remove(_lockoutUntilKey);
  }
}
