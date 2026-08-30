import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:dula_auth/core/crypto/vault_crypto.dart';
import 'package:dula_auth/core/crypto/vault_meta.dart';
import 'package:dula_auth/core/security/credential_kind.dart';
import 'package:dula_auth/core/vault/secret_store.dart';

/// Outcome of an unlock attempt. [key] is null when the credential was wrong.
class UnlockResult {
  final MasterKey? key;

  const UnlockResult({this.key});

  bool get isUnlocked => key != null;

  static const UnlockResult failed = UnlockResult();
}

/// Owns the encrypted vault: credential verification, key derivation, and
/// secret encryption.
///
/// Secrets are sealed with AES-256-GCM under a key derived by Argon2id; the
/// vault records its format version and KDF cost parameters so a future
/// release can raise the cost, or change the scheme, without stranding
/// existing data (see docs/adr/0010-vault-cryptography-modernization.md).
class VaultService {
  static const String metaKey = 'vault_meta';
  static const String saltKey = 'vault_salt';
  static const String verifierKey = 'vault_verifier';
  static const String accountsKey = 'vault_accounts';

  final SecretStore _store;
  final KdfParams _params;

  VaultService(this._store, {KdfParams params = KdfParams.owaspDefault})
      : _params = params;

  /// Whether a credential has been set up.
  Future<bool> isInitialized() async {
    final verifier = await _store.read(verifierKey);
    return verifier != null && verifier.isNotEmpty;
  }

  /// Creates a new vault protected by [password].
  ///
  /// [kind] records which knowledge factor the user chose, so the lock screen
  /// can present the matching input without unlocking anything first.
  ///
  /// The raw credential is never stored — only a random salt and a verifier
  /// derived from the Argon2id output.
  Future<MasterKey> initialize(
    String password, {
    CredentialKind kind = CredentialKind.pin,
  }) async {
    final salt = _randomSalt();
    final key = await VaultCrypto.deriveKey(password, salt, _params);

    await _store.write(saltKey, base64.encode(salt));
    await _store.write(verifierKey, VaultCrypto.verifierFor(key));
    await _store.write(
      metaKey,
      VaultMeta(
        version: VaultMeta.currentVersion,
        kdfParams: _params,
        credentialKind: kind,
      ).toJson(),
    );

    return key;
  }

  /// Which credential opens this vault. Readable while locked.
  Future<CredentialKind> credentialKind() async =>
      VaultMeta.fromJson(await _store.read(metaKey)).credentialKind;

  /// Verifies [password] and returns the vault key.
  Future<UnlockResult> unlock(String password) async {
    final meta = VaultMeta.fromJson(await _store.read(metaKey));
    if (!meta.isSupported) return UnlockResult.failed;

    final saltB64 = await _store.read(saltKey);
    final expected = await _store.read(verifierKey);
    if (saltB64 == null || expected == null) return UnlockResult.failed;

    // Derive using the parameters this vault was created with, not the current
    // defaults, so raising the cost in a later release stays backward safe.
    final key = await VaultCrypto.deriveKey(
      password,
      Uint8List.fromList(base64.decode(saltB64)),
      meta.kdfParams,
    );

    if (VaultCrypto.verifierFor(key) != expected) return UnlockResult.failed;

    return UnlockResult(key: key);
  }

  /// Re-keys the vault to a new credential, re-encrypting stored accounts.
  ///
  /// The rewritten accounts are persisted before the new salt and verifier, so
  /// a failure partway through leaves the old credential working rather than
  /// producing a vault nobody can open.
  /// [newKind] switches the credential type at the same time (PIN to
  /// passphrase or back); omit it to keep the current kind.
  Future<bool> changeCredential({
    required String currentPassword,
    required String newPassword,
    CredentialKind? newKind,
  }) async {
    final current = await unlock(currentPassword);
    if (!current.isUnlocked) return false;

    // Read before the metadata is overwritten below.
    final kind = newKind ?? await credentialKind();
    final newSalt = _randomSalt();
    final newKey = await VaultCrypto.deriveKey(newPassword, newSalt, _params);

    try {
      final raw = await _store.read(accountsKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw) as List<dynamic>;
        final rewritten = <Map<String, dynamic>>[];

        for (final entry in decoded) {
          final account = Map<String, dynamic>.from(entry as Map);
          final sealed = account['secret'] as String? ?? '';
          if (sealed.isNotEmpty) {
            final plaintext =
                await VaultCrypto.decrypt(sealed, current.key!);
            if (plaintext == null) return false;
            account['secret'] = await VaultCrypto.encrypt(plaintext, newKey);
          }
          rewritten.add(account);
        }

        await _store.write(accountsKey, jsonEncode(rewritten));
      }

      await _store.write(saltKey, base64.encode(newSalt));
      await _store.write(verifierKey, VaultCrypto.verifierFor(newKey));
      await _store.write(
        metaKey,
        VaultMeta(
          version: VaultMeta.currentVersion,
          kdfParams: _params,
          credentialKind: kind,
        ).toJson(),
      );
    } catch (_) {
      return false;
    }

    return true;
  }

  Future<String> encryptSecret(String plaintext, MasterKey key) =>
      VaultCrypto.encrypt(plaintext, key);

  /// Returns null when the value is missing, tampered with, or was encrypted
  /// under a different key. Callers must not treat null as an empty secret.
  Future<String?> decryptSecret(String sealed, MasterKey key) =>
      VaultCrypto.decrypt(sealed, key);

  /// Wipes all vault state. Used by the "forgot credential" reset flow.
  Future<void> reset() async {
    await _store.delete(metaKey);
    await _store.delete(saltKey);
    await _store.delete(verifierKey);
    await _store.delete(accountsKey);
  }

  Uint8List _randomSalt() {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(32, (_) => random.nextInt(256)),
    );
  }
}
