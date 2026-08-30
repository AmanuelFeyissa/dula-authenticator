import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dula_auth/core/crypto/vault_crypto.dart';
import 'package:dula_auth/core/security/credential_kind.dart';
import 'package:dula_auth/core/security/credential_policy.dart';
import 'package:dula_auth/core/settings/app_settings.dart';
import 'package:dula_auth/features/auth/repositories/auth_repository.dart';
import 'package:dula_auth/features/home/providers/home_provider.dart';
import 'package:dula_auth/features/settings/providers/settings_provider.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository();
});

final authStateProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(ref.read(authRepositoryProvider), ref);
});

class AuthState {
  /// Vault closed; no key in memory.
  final bool isLocked;

  /// No credential exists yet, so the app is in first-run setup.
  final bool isSetupRequired;

  /// Which credential the vault expects, so the lock screen can present a
  /// keypad or a text field.
  final CredentialKind credentialKind;

  /// Whether this device can perform biometrics at all. Distinct from the
  /// user's preference: a device may support it while the user declines it.
  final bool biometricsAvailable;

  /// The optional rotation policy says this credential is due for renewal.
  /// Always false while that policy is disabled, which is the default.
  final bool isCredentialExpired;

  /// The expired credential has been verified, so a replacement may be set.
  final bool isVerifiedForRotation;

  final int failedAttempts;
  final DateTime? lockoutUntil;
  final DateTime? lastSetDate;
  final MasterKey? masterKey;

  AuthState({
    required this.isLocked,
    required this.isSetupRequired,
    this.credentialKind = CredentialKind.pin,
    this.biometricsAvailable = false,
    this.isCredentialExpired = false,
    this.isVerifiedForRotation = false,
    this.failedAttempts = 0,
    this.lockoutUntil,
    this.lastSetDate,
    this.masterKey,
  });

  bool get isLockedOut =>
      lockoutUntil != null && lockoutUntil!.isAfter(DateTime.now());

  AuthState copyWith({
    bool? isLocked,
    bool? isSetupRequired,
    CredentialKind? credentialKind,
    bool? biometricsAvailable,
    bool? isCredentialExpired,
    bool? isVerifiedForRotation,
    int? failedAttempts,
    DateTime? lockoutUntil,
    DateTime? lastSetDate,
    MasterKey? masterKey,
    bool clearLockout = false,
    bool clearMasterKey = false,
    bool clearRotation = false,
  }) {
    return AuthState(
      isLocked: isLocked ?? this.isLocked,
      isSetupRequired: isSetupRequired ?? this.isSetupRequired,
      credentialKind: credentialKind ?? this.credentialKind,
      biometricsAvailable: biometricsAvailable ?? this.biometricsAvailable,
      isCredentialExpired:
          clearRotation ? false : (isCredentialExpired ?? this.isCredentialExpired),
      isVerifiedForRotation: clearRotation
          ? false
          : (isVerifiedForRotation ?? this.isVerifiedForRotation),
      failedAttempts: failedAttempts ?? this.failedAttempts,
      lockoutUntil: clearLockout ? null : (lockoutUntil ?? this.lockoutUntil),
      lastSetDate: lastSetDate ?? this.lastSetDate,
      masterKey: clearMasterKey ? null : (masterKey ?? this.masterKey),
    );
  }
}

/// Owns unlocking: credential setup, verification, throttling, and the
/// biometric path.
///
/// Callers: `lib/features/auth/screens/**`, `lib/core/widgets/
/// app_lifecycle_wrapper.dart`, `lib/features/home/providers/home_provider.dart`
/// (reads the master key). Data schema: none directly — it goes through
/// [AuthRepository] and [SettingsNotifier].
///
/// Reworked for the user instruction "go ahead on phase 3", implementing
/// ADR-0011: the credential is a PIN *or* a passphrase, biometrics are an
/// opt-in convenience over the top, and forced rotation is a policy a
/// deployment turns on rather than something every user endures.
class AuthNotifier extends StateNotifier<AuthState> {
  final AuthRepository _repository;
  final Ref _ref;

  late final Future<void> _ready;

  AuthNotifier(this._repository, this._ref)
      : super(AuthState(isLocked: true, isSetupRequired: false)) {
    _ready = _checkInitialState();
  }

  /// Completes once startup state has been read from the device.
  Future<void> get ready => _ready;

  /// The settings this notifier is currently operating under.
  AppSettings get settings => _ref.read(settingsProvider);

  Future<void> _checkInitialState() async {
    // Rotation and biometrics are policy questions, so the stored settings
    // must be in hand before either is decided — acting on defaults here is
    // how the app ends up enforcing a policy nobody enabled.
    await _ref.read(settingsProvider.notifier).ready;

    final hasCredential = await _repository.hasCredential();
    final biometricsAvailable = await _repository.canUseBiometrics();

    if (!hasCredential) {
      state = state.copyWith(
        isLocked: false,
        isSetupRequired: true,
        biometricsAvailable: biometricsAvailable,
        failedAttempts: 0,
        clearLockout: true,
        clearRotation: true,
      );
      return;
    }

    final kind = await _repository.credentialKind();
    final lastSetDate = await _repository.getCredentialLastSetDate();
    final failedAttempts = await _repository.getFailedAttempts();
    final lockoutUntil = await _repository.getLockoutUntil();

    state = state.copyWith(
      isLocked: true,
      isSetupRequired: false,
      credentialKind: kind,
      biometricsAvailable: biometricsAvailable,
      isCredentialExpired: settings.isCredentialExpired(lastSetDate),
      failedAttempts: failedAttempts,
      lockoutUntil: lockoutUntil,
      lastSetDate: lastSetDate,
    );

    // The biometric prompt is deliberately not fired here. The lock screen
    // owns that, so there is exactly one place it can be triggered from and
    // the user never gets two prompts racing each other.
  }

  void lock() {
    if (!state.isSetupRequired) {
      state = state.copyWith(
        isLocked: true,
        clearMasterKey: true,
        clearRotation: true,
      );
    }
  }

  void unlock() {
    state = state.copyWith(isLocked: false);
  }

  /// Verifies [credential] and opens the vault.
  Future<bool> unlockWithCredential(String credential) async {
    if (state.isLockedOut) return false;

    final result = await _repository.unlockVault(credential);

    if (result.isUnlocked) {
      final key = result.key!;
      await _repository.setFailedAttempts(0);
      await _repository.setLockoutUntil(null);
      await _syncCachedKey(key);

      if (state.isCredentialExpired) {
        // Correct but expired: allow rotation without opening the vault.
        state = state.copyWith(
          failedAttempts: 0,
          clearLockout: true,
          isVerifiedForRotation: true,
          masterKey: key,
        );
        return true;
      }

      // Single atomic update: key and unlocked state together, so account
      // loading never observes an unlocked state without a key.
      state = state.copyWith(
        failedAttempts: 0,
        clearLockout: true,
        masterKey: key,
        isLocked: false,
      );
      return true;
    }

    final newAttempts = state.failedAttempts + 1;
    await _repository.setFailedAttempts(newAttempts);

    DateTime? lockoutUntil;
    if (newAttempts >= 10) {
      lockoutUntil = DateTime.now().add(const Duration(hours: 1));
    } else if (newAttempts >= 5) {
      lockoutUntil = DateTime.now().add(const Duration(minutes: 5));
    } else if (newAttempts >= 3) {
      lockoutUntil = DateTime.now().add(const Duration(seconds: 30));
    }

    if (lockoutUntil != null) {
      await _repository.setLockoutUntil(lockoutUntil);
    }

    state = state.copyWith(
      failedAttempts: newAttempts,
      lockoutUntil: lockoutUntil,
    );
    return false;
  }

  /// Opens the vault with the cached key, gated by a biometric prompt.
  ///
  /// Does nothing unless the user enabled biometrics: no preference, no
  /// prompt, and no cached key to restore.
  Future<bool> unlockWithBiometrics() async {
    if (!settings.biometricUnlockEnabled) return false;
    if (!await _repository.canUseBiometrics()) return false;

    final approved =
        await _repository.authenticateWithBiometrics('Unlock authenticator');
    if (!approved) return false;

    final key = await _repository.getStoredMasterKey();
    if (key == null) return false;

    await _repository.setFailedAttempts(0);
    await _repository.setLockoutUntil(null);

    state = state.copyWith(
      failedAttempts: 0,
      clearLockout: true,
      masterKey: key,
      isLocked: false,
    );
    return true;
  }

  /// Creates the vault under a new [credential] of the chosen [kind].
  ///
  /// Returns null on success, or the reason the credential was refused.
  Future<String?> setupCredential(
    String credential,
    CredentialKind kind,
  ) async {
    final policyError = CredentialPolicy.validate(kind, credential);
    if (policyError != null) return policyError;

    // Prevent reuse of the current credential during rotation.
    if (await _repository.hasCredential() &&
        await _repository.verifyCredential(credential)) {
      return 'Choose a credential you have not used before.';
    }

    final key = await _repository.setCredential(credential, kind);
    await _syncCachedKey(key);

    state = state.copyWith(
      isSetupRequired: false,
      isLocked: false,
      credentialKind: kind,
      masterKey: key,
      lastSetDate: DateTime.now(),
      failedAttempts: 0,
      clearLockout: true,
      clearRotation: true,
    );
    return null;
  }

  /// Replaces the credential, optionally switching kind, without disturbing
  /// enrolled accounts.
  ///
  /// Returns null on success, or the reason it was refused.
  Future<String?> changeCredential({
    required String current,
    required String next,
    required CredentialKind kind,
  }) async {
    final policyError = CredentialPolicy.validate(kind, next);
    if (policyError != null) return policyError;

    final changed = await _repository.changeCredential(
      current: current,
      next: next,
      kind: kind,
    );
    if (!changed) return 'That is not your current credential.';

    final reopened = await _repository.unlockVault(next);
    final key = reopened.key;
    if (key == null) return 'The vault could not be reopened.';

    // The cached key is derived from the credential, so a re-keyed vault
    // strands the old cache — refresh it, or biometric unlock breaks quietly.
    await _syncCachedKey(key);

    state = state.copyWith(
      isLocked: false,
      credentialKind: kind,
      masterKey: key,
      lastSetDate: DateTime.now(),
      failedAttempts: 0,
      clearLockout: true,
      clearRotation: true,
    );
    return null;
  }

  /// Turns biometric unlock on or off.
  ///
  /// Returns false when it could not be enabled — no biometric hardware, or
  /// the vault is not currently open so there is no key to cache.
  Future<bool> setBiometricUnlockEnabled(bool enabled) async {
    if (enabled) {
      if (!await _repository.canUseBiometrics()) return false;
      final key = state.masterKey;
      if (key == null) return false;
      await _repository.storeMasterKey(key);
    } else {
      // Switching biometrics off must also remove the reason the key was
      // cached. Leaving it behind would keep the vault key at rest for a
      // feature the user just declined.
      await _repository.clearStoredMasterKey();
    }

    await _ref
        .read(settingsProvider.notifier)
        .setBiometricUnlockEnabled(enabled);
    return true;
  }

  /// Keeps the cached key in step with the biometric preference.
  Future<void> _syncCachedKey(MasterKey key) async {
    if (settings.biometricUnlockEnabled) {
      await _repository.storeMasterKey(key);
    } else {
      await _repository.clearStoredMasterKey();
    }
  }

  /// Wipes the vault and returns the app to first-run setup.
  ///
  /// Destroys every enrolled account, so it is reachable only from an explicit
  ///, confirmed action in settings. Encrypted backup and restore (ADR-0013) is
  /// the intended recovery path; this is the deliberate "start over" one.
  Future<void> resetApp() async {
    await _repository.clearAuthData();
    await _ref.read(accountListProvider.notifier).clearAllAccounts();
    await _ref.read(settingsProvider.notifier).reset();
    state = AuthState(
      isLocked: false,
      isSetupRequired: true,
      biometricsAvailable: state.biometricsAvailable,
    );
  }
}
