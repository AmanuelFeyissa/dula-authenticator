import 'package:shared_preferences/shared_preferences.dart';
import 'package:dula_auth/core/settings/app_settings.dart';

/// Persists [AppSettings] in shared preferences.
///
/// Callers: `lib/features/settings/providers/settings_provider.dart`, which is
/// the only thing that should touch this directly; `AuthRepository` loses its
/// ad-hoc `mfa_use_biometrics` key to this. Data schema: one preferences key
/// per field, prefixed `settings_` — see [_key].
///
/// Preferences, not the secure store: none of this is a secret, and settings
/// that lived in the encrypted vault could not be read before unlock, which is
/// exactly when the auto-lock and biometric values are needed.
///
/// Added for the user instruction "go ahead on phase 3" (ADR-0011).
class SettingsRepository {
  static const String _prefix = 'settings_';

  static String _key(String field) => '$_prefix$field';

  Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();

    // Each field is read independently and defensively: shared preferences are
    // typed, so a value written as the wrong type throws on read. One bad key
    // must not be able to take the app down on launch.
    Object? read(String field) {
      try {
        return prefs.get(_key(field));
      } catch (_) {
        return null;
      }
    }

    return AppSettings.fromMap({
      for (final field in const [
        'autoLock',
        'biometricUnlockEnabled',
        'credentialRotationEnabled',
        'credentialRotationDays',
      ])
        field: read(field),
    });
  }

  Future<void> save(AppSettings settings) async {
    final prefs = await SharedPreferences.getInstance();

    for (final entry in settings.toMap().entries) {
      final key = _key(entry.key);
      final value = entry.value;
      if (value is bool) {
        await prefs.setBool(key, value);
      } else if (value is int) {
        await prefs.setInt(key, value);
      } else if (value is String) {
        await prefs.setString(key, value);
      } else {
        await prefs.remove(key);
      }
    }
  }

  /// Drops every stored setting, returning the app to its defaults. Used by
  /// the reset-app flow so a wiped vault does not leave stale policy behind.
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in prefs.getKeys().toList()) {
      if (key.startsWith(_prefix)) await prefs.remove(key);
    }
  }
}
