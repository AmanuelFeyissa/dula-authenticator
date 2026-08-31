import 'dart:convert';
import 'dart:typed_data';

import 'package:base32/base32.dart';
import 'package:dula_auth/core/models/otp_account.dart';
import 'package:dula_auth/core/otp/otp_algorithm.dart';
import 'package:dula_auth/core/otp/otp_type.dart';

/// Decodes Google Authenticator's `otpauth-migration://` export payload.
///
/// Callers: `lib/features/backup/**` (import screen). No data schema of its
/// own — it produces [OtpAccount] values that the caller then hands to
/// `AccountRepository`.
///
/// The payload's `data` query parameter is a base64-encoded protobuf
/// message (undocumented by Google, but its wire format has been reverse
/// engineered and independently corroborated: see
/// https://github.com/dim13/otpauth and
/// https://github.com/scito/extract_otp_secrets). This is a hand-written
/// protobuf decoder rather than a dependency on the `protobuf` package: the
/// schema is two small, fixed messages, and a minimal decoder keeps this
/// air-gap-friendly project's footprint down (ADR-0007).
///
/// `MigrationPayload`:
/// ```
/// message MigrationPayload {
///   repeated OtpParameters otp_parameters = 1;
///   int32 version = 2;
///   int32 batch_size = 3;
///   int32 batch_index = 4;
///   int32 batch_id = 5;
/// }
/// message OtpParameters {
///   bytes secret = 1;
///   string name = 2;
///   string issuer = 3;
///   Algorithm algorithm = 4;  // 0=UNSPECIFIED 1=SHA1 2=SHA256 3=SHA512 4=MD5
///   DigitCount digits = 5;    // 0=UNSPECIFIED 1=SIX 2=EIGHT
///   OtpType type = 6;         // 0=UNSPECIFIED 1=HOTP 2=TOTP
///   uint64 counter = 7;
///   string unique_id = 8;
/// }
/// ```
///
/// See docs/adr/0013-backup-export-and-import.md. Input here is a scanned QR
/// code or pasted string — untrusted by construction — so every failure mode
/// returns null rather than throwing or producing a partial result.
class GoogleAuthenticatorMigration {
  /// Parses [raw] into accounts, or returns null if it is not a well-formed
  /// migration payload. [newId] supplies a fresh id per decoded account.
  static List<OtpAccount>? parse(String raw, {required String Function() newId}) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    final Uri uri;
    try {
      uri = Uri.parse(trimmed);
    } on FormatException {
      return null;
    }
    if (uri.scheme.toLowerCase() != 'otpauth-migration') return null;

    // Present-but-empty (`?data=`) is a legitimate zero-entry payload,
    // distinct from the parameter being absent entirely.
    final data = uri.queryParameters['data'];
    if (data == null) return null;

    final Uint8List payload;
    try {
      payload = data.isEmpty
          ? Uint8List(0)
          : base64.decode(base64.normalize(data));
    } on FormatException {
      return null;
    }

    final entries = _readFields(payload);
    if (entries == null) return null;

    final accounts = <OtpAccount>[];
    for (final field in entries) {
      if (field.number != 1 || field.wireType != _wireLengthDelimited) {
        continue; // version/batch_size/batch_index/batch_id, or unknown.
      }
      final account = _parseOtpParameters(field.bytes!, newId());
      if (account == null) return null; // Fail closed: one bad entry, no import.
      accounts.add(account);
    }
    return accounts;
  }

  static OtpAccount? _parseOtpParameters(Uint8List bytes, String id) {
    final fields = _readFields(bytes);
    if (fields == null) return null;

    Uint8List? secret;
    var name = '';
    var issuer = '';
    var algorithm = 0;
    var digits = 0;
    var type = 0;
    var counter = 0;

    for (final field in fields) {
      switch (field.number) {
        case 1:
          if (field.wireType == _wireLengthDelimited) secret = field.bytes;
        case 2:
          if (field.wireType == _wireLengthDelimited) {
            name = _decodeUtf8(field.bytes!) ?? '';
          }
        case 3:
          if (field.wireType == _wireLengthDelimited) {
            issuer = _decodeUtf8(field.bytes!) ?? '';
          }
        case 4:
          if (field.wireType == _wireVarint) algorithm = field.varint!;
        case 5:
          if (field.wireType == _wireVarint) digits = field.varint!;
        case 6:
          if (field.wireType == _wireVarint) type = field.varint!;
        case 7:
          if (field.wireType == _wireVarint) counter = field.varint!;
        default:
        // Unknown field (e.g. unique_id, or a future addition): skipped.
      }
    }

    if (secret == null || secret.isEmpty) return null;

    return OtpAccount(
      id: id,
      issuer: issuer,
      accountName: name,
      secret: base32.encode(secret).replaceAll('=', ''),
      type: type == 1 ? OtpType.hotp : OtpType.totp,
      digits: digits == 2 ? 8 : 6,
      algorithm: switch (algorithm) {
        2 => OtpAlgorithm.sha256,
        3 => OtpAlgorithm.sha512,
        _ => OtpAlgorithm.sha1, // Covers SHA1, unspecified, and MD5 (field
        // exists in the schema but this app has no MD5 generator; a labelled
        // fallback beats a silently wrong algorithm).
      },
      counter: counter,
      // period is left at the OtpAccount default (30s): the migration
      // payload carries no period field, and Google Authenticator has never
      // issued anything else.
    );
  }

  static String? _decodeUtf8(Uint8List bytes) {
    try {
      return utf8.decode(bytes);
    } on FormatException {
      return null;
    }
  }

  static const int _wireVarint = 0;
  static const int _wireLengthDelimited = 2;

  /// Splits a protobuf message into its top-level fields.
  ///
  /// Returns null on any malformed input — a truncated buffer, a varint that
  /// never terminates, a length-delimited field whose declared length runs
  /// past the end, or a wire type this schema does not use. Failing the whole
  /// message rather than returning what was parsed so far keeps a corrupted
  /// or truncated payload from producing a plausible-looking partial account.
  static List<_Field>? _readFields(Uint8List bytes) {
    final fields = <_Field>[];
    var offset = 0;

    while (offset < bytes.length) {
      final tag = _readVarint(bytes, offset);
      if (tag == null) return null;
      offset = tag.nextOffset;

      final fieldNumber = tag.value >> 3;
      final wireType = tag.value & 0x7;

      switch (wireType) {
        case _wireVarint:
          final value = _readVarint(bytes, offset);
          if (value == null) return null;
          offset = value.nextOffset;
          fields.add(_Field(fieldNumber, wireType, varint: value.value));
        case _wireLengthDelimited:
          final length = _readVarint(bytes, offset);
          if (length == null) return null;
          offset = length.nextOffset;
          final end = offset + length.value;
          if (length.value < 0 || end > bytes.length) return null;
          fields.add(
            _Field(fieldNumber, wireType, bytes: bytes.sublist(offset, end)),
          );
          offset = end;
        case 1: // fixed64 — unused by this schema, but skip correctly.
          if (offset + 8 > bytes.length) return null;
          offset += 8;
        case 5: // fixed32 — unused by this schema, but skip correctly.
          if (offset + 4 > bytes.length) return null;
          offset += 4;
        default:
          return null; // Unknown/reserved wire type: cannot be skipped safely.
      }
    }
    return fields;
  }

  /// Reads one LEB128 varint starting at [offset]. Returns null if the
  /// buffer ends before a terminating byte (high bit clear) is found.
  static _Varint? _readVarint(Uint8List bytes, int offset) {
    var result = 0;
    var shift = 0;
    var i = offset;

    while (true) {
      if (i >= bytes.length) return null;
      final byte = bytes[i];
      result |= (byte & 0x7f) << shift;
      i++;
      if (byte & 0x80 == 0) break;
      shift += 7;
      if (shift > 63) return null; // Guards against a pathological input.
    }
    return _Varint(result, i);
  }
}

class _Field {
  final int number;
  final int wireType;
  final int? varint;
  final Uint8List? bytes;

  const _Field(this.number, this.wireType, {this.varint, this.bytes});
}

class _Varint {
  final int value;
  final int nextOffset;

  const _Varint(this.value, this.nextOffset);
}
