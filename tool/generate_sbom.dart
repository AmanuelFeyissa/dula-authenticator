// Emits a CycloneDX 1.5 SBOM for this project's Dart/Flutter dependencies.
//
//   dart run tool/generate_sbom.dart dist/sbom.cdx.json
//
// Takes the output path as an argument rather than writing to stdout on
// purpose: `dart run` prints "Running build hooks..." to stdout itself, so a
// shell redirect produces a file that is not valid JSON.
//
// Required by ADR-0007: an adopter on an air-gapped network cannot resolve
// this dependency tree to see what they are running, so each release states
// it, with the SHA-256 of every package so the tree can be verified offline.
//
// Reads pubspec.lock and pubspec.yaml; writes only to stdout. Parsing and
// rendering live in tool/sbom_lib.dart, covered by test/tool/sbom_test.dart.
import 'dart:io';

import 'sbom_lib.dart';

void main(List<String> args) {
  final lock = File('pubspec.lock');
  final spec = File('pubspec.yaml');
  if (!lock.existsSync() || !spec.existsSync()) {
    stderr.writeln('run this from the repository root: pubspec.lock not found');
    exit(1);
  }

  final pubspec = spec.readAsStringSync();
  final name = _field(pubspec, 'name') ?? 'dula_auth';
  // `1.0.0+1` is an app version plus a build number; the SBOM wants the former.
  final version = (_field(pubspec, 'version') ?? '0.0.0').split('+').first;

  final sbom = buildCycloneDx(
    packages: parseLockfile(lock.readAsStringSync()),
    appName: name,
    appVersion: version,
    // SOURCE_DATE_EPOCH, when set, makes the output reproducible for a given
    // commit — the convention build systems already use for this.
    timestamp: _timestamp(),
  );

  if (args.isEmpty) {
    stderr.writeln('usage: dart run tool/generate_sbom.dart <output.json>');
    exit(2);
  }

  final out = File(args.first);
  out.parent.createSync(recursive: true);
  out.writeAsStringSync(sbom);
  stderr.writeln('wrote ${out.path}');
}

String? _field(String pubspec, String key) {
  for (final line in pubspec.split('\n')) {
    if (line.startsWith('$key:')) {
      return line.substring(key.length + 1).trim().replaceAll('"', '');
    }
  }
  return null;
}

DateTime _timestamp() {
  final epoch = Platform.environment['SOURCE_DATE_EPOCH'];
  final seconds = int.tryParse(epoch ?? '');
  return seconds == null
      ? DateTime.now().toUtc()
      : DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
}
