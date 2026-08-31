import 'dart:convert';
import 'dart:io' as io;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

/// Native save/open file dialogs for backup export and import.
///
/// Callers: `lib/features/backup/**` (export/import screens). No data schema
/// — this reads and writes whatever content the caller supplies.
///
/// **Platform note (CLAUDE.md: verify, don't assume):** `file_picker`'s
/// `saveFile(bytes: ...)` convenience — write the bytes directly — has a
/// documented bug on Linux where the call reports success but the file is
/// never actually written
/// (https://github.com/miguelpruivo/flutter_file_picker/issues/1907, package
/// 10.3.3, Nov 2025). Rather than trust that path, [save] uses `saveFile()`
/// only to obtain a destination **path** chosen by the user, then writes the
/// bytes itself via `dart:io`, which has no such bug. Web has no filesystem
/// to write to, so it is the one platform where passing `bytes` to
/// `saveFile()` is both necessary and the documented, correct mechanism (it
/// triggers a browser download).
///
/// Added for the user instruction "go ahead with phase 4"
/// (docs/adr/0013-backup-export-and-import.md).
class BackupFileIO {
  /// Writes [content] to a location the user chooses. Returns true if a file
  /// was written, false if the user cancelled.
  static Future<bool> save({
    required String content,
    required String suggestedName,
  }) async {
    final bytes = Uint8List.fromList(utf8.encode(content));

    if (kIsWeb) {
      final path = await FilePicker.saveFile(
        dialogTitle: 'Save backup',
        fileName: suggestedName,
        bytes: bytes,
      );
      return path != null;
    }

    final path = await FilePicker.saveFile(
      dialogTitle: 'Save backup',
      fileName: suggestedName,
    );
    if (path == null) return false;

    await io.File(path).writeAsBytes(bytes);
    return true;
  }

  /// Prompts the user to choose a file and returns its content decoded as
  /// UTF-8 text, or null if they cancelled or the file could not be read as
  /// text (e.g. it was not actually a text file).
  static Future<String?> pickAndRead({List<String>? allowedExtensions}) async {
    final result = await FilePicker.pickFiles(
      dialogTitle: 'Choose a file to import',
      type: allowedExtensions == null ? FileType.any : FileType.custom,
      allowedExtensions: allowedExtensions,
      withData: true,
    );
    final bytes = result?.files.single.bytes;
    if (bytes == null) return null;

    try {
      return utf8.decode(bytes);
    } on FormatException {
      return null;
    }
  }
}
