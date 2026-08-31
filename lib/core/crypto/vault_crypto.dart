import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as classic;
import 'package:cryptography/cryptography.dart';

/// Argon2id cost parameters.
///
/// [memoryKiB] is the number of 1 KiB blocks the KDF must allocate, which is
/// what makes the function memory-hard and therefore expensive to parallelise
/// on GPUs and ASICs.
class KdfParams {
  final int memoryKiB;
  final int iterations;
  final int parallelism;

  const KdfParams({
    required this.memoryKiB,
    required this.iterations,
    required this.parallelism,
  });

  /// OWASP Password Storage Cheat Sheet minimum for Argon2id:
  /// m = 19456 KiB (19 MiB), t = 2, p = 1. Fixed — this is the security
  /// floor, not a deployer-adjustable value. New vaults use
  /// [deploymentDefault] instead, which starts equal to this.
  static const KdfParams owaspDefault =
      KdfParams(memoryKiB: 19456, iterations: 2, parallelism: 1);

  /// Parameters used for newly created vaults. Deployer-configurable via
  /// `assets/config/deployment_config.json`'s `security.argon2*` fields (see
  /// docs/adr/0016-deployment-configuration.md) through [configureDefault].
  /// A mutable static — `VaultService` and `BackupService.export` read it as
  /// their default parameter value's fallback, since a mutable static cannot
  /// itself be a `const` default-parameter literal.
  static KdfParams deploymentDefault = owaspDefault;

  /// Sets [deploymentDefault]. Call once at startup, before any vault is
  /// created.
  static void configureDefault(KdfParams params) {
    deploymentDefault = params;
  }

  /// Restores [deploymentDefault] to [owaspDefault]. Test-only — call in
  /// `tearDown` after any test that calls [configureDefault].
  static void resetForTesting() {
    deploymentDefault = owaspDefault;
  }

  Map<String, dynamic> toMap() => {
        'alg': 'argon2id',
        'm': memoryKiB,
        't': iterations,
        'p': parallelism,
      };

  factory KdfParams.fromMap(Map<String, dynamic> map) => KdfParams(
        memoryKiB: map['m'] as int? ?? owaspDefault.memoryKiB,
        iterations: map['t'] as int? ?? owaspDefault.iterations,
        parallelism: map['p'] as int? ?? owaspDefault.parallelism,
      );

  @override
  bool operator ==(Object other) =>
      other is KdfParams &&
      memoryKiB == other.memoryKiB &&
      iterations == other.iterations &&
      parallelism == other.parallelism;

  @override
  int get hashCode => Object.hash(memoryKiB, iterations, parallelism);
}

/// A derived 256-bit vault key held in memory.
class MasterKey {
  final Uint8List bytes;

  const MasterKey(this.bytes);

  @override
  bool operator ==(Object other) =>
      other is MasterKey && _constantTimeEquals(bytes, other.bytes);

  @override
  int get hashCode => bytes.length;

  /// Never print key material.
  @override
  String toString() => 'MasterKey(<redacted>)';

  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}

/// Vault cryptography: Argon2id key derivation and AES-256-GCM authenticated
/// encryption.
///
/// See docs/adr/0010-vault-cryptography-modernization.md. GCM is used rather
/// than CBC so that tampering with stored ciphertext is detected instead of
/// silently producing garbage plaintext.
class VaultCrypto {
  /// Nonce size recommended for AES-GCM (96 bits).
  static const int nonceLength = 12;

  /// GCM authentication tag size (128 bits).
  static const int macLength = 16;

  static const int keyLength = 32;

  static const String _verifierDomain = 'dula-auth-key-verifier-v2';

  static final AesGcm _aesGcm = AesGcm.with256bits();

  /// Derives a 256-bit vault key from [password] and [salt] using Argon2id.
  static Future<MasterKey> deriveKey(
    String password,
    Uint8List salt,
    KdfParams params,
  ) async {
    final argon2id = Argon2id(
      memory: params.memoryKiB,
      iterations: params.iterations,
      parallelism: params.parallelism,
      hashLength: keyLength,
    );

    final derived = await argon2id.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: salt,
    );

    return MasterKey(Uint8List.fromList(await derived.extractBytes()));
  }

  /// Encrypts [plaintext] with AES-256-GCM under [key].
  ///
  /// A fresh random nonce is generated per call. The returned value is
  /// base64(nonce || ciphertext || mac).
  static Future<String> encrypt(String plaintext, MasterKey key) async {
    final secretBox = await _aesGcm.encrypt(
      utf8.encode(plaintext),
      secretKey: SecretKey(key.bytes),
    );
    return base64.encode(secretBox.concatenation());
  }

  /// Decrypts a value produced by [encrypt].
  ///
  /// Returns `null` when the payload is malformed, was encrypted under a
  /// different key, or fails GCM authentication (i.e. it was tampered with).
  /// Callers must treat `null` as "could not be trusted", never as "empty".
  static Future<String?> decrypt(String sealed, MasterKey key) async {
    try {
      final raw = base64.decode(sealed);
      if (raw.length < nonceLength + macLength) return null;

      final secretBox = SecretBox.fromConcatenation(
        raw,
        nonceLength: nonceLength,
        macLength: macLength,
      );

      final clear = await _aesGcm.decrypt(
        secretBox,
        secretKey: SecretKey(key.bytes),
      );
      return utf8.decode(clear);
    } catch (_) {
      // SecretBoxAuthenticationError (tampering / wrong key), FormatException
      // (bad base64 or non-UTF8 plaintext), or a malformed concatenation.
      return null;
    }
  }

  /// A value that proves knowledge of [key] without revealing it.
  ///
  /// Stored alongside the vault so a candidate password can be checked without
  /// attempting to decrypt account data. SHA-256 is appropriate here (rather
  /// than a slow KDF) because its input is already the Argon2id output — an
  /// attacker must pay the Argon2id cost per guess regardless.
  static String verifierFor(MasterKey key) {
    final digest = classic.sha256.convert([
      ...key.bytes,
      ...utf8.encode(_verifierDomain),
    ]);
    return digest.toString();
  }
}
