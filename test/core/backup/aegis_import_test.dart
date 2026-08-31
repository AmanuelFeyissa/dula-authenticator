import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:dula_auth/core/backup/aegis_import.dart';
import 'package:dula_auth/core/backup/third_party_import_result.dart';
import 'package:dula_auth/core/otp/otp_algorithm.dart';
import 'package:dula_auth/core/otp/otp_type.dart';

/// Fixtures shaped from the published Aegis vault format:
/// https://github.com/beemdevelopment/Aegis/blob/master/docs/vault.md
String _plaintextVault(List<Map<String, dynamic>> entries) => jsonEncode({
      'version': 1,
      'header': {'slots': null, 'params': null},
      'db': {
        'version': 3,
        'entries': entries,
        'groups': [],
      },
    });

Map<String, dynamic> _entry({
  String type = 'totp',
  String uuid = 'a1b2c3',
  String name = '',
  String issuer = '',
  String secret = 'JBSWY3DPEHPK3PXP',
  String algo = 'SHA1',
  int digits = 6,
  int? period,
  int? counter,
}) =>
    {
      'type': type,
      'uuid': uuid,
      'name': name,
      'issuer': issuer,
      'note': '',
      'icon': null,
      'favorite': false,
      'info': {
        'secret': secret,
        'algo': algo,
        'digits': digits,
        if (period != null) 'period': period,
        if (counter != null) 'counter': counter,
      },
      'groups': [],
    };

void main() {
  var counter = 0;
  String nextId() => 'id-${counter++}';
  setUp(() => counter = 0);

  group('plaintext vault', () {
    test('decodes a TOTP entry', () {
      final vault = _plaintextVault([
        _entry(name: 'dev@example.com', issuer: 'GitHub', period: 30),
      ]);

      final result = AegisImport.parse(vault, newId: nextId);

      expect(result, isA<ThirdPartyImportSuccess>());
      final account = (result as ThirdPartyImportSuccess).accounts.single;
      expect(account.accountName, 'dev@example.com');
      expect(account.issuer, 'GitHub');
      expect(account.secret, 'JBSWY3DPEHPK3PXP');
      expect(account.type, OtpType.totp);
      expect(account.period, 30);
      expect(account.id, 'id-0');
    });

    test('decodes an HOTP entry with its counter', () {
      final vault = _plaintextVault([
        _entry(type: 'hotp', counter: 7, period: null),
      ]);

      final result = AegisImport.parse(vault, newId: nextId)
          as ThirdPartyImportSuccess;

      expect(result.accounts.single.type, OtpType.hotp);
      expect(result.accounts.single.counter, 7);
    });

    test('decodes a Steam entry', () {
      final vault = _plaintextVault([_entry(type: 'steam', digits: 5)]);

      final result = AegisImport.parse(vault, newId: nextId)
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
        final vault = _plaintextVault([_entry(algo: entry.key)]);
        final result = AegisImport.parse(vault, newId: nextId)
            as ThirdPartyImportSuccess;
        expect(result.accounts.single.algorithm, entry.value,
            reason: entry.key);
      }
    });

    test('decodes every entry in the vault, in order', () {
      final vault = _plaintextVault([
        _entry(issuer: 'One'),
        _entry(issuer: 'Two'),
        _entry(issuer: 'Three'),
      ]);

      final result = AegisImport.parse(vault, newId: nextId)
          as ThirdPartyImportSuccess;

      expect(result.accounts.map((a) => a.issuer), ['One', 'Two', 'Three']);
    });

    test('an empty vault yields an empty success, not unrecognized', () {
      final result = AegisImport.parse(_plaintextVault([]), newId: nextId);
      expect(result, isA<ThirdPartyImportSuccess>());
      expect((result as ThirdPartyImportSuccess).accounts, isEmpty);
    });
  });

  group('encrypted vault', () {
    test('is reported as requiring a password, not silently skipped', () {
      final vault = jsonEncode({
        'version': 1,
        'header': {
          'slots': [
            {
              'type': 1,
              'uuid': 'x',
              'key': 'deadbeef',
              'key_params': {'nonce': 'aaaa', 'tag': 'bbbb'},
              'n': 32768,
              'r': 8,
              'p': 1,
              'salt': 'cccc',
            },
          ],
          'params': {'nonce': 'dddd', 'tag': 'eeee'},
        },
        // db is an opaque base64 string when the vault is encrypted.
        'db': 'c29tZS1lbmNyeXB0ZWQtYmxvYg==',
      });

      final result = AegisImport.parse(vault, newId: nextId);
      expect(result, isA<ThirdPartyImportRequiresPassword>());
    });
  });

  group('hostile input', () {
    test('rejects input that is not JSON', () {
      final result = AegisImport.parse('not json at all', newId: nextId);
      expect(result, isA<ThirdPartyImportUnrecognized>());
    });

    test('rejects JSON with no db field', () {
      final result =
          AegisImport.parse(jsonEncode({'version': 1}), newId: nextId);
      expect(result, isA<ThirdPartyImportUnrecognized>());
    });

    test('rejects an entry with no secret rather than importing an empty one',
        () {
      final vault = _plaintextVault([_entry(secret: '')]);
      final result = AegisImport.parse(vault, newId: nextId);
      expect(result, isA<ThirdPartyImportUnrecognized>());
    });

    test('rejects an unrecognised type rather than guessing', () {
      final vault = _plaintextVault([_entry(type: 'mystery-type')]);
      final result = AegisImport.parse(vault, newId: nextId);
      expect(result, isA<ThirdPartyImportUnrecognized>());
    });
  });
}
