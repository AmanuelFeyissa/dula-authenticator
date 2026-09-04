import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';

import 'package:dula_auth/core/security/isolated_secure_storage_probe.dart';

Future<void> _answersTrue(List<Object?> args) async {
  (args[0] as SendPort).send(true);
}

Future<void> _answersFalse(List<Object?> args) async {
  (args[0] as SendPort).send(false);
}

Future<void> _neverAnswers(List<Object?> args) async {
  await Future<void>.delayed(const Duration(days: 1));
}

Future<void> _throws(List<Object?> args) async {
  throw StateError('probe blew up');
}

void main() {
  group('IsolatedSecureStorageProbe.runEntry', () {
    test('returns what the probe isolate answers', () async {
      expect(
        await IsolatedSecureStorageProbe.runEntry(_answersTrue, const []),
        isTrue,
      );
      expect(
        await IsolatedSecureStorageProbe.runEntry(_answersFalse, const []),
        isFalse,
      );
    });

    test(
      'returns false within the timeout when the probe never answers, so a '
      'blocking platform call cannot freeze startup (ADR-0017)',
      () async {
        final stopwatch = Stopwatch()..start();
        final result = await IsolatedSecureStorageProbe.runEntry(
          _neverAnswers,
          const [],
          timeout: const Duration(seconds: 1),
        );
        stopwatch.stop();

        expect(result, isFalse);
        // The point of the isolate boundary: the caller stays responsive and
        // gives up on schedule instead of waiting forever.
        expect(stopwatch.elapsed, lessThan(const Duration(seconds: 10)));
      },
    );

    test('returns false when the probe isolate throws', () async {
      expect(
        await IsolatedSecureStorageProbe.runEntry(_throws, const []),
        isFalse,
      );
    });
  });
}
