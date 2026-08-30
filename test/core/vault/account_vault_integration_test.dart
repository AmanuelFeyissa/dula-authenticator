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

  test('surfaces tampering instead of returning a wrong secret', () async {
    final key = await vault.initialize('correct horse battery');
    await repo.addAccount(account('1', 'JBSWY3DPEHPK3PXP'), masterKey: key);

    final accounts =
        jsonDecode(await store.read(VaultService.accountsKey) as String)
            as List;
    final sealed = base64.decode(accounts[0]['secret'] as String);
    sealed[sealed.length ~/ 2] ^= 0x01;
    accounts[0]['secret'] = base64.encode(sealed);
    await store.write(VaultService.accountsKey, jsonEncode(accounts));

    expect(
      () => repo.getAccounts(masterKey: key),
      throwsA(isA<VaultDecryptionException>()),
    );
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
