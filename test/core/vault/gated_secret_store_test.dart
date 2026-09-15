import 'package:flutter_test/flutter_test.dart';

import 'package:dula_auth/core/vault/gated_secret_store.dart';
import 'package:dula_auth/core/vault/secret_store.dart';

/// Records every call so a test can prove the inner store was — or was not —
/// reached. The point of the gate is that an unavailable backend is never
/// entered at all, since on Linux entering it is what freezes the app.
class _RecordingSecretStore implements SecretStore {
  final calls = <String>[];
  final _values = <String, String>{};

  @override
  Future<String?> read(String key) async {
    calls.add('read $key');
    return _values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    calls.add('write $key');
    _values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    calls.add('delete $key');
    _values.remove(key);
  }
}

void main() {
  group('GatedSecretStore', () {
    test('passes read, write and delete through when the gate is open',
        () async {
      final inner = _RecordingSecretStore();
      final store = GatedSecretStore(inner, SecretStoreGate(() async => true));

      await store.write('k', 'v');
      expect(await store.read('k'), 'v');
      await store.delete('k');

      expect(inner.calls, ['write k', 'read k', 'delete k']);
    });

    test('throws SecretStoreUnavailableException without touching the inner '
        'store when the gate is closed', () async {
      final inner = _RecordingSecretStore();
      final store =
          GatedSecretStore(inner, SecretStoreGate(() async => false));

      await expectLater(
        store.read('k'),
        throwsA(isA<SecretStoreUnavailableException>()),
      );
      await expectLater(
        store.write('k', 'v'),
        throwsA(isA<SecretStoreUnavailableException>()),
      );
      await expectLater(
        store.delete('k'),
        throwsA(isA<SecretStoreUnavailableException>()),
      );
      expect(inner.calls, isEmpty);
    });

    test('a gate check that throws counts as closed', () async {
      final inner = _RecordingSecretStore();
      final store = GatedSecretStore(
        inner,
        SecretStoreGate(() async => throw StateError('dbus exploded')),
      );

      await expectLater(
        store.read('k'),
        throwsA(isA<SecretStoreUnavailableException>()),
      );
      expect(inner.calls, isEmpty);
    });
  });

  group('SecretStoreGate', () {
    test('runs the check once and memoises the verdict', () async {
      var checks = 0;
      final gate = SecretStoreGate(() async {
        checks++;
        return true;
      });
      final store = GatedSecretStore(_RecordingSecretStore(), gate);

      await store.write('a', '1');
      await store.read('a');
      await store.read('a');

      expect(checks, 1);
    });

    test('concurrent first calls share a single in-flight check', () async {
      var checks = 0;
      final gate = SecretStoreGate(() async {
        checks++;
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return true;
      });
      final store = GatedSecretStore(_RecordingSecretStore(), gate);

      await Future.wait([store.read('a'), store.read('b'), store.read('c')]);

      expect(checks, 1);
    });

    test('reset() makes the next call re-run the check, so RETRY on the '
        'error screen can pick up a keyring started since', () async {
      var available = false;
      var checks = 0;
      final gate = SecretStoreGate(() async {
        checks++;
        return available;
      });
      final store = GatedSecretStore(_RecordingSecretStore(), gate);

      await expectLater(
        store.read('k'),
        throwsA(isA<SecretStoreUnavailableException>()),
      );

      available = true;
      gate.reset();
      expect(await store.read('k'), isNull);
      expect(checks, 2);
    });

    test('alwaysOpen never blocks and never runs a subprocess', () async {
      final store =
          GatedSecretStore(_RecordingSecretStore(), SecretStoreGate.alwaysOpen);
      await store.write('k', 'v');
      expect(await store.read('k'), 'v');
    });
  });
}
