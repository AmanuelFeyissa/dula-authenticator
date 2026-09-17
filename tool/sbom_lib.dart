import 'dart:convert';

/// One entry from `pubspec.lock`.
class LockedPackage {
  final String name;
  final String version;

  /// The hash pub recorded for the archive it resolved. Null for packages
  /// that have no archive — the Flutter SDK's own pseudo-packages.
  final String? sha256;

  /// `hosted`, `sdk`, `git` or `path`.
  final String source;

  /// Where the package came from, when hosted.
  final String? url;

  /// A `direct dev` dependency: present at build time, absent from the
  /// shipped artifact. Recorded so the SBOM can say so rather than implying
  /// the linter is part of the product.
  final bool isDevOnly;

  const LockedPackage({
    required this.name,
    required this.version,
    required this.sha256,
    required this.source,
    required this.url,
    required this.isDevOnly,
  });
}

/// Parses `pubspec.lock`.
///
/// Deliberately hand-rolled rather than pulled through a YAML package: the
/// lockfile is machine-generated with a fixed two-space shape, this runs
/// during a release build where a new dependency would need its own ADR-0007
/// review, and the alternative was adding a parser to read a file whose
/// grammar is four keys deep.
List<LockedPackage> parseLockfile(String contents) {
  final packages = <LockedPackage>[];

  String? name;
  String? version;
  String? sha256;
  String? source;
  String? url;
  var isDevOnly = false;
  var inPackages = false;

  void flush() {
    if (name == null) return;
    packages.add(
      LockedPackage(
        name: name!,
        version: version ?? '',
        sha256: sha256,
        source: source ?? 'unknown',
        url: url,
        isDevOnly: isDevOnly,
      ),
    );
    name = version = sha256 = source = url = null;
    isDevOnly = false;
  }

  for (final raw in const LineSplitter().convert(contents)) {
    if (raw.trim().isEmpty || raw.trimLeft().startsWith('#')) continue;

    // Top-level keys: `packages:` opens the section we want, anything else
    // (`sdks:`) closes it, so the SDK constraints are never read as packages.
    if (!raw.startsWith(' ')) {
      flush();
      inPackages = raw.trimRight() == 'packages:';
      continue;
    }
    if (!inPackages) continue;

    final indent = raw.length - raw.trimLeft().length;
    final line = raw.trim();

    // Two spaces: a new package name.
    if (indent == 2 && line.endsWith(':')) {
      flush();
      name = _unquote(line.substring(0, line.length - 1));
      continue;
    }

    final colon = line.indexOf(':');
    if (colon < 0) continue;
    final key = line.substring(0, colon).trim();
    final value = _unquote(line.substring(colon + 1).trim());

    switch (key) {
      // `dependency` and `version` sit at four spaces, `name`/`sha256`/`url`
      // at six under `description`. Matching on the key alone is unambiguous
      // because none of them repeat within one package.
      case 'dependency':
        isDevOnly = value == 'direct dev';
      case 'version':
        version = value;
      case 'source':
        source = value;
      case 'sha256':
        if (value.isNotEmpty) sha256 = value;
      case 'url':
        url = value;
    }
  }
  flush();

  return packages;
}

String _unquote(String v) {
  if (v.length >= 2 &&
      ((v.startsWith('"') && v.endsWith('"')) ||
          (v.startsWith("'") && v.endsWith("'")))) {
    return v.substring(1, v.length - 1);
  }
  return v;
}

/// Renders a CycloneDX 1.5 SBOM as pretty-printed JSON.
///
/// Required by ADR-0007: an air-gapped adopter cannot resolve this dependency
/// tree themselves, so a release has to state what is in it, with the hashes
/// needed to verify each piece independently.
///
/// [timestamp] is a parameter rather than `DateTime.now()` so the output is
/// reproducible — two builds of the same commit should differ only by the time
/// they were made, and a caller that wants byte-identical output can pass a
/// fixed value.
String buildCycloneDx({
  required List<LockedPackage> packages,
  required String appName,
  required String appVersion,
  required DateTime timestamp,
}) {
  final sorted = [...packages]..sort((a, b) => a.name.compareTo(b.name));

  final components = sorted.map((p) {
    final purl = 'pkg:pub/${p.name}@${p.version}';
    return <String, dynamic>{
      'type': 'library',
      'bom-ref': purl,
      'name': p.name,
      'version': p.version,
      'purl': purl,
      'scope': p.isDevOnly ? 'excluded' : 'required',
      if (p.sha256 != null)
        'hashes': [
          {'alg': 'SHA-256', 'content': p.sha256},
        ],
      if (p.url != null)
        'externalReferences': [
          {'type': 'distribution', 'url': p.url},
        ],
    };
  }).toList();

  final bom = <String, dynamic>{
    'bomFormat': 'CycloneDX',
    'specVersion': '1.5',
    'version': 1,
    'metadata': {
      'timestamp': timestamp.toUtc().toIso8601String(),
      'tools': [
        {'name': 'tool/generate_sbom.dart', 'vendor': 'Dula Authenticator'},
      ],
      'component': {
        'type': 'application',
        'bom-ref': 'pkg:pub/$appName@$appVersion',
        'name': appName,
        'version': appVersion,
        'licenses': [
          {
            'license': {'id': 'Apache-2.0'},
          },
        ],
      },
    },
    'components': components,
  };

  return '${const JsonEncoder.withIndent('  ').convert(bom)}\n';
}
