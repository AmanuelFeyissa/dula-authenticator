import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:dula_auth/core/crypto/vault_crypto.dart';
import 'package:dula_auth/core/models/otp_account.dart';
import 'package:dula_auth/core/repositories/account_repository.dart';
import 'package:dula_auth/core/otp/otp_algorithm.dart';
import 'package:dula_auth/core/vault/secret_store.dart';
import 'package:dula_auth/core/vault/vault_service.dart';

const testParams = KdfParams(memoryKiB: 256, iterations: 1, parallelism: 1);

OtpAccount account(String id, String secret) => OtpAccount(
      id: id,
      issuer: 'Issuer $id',
      accountName: 'user$id@example.com',
      secret: secret,
    );

void main() {
  late InMemorySecretStore store;
  late VaultService vault;
  late AccountRepository repo;

  setUp(() {
    store = InMemorySecretStore({});
    vault = VaultService(store, params: testParams);
    repo = AccountRepository(store: store, vault: vault);
  });

  test('stores secrets encrypted at rest', () async {
    final key = await vault.initialize('correct horse battery');

    await repo.addAccount(account('1', 'JBSWY3DPEHPK3PXP'), masterKey: key);

    final raw = await store.read(VaultService.accountsKey);
    expect(raw, isNot(contains('JBSWY3DPEHPK3PXP')),
        reason: 'the plaintext secret must never touch storage');
  });

  test('holds many accounts, not just one', () async {
    final key = await vault.initialize('correct horse battery');

    for (var i = 1; i <= 5; i++) {
      await repo.addAccount(account('$i', 'JBSWY3DPEHPK3PXP'), masterKey: key);
    }

    expect((await repo.getAccounts(masterKey: key)).length, 5);
  });

  test('reads back distinct secrets for each account', () async {
    final key = await vault.initialize('correct horse battery');

    await repo.addAccount(account('1', 'JBSWY3DPEHPK3PXP'), masterKey: key);
    await repo.addAccount(account('2', 'KRSXG5CTMVRXEZLU'), masterKey: key);

    final loaded = await repo.getAccounts(masterKey: key);

    expect(loaded.map((a) => a.secret),
        containsAll(['JBSWY3DPEHPK3PXP', 'KRSXG5CTMVRXEZLU']));
  });

  test('a stored secret still generates the expected TOTP code', () async {
    // Proves the round trip preserves the secret exactly: a byte-off secret
    // would still decode but produce silently wrong codes.
    final key = await vault.initialize('correct horse battery');
    const secret = 'JBSWY3DPEHPK3PXP';
    final when = DateTime.fromMillisecondsSinceEpoch(59000, isUtc: true);
    final expected =
        OtpAccount(id: 'ref', issuer: '', accountName: '', secret: secret)
            .generateCode(time: when);

    await repo.addAccount(account('1', secret), masterKey: key);
    final loaded = await repo.getAccounts(masterKey: key);

    expect(loaded.single.generateCode(time: when), expected);
  });

  test('surfaces tampering as a per-account error, not a wrong secret',
      () async {
    // A tampered account must never be silently readable as garbage — but it
    // also must not take every other account down with it (ADR-0015 §7).
    final key = await vault.initialize('correct horse battery');
    await repo.addAccount(account('1', 'JBSWY3DPEHPK3PXP'), masterKey: key);

    final accounts =
        jsonDecode(await store.read(VaultService.accountsKey) as String)
            as List;
    final sealed = base64.decode(accounts[0]['secret'] as String);
    sealed[sealed.length ~/ 2] ^= 0x01;
    accounts[0]['secret'] = base64.encode(sealed);
    await store.write(VaultService.accountsKey, jsonEncode(accounts));

    final loaded = await repo.getAccounts(masterKey: key);

    expect(loaded.single.loadError, isNotNull);
    expect(loaded.single.secret, isNot('JBSWY3DPEHPK3PXP'),
        reason: 'a corrupted secret must never be reported as the real one');
  });

  test('one corrupt account does not block the others from loading',
      () async {
    final key = await vault.initialize('correct horse battery');
    await repo.addAccount(account('1', 'JBSWY3DPEHPK3PXP'), masterKey: key);
    await repo.addAccount(account('2', 'KRSXG5CTMVRXEZLU'), masterKey: key);
    await repo.addAccount(account('3', 'JBSWY3DPEHPK3PXP'), masterKey: key);

    final accounts =
        jsonDecode(await store.read(VaultService.accountsKey) as String)
            as List;
    final middle = accounts[1] as Map<String, dynamic>;
    final sealed = base64.decode(middle['secret'] as String);
    sealed[sealed.length ~/ 2] ^= 0x01;
    middle['secret'] = base64.encode(sealed);
    await store.write(VaultService.accountsKey, jsonEncode(accounts));

    final loaded = await repo.getAccounts(masterKey: key);

    expect(loaded, hasLength(3));
    expect(loaded[0].loadError, isNull);
    expect(loaded[0].secret, 'JBSWY3DPEHPK3PXP');
    expect(loaded[1].loadError, isNotNull);
    expect(loaded[2].loadError, isNull);
    expect(loaded[2].secret, 'JBSWY3DPEHPK3PXP');
  });

  test('deletes an account without disturbing the others', () async {
    final key = await vault.initialize('correct horse battery');
    await repo.addAccount(account('1', 'JBSWY3DPEHPK3PXP'), masterKey: key);
    await repo.addAccount(account('2', 'KRSXG5CTMVRXEZLU'), masterKey: key);

    await repo.deleteAccount('1', masterKey: key);
    final loaded = await repo.getAccounts(masterKey: key);

    expect(loaded.single.id, '2');
    expect(loaded.single.secret, 'KRSXG5CTMVRXEZLU');
  });

  group('reordering', () {
    test('persists a new order, no explicit sort field involved', () async {
      final key = await vault.initialize('correct horse battery');
      await repo.addAccount(account('1', 'JBSWY3DPEHPK3PXP'), masterKey: key);
      await repo.addAccount(account('2', 'KRSXG5CTMVRXEZLU'), masterKey: key);
      await repo.addAccount(account('3', 'JBSWY3DPEHPK3PXP'), masterKey: key);

      final reordered =
          await repo.reorderAccounts(['3', '1', '2'], masterKey: key);
      expect(reordered, isTrue);

      final loaded = await repo.getAccounts(masterKey: key);
      expect(loaded.map((a) => a.id), ['3', '1', '2']);
    });

    test('keeps every secret readable after a reorder', () async {
      final key = await vault.initialize('correct horse battery');
      await repo.addAccount(account('1', 'JBSWY3DPEHPK3PXP'), masterKey: key);
      await repo.addAccount(account('2', 'KRSXG5CTMVRXEZLU'), masterKey: key);

      await repo.reorderAccounts(['2', '1'], masterKey: key);
      final loaded = await repo.getAccounts(masterKey: key);

      expect(loaded.firstWhere((a) => a.id == '1').secret, 'JBSWY3DPEHPK3PXP');
      expect(loaded.firstWhere((a) => a.id == '2').secret, 'KRSXG5CTMVRXEZLU');
    });

    test('refuses an order that does not name every stored account',
        () async {
      final key = await vault.initialize('correct horse battery');
      await repo.addAccount(account('1', 'JBSWY3DPEHPK3PXP'), masterKey: key);
      await repo.addAccount(account('2', 'KRSXG5CTMVRXEZLU'), masterKey: key);

      // Missing '2' entirely — applying this would silently drop an account.
      final reordered = await repo.reorderAccounts(['1'], masterKey: key);

      expect(reordered, isFalse);
      final loaded = await repo.getAccounts(masterKey: key);
      expect(loaded, hasLength(2),
          reason: 'a rejected reorder must not lose an account');
    });

    test('ignores an id that does not exist rather than inventing an entry',
        () async {
      final key = await vault.initialize('correct horse battery');
      await repo.addAccount(account('1', 'JBSWY3DPEHPK3PXP'), masterKey: key);

      final reordered =
          await repo.reorderAccounts(['1', 'does-not-exist'], masterKey: key);

      expect(reordered, isFalse);
    });
  });

  test('survives a lock and unlock cycle', () async {
    await vault.initialize('correct horse battery');
    final key = (await vault.unlock('correct horse battery')).key!;
    await repo.addAccount(account('1', 'JBSWY3DPEHPK3PXP'), masterKey: key);

    // Simulate relaunching: a fresh service over the same storage.
    final reopened = VaultService(store, params: testParams);
    final reopenedRepo = AccountRepository(store: store, vault: reopened);
    final restoredKey = (await reopened.unlock('correct horse battery')).key!;

    final loaded = await reopenedRepo.getAccounts(masterKey: restoredKey);

    expect(loaded.single.secret, 'JBSWY3DPEHPK3PXP');
  });

  test('preserves non-default OTP parameters through storage', () async {
    final key = await vault.initialize('correct horse battery');
    final custom = OtpAccount(
      id: '1',
      issuer: 'Custom',
      accountName: 'ops@example.com',
      secret: 'JBSWY3DPEHPK3PXP',
      digits: 8,
      period: 60,
      algorithm: OtpAlgorithm.sha256,
    );

    await repo.addAccount(custom, masterKey: key);
    final loaded = (await repo.getAccounts(masterKey: key)).single;

    expect(loaded.digits, 8);
    expect(loaded.period, 60);
    expect(loaded.algorithm, OtpAlgorithm.sha256);
  });
}
