import 'package:dula_auth/core/models/otp_account.dart';
import 'package:dula_auth/core/otp/otp_algorithm.dart';
import 'package:dula_auth/core/otp/otp_generator.dart';
import 'package:dula_auth/core/otp/otp_type.dart';

/// Reads and writes `otpauth://` credential URIs.
///
/// This is the single place QR payloads are interpreted. Every value it
/// produces comes from the URI rather than from defaults assumed at the call
/// site — the previous inline parser discarded `digits`, `period` and
/// `algorithm`, which silently produced wrong codes for any non-default
/// credential (see docs/adr/0012-pluggable-otp-types.md).
///
/// Input is untrusted (it arrives from a scanned QR code or pasted text), so
/// anything malformed yields null rather than a partially-populated account.
class OtpUri {
  /// Digit counts a credential may legitimately request.
  static const int minDigits = 6;
  static const int maxDigits = 10;

  static OtpAccount? parse(String raw, {required String id}) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    final Uri uri;
    try {
      uri = Uri.parse(trimmed);
    } on FormatException {
      return null;
    }

    if (uri.scheme.toLowerCase() != 'otpauth') return null;

    final params = uri.queryParameters;

    // Type comes from the host, with Aegis/2FAS-style `encoder=steam` also
    // recognised since Steam credentials are commonly published as totp.
    final host = uri.host.toLowerCase();
    final OtpType type;
    if (host == 'steam' || params['encoder']?.toLowerCase() == 'steam') {
      type = OtpType.steam;
    } else if (host == 'hotp') {
      type = OtpType.hotp;
    } else if (host == 'totp') {
      type = OtpType.totp;
    } else {
      // An unrecognised type would be stored and then generate wrong codes.
      return null;
    }

    final secret = params['secret']?.trim() ?? '';
    if (secret.isEmpty) return null;
    try {
      OtpGenerator.decodeSecret(secret);
    } on FormatException {
      return null;
    }

    // Label is "Issuer:Account" or just "Account"; the path retains percent
    // encoding, so decode before splitting on the separator.
    final label = uri.path.startsWith('/') ? uri.path.substring(1) : uri.path;
    final decodedLabel = Uri.decodeComponent(label);

    var issuer = params['issuer']?.trim() ?? '';
    var accountName = decodedLabel;
    final separator = decodedLabel.indexOf(':');
    if (separator >= 0) {
      final prefix = decodedLabel.substring(0, separator).trim();
      accountName = decodedLabel.substring(separator + 1).trim();
      if (issuer.isEmpty) issuer = prefix;
    }

    final digits = type == OtpType.steam
        ? 5
        : _clampInt(params['digits'],
            fallback: 6, min: minDigits, max: maxDigits);
    final period = _clampInt(params['period'], fallback: 30, min: 1, max: 300);
    final counter =
        _clampInt(params['counter'], fallback: 0, min: 0, max: 1 << 40);

    return OtpAccount(
      id: id,
      issuer: issuer,
      accountName: accountName,
      secret: secret.replaceAll(RegExp(r'\s'), '').toUpperCase(),
      type: type,
      digits: digits,
      period: period,
      algorithm: OtpAlgorithm.fromName(params['algorithm']),
      counter: counter,
    );
  }

  /// Renders [account] as an `otpauth://` URI.
  static String toUri(OtpAccount account) {
    final label = account.issuer.isNotEmpty
        ? '${Uri.encodeComponent(account.issuer)}:'
            '${Uri.encodeComponent(account.accountName)}'
        : Uri.encodeComponent(account.accountName);

    final params = <String, String>{
      'secret': account.secret,
      if (account.issuer.isNotEmpty) 'issuer': account.issuer,
      'algorithm': account.algorithm.name.toUpperCase(),
      'digits': '${account.digits}',
      if (account.type.isTimeBased) 'period': '${account.period}',
      if (account.type == OtpType.hotp) 'counter': '${account.counter}',
      if (account.type == OtpType.steam) 'encoder': 'steam',
    };

    final query = params.entries
        .map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');

    return 'otpauth://${account.type.uriValue}/$label?$query';
  }

  /// Parses an integer parameter, falling back when absent or out of range.
  ///
  /// Values are clamped rather than trusted: a hostile or broken QR code
  /// specifying `digits=99` would otherwise overflow code generation.
  static int _clampInt(
    String? raw, {
    required int fallback,
    required int min,
    required int max,
  }) {
    final parsed = int.tryParse(raw ?? '');
    if (parsed == null) return fallback;
    if (parsed < min || parsed > max) return fallback;
    return parsed;
  }
}
