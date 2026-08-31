import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:dula_auth/core/backup/third_party_import_result.dart';
import 'package:dula_auth/core/backup/twofas_import.dart';
import 'package:dula_auth/core/otp/otp_algorithm.dart';
import 'package:dula_auth/core/otp/otp_type.dart';

/// Fixtures shaped from the 2FAS export format as corroborated across
/// multiple independent decryption/decoding tools (wodny/decrypt-2fas-backup,
/// elliotwutingfeng/2fas-backup-decryptor): top-level schemaVersion/
/// appVersionCode/appVersionName/appOrigin/servicesEncrypted/reference, and a
/// plaintext `services` array of {name, secret, otp{...}} when not
/// password-protected.
String _plaintextExport(List<Map<String, dynamic>> services) => jsonEncode({
      'schemaVersion': 4,
      'appVersionCode': 100,
      'appVersionName': '5.0.0',
      'appOrigin': 'android',
      'servicesEncrypted': null,
      'reference': 'ref-1',
      'services': services,
    });

Map<String, dynamic> _service({
  String name = '',
  String secret = 'JBSWY3DPEHPK3PXP',
  String account = '',
  String issuer = '',
  int digits = 6,
  int? period,
  int? counter,
  String algorithm = 'SHA1',
  String tokenType = 'TOTP',
}) =>
    {
      'name': name,
      'secret': secret,
      'updatedAt': 1700000000000,
      'otp': {
        'account': account,
        'issuer': issuer,
        'digits': digits,
        if (period != null) 'period': period,
        if (counter != null) 'counter': counter,
        'algorithm': algorithm,
        'tokenType': tokenType,
      },
    };

void main() {
  var counter = 0;
  String nextId() => 'id-${counter++}';
  setUp(() => counter = 0);

  group('plaintext export', () {
    test('decodes a TOTP service', () {
      final export = _plaintextExport([
        _service(account: 'dev@example.com', issuer: 'GitHub', period: 30),
      ]);

      final result = TwoFasImport.parse(export, newId: nextId);

      expect(result, isA<ThirdPartyImportSuccess>());
      final account = (result as ThirdPartyImportSuccess).accounts.single;
      expect(account.accountName, 'dev@example.com');
      expect(account.issuer, 'GitHub');
      expect(account.secret, 'JBSWY3DPEHPK3PXP');
      expect(account.type, OtpType.totp);
      expect(account.period, 30);
      expect(account.id, 'id-0');
    });

    test('falls back to the service name when otp.account is blank', () {
      final export =
          _plaintextExport([_service(name: 'Backup Codes', account: '')]);

      final result = TwoFasImport.parse(export, newId: nextId)
          as ThirdPartyImportSuccess;

      expect(result.accounts.single.accountName, 'Backup Codes');
    });

    test('decodes an HOTP service with its counter', () {
      final export = _plaintextExport([
        _service(tokenType: 'HOTP', counter: 3, period: null),
      ]);

      final result = TwoFasImport.parse(export, newId: nextId)
          as ThirdPartyImportSuccess;

      expect(result.accounts.single.type, OtpType.hotp);
      expect(result.accounts.single.counter, 3);
    });

    test('decodes a Steam service', () {
      final export =
          _plaintextExport([_service(tokenType: 'STEAM', digits: 5)]);

      final result = TwoFasImport.parse(export, newId: nextId)
          as ThirdPartyImportSuccess;

      expect(result.accounts.single.type, OtpType.steam);
    });

    test('maps every algorithm', () {
      final cases = {
        'SHA1': OtpAlgorithm.sha1,
        'SHA256': OtpAlgorithm.sha256,
        'SHA512': OtpAlgorithm.sha512,
      };
      for (final entry in cases.entries) {
        final export = _plaintextExport([_service(algorithm: entry.key)]);
        final result = TwoFasImport.parse(export, newId: nextId)
            as ThirdPartyImportSuccess;
        expect(result.accounts.single.algorithm, entry.value,
            reason: entry.key);
      }
    });

    test('decodes every service in order', () {
      final export = _plaintextExport([
        _service(issuer: 'One'),
        _service(issuer: 'Two'),
        _service(issuer: 'Three'),
      ]);

      final result = TwoFasImport.parse(export, newId: nextId)
          as ThirdPartyImportSuccess;

      expect(result.accounts.map((a) => a.issuer), ['One', 'Two', 'Three']);
    });

    test('an empty services array yields an empty success', () {
      final result = TwoFasImport.parse(_plaintextExport([]), newId: nextId);
      expect(result, isA<ThirdPartyImportSuccess>());
      expect((result as ThirdPartyImportSuccess).accounts, isEmpty);
    });
  });

  group('encrypted export', () {
    test('is reported as requiring a password, not silently skipped', () {
      final export = jsonEncode({
        'schemaVersion': 4,
        'appVersionCode': 100,
        'appVersionName': '5.0.0',
        'appOrigin': 'android',
        'servicesEncrypted': 'base64-ciphertext-blob==',
        'reference': 'ref-1',
        'services': <Map<String, dynamic>>[],
      });

      final result = TwoFasImport.parse(export, newId: nextId);
      expect(result, isA<ThirdPartyImportRequiresPassword>());
    });
  });

  group('hostile input', () {
    test('rejects input that is not JSON', () {
      expect(TwoFasImport.parse('not json', newId: nextId),
          isA<ThirdPartyImportUnrecognized>());
    });

    test('rejects JSON with no services field and no servicesEncrypted', () {
      final result = TwoFasImport.parse(
          jsonEncode({'schemaVersion': 4}), newId: nextId);
      expect(result, isA<ThirdPartyImportUnrecognized>());
    });

    test('rejects a service with no secret', () {
      final export = _plaintextExport([_service(secret: '')]);
      final result = TwoFasImport.parse(export, newId: nextId);
      expect(result, isA<ThirdPartyImportUnrecognized>());
    });

    test('rejects an unrecognised token type rather than guessing', () {
      final export = _plaintextExport([_service(tokenType: 'MYSTERY')]);
      final result = TwoFasImport.parse(export, newId: nextId);
      expect(result, isA<ThirdPartyImportUnrecognized>());
    });
  });
}
