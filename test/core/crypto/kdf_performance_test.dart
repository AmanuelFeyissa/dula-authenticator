import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:dula_auth/core/crypto/vault_crypto.dart';

/// Argon2id is deliberately slow, but unlock has to stay usable. ADR-0010
/// flagged this as the main trade-off of the migration, so the cost is
/// measured rather than assumed.
///
/// The bound below is intentionally generous: this is a regression guard
/// against a parameter change making unlock unbearable, not a benchmark.
void main() {
  test('deriving a key at OWASP defaults stays within the unlock budget',
      () async {
    final salt = Uint8List.fromList(List<int>.generate(32, (i) => i));

    final stopwatch = Stopwatch()..start();
    await VaultCrypto.deriveKey(
      'a representative passphrase',
      salt,
      KdfParams.owaspDefault,
    );
    stopwatch.stop();

    // ignore: avoid_print
    print('Argon2id (m=${KdfParams.owaspDefault.memoryKiB} KiB, '
        't=${KdfParams.owaspDefault.iterations}, '
        'p=${KdfParams.owaspDefault.parallelism}) '
        'took ${stopwatch.elapsedMilliseconds} ms on this host');

    expect(
      stopwatch.elapsedMilliseconds,
      lessThan(5000),
      reason: 'unlock must not feel broken; revisit KDF parameters if this '
          'fails on target hardware',
    );
  }, timeout: const Timeout(Duration(minutes: 2)));
}
