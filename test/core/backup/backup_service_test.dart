import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:dula_auth/core/backup/backup_service.dart';
import 'package:dula_auth/core/crypto/vault_crypto.dart';
import 'package:dula_auth/core/models/otp_account.dart';
import 'package:dula_auth/core/otp/otp_algorithm.dart';
import 'package:dula_auth/core/otp/otp_type.dart';

const testParams = KdfParams(memoryKiB: 256, iterations: 1, parallelism: 1);
const passphrase = 'rope anchor lantern harbour';

void main() {
  final accounts = [
    const OtpAccount(
      id: '1',
      issuer: 'GitHub',
      accountName: 'dev@example.com',
      secret: 'JBSWY3DPEHPK3PXP',
    ),
    const OtpAccount(
      id: '2',
      issuer: 'Bank',
      accountName: 'ops@example.com',
      secret: 'KRSXG5CTMVRXEZLU',
      digits: 8,
      period: 60,
      algorithm: OtpAlgorithm.sha256,
    ),
    const OtpAccount(
      id: '3',
      issuer: 'Token',
      accountName: 'alice',
      secret: 'JBSWY3DPEHPK3PXP',
      type: OtpType.hotp,
      counter: 5,
    ),
  ];

  group('export', () {
    test('refuses a passphrase below policy rather than encrypting anyway',
        () async {
      final result =
          await BackupService.export(accounts, 'short', params: testParams);

      expect(result, isA<BackupExportRejected>());
      expect((result as BackupExportRejected).reason, isNotEmpty);
    });

    test('never writes a secret in the clear', () async {
      final result = await BackupService.export(accounts, passphrase,
          params: testParams) as BackupExportSuccess;

      expect(result.fileContent, isNot(contains('JBSWY3DPEHPK3PXP')));
      expect(result.fileContent, isNot(contains('KRSXG5CTMVRXEZLU')));
      expect(result.fileContent, isNot(contains(passphrase)));
    });

    test('produces a self-describing envelope', () async {
      final result = await BackupService.export(accounts, passphrase,
          params: testParams) as BackupExportSuccess;

      final envelope = jsonDecode(result.fileContent) as Map<String, dynamic>;
      expect(envelope['v'], BackupService.formatVersion);
      expect(envelope['app'], BackupService.appIdentifier);
      expect(envelope['kdf'], isNotNull);
      expect(envelope['salt'], isNotNull);
      expect(envelope['payload'], isNotNull);
    });
  });

  group('import', () {
    test('round-trips every account field exactly', () async {
      final exported = await BackupService.export(accounts, passphrase,
          params: testParams) as BackupExportSuccess;

      final result = await BackupService.import(
          exported.fileContent, passphrase) as BackupImportSuccess;

      expect(result.accounts, hasLength(3));
      expect(result.accounts[1].digits, 8);
      expect(result.accounts[1].period, 60);
      expect(result.accounts[1].algorithm, OtpAlgorithm.sha256);
      expect(result.accounts[2].type, OtpType.hotp);
      expect(result.accounts[2].counter, 5);
      expect(result.accounts.map((a) => a.secret),
          containsAll(['JBSWY3DPEHPK3PXP', 'KRSXG5CTMVRXEZLU']));
    });

    test('preserves the original account ids', () async {
      final exported = await BackupService.export(accounts, passphrase,
          params: testParams) as BackupExportSuccess;

      final result = await BackupService.import(
          exported.fileContent, passphrase) as BackupImportSuccess;

      expect(result.accounts.map((a) => a.id), ['1', '2', '3']);
    });

    test('reports the wrong passphrase distinctly from a corrupt file',
        () async {
      final exported = await BackupService.export(accounts, passphrase,
          params: testParams) as BackupExportSuccess;

      final result = await BackupService.import(
          exported.fileContent, 'not the passphrase');

      expect(result, isA<BackupImportWrongPassphrase>());
    });

    test('rejects a file that is not JSON', () async {
      final result = await BackupService.import('not json at all', passphrase);
      expect(result, isA<BackupImportMalformed>());
    });

    test('rejects a file missing required envelope fields', () async {
      final result =
          await BackupService.import(jsonEncode({'v': 1}), passphrase);
      expect(result, isA<BackupImportMalformed>());
    });

    test('refuses a file from an unsupported future format version',
        () async {
      final exported = await BackupService.export(accounts, passphrase,
          params: testParams) as BackupExportSuccess;
      final envelope =
          jsonDecode(exported.fileContent) as Map<String, dynamic>;
      envelope['v'] = BackupService.formatVersion + 1;

      final result =
          await BackupService.import(jsonEncode(envelope), passphrase);

      expect(result, isA<BackupImportMalformed>(),
          reason: 'guessing at an unknown backup format risks data loss');
    });

    test('detects tampering with the encrypted payload', () async {
      final exported = await BackupService.export(accounts, passphrase,
          params: testParams) as BackupExportSuccess;
      final envelope =
          jsonDecode(exported.fileContent) as Map<String, dynamic>;
      final payload = base64.decode(envelope['payload'] as String);
      payload[payload.length ~/ 2] ^= 0x01;
      envelope['payload'] = base64.encode(payload);

      final result =
          await BackupService.import(jsonEncode(envelope), passphrase);

      // GCM authentication fails the same way a wrong passphrase would — both
      // mean "this key does not open this payload" — so it must not be
      // reported as success.
      expect(result, isNot(isA<BackupImportSuccess>()));
    });

    test('an empty account list round-trips to an empty list', () async {
      final exported = await BackupService.export([], passphrase,
          params: testParams) as BackupExportSuccess;

      final result = await BackupService.import(
          exported.fileContent, passphrase) as BackupImportSuccess;

      expect(result.accounts, isEmpty);
    });
  });
}
