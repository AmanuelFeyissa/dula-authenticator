import 'package:flutter_test/flutter_test.dart';
import 'package:dula_auth/core/settings/app_settings.dart';

void main() {
  group('defaults', () {
    test('locks after thirty seconds in the background', () {
      expect(
        AppSettings().autoLock,
        AutoLockDelay.thirtySeconds,
      );
    });

    test('leaves biometric unlock off until the user opts in', () {
      expect(AppSettings().biometricUnlockEnabled, isFalse);
    });

    test('leaves forced credential rotation off', () {
      // NIST SP 800-63B advises against mandatory periodic rotation of
      // user-chosen secrets; it stays available for deployments whose
      // compliance regime demands it, but nobody gets it by default.
      expect(AppSettings().credentialRotationEnabled, isFalse);
      expect(AppSettings().credentialRotationDays, 90);
    });
  });

  group('auto-lock delays', () {
    test('immediate means no grace period at all', () {
      expect(AutoLockDelay.immediate.duration, Duration.zero);
    });

    test('never means there is no delay to wait for', () {
      expect(AutoLockDelay.never.duration, isNull);
    });

    test('each option has an ascending, labelled delay', () {
      expect(AutoLockDelay.thirtySeconds.duration,
          const Duration(seconds: 30));
      expect(AutoLockDelay.oneMinute.duration, const Duration(minutes: 1));
      expect(AutoLockDelay.fiveMinutes.duration, const Duration(minutes: 5));
      for (final option in AutoLockDelay.values) {
        expect(option.label, isNotEmpty);
      }
    });
  });

  group('serialization', () {
    test('round-trips every field', () {
      final settings = AppSettings(
        autoLock: AutoLockDelay.fiveMinutes,
        biometricUnlockEnabled: true,
        credentialRotationEnabled: true,
        credentialRotationDays: 30,
      );

      expect(AppSettings.fromMap(settings.toMap()), settings);
    });

    test('an unreadable auto-lock value falls back to the default', () {
      // Falling back to "never" would silently disable locking, so an
      // unparseable value must not be able to produce it.
      final restored = AppSettings.fromMap({'autoLock': 'whenever'});

      expect(restored.autoLock, AppSettings().autoLock);
    });

    test('an empty map yields the defaults', () {
      expect(AppSettings.fromMap(const {}), AppSettings());
    });

    test('a nonsensical rotation period is clamped, not honoured', () {
      expect(
        AppSettings.fromMap(const {'credentialRotationDays': 0})
            .credentialRotationDays,
        greaterThan(0),
      );
    });
  });

  group('credential expiry', () {
    final setOn = DateTime(2026, 1, 1);
    final muchLater = DateTime(2027, 1, 1);

    test('never expires while rotation is disabled', () {
      // The regression this guards: rotation was documented as opt-in but
      // applied to every user, so a year-old PIN forced a rotation prompt.
      final settings = AppSettings();

      expect(
        settings.isCredentialExpired(setOn, now: muchLater),
        isFalse,
      );
    });

    test('expires once the period has elapsed and rotation is enabled', () {
      final settings = AppSettings(credentialRotationEnabled: true);

      expect(settings.isCredentialExpired(setOn, now: muchLater), isTrue);
    });

    test('does not expire before the period has elapsed', () {
      final settings = AppSettings(credentialRotationEnabled: true);

      expect(
        settings.isCredentialExpired(setOn, now: DateTime(2026, 2, 1)),
        isFalse,
      );
    });

    test('treats an unknown set date as not expired', () {
      final settings = AppSettings(credentialRotationEnabled: true);

      expect(settings.isCredentialExpired(null, now: muchLater), isFalse);
    });
  });

  group('AppSettings.configureDefaults', () {
    tearDown(AppSettings.resetDefaultsForTesting);

    test('changes the default auto-lock delay', () {
      AppSettings.configureDefaults(autoLock: AutoLockDelay.immediate);
      expect(AppSettings().autoLock, AutoLockDelay.immediate);
    });

    test('changes the default rotation period and its bounds', () {
      AppSettings.configureDefaults(
        rotationDays: 60,
        minRotationDays: 7,
        maxRotationDays: 365,
      );
      expect(AppSettings().credentialRotationDays, 60);
      expect(
        AppSettings.fromMap(const {'credentialRotationDays': 1})
            .credentialRotationDays,
        7,
      );
      expect(
        AppSettings.fromMap(const {'credentialRotationDays': 9999})
            .credentialRotationDays,
        365,
      );
    });

    test('resetDefaultsForTesting restores the historical defaults', () {
      AppSettings.configureDefaults(
        autoLock: AutoLockDelay.immediate,
        rotationDays: 60,
      );
      AppSettings.resetDefaultsForTesting();
      expect(AppSettings.defaultAutoLock, AutoLockDelay.thirtySeconds);
      expect(AppSettings.defaultRotationDays, 90);
    });
  });
}
