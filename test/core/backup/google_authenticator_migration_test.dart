import 'dart:convert';

import 'package:base32/base32.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dula_auth/core/backup/google_authenticator_migration.dart';
import 'package:dula_auth/core/otp/otp_algorithm.dart';
import 'package:dula_auth/core/otp/otp_type.dart';

/// Hand-rolled protobuf wire-format encoder, independent of the production
/// decoder, so a bug shared between "test fixture" and "implementation"
/// cannot cancel itself out. Built strictly from the documented
/// MigrationPayload / OtpParameters schema (field numbers and wire types),
/// not from reading GoogleAuthenticatorMigration's source.
List<int> _varint(int value) {
  final bytes = <int>[];
  var v = value;
  while (true) {
    final byte = v & 0x7f;
    v >>= 7;
    if (v != 0) {
      bytes.add(byte | 0x80);
    } else {
      bytes.add(byte);
      break;
    }
  }
  return bytes;
}

List<int> _tag(int fieldNumber, int wireType) =>
    _varint((fieldNumber << 3) | wireType);

List<int> _lengthDelimited(int fieldNumber, List<int> data) =>
    [..._tag(fieldNumber, 2), ..._varint(data.length), ...data];

List<int> _varintField(int fieldNumber, int value) =>
    [..._tag(fieldNumber, 0), ..._varint(value)];

List<int> _otpParameters({
  required List<int> secret,
  String name = '',
  String issuer = '',
  int? algorithm,
  int? digits,
  int? type,
  int? counter,
}) {
  final out = <int>[];
  out.addAll(_lengthDelimited(1, secret));
  out.addAll(_lengthDelimited(2, utf8.encode(name)));
  out.addAll(_lengthDelimited(3, utf8.encode(issuer)));
  if (algorithm != null) out.addAll(_varintField(4, algorithm));
  if (digits != null) out.addAll(_varintField(5, digits));
  if (type != null) out.addAll(_varintField(6, type));
  if (counter != null) out.addAll(_varintField(7, counter));
  return out;
}

List<int> _payload(List<List<int>> entries, {int? version}) {
  final out = <int>[];
  for (final e in entries) {
    out.addAll(_lengthDelimited(1, e));
  }
  if (version != null) out.addAll(_varintField(2, version));
  return out;
}

String _migrationUri(List<int> payloadBytes) =>
    'otpauth-migration://offline?data=${Uri.encodeComponent(base64.encode(payloadBytes))}';

void main() {
  // Known secret already trusted elsewhere in this test suite.
  final secretBytes = base32.decode('JBSWY3DPEHPK3PXP');
  var counter = 0;
  String nextId() => 'id-${counter++}';

  setUp(() => counter = 0);

  group('shape', () {
    test('rejects a non-migration scheme', () {
      expect(
        GoogleAuthenticatorMigration.parse(
          'otpauth://totp/Foo?secret=JBSWY3DPEHPK3PXP',
          newId: nextId,
        ),
        isNull,
      );
    });

    test('rejects a migration URI with no data parameter', () {
      expect(
        GoogleAuthenticatorMigration.parse('otpauth-migration://offline',
            newId: nextId),
        isNull,
      );
    });

    test('rejects non-base64 data', () {
      expect(
        GoogleAuthenticatorMigration.parse(
          'otpauth-migration://offline?data=not-valid-base64!!!',
          newId: nextId,
        ),
        isNull,
      );
    });

    test('an empty payload yields an empty list, not null', () {
      // Zero entries is a valid (if useless) payload — distinct from a
      // payload that could not be parsed at all.
      expect(
        GoogleAuthenticatorMigration.parse(_migrationUri(_payload([])),
            newId: nextId),
        isEmpty,
      );
    });
  });

  group('single entry', () {
    test('decodes secret, name, and issuer', () {
      final uri = _migrationUri(_payload([
        _otpParameters(secret: secretBytes, name: 'alice', issuer: 'GitHub'),
      ]));

      final accounts = GoogleAuthenticatorMigration.parse(uri, newId: nextId)!;

      expect(accounts, hasLength(1));
      expect(accounts.single.secret, 'JBSWY3DPEHPK3PXP');
      expect(accounts.single.accountName, 'alice');
      expect(accounts.single.issuer, 'GitHub');
      expect(accounts.single.id, 'id-0');
    });

    test('defaults to SHA-1, 6 digits, TOTP when fields are absent', () {
      final uri = _migrationUri(_payload([
        _otpParameters(secret: secretBytes, name: 'alice', issuer: 'GitHub'),
      ]));

      final account = GoogleAuthenticatorMigration.parse(uri, newId: nextId)!.single;

      expect(account.algorithm, OtpAlgorithm.sha1);
      expect(account.digits, 6);
      expect(account.type, OtpType.totp);
      expect(account.period, 30,
          reason: 'the migration payload carries no period; GA always uses 30s');
    });

    test('maps each algorithm enum value', () {
      final cases = {1: OtpAlgorithm.sha1, 2: OtpAlgorithm.sha256, 3: OtpAlgorithm.sha512};
      for (final entry in cases.entries) {
        final uri = _migrationUri(_payload([
          _otpParameters(secret: secretBytes, algorithm: entry.key),
        ]));
        final account =
            GoogleAuthenticatorMigration.parse(uri, newId: nextId)!.single;
        expect(account.algorithm, entry.value, reason: 'algorithm=${entry.key}');
      }
    });

    test('falls back to SHA-1 for the unsupported MD5 enum value', () {
      // MD5 (4) exists in the schema but this app has no MD5 generator; a
      // silently wrong algorithm is worse than a clearly-labelled fallback.
      final uri = _migrationUri(_payload([
        _otpParameters(secret: secretBytes, algorithm: 4),
      ]));
      final account =
          GoogleAuthenticatorMigration.parse(uri, newId: nextId)!.single;
      expect(account.algorithm, OtpAlgorithm.sha1);
    });

    test('maps the eight-digit enum value', () {
      final uri = _migrationUri(_payload([
        _otpParameters(secret: secretBytes, digits: 2),
      ]));
      final account =
          GoogleAuthenticatorMigration.parse(uri, newId: nextId)!.single;
      expect(account.digits, 8);
    });

    test('maps HOTP and carries the counter', () {
      final uri = _migrationUri(_payload([
        _otpParameters(secret: secretBytes, type: 1, counter: 42),
      ]));
      final account =
          GoogleAuthenticatorMigration.parse(uri, newId: nextId)!.single;
      expect(account.type, OtpType.hotp);
      expect(account.counter, 42);
    });

    test('maps TOTP explicitly', () {
      final uri = _migrationUri(_payload([
        _otpParameters(secret: secretBytes, type: 2),
      ]));
      final account =
          GoogleAuthenticatorMigration.parse(uri, newId: nextId)!.single;
      expect(account.type, OtpType.totp);
    });
  });

  group('multiple entries', () {
    test('decodes every entry in a batch, in order', () {
      final uri = _migrationUri(_payload([
        _otpParameters(secret: secretBytes, name: 'a', issuer: 'One'),
        _otpParameters(secret: secretBytes, name: 'b', issuer: 'Two'),
        _otpParameters(secret: secretBytes, name: 'c', issuer: 'Three'),
      ]));

      final accounts = GoogleAuthenticatorMigration.parse(uri, newId: nextId)!;

      expect(accounts.map((a) => a.issuer), ['One', 'Two', 'Three']);
      expect(accounts.map((a) => a.id), ['id-0', 'id-1', 'id-2']);
    });

    test('a batch header does not disturb entry parsing', () {
      final uri = _migrationUri(_payload(
        [_otpParameters(secret: secretBytes, issuer: 'Solo')],
        version: 1,
      ));

      final accounts = GoogleAuthenticatorMigration.parse(uri, newId: nextId)!;
      expect(accounts, hasLength(1));
      expect(accounts.single.issuer, 'Solo');
    });
  });

  group('hostile input', () {
    test('rejects an entry with no secret', () {
      final uri = _migrationUri(_payload([
        _otpParameters(secret: [], issuer: 'Empty'),
      ]));
      // A credential with no secret can never produce a code; it must not
      // silently become an unusable account.
      expect(GoogleAuthenticatorMigration.parse(uri, newId: nextId), isNull);
    });

    test('fails closed on truncated bytes rather than throwing', () {
      final good = _payload([
        _otpParameters(secret: secretBytes, issuer: 'Truncated'),
      ]);
      final truncated = good.sublist(0, good.length - 3);
      final uri = _migrationUri(truncated);

      expect(() => GoogleAuthenticatorMigration.parse(uri, newId: nextId),
          returnsNormally);
      expect(GoogleAuthenticatorMigration.parse(uri, newId: nextId), isNull);
    });

    test('fails closed on a dangling varint at the end of the buffer', () {
      final malformed = [..._tag(1, 2), 0xFF];
      final uri = _migrationUri(malformed);

      expect(() => GoogleAuthenticatorMigration.parse(uri, newId: nextId),
          returnsNormally);
      expect(GoogleAuthenticatorMigration.parse(uri, newId: nextId), isNull);
    });

    test('skips an unknown field rather than failing the whole entry', () {
      // Forward compatibility: a future GA version may add fields this app
      // does not know about. Encode field 9 (unknown) before the known ones.
      final unknownField = _lengthDelimited(9, utf8.encode('future-field'));
      final entry = [
        ...unknownField,
        ..._otpParameters(secret: secretBytes, issuer: 'StillWorks'),
      ];
      final uri = _migrationUri(_payload([entry]));

      final accounts = GoogleAuthenticatorMigration.parse(uri, newId: nextId)!;
      expect(accounts.single.issuer, 'StillWorks');
    });

    test('rejects raw bytes that are not a valid otpauth-migration payload', () {
      final uri = _migrationUri(utf8.encode('this is not protobuf at all'));
      expect(GoogleAuthenticatorMigration.parse(uri, newId: nextId), isNull);
    });
  });
}
