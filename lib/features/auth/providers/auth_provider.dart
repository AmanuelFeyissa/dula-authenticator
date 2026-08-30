import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dula_auth/core/crypto/vault_crypto.dart';
import 'package:dula_auth/core/security/pin_policy.dart';
import 'package:dula_auth/features/auth/repositories/auth_repository.dart';
import 'package:dula_auth/features/home/providers/home_provider.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository();
});

final authStateProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(ref.read(authRepositoryProvider), ref);
});

class AuthState {
  final bool isLocked;
  final bool isPinSetupRequired;
  final bool isPinExpired;
  final bool isPinVerifiedForRotation;
  final int failedAttempts;
  final DateTime? lockoutUntil;
  final DateTime? lastSetDate;
  final MasterKey? masterKey;

  AuthState({
    required this.isLocked,
    required this.isPinSetupRequired,
    this.isPinExpired = false,
    this.isPinVerifiedForRotation = false,
    this.failedAttempts = 0,
    this.lockoutUntil,
    this.lastSetDate,
    this.masterKey,
  });

  bool get isLockedOut =>
      lockoutUntil != null && lockoutUntil!.isAfter(DateTime.now());

  AuthState copyWith({
    bool? isLocked,
    bool? isPinSetupRequired,
    bool? isPinExpired,
    bool? isPinVerifiedForRotation,
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
      isPinSetupRequired: isPinSetupRequired ?? this.isPinSetupRequired,
      isPinExpired: clearRotation ? false : (isPinExpired ?? this.isPinExpired),
      isPinVerifiedForRotation: clearRotation
          ? false
          : (isPinVerifiedForRotation ?? this.isPinVerifiedForRotation),
      failedAttempts: failedAttempts ?? this.failedAttempts,
      lockoutUntil: clearLockout ? null : (lockoutUntil ?? this.lockoutUntil),
      lastSetDate: lastSetDate ?? this.lastSetDate,
      masterKey: clearMasterKey ? null : (masterKey ?? this.masterKey),
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  final AuthRepository _repository;
  final Ref _ref;

  /// Credential rotation period, when the optional rotation policy is enabled.
  /// NIST SP 800-63B advises against forced periodic rotation, so this is not
  /// applied unless a deployment opts in — see ADR-0011.
  static const int _pinExpirationDays = 90;

  AuthNotifier(this._repository, this._ref)
      : super(AuthState(isLocked: true, isPinSetupRequired: false)) {
    _checkInitialState();
  }

  Future<void> _checkInitialState() async {
    final hasPin = await _repository.hasPinSet();
    final lastSetDate = await _repository.getPinLastSetDate();
    final failedAttempts = await _repository.getFailedAttempts();
    final lockoutUntil = await _repository.getLockoutUntil();

    bool isExpired = false;
    if (lastSetDate != null) {
      isExpired =
          DateTime.now().difference(lastSetDate).inDays >= _pinExpirationDays;
    }

    if (!hasPin) {
      state = state.copyWith(
        isLocked: false,
        isPinSetupRequired: true,
        failedAttempts: 0,
        lockoutUntil: null,
      );
    } else {
      state = state.copyWith(
        isLocked: true,
        isPinSetupRequired: false,
        isPinExpired: isExpired,
        failedAttempts: failedAttempts,
        lockoutUntil: lockoutUntil,
        lastSetDate: lastSetDate,
      );
      if (await _repository.isBiometricsEnabled()) {
        await unlockWithBiometrics();
      }
    }
  }

  void lock() {
    if (!state.isPinSetupRequired) {
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

  Future<bool> unlockWithPin(String pin) async {
    if (state.lockoutUntil != null &&
        state.lockoutUntil!.isAfter(DateTime.now())) {
      return false;
    }

    final result = await _repository.unlockVault(pin);

    if (result.isUnlocked) {
      final key = result.key!;
      await _repository.setFailedAttempts(0);
      await _repository.setLockoutUntil(null);

      // Cache the key so biometric unlock can restore it without the
      // credential being re-entered.
      await _repository.storeMasterKey(key);

      if (state.isPinExpired) {
        // Credential is correct but expired — allow rotation without unlocking.
        state = state.copyWith(
          failedAttempts: 0,
          clearLockout: true,
          isPinVerifiedForRotation: true,
          masterKey: key,
        );
        return true;
      }

      // Single atomic update: set key and unlock together, so account loading
      // never observes an unlocked state without a key.
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

  Future<bool> unlockWithBiometrics() async {
    if (!await _repository.canUseBiometrics()) return false;

    final success = await _repository.authenticateWithBiometrics(
      'Unlock authenticator',
    );
    if (!success) return false;

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

  Future<bool> setupPin(String pin, {bool useBiometrics = false}) async {
    // Enforce the full strength policy (blocklist + pattern checks).
    if (PinPolicy.validate(pin) != null) {
      return false;
    }
    // Prevent reuse of the current credential during rotation.
    if (await _repository.hasPinSet() && await _repository.verifyPin(pin)) {
      return false;
    }

    final key = await _repository.setPin(pin);
    if (useBiometrics) {
      await _repository.setBiometricsEnabled(true);
    }
    await _repository.storeMasterKey(key);

    state = state.copyWith(
      isPinSetupRequired: false,
      isLocked: false,
      masterKey: key,
      lastSetDate: DateTime.now(),
      clearRotation: true,
    );
    return true;
  }

  /// Wipes the vault and returns the app to first-run setup.
  ///
  /// Not reachable from the UI: the "forgot PIN" escape hatch was removed
  /// because destroying every enrolled account is not an acceptable recovery
  /// path. Encrypted backup and restore (ADR-0013) is the intended recovery
  /// mechanism; a deliberate "reset app" action belongs in settings once that
  /// exists. Retained here because vault teardown is a real operation the
  /// settings screen will need.
  Future<void> resetApp() async {
    await _repository.clearAuthData();
    await _ref.read(accountListProvider.notifier).clearAllAccounts();
    state = state.copyWith(
      isLocked: false,
      isPinSetupRequired: true,
      clearMasterKey: true,
    );
  }
}
