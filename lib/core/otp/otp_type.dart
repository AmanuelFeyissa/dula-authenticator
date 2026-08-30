/// The kind of one-time password a credential produces.
///
/// See docs/adr/0012-pluggable-otp-types.md.
enum OtpType {
  /// Time-based, RFC 6238. The overwhelmingly common case.
  totp,

  /// Counter-based, RFC 4226. Used by hardware tokens and some enterprise
  /// systems; the counter advances on use rather than with the clock.
  hotp,

  /// Steam's variant: time-based, but rendered as five characters from a
  /// custom alphabet instead of decimal digits.
  steam;

  /// The `type` component of an `otpauth://` URI.
  String get uriValue => switch (this) {
        OtpType.totp => 'totp',
        OtpType.hotp => 'hotp',
        OtpType.steam => 'totp',
      };

  String get label => switch (this) {
        OtpType.totp => 'Time-based (TOTP)',
        OtpType.hotp => 'Counter-based (HOTP)',
        OtpType.steam => 'Steam Guard',
      };

  /// Whether codes refresh on a timer rather than on demand.
  bool get isTimeBased => this != OtpType.hotp;

  static OtpType fromName(String? name) => switch (name?.toLowerCase()) {
        'hotp' => OtpType.hotp,
        'steam' => OtpType.steam,
        _ => OtpType.totp,
      };
}
