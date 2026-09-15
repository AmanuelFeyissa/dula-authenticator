import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Exit code and captured output of a finished subprocess.
class CommandResult {
  final int exitCode;
  final String stdout;
  final String stderr;
  const CommandResult(this.exitCode, this.stdout, this.stderr);
}

/// Runs [executable] with [args], killing it and throwing [TimeoutException]
/// if it has not exited within [timeout]. Throws [ProcessException] when the
/// executable does not exist.
typedef CommandRunner = Future<CommandResult> Function(
  String executable,
  List<String> args, {
  required Duration timeout,
});

/// Asks the D-Bus session bus whether a Secret Service is reachable, without
/// ever touching libsecret.
///
/// Caller: `lib/core/vault/secret_store_provider.dart`, as the check behind
/// the Linux `SecretStoreGate`. Data: none stored; it parses the stdout of
/// `gdbus` (`(true,)` / `(uint32 1,)`) or `dbus-send` (`boolean true`).
///
/// Why a subprocess (ADR-0018): the app has no D-Bus client library, and adding
/// one for a single yes/no question is more dependency than the question is
/// worth. `dart:io` `Process` is fully asynchronous, so a hung `gdbus` cannot
/// take the platform thread with it the way a hung libsecret call does — it
/// simply gets killed at the timeout and reported as "unavailable".
///
/// Three questions are asked, in order:
///  1. `NameHasOwner org.freedesktop.secrets` — a daemon is already running.
///  2. If not, `StartServiceByName` — the bus may be able to activate one
///     (gnome-keyring installs an activation file), bounded because that is
///     one place a headless session can hang.
///  3. `ReadAlias default` and the collection's `Locked` property — a daemon
///     with **no unlocked default collection** is the trap: activation
///     produces exactly that (verified in the ADR-0018 container), and the
///     plugin's store-to-default-collection call then makes the daemon raise
///     a create/unlock *prompt* nobody can answer. That prompt, not the
///     daemon's absence, is what blocks the platform thread.
///
/// If neither `gdbus` nor `dbus-send` is installed the answer is unknown; that
/// is treated as available, because refusing to run on a machine whose keyring
/// may be perfectly fine is the wrong failure. The trade-off is recorded in
/// ADR-0018.
class LinuxSecretServiceProbe {
  static const secretsBusName = 'org.freedesktop.secrets';
  static const _busDest = 'org.freedesktop.DBus';
  static const _busPath = '/org/freedesktop/DBus';

  final CommandRunner _run;
  final Duration queryTimeout;
  final Duration activationTimeout;

  LinuxSecretServiceProbe({
    CommandRunner? run,
    this.queryTimeout = const Duration(seconds: 3),
    this.activationTimeout = const Duration(seconds: 10),
  }) : _run = run ?? runCommand;

  Future<bool> isAvailable() async {
    final owned = await _nameHasOwner();
    if (owned != null) {
      if (!owned && !await _startService()) return false;
      return _defaultCollectionUnlocked();
    }
    // Neither tool present: unknown, so do not block a possibly-working
    // system. Logged so a stuck deployment has a trail to follow.
    debugPrint(
      'LinuxSecretServiceProbe: neither gdbus nor dbus-send is available; '
      'cannot verify $secretsBusName before using it.',
    );
    return true;
  }

  /// `true`/`false` from the bus, or `null` when no tool could ask.
  Future<bool?> _nameHasOwner() async {
    try {
      final r = await _run(
        'gdbus',
        [
          'call', '--session',
          '--dest', _busDest, '--object-path', _busPath,
          '--method', '$_busDest.NameHasOwner', secretsBusName,
        ],
        timeout: queryTimeout,
      );
      // A failed call here means no session bus at all — nothing to activate.
      if (r.exitCode != 0) return false;
      return r.stdout.contains('true');
    } on ProcessException {
      // gdbus missing: try dbus-send below.
    } on TimeoutException {
      return false;
    }

    try {
      final r = await _run(
        'dbus-send',
        [
          '--session', '--print-reply', '--dest=$_busDest', _busPath,
          '$_busDest.NameHasOwner', 'string:$secretsBusName',
        ],
        timeout: queryTimeout,
      );
      if (r.exitCode != 0) return false;
      return r.stdout.contains('boolean true');
    } on ProcessException {
      return null;
    } on TimeoutException {
      return false;
    }
  }

  Future<bool> _startService() async {
    try {
      final r = await _run(
        'gdbus',
        [
          'call', '--session',
          '--dest', _busDest, '--object-path', _busPath,
          '--method', '$_busDest.StartServiceByName', secretsBusName, '0',
        ],
        timeout: activationTimeout,
      );
      return r.exitCode == 0;
    } on ProcessException {
      // gdbus was missing above too, so we got here via dbus-send.
    } on TimeoutException {
      return false;
    }

    try {
      final r = await _run(
        'dbus-send',
        [
          '--session', '--print-reply', '--dest=$_busDest', _busPath,
          '$_busDest.StartServiceByName', 'string:$secretsBusName', 'uint32:0',
        ],
        timeout: activationTimeout,
      );
      return r.exitCode == 0;
    } on ProcessException {
      return false;
    } on TimeoutException {
      return false;
    }
  }

  static const _secretsPath = '/org/freedesktop/secrets';
  static const _serviceIface = 'org.freedesktop.Secret.Service';
  static const _collectionIface = 'org.freedesktop.Secret.Collection';

  /// `true` only when a default collection exists and is unlocked. Both
  /// tools print the object path in quotes; a missing alias comes back as
  /// the root path `/`.
  Future<bool> _defaultCollectionUnlocked() async {
    final String? path;
    try {
      final r = await _run(
        'gdbus',
        [
          'call', '--session',
          '--dest', secretsBusName, '--object-path', _secretsPath,
          '--method', '$_serviceIface.ReadAlias', 'default',
        ],
        timeout: queryTimeout,
      );
      path = r.exitCode == 0 ? _objectPath(r.stdout) : null;
    } on ProcessException {
      return _defaultCollectionUnlockedViaDbusSend();
    } on TimeoutException {
      return false;
    }
    if (path == null || path == '/') return false;

    try {
      final r = await _run(
        'gdbus',
        [
          'call', '--session',
          '--dest', secretsBusName, '--object-path', path,
          '--method', 'org.freedesktop.DBus.Properties.Get',
          _collectionIface, 'Locked',
        ],
        timeout: queryTimeout,
      );
      return r.exitCode == 0 && r.stdout.contains('false');
    } on ProcessException {
      return false;
    } on TimeoutException {
      return false;
    }
  }

  Future<bool> _defaultCollectionUnlockedViaDbusSend() async {
    final String? path;
    try {
      final r = await _run(
        'dbus-send',
        [
          '--session', '--print-reply', '--dest=$secretsBusName', _secretsPath,
          '$_serviceIface.ReadAlias', 'string:default',
        ],
        timeout: queryTimeout,
      );
      path = r.exitCode == 0 ? _objectPath(r.stdout) : null;
    } on ProcessException {
      return false;
    } on TimeoutException {
      return false;
    }
    if (path == null || path == '/') return false;

    try {
      final r = await _run(
        'dbus-send',
        [
          '--session', '--print-reply', '--dest=$secretsBusName', path,
          'org.freedesktop.DBus.Properties.Get',
          'string:$_collectionIface', 'string:Locked',
        ],
        timeout: queryTimeout,
      );
      return r.exitCode == 0 && r.stdout.contains('boolean false');
    } on ProcessException {
      return false;
    } on TimeoutException {
      return false;
    }
  }

  /// Extracts the first quoted D-Bus object path from tool output —
  /// `(objectpath '/x',)` from gdbus, `object path "/x"` from dbus-send.
  static String? _objectPath(String stdout) {
    final m = RegExp(r'''['"](/[^'"]*)['"]''').firstMatch(stdout);
    return m?.group(1);
  }

  /// The production [CommandRunner]: a real subprocess with a hard kill at
  /// [timeout], so the caller is never left waiting on it.
  static Future<CommandResult> runCommand(
    String executable,
    List<String> args, {
    required Duration timeout,
  }) async {
    final process = await Process.start(executable, args);
    final out = process.stdout.transform(utf8.decoder).join();
    final err = process.stderr.transform(utf8.decoder).join();
    try {
      final code = await process.exitCode.timeout(timeout);
      final result = CommandResult(code, await out, await err);
      // D-Bus bookkeeping only — never a secret. Debug builds only, so a
      // stuck deployment can be diagnosed from the console.
      if (kDebugMode) {
        debugPrint(
          'LinuxSecretServiceProbe: $executable ${args.last} -> '
          'exit=$code out=${result.stdout.trim()} err=${result.stderr.trim()}',
        );
      }
      return result;
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
      if (kDebugMode) {
        debugPrint('LinuxSecretServiceProbe: $executable ${args.last} timed out');
      }
      rethrow;
    }
  }
}
