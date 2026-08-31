import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:dula_auth/core/backup/backup_service.dart';
import 'package:dula_auth/core/backup/import_source_detector.dart';

void main() {
  test('recognises this app\'s own backup format', () {
    final content = jsonEncode({
      'v': BackupService.formatVersion,
      'app': BackupService.appIdentifier,
      'kdf': {},
      'salt': 'x',
      'payload': 'y',
    });
    expect(ImportSourceDetector.detect(content), BackupSourceKind.ownFormat);
  });

  test('recognises an Aegis vault by its db field', () {
    final content = jsonEncode({
      'version': 1,
      'header': {},
      'db': {'entries': []},
    });
    expect(ImportSourceDetector.detect(content), BackupSourceKind.aegis);
  });

  test('recognises a 2FAS export by its services field', () {
    final content = jsonEncode({'schemaVersion': 4, 'services': []});
    expect(ImportSourceDetector.detect(content), BackupSourceKind.twoFas);
  });

  test('recognises an encrypted 2FAS export even with no services field', () {
    final content = jsonEncode({'servicesEncrypted': 'blob=='});
    expect(ImportSourceDetector.detect(content), BackupSourceKind.twoFas);
  });

  test('reports unrecognized JSON that matches no known shape', () {
    expect(ImportSourceDetector.detect(jsonEncode({'hello': 'world'})),
        BackupSourceKind.unrecognized);
  });

  test('reports unrecognized for input that is not JSON', () {
    expect(ImportSourceDetector.detect('not json'),
        BackupSourceKind.unrecognized);
  });

  test('reports unrecognized for JSON that is not an object', () {
    expect(ImportSourceDetector.detect(jsonEncode([1, 2, 3])),
        BackupSourceKind.unrecognized);
  });
}
