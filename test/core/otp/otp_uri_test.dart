import 'package:flutter_test/flutter_test.dart';
import 'package:dula_auth/core/models/otp_account.dart';
import 'package:dula_auth/core/otp/otp_algorithm.dart';
import 'package:dula_auth/core/otp/otp_uri.dart';
import 'package:dula_auth/core/otp/otp_type.dart';

void main() {
  group('parsing a standard TOTP URI', () {
    test('extracts issuer, account and secret', () {
      final account = OtpUri.parse(
        'otpauth://totp/GitHub:dev@example.com?secret=JBSWY3DPEHPK3PXP&issuer=GitHub',
        id: 'x',
      );

      expect(account, isNotNull);
      expect(account!.issuer, 'GitHub');
      expect(account.accountName, 'dev@example.com');
      expect(account.secret, 'JBSWY3DPEHPK3PXP');
      expect(account.type, OtpType.totp);
    });

    test('applies RFC defaults when parameters are absent', () {
      final account = OtpUri.parse(
        'otpauth://totp/Example:alice?secret=JBSWY3DPEHPK3PXP',
        id: 'x',
      )!;

      expect(account.digits, 6);
      expect(account.period, 30);
      expect(account.algorithm, OtpAlgorithm.sha1);
    });

    test('reads the issuer from the label prefix when no query param exists',
        () {
      final account = OtpUri.parse(
        'otpauth://totp/ACME%20Co:alice@example.com?secret=JBSWY3DPEHPK3PXP',
        id: 'x',
      )!;

      expect(account.issuer, 'ACME Co');
      expect(account.accountName, 'alice@example.com');
    });

    test('decodes percent-encoded labels', () {
      final account = OtpUri.parse(
        'otpauth://totp/Big%20Corp:bob%2Bwork%40example.com?secret=JBSWY3DPEHPK3PXP',
        id: 'x',
      )!;

      expect(account.issuer, 'Big Corp');
      expect(account.accountName, 'bob+work@example.com');
    });

    test('handles a label with no issuer prefix', () {
      final account = OtpUri.parse(
        'otpauth://totp/alice@example.com?secret=JBSWY3DPEHPK3PXP',
        id: 'x',
      )!;

      expect(account.accountName, 'alice@example.com');
      expect(account.issuer, isEmpty);
    });
  });

  group('non-default parameters are honoured', () {
    // These were silently discarded before: the URI was parsed, then the
    // account was constructed with hardcoded 6/30/SHA-1. Scanning a valid
    // 8-digit or SHA-256 code produced plausible but wrong output.
    test('digits', () {
      final account = OtpUri.parse(
        'otpauth://totp/Example:alice?secret=JBSWY3DPEHPK3PXP&digits=8',
        id: 'x',
      )!;

      expect(account.digits, 8);
    });

    test('period', () {
      final account = OtpUri.parse(
        'otpauth://totp/Example:alice?secret=JBSWY3DPEHPK3PXP&period=60',
        id: 'x',
      )!;

      expect(account.period, 60);
    });

    test('algorithm', () {
      final sha256 = OtpUri.parse(
        'otpauth://totp/Example:alice?secret=JBSWY3DPEHPK3PXP&algorithm=SHA256',
        id: 'x',
      )!;
      final sha512 = OtpUri.parse(
        'otpauth://totp/Example:alice?secret=JBSWY3DPEHPK3PXP&algorithm=SHA512',
        id: 'x',
      )!;

      expect(sha256.algorithm, OtpAlgorithm.sha256);
      expect(sha512.algorithm, OtpAlgorithm.sha512);
    });

    test('all three together', () {
      final account = OtpUri.parse(
        'otpauth://totp/Example:alice?secret=JBSWY3DPEHPK3PXP'
        '&digits=8&period=45&algorithm=SHA512',
        id: 'x',
      )!;

      expect(account.digits, 8);
      expect(account.period, 45);
      expect(account.algorithm, OtpAlgorithm.sha512);
    });
  });

  group('HOTP', () {
    test('parses type and counter', () {
      final account = OtpUri.parse(
        'otpauth://hotp/Token:alice?secret=JBSWY3DPEHPK3PXP&counter=42',
        id: 'x',
      )!;

      expect(account.type, OtpType.hotp);
      expect(account.counter, 42);
    });

    test('defaults the counter to zero when absent', () {
      final account = OtpUri.parse(
        'otpauth://hotp/Token:alice?secret=JBSWY3DPEHPK3PXP',
        id: 'x',
      )!;

      expect(account.counter, 0);
    });
  });

  group('Steam', () {
    test('recognises an explicit steam encoder', () {
      final account = OtpUri.parse(
        'otpauth://totp/Steam:alice?secret=JBSWY3DPEHPK3PXP&encoder=steam',
        id: 'x',
      )!;

      expect(account.type, OtpType.steam);
    });

    test('recognises the steam scheme', () {
      final account = OtpUri.parse(
        'otpauth://steam/Steam:alice?secret=JBSWY3DPEHPK3PXP',
        id: 'x',
      )!;

      expect(account.type, OtpType.steam);
    });

    test('forces five digits regardless of the URI', () {
      final account = OtpUri.parse(
        'otpauth://steam/Steam:alice?secret=JBSWY3DPEHPK3PXP&digits=6',
        id: 'x',
      )!;

      expect(account.digits, 5);
    });
  });

  group('rejecting bad input', () {
    test('returns null for input that is not an otpauth URI', () {
      expect(OtpUri.parse('https://example.com', id: 'x'), isNull);
      expect(OtpUri.parse('just some text', id: 'x'), isNull);
      expect(OtpUri.parse('', id: 'x'), isNull);
    });

    test('returns null when the secret is missing', () {
      expect(
        OtpUri.parse('otpauth://totp/Example:alice', id: 'x'),
        isNull,
      );
      expect(
        OtpUri.parse('otpauth://totp/Example:alice?secret=', id: 'x'),
        isNull,
      );
    });

    test('returns null when the secret is not base32', () {
      // Untrusted input: a malformed QR must be refused, not stored as an
      // account that later fails to generate codes.
      expect(
        OtpUri.parse('otpauth://totp/Example:alice?secret=not!base32', id: 'x'),
        isNull,
      );
    });

    test('returns null for an unknown otp type', () {
      expect(
        OtpUri.parse('otpauth://motp/Example:alice?secret=JBSWY3DPEHPK3PXP',
            id: 'x'),
        isNull,
      );
    });

    test('clamps out-of-range digits and period rather than trusting them', () {
      final account = OtpUri.parse(
        'otpauth://totp/Example:alice?secret=JBSWY3DPEHPK3PXP'
        '&digits=99&period=0',
        id: 'x',
      );

      // Either rejected outright or clamped to something usable — never
      // propagated as-is, which would crash code generation.
      if (account != null) {
        expect(account.digits, inInclusiveRange(6, 10));
        expect(account.period, greaterThan(0));
      }
    });
  });

  group('round trip', () {
    test('an account can be rendered back to a URI and reparsed', () {
      const original = OtpAccount(
        id: 'x',
        issuer: 'GitHub',
        accountName: 'dev@example.com',
        secret: 'JBSWY3DPEHPK3PXP',
        digits: 8,
        period: 45,
        algorithm: OtpAlgorithm.sha256,
      );

      final reparsed = OtpUri.parse(OtpUri.toUri(original), id: 'x')!;

      expect(reparsed.issuer, original.issuer);
      expect(reparsed.accountName, original.accountName);
      expect(reparsed.secret, original.secret);
      expect(reparsed.digits, original.digits);
      expect(reparsed.period, original.period);
      expect(reparsed.algorithm, original.algorithm);
    });
  });
}
