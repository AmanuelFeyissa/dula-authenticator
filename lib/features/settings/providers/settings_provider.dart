import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dula_auth/core/settings/app_settings.dart';
import 'package:dula_auth/core/settings/settings_repository.dart';

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  return SettingsRepository();
});

/// Holds the user's security preferences.
///
/// Callers: `lib/features/auth/providers/auth_provider.dart` (rotation policy
/// and the biometric flag), `lib/core/widgets/app_lifecycle_wrapper.dart`
/// (auto-lock delay), and `lib/features/settings/screens/settings_screen.dart`.
/// Data schema: delegated entirely to [SettingsRepository], which owns the
/// `settings_*` preference keys.
///
/// Starts from [AppSettings]'s defaults and replaces them once the stored
/// values load. The defaults are the safe ones — a 30-second auto-lock and no
/// biometrics — so a widget that builds before the load finishes is never
/// briefly less secure than the user asked for.
///
/// Added for the user instruction "go ahead on phase 3" (ADR-0011).
class SettingsNotifier extends StateNotifier<AppSettings> {
  final SettingsRepository _repository;

  /// Completes once the stored settings have been read. Callers that must not
  /// act on defaults — the auth notifier deciding whether rotation applies —
  /// await this first.
  late final Future<void> ready;

  SettingsNotifier(this._repository) : super(AppSettings()) {
    ready = _load();
  }

  Future<void> _load() async {
    state = await _repository.load();
  }

  Future<void> _update(AppSettings next) async {
    state = next;
    await _repository.save(next);
  }

  Future<void> setAutoLock(AutoLockDelay delay) =>
      _update(state.copyWith(autoLock: delay));

  /// Records the biometric preference. Enabling and disabling also has to
  /// manage the cached vault key, which is the auth notifier's job — call
  /// `AuthNotifier.setBiometricUnlockEnabled` rather than this directly.
  Future<void> setBiometricUnlockEnabled(bool enabled) =>
      _update(state.copyWith(biometricUnlockEnabled: enabled));

  Future<void> setCredentialRotationEnabled(bool enabled) =>
      _update(state.copyWith(credentialRotationEnabled: enabled));

  Future<void> setCredentialRotationDays(int days) => _update(
        state.copyWith(
          credentialRotationDays: days.clamp(
            AppSettings.minRotationDays,
            AppSettings.maxRotationDays,
          ),
        ),
      );

  /// Returns every setting to its default. Used by the reset-app flow.
  Future<void> reset() async {
    state = AppSettings();
    await _repository.clear();
  }
}

final settingsProvider =
    StateNotifierProvider<SettingsNotifier, AppSettings>((ref) {
  return SettingsNotifier(ref.read(settingsRepositoryProvider));
});
