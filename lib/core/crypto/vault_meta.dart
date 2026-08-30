import 'dart:convert';

import 'package:dula_auth/core/crypto/vault_crypto.dart';
import 'package:dula_auth/core/security/credential_kind.dart';

/// Format record for the on-device vault.
///
/// Stored alongside the encrypted account data so the app knows which
/// cryptographic scheme the stored values use, and with which KDF cost
/// parameters. Recording the parameters rather than hardcoding them means the
/// Argon2id cost can be raised in a future release without making
/// already-encrypted vaults unreadable — and the version field gives a future
/// release a hook for migrating to a different scheme entirely.
///
/// See docs/adr/0010-vault-cryptography-modernization.md.
class VaultMeta {
  /// Argon2id key derivation + AES-256-GCM.
  static const int currentVersion = 1;

  final int version;
  final KdfParams kdfParams;

  /// Which knowledge factor opens this vault.
  ///
  /// Recorded here rather than in app preferences because the lock screen
  /// needs it before anything is decrypted, and because preferences can be
  /// cleared independently of the vault — which would leave the app offering
  /// the wrong input for a vault that still exists (ADR-0011).
  final CredentialKind credentialKind;

  const VaultMeta({
    required this.version,
    required this.kdfParams,
    this.credentialKind = CredentialKind.pin,
  });

  /// A vault this build knows how to open.
  ///
  /// A newer version means the vault was written by a later release; refusing
  /// it is safer than guessing at a format we do not understand.
  bool get isSupported => version == currentVersion;

  String toJson() => jsonEncode({
        'v': version,
        'kdf': kdfParams.toMap(),
        'cred': credentialKind.name,
      });

  /// Parses a stored metadata record. Missing or unreadable metadata yields
  /// the current version with default parameters, which the verifier check
  /// will then reject if the vault does not actually match.
  factory VaultMeta.fromJson(String? raw) {
    if (raw == null || raw.isEmpty) {
      return const VaultMeta(
        version: currentVersion,
        kdfParams: KdfParams.owaspDefault,
        credentialKind: CredentialKind.passphrase,
      );
    }
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final kdf = map['kdf'];
      return VaultMeta(
        version: map['v'] as int? ?? currentVersion,
        kdfParams: kdf is Map<String, dynamic>
            ? KdfParams.fromMap(kdf)
            : KdfParams.owaspDefault,
        credentialKind: CredentialKind.fromName(map['cred'] as String?),
      );
    } catch (_) {
      return const VaultMeta(
        version: currentVersion,
        kdfParams: KdfParams.owaspDefault,
        credentialKind: CredentialKind.passphrase,
      );
    }
  }
}
