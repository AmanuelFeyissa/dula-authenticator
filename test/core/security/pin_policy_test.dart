import 'package:flutter_test/flutter_test.dart';
import 'package:dula_auth/core/security/pin_policy.dart';

void main() {
  group('PinPolicy.validate', () {
    test('accepts complex non-sequential, non-repeating PINs', () {
      for (final pin in ['193850', '928374', '104829', '384729', '857391']) {
        expect(PinPolicy.validate(pin), isNull, reason: '$pin should be valid');
      }
    });

    test('rejects the wrong length', () {
      expect(PinPolicy.validate('123'), contains('exactly 6 digits'));
      expect(PinPolicy.validate('1234567'), contains('exactly 6 digits'));
      expect(PinPolicy.validate(''), contains('exactly 6 digits'));
    });

    test('rejects non-digit characters', () {
      expect(PinPolicy.validate('12a456'), contains('digits only'));
      expect(PinPolicy.validate('12 456'), contains('digits only'));
    });

    test('rejects ascending sequences', () {
      for (final pin in ['123456', '012345', '456789', '234567']) {
        expect(PinPolicy.validate(pin), isNotNull, reason: '$pin is sequential');
      }
    });

    test('rejects descending sequences', () {
      for (final pin in ['654321', '543210', '987654', '765432']) {
        expect(PinPolicy.validate(pin), isNotNull, reason: '$pin is sequential');
      }
    });

    test('rejects a single repeated digit', () {
      for (final pin in ['111111', '999999', '000000']) {
        expect(PinPolicy.validate(pin), isNotNull, reason: '$pin is repeated');
      }
    });

    test('rejects repeated pairs and triplets', () {
      expect(PinPolicy.validate('121212'), isNotNull);
      expect(PinPolicy.validate('456456'), isNotNull);
    });

    test('rejects mixed sequential-repeating patterns', () {
      expect(PinPolicy.validate('112233'), isNotNull);
      expect(PinPolicy.validate('998877'), isNotNull);
    });

    test('rejects PINs on the common blocklist', () {
      expect(PinPolicy.validate('696969'), contains('too common'));
      expect(PinPolicy.validate('147258'), contains('too common'));
    });

    test('explains why a PIN was rejected', () {
      // The message reaches the user, so it must be specific enough to act on.
      expect(PinPolicy.validate('111111'), isNot(contains('exactly 6 digits')));
      expect(PinPolicy.validate('111111'), isNotEmpty);
    });
  });

  group('PinPolicy.isWeakPattern', () {
    test('flags weak patterns', () {
      expect(PinPolicy.isWeakPattern('123456'), isTrue);
      expect(PinPolicy.isWeakPattern('111111'), isTrue);
      expect(PinPolicy.isWeakPattern('121212'), isTrue);
    });

    test('accepts strong PINs', () {
      expect(PinPolicy.isWeakPattern('193850'), isFalse);
      expect(PinPolicy.isWeakPattern('857391'), isFalse);
    });

    test('treats a wrong-length PIN as no pattern, not a weak one', () {
      // Wrong length is a separate failure; reporting it as "sequential or
      // repeating" would be inaccurate. Length is enforced by validate().
      expect(PinPolicy.isWeakPattern('123'), isFalse);
      expect(PinPolicy.isWeakPattern('1234567'), isFalse);
    });
  });
}
