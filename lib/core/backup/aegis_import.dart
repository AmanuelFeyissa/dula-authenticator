import 'dart:convert';

import 'package:dula_auth/core/backup/third_party_import_result.dart';
import 'package:dula_auth/core/models/otp_account.dart';
import 'package:dula_auth/core/otp/otp_algorithm.dart';
import 'package:dula_auth/core/otp/otp_generator.dart';
import 'package:dula_auth/core/otp/otp_type.dart';

/// Parses an Aegis vault export.
///
/// Callers: `lib/features/backup/**` (import screen). No data schema of its
/// own — produces [OtpAccount] values for the caller to hand to
/// `AccountRepository`.
///
/// Format per Aegis's own documentation:
/// https://github.com/beemdevelopment/Aegis/blob/master/docs/vault.md — a
/// vault is `{version, header, db}`. When unencrypted, `db` is an object with
/// an `entries` array; when password-protected, `db` is an opaque base64
/// string and `header.slots` carries the scrypt/AES-GCM parameters needed to
/// decrypt it.
///
/// **Encrypted vaults are recognised but not decrypted.** This app does not
/// implement Aegis's encryption scheme: doing so without a reference
/// implementation to validate against (unlike the Steam Guard algorithm in
/// ADR-0012, which was cross-checked against `steam-totp`) risks a subtly
/// wrong decrypt of someone's OTP vault, which is worse than declining to
/// support it. See docs/adr/0013-backup-export-and-import.md for the scope
/// decision. A user with an encrypted vault is told to re-export without a
/// password rather than have the file silently rejected as unrecognised.
///
/// Input is an untrusted file, so any malformed shape yields
/// [ThirdPartyImportUnrecognized] — never a partial import.
class AegisImport {
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

    final db = decoded['db'];
    if (db is String) return const ThirdPartyImportRequiresPassword();
    if (db is! Map<String, dynamic>) {
      return const ThirdPartyImportUnrecognized();
    }

    final entries = db['entries'];
    if (entries is! List) return const ThirdPartyImportUnrecognized();

    final accounts = <OtpAccount>[];
    for (final entry in entries) {
      if (entry is! Map<String, dynamic>) {
        return const ThirdPartyImportUnrecognized();
      }
      final account = _parseEntry(entry, newId());
      if (account == null) return const ThirdPartyImportUnrecognized();
      accounts.add(account);
    }

    return ThirdPartyImportSuccess(accounts);
  }

  static OtpAccount? _parseEntry(Map<String, dynamic> entry, String id) {
    final type = switch ((entry['type'] as String?)?.toLowerCase()) {
      'totp' => OtpType.totp,
      'hotp' => OtpType.hotp,
      'steam' => OtpType.steam,
      _ => null,
    };
    if (type == null) return null;

    final info = entry['info'];
    if (info is! Map<String, dynamic>) return null;

    final secret = (info['secret'] as String?)?.trim().toUpperCase() ?? '';
    if (secret.isEmpty) return null;
    try {
      OtpGenerator.decodeSecret(secret);
    } on FormatException {
      return null;
    }

    return OtpAccount(
      id: id,
      issuer: entry['issuer'] as String? ?? '',
      accountName: entry['name'] as String? ?? '',
      secret: secret,
      type: type,
      digits: type == OtpType.steam
          ? 5
          : (info['digits'] as num?)?.toInt() ?? 6,
      period: (info['period'] as num?)?.toInt() ?? 30,
      algorithm: OtpAlgorithm.fromName(info['algo'] as String?),
      counter: (info['counter'] as num?)?.toInt() ?? 0,
    );
  }
}
