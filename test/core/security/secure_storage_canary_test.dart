import 'dart:async';

import 'package:flutter/material.dart' show TargetPlatform;
import 'package:flutter_test/flutter_test.dart';
import 'package:dula_auth/core/security/secure_storage_canary.dart';
import 'package:dula_auth/core/vault/secret_store.dart';

class _HangingSecretStore implements SecretStore {
  @override
  Future<String?> read(String key) => Completer<String?>().future;

  @override
  Future<void> write(String key, String value) => Completer<void>().future;

  @override
  Future<void> delete(String key) => Completer<void>().future;
}

class _ThrowingSecretStore implements SecretStore {
  @override
  Future<String?> read(String key) async => throw StateError('no keyring');

  @override
  Future<void> write(String key, String value) async =>
      throw StateError('no keyring');

  @override
  Future<void> delete(String key) async {}
}

class _SilentlyWrongSecretStore implements SecretStore {
  @override
  Future<String?> read(String key) async => 'not what was written';

  @override
  Future<void> write(String key, String value) async {}

  @override
  Future<void> delete(String key) async {}
}

void main() {
  group('SecureStorageCanary.check', () {
    test('true when a value round-trips through the store', () async {
      final store = InMemorySecretStore();
      expect(await SecureStorageCanary.check(store), isTrue);
    });

    test('false when the store throws (e.g. no keyring daemon)', () async {
      expect(await SecureStorageCanary.check(_ThrowingSecretStore()), isFalse);
    });

    test('false when the read-back does not match what was written',
        () async {
      expect(
        await SecureStorageCanary.check(_SilentlyWrongSecretStore()),
        isFalse,
      );
    });

    test(
        'false within a bounded time when the store never responds '
        '(e.g. a hung platform call with no D-Bus session)', () async {
      final result = await SecureStorageCanary.check(_HangingSecretStore())
          .timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw TimeoutException(
          'check() did not resolve on its own — it needs its own internal '
          'timeout around the underlying store calls',
        ),
      );
      expect(result, isFalse);
    });

    test('leaves no canary key behind after a successful check', () async {
      final store = InMemorySecretStore();
      await SecureStorageCanary.check(store);
      expect(store.dump(), isEmpty);
    });
  });

  group('secureStorageCanaryAppliesOn', () {
    test('applies on Linux', () {
      expect(secureStorageCanaryAppliesOn(TargetPlatform.linux), isTrue);
    });

    test('does not apply on Windows, macOS, Android, or iOS', () {
      expect(secureStorageCanaryAppliesOn(TargetPlatform.windows), isFalse);
      expect(secureStorageCanaryAppliesOn(TargetPlatform.macOS), isFalse);
      expect(secureStorageCanaryAppliesOn(TargetPlatform.android), isFalse);
      expect(secureStorageCanaryAppliesOn(TargetPlatform.iOS), isFalse);
    });
  });
}
