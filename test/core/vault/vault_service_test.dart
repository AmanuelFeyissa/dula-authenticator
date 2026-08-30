import 'package:flutter_test/flutter_test.dart';
import 'package:dula_auth/core/crypto/vault_crypto.dart';
import 'package:dula_auth/core/crypto/vault_meta.dart';
import 'package:dula_auth/core/vault/secret_store.dart';
import 'package:dula_auth/core/vault/vault_service.dart';

/// Fast KDF parameters so the suite stays quick. Production uses
/// [KdfParams.owaspDefault]; a separate test asserts that default is sane.
const testParams = KdfParams(memoryKiB: 256, iterations: 1, parallelism: 1);

void main() {
  late InMemorySecretStore store;
  late VaultService vault;

  setUp(() {
    store = InMemorySecretStore({});
    vault = VaultService(store, params: testParams);
  });

  group('setup', () {
    test('is not initialized before a credential is set', () async {
      expect(await vault.isInitialized(), isFalse);
    });

    test('initialize records the vault format and reports initialized',
        () async {
      await vault.initialize('correct horse battery');

      expect(await vault.isInitialized(), isTrue);
      expect(
        VaultMeta.fromJson(await store.read(VaultService.metaKey)).version,
        VaultMeta.currentVersion,
      );
    });

    test('never stores the raw credential', () async {
      await vault.initialize('correct horse battery');

      expect(
        store.dump().values.join(' '),
        isNot(contains('correct horse battery')),
      );
    });

    test('generates a distinct salt per vault', () async {
      await vault.initialize('correct horse battery');
      final firstSalt = await store.read(VaultService.saltKey);

      final other = VaultService(InMemorySecretStore({}), params: testParams);
      await other.initialize('correct horse battery');

      expect(firstSalt, isNotNull);
      // Same password, different vault: the stored salt must differ, otherwise
      // identical credentials would derive identical keys across installs.
      final secondStore = InMemorySecretStore({});
      final third = VaultService(secondStore, params: testParams);
      await third.initialize('correct horse battery');
      expect(await secondStore.read(VaultService.saltKey), isNot(firstSalt));
    });
  });

  group('unlock', () {
    test('unlocks with the correct credential', () async {
      await vault.initialize('correct horse battery');

      expect((await vault.unlock('correct horse battery')).isUnlocked, isTrue);
    });

    test('rejects the wrong credential', () async {
      await vault.initialize('correct horse battery');

      expect((await vault.unlock('wrong horse battery')).isUnlocked, isFalse);
    });

    test('rejects unlocking an uninitialized vault', () async {
      expect((await vault.unlock('anything')).isUnlocked, isFalse);
    });

    test('derives the same key across unlocks', () async {
      await vault.initialize('correct horse battery');

      final first = await vault.unlock('correct horse battery');
      final second = await vault.unlock('correct horse battery');

      expect(first.key, second.key);
    });

    test('refuses a vault written by a newer version of the app', () async {
      await vault.initialize('correct horse battery');
      await store.write(
        VaultService.metaKey,
        '{"v":${VaultMeta.currentVersion + 1},"kdf":{"alg":"argon2id","m":256,"t":1,"p":1}}',
      );

      expect((await vault.unlock('correct horse battery')).isUnlocked, isFalse,
          reason: 'guessing at an unknown vault format risks data loss');
    });
  });

  group('secrets', () {
    test('round-trips a secret through the derived key', () async {
      await vault.initialize('correct horse battery');
      final key = (await vault.unlock('correct horse battery')).key!;

      final sealed = await vault.encryptSecret('JBSWY3DPEHPK3PXP', key);

      expect(await vault.decryptSecret(sealed, key), 'JBSWY3DPEHPK3PXP');
    });

    test('cannot read a secret with a key from another vault', () async {
      await vault.initialize('correct horse battery');
      final key = (await vault.unlock('correct horse battery')).key!;
      final sealed = await vault.encryptSecret('JBSWY3DPEHPK3PXP', key);

      final otherStore = InMemorySecretStore({});
      final otherVault = VaultService(otherStore, params: testParams);
      final otherKey = await otherVault.initialize('correct horse battery');

      expect(await vault.decryptSecret(sealed, otherKey), isNull);
    });
  });

  group('changing the credential', () {
    test('re-keys the vault and keeps secrets readable', () async {
      await vault.initialize('old passphrase');
      final oldKey = (await vault.unlock('old passphrase')).key!;
      await store.write(
        VaultService.accountsKey,
        '[{"id":"1","secret":"${await vault.encryptSecret('JBSWY3DPEHPK3PXP', oldKey)}"}]',
      );

      final changed = await vault.changeCredential(
        currentPassword: 'old passphrase',
        newPassword: 'new passphrase',
      );

      expect(changed, isTrue);
      expect((await vault.unlock('old passphrase')).isUnlocked, isFalse);

      final newKey = (await vault.unlock('new passphrase')).key!;
      final raw = await store.read(VaultService.accountsKey) as String;
      final sealed = RegExp(r'"secret":"([^"]+)"').firstMatch(raw)!.group(1)!;
      expect(await vault.decryptSecret(sealed, newKey), 'JBSWY3DPEHPK3PXP');
    });

    test('refuses when the current credential is wrong', () async {
      await vault.initialize('old passphrase');

      final changed = await vault.changeCredential(
        currentPassword: 'not the passphrase',
        newPassword: 'new passphrase',
      );

      expect(changed, isFalse);
      expect((await vault.unlock('old passphrase')).isUnlocked, isTrue,
          reason: 'the original credential must keep working');
    });
  });

  group('reset', () {
    test('clears every vault record', () async {
      await vault.initialize('correct horse battery');
      await store.write(VaultService.accountsKey, '[]');

      await vault.reset();

      expect(await vault.isInitialized(), isFalse);
      expect(await store.read(VaultService.saltKey), isNull);
      expect(await store.read(VaultService.verifierKey), isNull);
      expect(await store.read(VaultService.accountsKey), isNull);
      expect(await store.read(VaultService.metaKey), isNull);
    });
  });
}
