import 'dart:convert';

import 'package:dula_auth/core/crypto/vault_crypto.dart';
import 'package:dula_auth/core/models/otp_account.dart';
import 'package:dula_auth/core/vault/secret_store.dart';
import 'package:dula_auth/core/vault/vault_service.dart';

/// Raised when a stored secret cannot be decrypted.
///
/// Surfaced rather than swallowed: a secret that fails authentication has been
/// tampered with or was written under a different key, and generating codes
/// from a silently-empty secret would produce plausible-looking but wrong
/// output — the worst failure mode for an authenticator.
class VaultDecryptionException implements Exception {
  final String accountId;

  const VaultDecryptionException(this.accountId);

  @override
  String toString() =>
      'Could not decrypt the stored secret for account "$accountId". '
      'The vault may be corrupted or was written by a different installation.';
}

class AccountRepository {
  final SecretStore _store;
  final VaultService _vault;

  static const String _accountsKey = VaultService.accountsKey;

  AccountRepository({SecretStore? store, VaultService? vault})
      : _store = store ?? const FlutterSecretStore(),
        _vault = vault ?? VaultService(store ?? const FlutterSecretStore());

  /// Loads all accounts, decrypting secrets when [masterKey] is supplied.
  ///
  /// Throws [VaultDecryptionException] if a secret cannot be decrypted.
  Future<List<OtpAccount>> getAccounts({MasterKey? masterKey}) async {
    final raw = await _store.read(_accountsKey);
    if (raw == null || raw.isEmpty) return [];

    final decoded = jsonDecode(raw) as List<dynamic>;
    final accounts = decoded
        .map((item) => OtpAccount.fromMap(item as Map<String, dynamic>))
        .toList();

    if (masterKey == null) return accounts;

    final result = <OtpAccount>[];
    for (final account in accounts) {
      if (account.secret.isEmpty) {
        result.add(account);
        continue;
      }
      final plaintext = await _vault.decryptSecret(account.secret, masterKey);
      if (plaintext == null) {
        throw VaultDecryptionException(account.id);
      }
      result.add(account.copyWith(secret: plaintext));
    }
    return result;
  }

  Future<void> _saveAccounts(
    List<OtpAccount> accounts, {
    MasterKey? masterKey,
  }) async {
    final toSave = <OtpAccount>[];
    for (final account in accounts) {
      if (masterKey == null || account.secret.isEmpty) {
        toSave.add(account);
        continue;
      }
      toSave.add(
        account.copyWith(
          secret: await _vault.encryptSecret(account.secret, masterKey),
        ),
      );
    }

    await _store.write(
      _accountsKey,
      jsonEncode(toSave.map((a) => a.toMap()).toList()),
    );
  }

  /// Adds an account. Returns false if the id is already present.
  Future<bool> addAccount(OtpAccount account, {MasterKey? masterKey}) async {
    final accounts = await getAccounts(masterKey: masterKey);
    if (accounts.any((a) => a.id == account.id)) return false;

    accounts.add(account);
    await _saveAccounts(accounts, masterKey: masterKey);
    return true;
  }

  /// Updates an existing account. Returns false if it was not found.
  Future<bool> updateAccount(
    OtpAccount updatedAccount, {
    MasterKey? masterKey,
  }) async {
    final accounts = await getAccounts(masterKey: masterKey);
    final index = accounts.indexWhere((a) => a.id == updatedAccount.id);
    if (index == -1) return false;

    accounts[index] = updatedAccount;
    await _saveAccounts(accounts, masterKey: masterKey);
    return true;
  }

  /// Deletes an account by id. Returns false if it was not found.
  Future<bool> deleteAccount(String id, {MasterKey? masterKey}) async {
    final accounts = await getAccounts(masterKey: masterKey);
    final initialLength = accounts.length;
    accounts.removeWhere((a) => a.id == id);
    if (accounts.length == initialLength) return false;

    await _saveAccounts(accounts, masterKey: masterKey);
    return true;
  }

  Future<void> clearAll() => _store.delete(_accountsKey);
}
