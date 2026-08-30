import 'package:flutter_test/flutter_test.dart';
import 'package:dula_auth/core/otp/otp_algorithm.dart';
import 'package:dula_auth/core/otp/otp_generator.dart';
import 'package:dula_auth/core/otp/otp_type.dart';

/// ASCII "12345678901234567890" — the RFC 4226 / RFC 6238 test seed.
const rfcSecret = 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ';

/// RFC 6238 Appendix B seeds for the stronger hashes (32 and 64 bytes).
const rfcSecretSha256 =
    'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZA';
const rfcSecretSha512 =
    'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ'
    'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNA';

DateTime utc(int seconds) =>
    DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);

void main() {
  group('HOTP (RFC 4226 Appendix D)', () {
    // The canonical published vectors. These are the contract: if they break,
    // every HOTP credential this app holds produces wrong codes.
    const expected = [
      '755224', '287082', '359152', '969429', '338314',
      '254676', '287922', '162583', '399871', '520489',
    ];

    for (var counter = 0; counter < expected.length; counter++) {
      test('counter $counter generates ${expected[counter]}', () {
        final code = OtpGenerator.forType(OtpType.hotp).generate(
          secret: rfcSecret,
          counter: counter,
          digits: 6,
          algorithm: OtpAlgorithm.sha1,
        );

        expect(code, expected[counter]);
      });
    }
  });

  group('TOTP (RFC 6238)', () {
    test('SHA-1 8-digit vectors', () {
      const vectors = {
        59: '94287082',
        1111111109: '07081804',
        1111111111: '14050471',
        1234567890: '89005924',
        2000000000: '69279037',
      };

      vectors.forEach((time, expected) {
        final code = OtpGenerator.forType(OtpType.totp).generate(
          secret: rfcSecret,
          counter: time ~/ 30,
          digits: 8,
          algorithm: OtpAlgorithm.sha1,
        );
        expect(code, expected, reason: 'at t=$time');
      });
    });

    test('SHA-256 8-digit vectors', () {
      const vectors = {
        59: '46119246',
        1111111109: '68084774',
        1111111111: '67062674',
        1234567890: '91819424',
        2000000000: '90698825',
        20000000000: '77737706',
      };

      vectors.forEach((time, expected) {
        final code = OtpGenerator.forType(OtpType.totp).generate(
          secret: rfcSecretSha256,
          counter: time ~/ 30,
          digits: 8,
          algorithm: OtpAlgorithm.sha256,
        );
        expect(code, expected, reason: 'at t=$time');
      });
    });

    test('SHA-512 8-digit vectors', () {
      const vectors = {
        59: '90693936',
        1111111109: '25091201',
        1111111111: '99943326',
        1234567890: '93441116',
        2000000000: '38618901',
        20000000000: '47863826',
      };

      vectors.forEach((time, expected) {
        final code = OtpGenerator.forType(OtpType.totp).generate(
          secret: rfcSecretSha512,
          counter: time ~/ 30,
          digits: 8,
          algorithm: OtpAlgorithm.sha512,
        );
        expect(code, expected, reason: 'at t=$time');
      });
    });

    test('handles a counter beyond 32 bits', () {
      // t=20000000000 yields counter 666666666; the counter is packed into
      // eight bytes, so a 32-bit truncation would corrupt it.
      final code = OtpGenerator.forType(OtpType.totp).generate(
        secret: rfcSecret,
        counter: 20000000000 ~/ 30,
        digits: 8,
        algorithm: OtpAlgorithm.sha1,
      );

      expect(code, '65353130');
    });

    test('honours a 6-digit request', () {
      final code = OtpGenerator.forType(OtpType.totp).generate(
        secret: rfcSecret,
        counter: 59 ~/ 30,
        digits: 6,
        algorithm: OtpAlgorithm.sha1,
      );

      // The 6-digit code is the last six digits of the 8-digit vector.
      expect(code, '287082');
    });

    test('a different algorithm produces a different code', () {
      final sha1 = OtpGenerator.forType(OtpType.totp).generate(
        secret: rfcSecret,
        counter: 59 ~/ 30,
        digits: 8,
        algorithm: OtpAlgorithm.sha1,
      );
      final sha256 = OtpGenerator.forType(OtpType.totp).generate(
        secret: rfcSecret,
        counter: 59 ~/ 30,
        digits: 8,
        algorithm: OtpAlgorithm.sha256,
      );

      expect(sha1, isNot(sha256),
          reason: 'the algorithm parameter must actually be applied');
    });
  });

  group('Steam Guard', () {
    // Cross-validated against the reference JS implementation
    // (npm "steam-totp", DoctorMcKay), using the RFC test seed.
    const vectors = {
      0: 'GG5F5',
      1: 'PV9M4',
      2: 'B26KJ',
      37037036: 'PY4YB',
      41152263: 'VHHQY',
      66666666: '9N776',
    };

    vectors.forEach((counter, expected) {
      test('counter $counter generates $expected', () {
        final code = OtpGenerator.forType(OtpType.steam).generate(
          secret: rfcSecret,
          counter: counter,
          digits: 5,
          algorithm: OtpAlgorithm.sha1,
        );

        expect(code, expected);
      });
    });

    test('always produces five characters from the Steam alphabet', () {
      const alphabet = '23456789BCDFGHJKMNPQRTVWXY';

      for (var counter = 0; counter < 50; counter++) {
        final code = OtpGenerator.forType(OtpType.steam).generate(
          secret: rfcSecret,
          counter: counter,
          digits: 5,
          algorithm: OtpAlgorithm.sha1,
        );

        expect(code.length, 5, reason: 'counter $counter');
        for (final ch in code.split('')) {
          expect(alphabet.contains(ch), isTrue,
              reason: '"$ch" is not in the Steam alphabet (counter $counter)');
        }
      }
    });

    test('ignores the digits parameter', () {
      // Steam codes are always five characters regardless of what an
      // otpauth URI claims.
      final code = OtpGenerator.forType(OtpType.steam).generate(
        secret: rfcSecret,
        counter: 0,
        digits: 8,
        algorithm: OtpAlgorithm.sha1,
      );

      expect(code, 'GG5F5');
    });
  });

  group('secret handling', () {
    test('accepts lowercase and spaced base32', () {
      final canonical = OtpGenerator.forType(OtpType.totp).generate(
        secret: rfcSecret,
        counter: 1,
        digits: 6,
        algorithm: OtpAlgorithm.sha1,
      );
      final messy = OtpGenerator.forType(OtpType.totp).generate(
        secret: 'gezd gnbv gy3t qojq gezd gnbv gy3t qojq',
        counter: 1,
        digits: 6,
        algorithm: OtpAlgorithm.sha1,
      );

      expect(messy, canonical);
    });

    test('rejects a secret that is not valid base32', () {
      expect(
        () => OtpGenerator.forType(OtpType.totp).generate(
          secret: '!!!not-base32!!!',
          counter: 0,
          digits: 6,
          algorithm: OtpAlgorithm.sha1,
        ),
        throwsA(isA<FormatException>()),
        reason: 'a malformed secret must fail loudly, not emit a wrong code',
      );
    });
  });

  group('counter derivation', () {
    test('TOTP counter advances once per period', () {
      final generator = OtpGenerator.forType(OtpType.totp);

      expect(generator.counterFor(time: utc(0), period: 30), 0);
      expect(generator.counterFor(time: utc(29), period: 30), 0);
      expect(generator.counterFor(time: utc(30), period: 30), 1);
      expect(generator.counterFor(time: utc(89), period: 30), 2);
    });

    test('respects a non-default period', () {
      final generator = OtpGenerator.forType(OtpType.totp);

      expect(generator.counterFor(time: utc(59), period: 60), 0);
      expect(generator.counterFor(time: utc(60), period: 60), 1);
    });

    test('reports seconds remaining in the current window', () {
      final generator = OtpGenerator.forType(OtpType.totp);

      expect(generator.secondsRemaining(time: utc(0), period: 30), 30);
      expect(generator.secondsRemaining(time: utc(1), period: 30), 29);
      expect(generator.secondsRemaining(time: utc(29), period: 30), 1);
    });
  });
}
