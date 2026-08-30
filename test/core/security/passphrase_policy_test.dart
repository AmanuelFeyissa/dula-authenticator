import 'package:flutter_test/flutter_test.dart';
import 'package:dula_auth/core/security/passphrase_policy.dart';

void main() {
  group('length', () {
    test('accepts a passphrase at the minimum length', () {
      expect(PassphrasePolicy.validate('rope-anchor-9'), isNull);
    });

    test('rejects a passphrase shorter than the minimum', () {
      expect(PassphrasePolicy.validate('short-one'), contains('12'));
    });

    test('rejects an empty passphrase', () {
      expect(PassphrasePolicy.validate(''), isNotNull);
    });

    test('rejects a passphrase that is only whitespace', () {
      expect(PassphrasePolicy.validate('               '), isNotNull);
    });

    test('accepts a long passphrase', () {
      // NIST SP 800-63B: verifiers must accept at least 64 characters.
      expect(
        PassphrasePolicy.validate('rope anchor lantern harbour ${'cinder ' * 9}'),
        isNull,
      );
    });

    test('rejects a passphrase beyond the maximum length', () {
      expect(PassphrasePolicy.validate('x' * 300), isNotNull);
    });
  });

  group('composition', () {
    test('accepts spaces, which is the point of a passphrase', () {
      expect(PassphrasePolicy.validate('rope anchor lantern'), isNull);
    });

    test('accepts a passphrase with no digits, symbols or capitals', () {
      // NIST SP 800-63B advises against composition rules, so lowercase-only
      // must be allowed when it is long enough.
      expect(PassphrasePolicy.validate('rope anchor lantern harbour'), isNull);
    });

    test('accepts non-ASCII characters', () {
      expect(PassphrasePolicy.validate('quiça-ancoradouro-lanterna'), isNull);
    });

    test('does not trim the passphrase it validates', () {
      // Trimming would mean the stored passphrase differs from what the user
      // typed, so a leading space must count toward the length.
      expect(PassphrasePolicy.validate(' rope-anchor'), isNull);
    });
  });

  group('predictable values', () {
    test('rejects a known common passphrase', () {
      expect(PassphrasePolicy.validate('correcthorsebatterystaple'), isNotNull);
    });

    test('rejects a common passphrase regardless of case', () {
      expect(PassphrasePolicy.validate('CorrectHorseBatteryStaple'), isNotNull);
    });

    test('rejects a common passphrase written with separators', () {
      expect(
        PassphrasePolicy.validate('correct horse battery staple'),
        isNotNull,
      );
    });

    test('rejects a single character repeated', () {
      expect(PassphrasePolicy.validate('aaaaaaaaaaaaaaaa'), isNotNull);
    });

    test('rejects an alphabetic run', () {
      expect(PassphrasePolicy.validate('abcdefghijklmnop'), isNotNull);
    });

    test('rejects a numeric run', () {
      expect(PassphrasePolicy.validate('12345678901234'), isNotNull);
    });

    test('rejects a keyboard walk', () {
      expect(PassphrasePolicy.validate('qwertyuiopasdfgh'), isNotNull);
    });

    test('rejects a common value padded with digits to reach the minimum', () {
      // Long enough to pass the length rule, but the length comes from a
      // suffix an attacker's rules would try first.
      expect(PassphrasePolicy.validate('password1234'), isNotNull);
    });

    test('rejects a common value padded with a year', () {
      expect(PassphrasePolicy.validate('letmein!2024'), isNotNull);
    });

    test('does not reject an ordinary passphrase that ends in digits', () {
      expect(PassphrasePolicy.validate('rope anchor 42'), isNull);
    });
  });

  group('strength guidance', () {
    test('rates a barely-long-enough passphrase as weak', () {
      expect(
        PassphrasePolicy.strengthOf('rope-anchor-9'),
        PassphraseStrength.weak,
      );
    });

    test('rates a passphrase at the recommended length as fair or better', () {
      expect(
        PassphrasePolicy.strengthOf('rope anchor lantern').index,
        greaterThanOrEqualTo(PassphraseStrength.fair.index),
      );
    });

    test('rates a long multi-word passphrase as strong', () {
      expect(
        PassphrasePolicy.strengthOf('rope anchor lantern harbour cinder 42'),
        PassphraseStrength.strong,
      );
    });

    test('rates a rejected passphrase as weak rather than throwing', () {
      expect(PassphrasePolicy.strengthOf('abc'), PassphraseStrength.weak);
    });

    test('does not let sheer length disguise a repeated character', () {
      expect(PassphrasePolicy.strengthOf('a' * 40), PassphraseStrength.weak);
    });

    test('does not let sheer length disguise a two-character alternation', () {
      // 20 characters, but only two of them. Length alone would call this
      // fair; an attacker searching a 2-symbol alphabet would not.
      expect(
        PassphrasePolicy.strengthOf('ab' * 10),
        PassphraseStrength.weak,
      );
    });

    test('caps a long but narrow passphrase at fair', () {
      expect(
        PassphrasePolicy.strengthOf('abcdef' * 6),
        PassphraseStrength.fair,
      );
    });
  });
}
