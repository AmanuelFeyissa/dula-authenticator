import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';

/// Device biometric gate, behind an interface.
///
/// Callers: `lib/features/auth/repositories/auth_repository.dart`, which used
/// to hold a `LocalAuthentication` directly; `test/features/auth/*` supplies
/// its own implementation. No data schema — nothing here is persisted.
///
/// The interface exists for two reasons: biometric behaviour is untestable
/// against the real platform channel, and the platform-support question
/// deserves exactly one home rather than a `Platform.isX` check at each call
/// site.
///
/// Added for the user instruction "go ahead on phase 3" (ADR-0011).
abstract class BiometricAuthenticator {
  /// Whether this device can actually perform a biometric check right now.
  Future<bool> isAvailable();

  /// Prompts for biometrics. Returns false on failure, cancellation, or when
  /// the platform cannot do it at all.
  Future<bool> authenticate(String reason);
}

/// [BiometricAuthenticator] backed by the `local_auth` plugin.
///
/// `local_auth` ships implementations for Android, iOS, macOS and Windows
/// only: there is **no Linux implementation and no web implementation**. Those
/// platforms are answered `false` up front rather than left to throw a
/// MissingPluginException at the call site, which is what "verify, don't
/// assume" means here (CLAUDE.md; ADR-0005). Linux and web users therefore
/// unlock with their PIN or passphrase, which ADR-0011 requires to stay
/// available on every platform anyway.
class LocalAuthBiometrics implements BiometricAuthenticator {
  final LocalAuthentication _localAuth;

  LocalAuthBiometrics({LocalAuthentication? localAuth})
      : _localAuth = localAuth ?? LocalAuthentication();

  /// Platforms with a real `local_auth` implementation.
  static bool get isPlatformSupported {
    if (kIsWeb) return false;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
        return true;
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        return false;
    }
  }

  @override
  Future<bool> isAvailable() async {
    if (!isPlatformSupported) return false;
    try {
      return await _localAuth.canCheckBiometrics ||
          await _localAuth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> authenticate(String reason) async {
    if (!isPlatformSupported) return false;
    try {
      return await _localAuth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          // Biometrics only: the app has its own credential, so falling back
          // to the device passcode would quietly reduce the gate to whatever
          // unlocks the device.
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }
}
