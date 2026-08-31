import 'dart:convert';

import 'package:dula_auth/core/crypto/vault_crypto.dart';
import 'package:dula_auth/core/models/otp_account.dart';
import 'package:dula_auth/core/vault/secret_store.dart';
import 'package:dula_auth/core/vault/vault_service.dart';

class AccountRepository {
  final SecretStore _store;
  final VaultService _vault;

  static const String _accountsKey = VaultService.accountsKey;

  AccountRepository({SecretStore? store, VaultService? vault})
      : _store = store ?? const FlutterSecretStore(),
        _vault = vault ?? VaultService(store ?? const FlutterSecretStore());

  /// Loads all accounts, decrypting secrets when [masterKey] is supplied.
  ///
  /// An account whose secret fails to decrypt — tampered ciphertext, or a key
  /// from a different vault — is returned with [OtpAccount.loadError] set
  /// rather than aborting the whole load: one corrupted record must not make
  /// every other account unreachable too (docs/adr/0015-account-management.md
  /// §7). Its `secret` is left as the undecrypted ciphertext, which callers
  /// must never treat as usable — check `loadError` first.
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
        result.add(account.copyWith(
          loadError: 'Could not decrypt this account\'s secret. The vault '
              'may be corrupted, or this account was written by a different '
              'installation.',
        ));
        continue;
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

  /// Rewrites the persisted account order to [orderedIds].
  ///
  /// There is no separate sort-order field (ADR-0015 §3): the array position
  /// in storage *is* the order, so reordering is just rewriting that array.
  /// Returns false, changing nothing, unless [orderedIds] names every
  /// currently-stored account exactly once — a partial list would either
  /// silently drop an account or leave its position undefined, and neither
  /// is an acceptable outcome of a drag gesture.
  Future<bool> reorderAccounts(
    List<String> orderedIds, {
    MasterKey? masterKey,
  }) async {
    final accounts = await getAccounts(masterKey: masterKey);
    if (orderedIds.length != accounts.length) return false;
    if (orderedIds.toSet().length != orderedIds.length) return false;

    final byId = {for (final a in accounts) a.id: a};
    final reordered = <OtpAccount>[];
    for (final id in orderedIds) {
      final match = byId[id];
      if (match == null) return false;
      reordered.add(match);
    }

    await _saveAccounts(reordered, masterKey: masterKey);
    return true;
  }

  Future<void> clearAll() => _store.delete(_accountsKey);
}
