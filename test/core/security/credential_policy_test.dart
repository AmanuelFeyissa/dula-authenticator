import 'package:flutter_test/flutter_test.dart';
import 'package:dula_auth/core/security/credential_kind.dart';
import 'package:dula_auth/core/security/credential_policy.dart';

void main() {
  group('kind serialization', () {
    test('round-trips each kind through its stored name', () {
      for (final kind in CredentialKind.values) {
        expect(CredentialKind.fromName(kind.name), kind);
      }
    });

    test('falls back to passphrase for an unreadable kind', () {
      // The fallback must be the kind whose input can express the other: a
      // text field can type six digits, a numeric keypad cannot type a
      // passphrase. Guessing wrong the other way locks the user out of their
      // own vault with no way to enter their credential.
      expect(CredentialKind.fromName(null), CredentialKind.passphrase);
      expect(CredentialKind.fromName('fingerprint'), CredentialKind.passphrase);
    });
  });

  group('validation dispatch', () {
    test('accepts a strong PIN under the pin kind', () {
      expect(CredentialPolicy.validate(CredentialKind.pin, '481629'), isNull);
    });

    test('applies the PIN blocklist under the pin kind', () {
      expect(
        CredentialPolicy.validate(CredentialKind.pin, '123456'),
        isNotNull,
      );
    });

    test('rejects a passphrase submitted as a PIN', () {
      expect(
        CredentialPolicy.validate(CredentialKind.pin, 'rope anchor lantern'),
        isNotNull,
      );
    });

    test('accepts a strong passphrase under the passphrase kind', () {
      expect(
        CredentialPolicy.validate(
          CredentialKind.passphrase,
          'rope anchor lantern',
        ),
        isNull,
      );
    });

    test('rejects a six-digit PIN submitted as a passphrase', () {
      // Choosing "passphrase" and then typing a PIN would otherwise sneak a
      // 10^6 keyspace past the passphrase rules.
      expect(
        CredentialPolicy.validate(CredentialKind.passphrase, '481629'),
        isNotNull,
      );
    });
  });

  group('presentation', () {
    test('each kind describes itself for the setup screen', () {
      for (final kind in CredentialKind.values) {
        expect(kind.label, isNotEmpty);
        expect(kind.explanation, isNotEmpty);
      }
    });
  });
}
