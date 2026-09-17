import 'dart:async';
import 'dart:io' show ProcessException;

import 'package:flutter_test/flutter_test.dart';

import 'package:dula_auth/core/security/linux_secret_service_probe.dart';

/// Canned subprocess results keyed by executable name. Each entry is consumed
/// in order, so a test can script "first call says X, second says Y".
class _FakeRunner {
  final Map<String, List<Object>> script;
  final invocations = <List<String>>[];

  _FakeRunner(this.script);

  Future<CommandResult> call(
    String executable,
    List<String> args, {
    required Duration timeout,
  }) async {
    invocations.add([executable, ...args]);
    final queue = script[executable];
    if (queue == null || queue.isEmpty) {
      throw ProcessException(executable, args, 'No such file or directory', 2);
    }
    final next = queue.removeAt(0);
    if (next is Exception) throw next;
    return next as CommandResult;
  }
}

CommandResult _ok(String stdout) => CommandResult(0, stdout, '');
CommandResult _fail(String stderr) => CommandResult(1, '', stderr);

/// `ReadAlias default` / `Collection.Locked` answers from a healthy desktop.
final _unlockedDefault = _ok(
  "(objectpath '/org/freedesktop/secrets/collection/login',)\n",
);
final _notLocked = _ok('(<false>,)\n');

void main() {
  group('LinuxSecretServiceProbe', () {
    test(
      'is available when org.freedesktop.secrets already has an owner',
      () async {
        final runner = _FakeRunner({
          'gdbus': [_ok('(true,)\n'), _unlockedDefault, _notLocked],
        });
        final probe = LinuxSecretServiceProbe(run: runner.call);

        expect(await probe.isAvailable(), isTrue);
        // Owner, default alias, Locked — and no activation attempt.
        expect(runner.invocations, hasLength(3));
        expect(runner.invocations.first.join(' '), contains('NameHasOwner'));
        expect(
          runner.invocations.join(' '),
          isNot(contains('StartServiceByName')),
        );
      },
    );

    test(
      'activates the service when not yet owned, and is available when '
      'activation succeeds and yields an unlocked default collection',
      () async {
        final runner = _FakeRunner({
          'gdbus': [
            _ok('(false,)\n'),
            _ok('(uint32 1,)\n'),
            _unlockedDefault,
            _notLocked,
          ],
        });
        final probe = LinuxSecretServiceProbe(run: runner.call);

        expect(await probe.isAvailable(), isTrue);
        expect(runner.invocations, hasLength(4));
        expect(runner.invocations[1].join(' '), contains('StartServiceByName'));
      },
    );

    test('is unavailable when the service is up but has no default '
        'collection — activation starts such a daemon, and storing into it '
        'raises a prompt nobody can answer', () async {
      final runner = _FakeRunner({
        'gdbus': [_ok('(true,)\n'), _ok("(objectpath '/',)\n")],
      });
      final probe = LinuxSecretServiceProbe(run: runner.call);

      expect(await probe.isAvailable(), isFalse);
    });

    test('is unavailable when the default collection is locked', () async {
      final runner = _FakeRunner({
        'gdbus': [_ok('(true,)\n'), _unlockedDefault, _ok('(<true>,)\n')],
      });
      final probe = LinuxSecretServiceProbe(run: runner.call);

      expect(await probe.isAvailable(), isFalse);
    });

    test('is unavailable when activation fails', () async {
      final runner = _FakeRunner({
        'gdbus': [
          _ok('(false,)\n'),
          _fail('Error: GDBus.Error:org.freedesktop.DBus.Error.ServiceUnknown'),
        ],
      });
      final probe = LinuxSecretServiceProbe(run: runner.call);

      expect(await probe.isAvailable(), isFalse);
    });

    test('is unavailable when activation hangs past the timeout — the case '
        'that used to freeze the whole app', () async {
      final runner = _FakeRunner({
        'gdbus': [_ok('(false,)\n'), TimeoutException('gdbus did not exit')],
      });
      final probe = LinuxSecretServiceProbe(run: runner.call);

      expect(await probe.isAvailable(), isFalse);
    });

    test('is unavailable when there is no session bus to ask', () async {
      final runner = _FakeRunner({
        'gdbus': [_fail('Error connecting: Could not connect: No such file')],
      });
      final probe = LinuxSecretServiceProbe(run: runner.call);

      expect(await probe.isAvailable(), isFalse);
    });

    test('falls back to dbus-send when gdbus is not installed', () async {
      final runner = _FakeRunner({
        'dbus-send': [
          _ok('method return ...\n   boolean true\n'),
          _ok(
            'method return ...\n   object path "/org/freedesktop/secrets/collection/login"\n',
          ),
          _ok('method return ...\n   variant       boolean false\n'),
        ],
      });
      final probe = LinuxSecretServiceProbe(run: runner.call);

      expect(await probe.isAvailable(), isTrue);
      expect(runner.invocations.last.first, 'dbus-send');
    });

    test('with neither tool installed the verdict is unknown, which is '
        'treated as available so a working system is never blocked', () async {
      final runner = _FakeRunner({});
      final probe = LinuxSecretServiceProbe(run: runner.call);

      expect(await probe.isAvailable(), isTrue);
    });
  });
}
