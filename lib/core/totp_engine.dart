import 'dart:math';
import 'dart:typed_data';
import 'package:base32/base32.dart';
import 'package:crypto/crypto.dart';

enum TotpAlgorithm { sha1, sha256, sha512 }

class TotpEngine {
  /// Generates a TOTP code based on RFC 6238.
  /// 
  /// [secret] is the base32 encoded secret key.
  /// [time] is the current time.
  /// [digits] is the length of the TOTP code (default 6).
  /// [period] is the time step in seconds (default 30).
  /// [algorithm] is the hash algorithm to use.
  static String generateCode({
    required String secret,
    required DateTime time,
    int digits = 6,
    int period = 30,
    TotpAlgorithm algorithm = TotpAlgorithm.sha1,
  }) {
    // 1. Decode the secret
    final String normalizedSecret = secret.replaceAll(' ', '').toUpperCase();
    final Uint8List secretBytes = base32.decode(normalizedSecret);

    // 2. Calculate the counter
    final int currentTimeSeconds = time.millisecondsSinceEpoch ~/ 1000;
    final int counter = currentTimeSeconds ~/ period;

    // 3. Generate the code
    return generateCodeFromCounter(
      secretBytes: secretBytes,
      counter: counter,
      digits: digits,
      algorithm: algorithm,
    );
  }

  /// Extracts the remaining seconds until the next TOTP code is generated.
  static int getRemainingSeconds({
    required DateTime time,
    int period = 30,
  }) {
    final int currentTimeSeconds = time.millisecondsSinceEpoch ~/ 1000;
    return period - (currentTimeSeconds % period);
  }

  /// HOTP algorithm (RFC 4226) based code generation
  static String generateCodeFromCounter({
    required Uint8List secretBytes,
    required int counter,
    int digits = 6,
    TotpAlgorithm algorithm = TotpAlgorithm.sha1,
  }) {
    // Convert counter to an 8-byte big-endian array
    final Uint8List counterBytes = Uint8List(8);
    for (int i = 7; i >= 0; i--) {
      counterBytes[i] = (counter & 0xff);
      counter >>= 8;
    }

    // Determine the Mac
    Hash hashFunction;
    switch (algorithm) {
      case TotpAlgorithm.sha1:
        hashFunction = sha1;
        break;
      case TotpAlgorithm.sha256:
        hashFunction = sha256;
        break;
      case TotpAlgorithm.sha512:
        hashFunction = sha512;
        break;
    }

    final Hmac hmac = Hmac(hashFunction, secretBytes);
    final Digest digest = hmac.convert(counterBytes);
    final List<int> mac = digest.bytes;

    // Dynamic truncation
    final int offset = mac[mac.length - 1] & 0xf;
    final int binaryCode = ((mac[offset] & 0x7f) << 24) |
        ((mac[offset + 1] & 0xff) << 16) |
        ((mac[offset + 2] & 0xff) << 8) |
        (mac[offset + 3] & 0xff);

    // Modulo to get target digits
    final int code = binaryCode % pow(10, digits).toInt();

    // Zero pad
    return code.toString().padLeft(digits, '0');
  }
}
