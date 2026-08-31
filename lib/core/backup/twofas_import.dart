import 'dart:convert';

import 'package:dula_auth/core/backup/third_party_import_result.dart';
import 'package:dula_auth/core/models/otp_account.dart';
import 'package:dula_auth/core/otp/otp_algorithm.dart';
import 'package:dula_auth/core/otp/otp_generator.dart';
import 'package:dula_auth/core/otp/otp_type.dart';

/// Parses a 2FAS backup export.
///
/// Callers: `lib/features/backup/**` (import screen). No data schema of its
/// own — produces [OtpAccount] values for the caller to hand to
/// `AccountRepository`.
///
/// Shape corroborated across multiple independent 2FAS decryption tools
/// (`wodny/decrypt-2fas-backup`, `elliotwutingfeng/2fas-backup-decryptor`):
/// top level carries `schemaVersion`, `appVersionCode`, `appVersionName`,
/// `appOrigin`, `servicesEncrypted`, `reference`; an unencrypted export also
/// carries a plaintext `services` array of `{name, secret, otp: {account,
/// issuer, digits, period, counter, algorithm, tokenType}}`.
///
/// **Password-protected exports are recognised but not decrypted.** 2FAS's
/// encrypted format uses a KDF and AEAD this project has no way to validate
/// an implementation against without a reference decoder or a real encrypted
/// fixture (unlike, say, the Steam Guard algorithm in ADR-0012, which was
/// cross-checked against `steam-totp`). Shipping an unverified decrypt of
/// someone's OTP vault is a worse outcome than declining to support it — see
/// docs/adr/0013-backup-export-and-import.md. The user is told to re-export
/// without a password rather than have the file rejected as unrecognised.
///
/// Input is an untrusted file, so any malformed shape yields
/// [ThirdPartyImportUnrecognized] — never a partial import.
class TwoFasImport {
  static ThirdPartyImportResult parse(
    String raw, {
    required String Function() newId,
  }) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return const ThirdPartyImportUnrecognized();
    }
    if (decoded is! Map<String, dynamic>) {
      return const ThirdPartyImportUnrecognized();
    }

    final encrypted = decoded['servicesEncrypted'];
    if (encrypted is String && encrypted.isNotEmpty) {
      return const ThirdPartyImportRequiresPassword();
    }

    final services = decoded['services'];
    if (services is! List) return const ThirdPartyImportUnrecognized();

    final accounts = <OtpAccount>[];
    for (final service in services) {
      if (service is! Map<String, dynamic>) {
        return const ThirdPartyImportUnrecognized();
      }
      final account = _parseService(service, newId());
      if (account == null) return const ThirdPartyImportUnrecognized();
      accounts.add(account);
    }

    return ThirdPartyImportSuccess(accounts);
  }

  static OtpAccount? _parseService(Map<String, dynamic> service, String id) {
    final otp = service['otp'];
    if (otp is! Map<String, dynamic>) return null;

    final type = switch ((otp['tokenType'] as String?)?.toUpperCase()) {
      'TOTP' => OtpType.totp,
      'HOTP' => OtpType.hotp,
      'STEAM' => OtpType.steam,
      _ => null,
    };
    if (type == null) return null;

    final secret =
        (service['secret'] as String?)?.trim().toUpperCase() ?? '';
    if (secret.isEmpty) return null;
    try {
      OtpGenerator.decodeSecret(secret);
    } on FormatException {
      return null;
    }

    // 2FAS allows a blank account label when the service name carries the
    // identifying text instead (e.g. "Backup Codes").
    final account = (otp['account'] as String?)?.trim() ?? '';
    final name = (service['name'] as String?)?.trim() ?? '';

    return OtpAccount(
      id: id,
      issuer: otp['issuer'] as String? ?? '',
      accountName: account.isNotEmpty ? account : name,
      secret: secret,
      type: type,
      digits:
          type == OtpType.steam ? 5 : (otp['digits'] as num?)?.toInt() ?? 6,
      period: (otp['period'] as num?)?.toInt() ?? 30,
      algorithm: OtpAlgorithm.fromName(otp['algorithm'] as String?),
      counter: (otp['counter'] as num?)?.toInt() ?? 0,
    );
  }
}
