import 'package:flutter_test/flutter_test.dart';
import 'package:dula_auth/core/config/deployment_config.dart';
import 'package:dula_auth/core/settings/app_settings.dart';

void main() {
  group('DeploymentConfig.fallback', () {
    test('matches the values that were hardcoded before this config existed', () {
      const fallback = DeploymentConfig.fallback;
      expect(fallback.pinLength, 6);
      expect(fallback.passphraseMinLength, 12);
      expect(fallback.passphraseRecommendedLength, 15);
      expect(fallback.passphraseMaxLength, 256);
      expect(fallback.argon2MemoryKiB, 19456);
      expect(fallback.argon2Iterations, 2);
      expect(fallback.argon2Parallelism, 1);
      expect(fallback.lockoutSteps.map((s) => s.attempts), [3, 5, 10]);
      expect(fallback.lockoutSteps.map((s) => s.lockoutDuration), [
        const Duration(seconds: 30),
        const Duration(minutes: 5),
        const Duration(hours: 1),
      ]);
      expect(fallback.defaultAutoLock, AutoLockDelay.thirtySeconds);
      expect(fallback.credentialRotationDefaultDays, 90);
      expect(fallback.credentialRotationMinDays, 1);
      expect(fallback.credentialRotationMaxDays, 3650);
      expect(fallback.credentialRotationOptionsDays, [30, 60, 90, 180, 365]);
      expect(fallback.backupFileNamePrefix, isNull);
      expect(fallback.copiedToClipboardSnackbarSeconds, 1);
    });
  });

  group('DeploymentConfig.parse', () {
    test('reads every field from a fully populated deployment_config.json', () {
      final config = DeploymentConfig.parse('''
      {
        "security": {
          "pinLength": 8,
          "passphraseMinLength": 16,
          "passphraseRecommendedLength": 20,
          "passphraseMaxLength": 128,
          "argon2MemoryKiB": 65536,
          "argon2Iterations": 3,
          "argon2Parallelism": 2,
          "lockoutSteps": [
            {"attempts": 2, "seconds": 10},
            {"attempts": 4, "seconds": 60}
          ],
          "defaultAutoLock": "immediate",
          "credentialRotationDefaultDays": 60,
          "credentialRotationMinDays": 7,
          "credentialRotationMaxDays": 365,
          "credentialRotationOptionsDays": [7, 30, 60]
        },
        "backup": {
          "fileNamePrefix": "acme-backup-"
        },
        "ui": {
          "copiedToClipboardSnackbarSeconds": 3
        }
      }
      ''');

      expect(config.pinLength, 8);
      expect(config.passphraseMinLength, 16);
      expect(config.passphraseRecommendedLength, 20);
      expect(config.passphraseMaxLength, 128);
      expect(config.argon2MemoryKiB, 65536);
      expect(config.argon2Iterations, 3);
      expect(config.argon2Parallelism, 2);
      expect(config.lockoutSteps.map((s) => s.attempts), [2, 4]);
      expect(config.lockoutSteps.map((s) => s.lockoutDuration), [
        const Duration(seconds: 10),
        const Duration(seconds: 60),
      ]);
      expect(config.defaultAutoLock, AutoLockDelay.immediate);
      expect(config.credentialRotationDefaultDays, 60);
      expect(config.credentialRotationMinDays, 7);
      expect(config.credentialRotationMaxDays, 365);
      expect(config.credentialRotationOptionsDays, [7, 30, 60]);
      expect(config.backupFileNamePrefix, 'acme-backup-');
      expect(config.copiedToClipboardSnackbarSeconds, 3);
    });

    test('falls back field-by-field when sections are missing entirely', () {
      final config = DeploymentConfig.parse('{"security": {"pinLength": 4}}');
      expect(config.pinLength, 4);
      expect(config.passphraseMinLength, DeploymentConfig.fallback.passphraseMinLength);
      expect(config.backupFileNamePrefix, isNull);
      expect(config.copiedToClipboardSnackbarSeconds,
          DeploymentConfig.fallback.copiedToClipboardSnackbarSeconds);
    });

    test('falls back to defaults for an unrecognized defaultAutoLock name', () {
      final config = DeploymentConfig.parse(
          '{"security": {"defaultAutoLock": "not-a-real-option"}}');
      expect(config.defaultAutoLock, DeploymentConfig.fallback.defaultAutoLock);
    });

    test('ignores a malformed lockoutSteps entry and falls back to defaults', () {
      final config = DeploymentConfig.parse('''
      {"security": {"lockoutSteps": [{"attempts": 2}]}}
      ''');
      expect(config.lockoutSteps, DeploymentConfig.fallback.lockoutSteps);
    });

    test('accepts an empty lockoutSteps as "lockout disabled", not malformed', () {
      final config = DeploymentConfig.parse('{"security": {"lockoutSteps": []}}');
      expect(config.lockoutSteps, isEmpty);
    });

    test('throws on invalid JSON so load() can catch it and use fallback', () {
      expect(() => DeploymentConfig.parse('not json'), throwsFormatException);
    });

    test('falls back to the default pinLength when below the safety floor', () {
      // A typo (or a deliberately hostile config) setting pinLength too low
      // must not silently ship a weaker PIN policy than the default.
      final config = DeploymentConfig.parse('{"security": {"pinLength": 2}}');
      expect(config.pinLength, DeploymentConfig.fallback.pinLength);
    });

    test('falls back to the default passphraseMinLength when below the NIST floor', () {
      final config =
          DeploymentConfig.parse('{"security": {"passphraseMinLength": 4}}');
      expect(config.passphraseMinLength, DeploymentConfig.fallback.passphraseMinLength);
    });

    test('accepts a passphraseMinLength raised above the default', () {
      final config =
          DeploymentConfig.parse('{"security": {"passphraseMinLength": 20}}');
      expect(config.passphraseMinLength, 20);
    });

    test('falls back to the default Argon2id parameters when below the OWASP floor', () {
      final config = DeploymentConfig.parse('''
      {"security": {"argon2MemoryKiB": 100, "argon2Iterations": 1, "argon2Parallelism": 0}}
      ''');
      expect(config.argon2MemoryKiB, DeploymentConfig.fallback.argon2MemoryKiB);
      expect(config.argon2Iterations, DeploymentConfig.fallback.argon2Iterations);
      expect(config.argon2Parallelism, DeploymentConfig.fallback.argon2Parallelism);
    });

    test('accepts Argon2id parameters raised above the OWASP floor', () {
      final config = DeploymentConfig.parse('''
      {"security": {"argon2MemoryKiB": 65536, "argon2Iterations": 3, "argon2Parallelism": 2}}
      ''');
      expect(config.argon2MemoryKiB, 65536);
      expect(config.argon2Iterations, 3);
      expect(config.argon2Parallelism, 2);
    });
  });

  group('lockout step resolution', () {
    test('fallback steps reproduce the historical lockout thresholds', () {
      final steps = DeploymentConfig.fallback.lockoutSteps;
      expect(durationForAttempts(steps, 1), isNull);
      expect(durationForAttempts(steps, 2), isNull);
      expect(durationForAttempts(steps, 3), const Duration(seconds: 30));
      expect(durationForAttempts(steps, 4), const Duration(seconds: 30));
      expect(durationForAttempts(steps, 5), const Duration(minutes: 5));
      expect(durationForAttempts(steps, 9), const Duration(minutes: 5));
      expect(durationForAttempts(steps, 10), const Duration(hours: 1));
      expect(durationForAttempts(steps, 100), const Duration(hours: 1));
    });
  });
}

/// Mirrors the resolution logic `LockoutPolicy.durationFor` will use — kept
/// here as a standalone helper so this test can pin the *data* shape
/// (`DeploymentConfig.lockoutSteps`) before `LockoutPolicy` exists.
Duration? durationForAttempts(List<LockoutStep> steps, int attempts) {
  Duration? result;
  for (final step in steps) {
    if (attempts >= step.attempts) result = step.lockoutDuration;
  }
  return result;
}
