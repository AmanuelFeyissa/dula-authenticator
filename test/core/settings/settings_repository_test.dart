import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dula_auth/core/settings/app_settings.dart';
import 'package:dula_auth/core/settings/settings_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SettingsRepository repository;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    repository = SettingsRepository();
  });

  test('a fresh install loads the defaults', () async {
    expect(await repository.load(), AppSettings());
  });

  test('saved settings survive a reload', () async {
    final chosen = AppSettings(
      autoLock: AutoLockDelay.never,
      biometricUnlockEnabled: true,
      credentialRotationEnabled: true,
      credentialRotationDays: 45,
    );

    await repository.save(chosen);

    expect(await SettingsRepository().load(), chosen);
  });

  test('a partially written store keeps its defaults for the rest', () async {
    SharedPreferences.setMockInitialValues({
      'settings_biometricUnlockEnabled': true,
    });

    final loaded = await SettingsRepository().load();

    expect(loaded.biometricUnlockEnabled, isTrue);
    expect(loaded.autoLock, AppSettings().autoLock);
  });

  test('a value stored with the wrong type does not crash the app', () async {
    // Preferences survive upgrades and are editable outside the app. Reading
    // one must never be able to prevent the app starting.
    SharedPreferences.setMockInitialValues({
      'settings_autoLock': 42,
      'settings_credentialRotationDays': 'ninety',
    });

    final loaded = await SettingsRepository().load();

    expect(loaded.autoLock, AppSettings().autoLock);
    expect(loaded.credentialRotationDays, AppSettings.defaultRotationDays);
  });

  test('turning a setting off persists the off state', () async {
    await repository.save(AppSettings(biometricUnlockEnabled: true));
    await repository.save(AppSettings(biometricUnlockEnabled: false));

    expect((await SettingsRepository().load()).biometricUnlockEnabled, isFalse);
  });
}
