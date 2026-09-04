import 'dart:async';
import 'dart:isolate';

import 'package:flutter/services.dart';

import 'package:dula_auth/core/security/secure_storage_canary.dart';
import 'package:dula_auth/core/vault/secret_store.dart';

/// Runs the ADR-0004 secure-storage canary on a background isolate.
///
/// Caller: `lib/core/widgets/app_lifecycle_wrapper.dart`, via
/// `secureStorageProbeProvider`. No data schema of its own — it answers a
/// single bool, "can this system actually persist a secret".
///
/// Why an isolate (ADR-0017): on Linux with no Secret Service registered on
/// D-Bus, `flutter_secure_storage`'s write does not return, throw, or time
/// out — it blocks the calling isolate outright. Measured directly: a
/// `Timer.periodic` heartbeat on the main isolate ticked once and then stopped
/// for the following 45 seconds, which is why the in-process
/// `Future.timeout()` in [SecureStorageCanary] cannot rescue it — the timer
/// that would fire the timeout is on the isolate that is stuck. Moving the
/// platform call to its own isolate keeps the UI isolate scheduling normally,
/// so the timeout here does fire and ADR-0004's blocking error screen is
/// actually reached.
class IsolatedSecureStorageProbe {
  static const _defaultTimeout = Duration(seconds: 5);

  /// The production probe: the real platform store, on its own isolate.
  static Future<bool> run({Duration timeout = _defaultTimeout}) {
    final token = RootIsolateToken.instance;
    if (token == null) {
      // No root token means platform channels cannot be bootstrapped on a
      // spawned isolate (a background isolate, or a test binding). Fall back
      // to checking in-process: less robust, but a real answer beats none.
      return SecureStorageCanary.check(const FlutterSecretStore());
    }
    return runEntry(_probeRealStore, [token], timeout: timeout);
  }

  /// Spawns [entry], waits for the single bool it sends back, and gives up
  /// after [timeout].
  ///
  /// A probe that never answers is killed rather than left running, so a stuck
  /// platform call cannot outlive the check that started it.
  static Future<bool> runEntry(
    void Function(List<Object?>) entry,
    List<Object?> message, {
    Duration timeout = _defaultTimeout,
  }) async {
    final port = ReceivePort();
    Isolate? isolate;
    try {
      isolate = await Isolate.spawn(
        entry,
        [port.sendPort, ...message],
        // Without this an uncaught error in the probe would take the whole
        // app down instead of simply failing the check.
        errorsAreFatal: false,
      );
      final answer = await port.first.timeout(timeout);
      return answer == true;
    } catch (_) {
      // Timed out, failed to spawn, or the probe died — all of which mean the
      // same thing here: secure storage could not be verified.
      return false;
    } finally {
      isolate?.kill(priority: Isolate.immediate);
      port.close();
    }
  }

  static Future<void> _probeRealStore(List<Object?> args) async {
    final send = args[0] as SendPort;
    final token = args[1] as RootIsolateToken;
    // Platform channels are not wired up on a spawned isolate by default.
    BackgroundIsolateBinaryMessenger.ensureInitialized(token);
    send.send(await SecureStorageCanary.check(const FlutterSecretStore()));
  }
}
