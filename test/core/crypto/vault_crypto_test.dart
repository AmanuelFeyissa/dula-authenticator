import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:dula_auth/core/crypto/vault_crypto.dart';

void main() {
  // Deliberately weak parameters so the suite stays fast. Production values
  // live in KdfParams.owaspDefault and are asserted separately below.
  const testParams = KdfParams(memoryKiB: 256, iterations: 1, parallelism: 1);

  final salt = Uint8List.fromList(List<int>.generate(32, (i) => i));

  group('Argon2id key derivation', () {
    test('derives a 256-bit key', () async {
      final key = await VaultCrypto.deriveKey('correct horse', salt, testParams);

      expect(key.bytes.length, 32);
    });

    test('is deterministic for the same password, salt and parameters',
        () async {
      final a = await VaultCrypto.deriveKey('correct horse', salt, testParams);
      final b = await VaultCrypto.deriveKey('correct horse', salt, testParams);

      expect(a.bytes, b.bytes);
    });

    test('produces a different key for a different password', () async {
      final a = await VaultCrypto.deriveKey('correct horse', salt, testParams);
      final b = await VaultCrypto.deriveKey('correct horsf', salt, testParams);

      expect(a.bytes, isNot(b.bytes));
    });

    test('produces a different key for a different salt', () async {
      final otherSalt =
          Uint8List.fromList(List<int>.generate(32, (i) => i + 1));

      final a = await VaultCrypto.deriveKey('correct horse', salt, testParams);
      final b =
          await VaultCrypto.deriveKey('correct horse', otherSalt, testParams);

      expect(a.bytes, isNot(b.bytes));
    });

    test('OWASP default parameters meet the recommended minimum', () {
      // OWASP Password Storage Cheat Sheet: m=19456 KiB, t=2, p=1.
      expect(KdfParams.owaspDefault.memoryKiB, greaterThanOrEqualTo(19456));
      expect(KdfParams.owaspDefault.iterations, greaterThanOrEqualTo(2));
      expect(KdfParams.owaspDefault.parallelism, greaterThanOrEqualTo(1));
    });
  });

  group('AES-256-GCM encryption', () {
    late MasterKey key;

    setUp(() async {
      key = await VaultCrypto.deriveKey('correct horse', salt, testParams);
    });

    test('round-trips a plaintext secret', () async {
      const plaintext = 'JBSWY3DPEHPK3PXP';

      final sealed = await VaultCrypto.encrypt(plaintext, key);
      final opened = await VaultCrypto.decrypt(sealed, key);

      expect(opened, plaintext);
    });

    test('produces different ciphertext each time for the same plaintext',
        () async {
      final a = await VaultCrypto.encrypt('JBSWY3DPEHPK3PXP', key);
      final b = await VaultCrypto.encrypt('JBSWY3DPEHPK3PXP', key);

      expect(a, isNot(b), reason: 'a fresh random nonce must be used per call');
    });

    test('rejects ciphertext modified by an attacker', () async {
      final sealed = await VaultCrypto.encrypt('JBSWY3DPEHPK3PXP', key);

      // Flip one bit in the middle of the payload.
      final raw = base64.decode(sealed);
      raw[raw.length ~/ 2] ^= 0x01;
      final tampered = base64.encode(raw);

      expect(await VaultCrypto.decrypt(tampered, key), isNull,
          reason: 'GCM must detect tampering rather than returning garbage');
    });

    test('rejects decryption with the wrong key', () async {
      final sealed = await VaultCrypto.encrypt('JBSWY3DPEHPK3PXP', key);
      final wrongKey =
          await VaultCrypto.deriveKey('wrong password', salt, testParams);

      expect(await VaultCrypto.decrypt(sealed, wrongKey), isNull);
    });

    test('returns null for malformed input rather than throwing', () async {
      expect(await VaultCrypto.decrypt('not-valid-base64!!', key), isNull);
      expect(await VaultCrypto.decrypt('', key), isNull);
      expect(await VaultCrypto.decrypt(base64.encode([1, 2, 3]), key), isNull);
    });
  });

  group('key verifier', () {
    test('is stable for the same key', () async {
      final key = await VaultCrypto.deriveKey('correct horse', salt, testParams);

      expect(VaultCrypto.verifierFor(key), VaultCrypto.verifierFor(key));
    });

    test('differs for a different key', () async {
      final a = await VaultCrypto.deriveKey('correct horse', salt, testParams);
      final b = await VaultCrypto.deriveKey('wrong horse', salt, testParams);

      expect(VaultCrypto.verifierFor(a), isNot(VaultCrypto.verifierFor(b)));
    });

    test('does not expose the raw key material', () async {
      final key = await VaultCrypto.deriveKey('correct horse', salt, testParams);

      expect(VaultCrypto.verifierFor(key), isNot(contains(base64.encode(key.bytes))));
      expect(VaultCrypto.verifierFor(key), isNot(equals(base64.encode(key.bytes))));
    });
  });
}
