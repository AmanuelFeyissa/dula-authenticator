import 'dart:math';
import 'dart:typed_data';

import 'package:base32/base32.dart';
import 'package:crypto/crypto.dart';

import 'package:dula_auth/core/otp/otp_algorithm.dart';
import 'package:dula_auth/core/otp/otp_type.dart';

/// Produces one-time passwords for a given credential type.
///
/// All variants share the RFC 4226 HMAC and dynamic-truncation core; they
/// differ only in how the truncated value is rendered and how the moving
/// factor (the counter) is obtained. See
/// docs/adr/0012-pluggable-otp-types.md.
abstract class OtpGenerator {
  const OtpGenerator();

  static const OtpGenerator _totp = TotpGenerator();
  static const OtpGenerator _hotp = HotpGenerator();
  static const OtpGenerator _steam = SteamGuardGenerator();

  static OtpGenerator forType(OtpType type) => switch (type) {
        OtpType.totp => _totp,
        OtpType.hotp => _hotp,
        OtpType.steam => _steam,
      };

  /// Renders the code for [counter].
  ///
  /// Throws [FormatException] if [secret] is not valid base32 — a malformed
  /// secret must fail loudly rather than silently produce a wrong code.
  String generate({
    required String secret,
    required int counter,
    required int digits,
    required OtpAlgorithm algorithm,
  });

  /// The moving factor for a time-based credential at [time].
  int counterFor({required DateTime time, required int period}) =>
      (time.millisecondsSinceEpoch ~/ 1000) ~/ period;

  /// Seconds until the current time window closes.
  int secondsRemaining({required DateTime time, required int period}) =>
      period - ((time.millisecondsSinceEpoch ~/ 1000) % period);

  // ---------------------------------------------------------------------------
  // Shared RFC 4226 core
  // ---------------------------------------------------------------------------

  /// Decodes a user-supplied base32 secret, tolerating spaces and lowercase.
  static Uint8List decodeSecret(String secret) {
    final normalized = secret.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();
    if (normalized.isEmpty || !RegExp(r'^[A-Z2-7]+=*$').hasMatch(normalized)) {
      throw FormatException('Secret is not valid base32', secret);
    }
    try {
      return base32.decode(normalized);
    } on Object {
      throw FormatException('Secret is not valid base32', secret);
    }
  }

  /// RFC 4226 section 5.3: HMAC the counter, then dynamically truncate to
  /// 31 bits.
  static int truncatedHash({
    required String secret,
    required int counter,
    required OtpAlgorithm algorithm,
  }) {
    final key = decodeSecret(secret);

    final counterBytes = Uint8List(8);
    var remaining = counter;
    for (var i = 7; i >= 0; i--) {
      counterBytes[i] = remaining & 0xff;
      remaining >>= 8;
    }

    final mac = Hmac(algorithm.hash, key).convert(counterBytes).bytes;

    final offset = mac[mac.length - 1] & 0x0f;
    return ((mac[offset] & 0x7f) << 24) |
        ((mac[offset + 1] & 0xff) << 16) |
        ((mac[offset + 2] & 0xff) << 8) |
        (mac[offset + 3] & 0xff);
  }
}

/// RFC 6238 time-based codes.
class TotpGenerator extends OtpGenerator {
  const TotpGenerator();

  @override
  String generate({
    required String secret,
    required int counter,
    required int digits,
    required OtpAlgorithm algorithm,
  }) {
    final binary = OtpGenerator.truncatedHash(
      secret: secret,
      counter: counter,
      algorithm: algorithm,
    );
    return (binary % pow(10, digits).toInt()).toString().padLeft(digits, '0');
  }
}

/// RFC 4226 counter-based codes.
///
/// Identical rendering to TOTP; the difference is that the caller supplies a
/// stored counter that advances on use rather than one derived from the clock.
class HotpGenerator extends OtpGenerator {
  const HotpGenerator();

  @override
  String generate({
    required String secret,
    required int counter,
    required int digits,
    required OtpAlgorithm algorithm,
  }) {
    final binary = OtpGenerator.truncatedHash(
      secret: secret,
      counter: counter,
      algorithm: algorithm,
    );
    return (binary % pow(10, digits).toInt()).toString().padLeft(digits, '0');
  }
}

/// Steam's five-character variant.
///
/// Uses the same HMAC and truncation as RFC 6238, then encodes the truncated
/// value in base-26 against a custom alphabet that omits easily-confused
/// characters (0/O, 1/I/L). Cross-validated in tests against the reference
/// JS implementation (npm `steam-totp`).
class SteamGuardGenerator extends OtpGenerator {
  const SteamGuardGenerator();

  static const String alphabet = '23456789BCDFGHJKMNPQRTVWXY';
  static const int codeLength = 5;

  @override
  String generate({
    required String secret,
    required int counter,
    // Steam codes are always five characters; any digits value from an
    // otpauth URI is deliberately ignored.
    required int digits,
    required OtpAlgorithm algorithm,
  }) {
    var value = OtpGenerator.truncatedHash(
      secret: secret,
      counter: counter,
      algorithm: algorithm,
    );

    final buffer = StringBuffer();
    for (var i = 0; i < codeLength; i++) {
      buffer.write(alphabet[value % alphabet.length]);
      value ~/= alphabet.length;
    }
    return buffer.toString();
  }
}
