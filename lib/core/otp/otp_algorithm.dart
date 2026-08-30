import 'package:crypto/crypto.dart' as crypto;

/// HMAC hash used to derive a one-time password.
///
/// SHA-1 is the near-universal default in deployed systems. The stronger
/// variants exist in RFC 6238 but interoperate unevenly outside the issuing
/// service's own app, so they are honoured when a credential specifies them
/// rather than preferred by default.
enum OtpAlgorithm {
  sha1,
  sha256,
  sha512;

  crypto.Hash get hash => switch (this) {
        OtpAlgorithm.sha1 => crypto.sha1,
        OtpAlgorithm.sha256 => crypto.sha256,
        OtpAlgorithm.sha512 => crypto.sha512,
      };

  String get label => switch (this) {
        OtpAlgorithm.sha1 => 'SHA-1',
        OtpAlgorithm.sha256 => 'SHA-256',
        OtpAlgorithm.sha512 => 'SHA-512',
      };

  /// Parses the `algorithm` parameter of an `otpauth://` URI.
  static OtpAlgorithm fromName(String? name) => switch (name?.toUpperCase()) {
        'SHA256' || 'SHA-256' => OtpAlgorithm.sha256,
        'SHA512' || 'SHA-512' => OtpAlgorithm.sha512,
        _ => OtpAlgorithm.sha1,
      };
}
