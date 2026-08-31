import 'dart:convert';

import 'package:dula_auth/core/backup/backup_service.dart';

/// Which parser a file's content belongs to.
enum BackupSourceKind { ownFormat, aegis, twoFas, unrecognized }

/// Sniffs a file's top-level JSON shape to decide which importer to hand it
/// to, so the import screen does not need its own copy of each format's
/// field names.
///
/// Callers: `lib/features/backup/**` (import screen). No data schema of its
/// own — reads the shape of whatever file the user picked.
///
/// Detection order matters: this app's own format is checked first via its
/// explicit `app` marker (an unambiguous signal), then Aegis's `db` field,
/// then 2FAS's `services`/`servicesEncrypted` fields. Anything else — not
/// JSON, not an object, or an object matching none of these shapes — is
/// unrecognized rather than guessed at.
///
/// Added for the user instruction "go ahead with phase 4"
/// (docs/adr/0013-backup-export-and-import.md).
class ImportSourceDetector {
  static BackupSourceKind detect(String raw) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return BackupSourceKind.unrecognized;
    }
    if (decoded is! Map<String, dynamic>) return BackupSourceKind.unrecognized;

    if (decoded['app'] == BackupService.appIdentifier) {
      return BackupSourceKind.ownFormat;
    }
    if (decoded.containsKey('db')) return BackupSourceKind.aegis;
    if (decoded.containsKey('services') ||
        decoded.containsKey('servicesEncrypted')) {
      return BackupSourceKind.twoFas;
    }
    return BackupSourceKind.unrecognized;
  }
}
