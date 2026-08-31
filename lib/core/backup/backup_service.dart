import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:dula_auth/core/crypto/vault_crypto.dart';
import 'package:dula_auth/core/models/otp_account.dart';
import 'package:dula_auth/core/security/passphrase_policy.dart';

/// Outcome of [BackupService.export].
sealed class BackupExportResult {
  const BackupExportResult();
}

class BackupExportSuccess extends BackupExportResult {
  final String fileContent;
  const BackupExportSuccess(this.fileContent);
}

/// The passphrase failed policy. Export never proceeds on a weak passphrase —
/// enforced here, not only suggested in the UI, per ADR-0013's Risks section.
class BackupExportRejected extends BackupExportResult {
  final String reason;
  const BackupExportRejected(this.reason);
}

/// Outcome of [BackupService.import].
sealed class BackupImportResult {
  const BackupImportResult();
}

class BackupImportSuccess extends BackupImportResult {
  final List<OtpAccount> accounts;
  const BackupImportSuccess(this.accounts);
}

/// The file is a recognised, supported-version backup, but the passphrase did
/// not open it. GCM authentication failure and "wrong key" are the same
/// event cryptographically, so this also covers a corrupted payload — both
/// mean "this passphrase does not open this file."
class BackupImportWrongPassphrase extends BackupImportResult {
  const BackupImportWrongPassphrase();
}

/// Not a backup file this version understands: not JSON, missing required
/// fields, or written by an unsupported format version.
class BackupImportMalformed extends BackupImportResult {
  const BackupImportMalformed();
}

/// Encrypted local export/import for the vault, independent of device
/// storage.
///
/// Callers: `lib/features/backup/**` (export/import screens). Data schema —
/// the file is a JSON envelope:
/// ```json
/// {
///   "v": 1,
///   "app": "dula-auth-backup",
///   "kdf": {"alg": "argon2id", "m": 19456, "t": 2, "p": 1},
///   "salt": "<base64>",
///   "payload": "<base64 AES-256-GCM sealed JSON account array>"
/// }
/// ```
/// The decrypted payload is `jsonEncode(accounts.map((a) => a.toMap()))`
/// (see `OtpAccount.toMap`), so a restored account keeps every field: type,
/// digits, period, algorithm, counter — not just the secret.
///
/// Reuses the same Argon2id + AES-256-GCM primitives as the vault itself
/// (ADR-0010), under an **independent** passphrase — never the PIN or vault
/// passphrase, per ADR-0013 §2: once a backup file leaves the device, none of
/// the on-device protections (secure storage, lockout) apply, so a 6-digit
/// PIN's keyspace is not adequate protection for an offline file regardless
/// of KDF cost.
///
/// See docs/adr/0013-backup-export-and-import.md.
class BackupService {
  static const int formatVersion = 1;
  static const String appIdentifier = 'dula-auth-backup';

  static Future<BackupExportResult> export(
    List<OtpAccount> accounts,
    String passphrase, {
    KdfParams? params,
  }) async {
    final policyError = PassphrasePolicy.validate(passphrase);
    if (policyError != null) return BackupExportRejected(policyError);

    final resolvedParams = params ?? KdfParams.deploymentDefault;
    final salt = _randomSalt();
    final key = await VaultCrypto.deriveKey(passphrase, salt, resolvedParams);
    final plaintext = jsonEncode(accounts.map((a) => a.toMap()).toList());
    final sealed = await VaultCrypto.encrypt(plaintext, key);

    final envelope = {
      'v': formatVersion,
      'app': appIdentifier,
      'kdf': resolvedParams.toMap(),
      'salt': base64.encode(salt),
      'payload': sealed,
    };
    return BackupExportSuccess(jsonEncode(envelope));
  }

  static Future<BackupImportResult> import(
    String fileContent,
    String passphrase,
  ) async {
    final Object? decoded;
    try {
      decoded = jsonDecode(fileContent);
    } on FormatException {
      return const BackupImportMalformed();
    }
    if (decoded is! Map<String, dynamic>) {
      return const BackupImportMalformed();
    }

    if (decoded['v'] != formatVersion) return const BackupImportMalformed();

    final kdfMap = decoded['kdf'];
    final saltB64 = decoded['salt'];
    final payload = decoded['payload'];
    if (kdfMap is! Map<String, dynamic> ||
        saltB64 is! String ||
        payload is! String) {
      return const BackupImportMalformed();
    }

    final Uint8List salt;
    try {
      salt = base64.decode(saltB64);
    } on FormatException {
      return const BackupImportMalformed();
    }

    final key = await VaultCrypto.deriveKey(
      passphrase,
      salt,
      KdfParams.fromMap(kdfMap),
    );

    final plaintext = await VaultCrypto.decrypt(payload, key);
    if (plaintext == null) return const BackupImportWrongPassphrase();

    try {
      final decodedAccounts = jsonDecode(plaintext) as List<dynamic>;
      final accounts = decodedAccounts
          .map((m) => OtpAccount.fromMap(m as Map<String, dynamic>))
          .toList();
      return BackupImportSuccess(accounts);
    } on Object {
      // The payload decrypted (so the passphrase was right) but did not
      // contain the shape this version expects — a backup from an
      // incompatible or corrupted source.
      return const BackupImportMalformed();
    }
  }

  static Uint8List _randomSalt() {
    final random = Random.secure();
    return Uint8List.fromList(List<int>.generate(32, (_) => random.nextInt(256)));
  }
}
