import 'package:flutter_test/flutter_test.dart';
import 'package:dula_auth/core/config/deployment_config.dart';
import 'package:dula_auth/core/security/lockout_policy.dart';

void main() {
  tearDown(LockoutPolicy.resetForTesting);

  group('LockoutPolicy.durationFor (default steps)', () {
    test('no lockout below the first threshold', () {
      expect(LockoutPolicy.durationFor(0), isNull);
      expect(LockoutPolicy.durationFor(2), isNull);
    });

    test('30 seconds at 3 or 4 attempts', () {
      expect(LockoutPolicy.durationFor(3), const Duration(seconds: 30));
      expect(LockoutPolicy.durationFor(4), const Duration(seconds: 30));
    });

    test('5 minutes at 5 through 9 attempts', () {
      expect(LockoutPolicy.durationFor(5), const Duration(minutes: 5));
      expect(LockoutPolicy.durationFor(9), const Duration(minutes: 5));
    });

    test('1 hour at 10 or more attempts', () {
      expect(LockoutPolicy.durationFor(10), const Duration(hours: 1));
      expect(LockoutPolicy.durationFor(1000), const Duration(hours: 1));
    });
  });

  group('LockoutPolicy.configure', () {
    test('a deployer-configured step list replaces the defaults', () {
      LockoutPolicy.configure(const [
        LockoutStep(attempts: 2, lockoutDuration: Duration(seconds: 5)),
      ]);
      expect(LockoutPolicy.durationFor(1), isNull);
      expect(LockoutPolicy.durationFor(2), const Duration(seconds: 5));
      expect(LockoutPolicy.durationFor(3), const Duration(seconds: 5));
    });

    test('an empty step list means lockout is disabled entirely', () {
      LockoutPolicy.configure(const []);
      expect(LockoutPolicy.durationFor(1000), isNull);
    });

    test('resetForTesting restores the default steps', () {
      LockoutPolicy.configure(const []);
      LockoutPolicy.resetForTesting();
      expect(LockoutPolicy.durationFor(3), const Duration(seconds: 30));
    });
  });
}
