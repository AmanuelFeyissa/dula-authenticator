import 'package:dula_auth/core/models/otp_account.dart';

/// Outcome of parsing a third-party export file (Aegis, 2FAS).
///
/// Callers: `lib/core/backup/aegis_import.dart`, `lib/core/backup/
/// twofas_import.dart`, and the import screen that renders the outcome. No
/// data schema — a transient parse result, nothing persisted here.
///
/// A plain nullable return cannot distinguish "this is not a file we
/// recognise" from "this is a password-protected export we do not decrypt" —
/// and those need different messages: the first says "wrong file", the
/// second says "re-export without a password." See
/// docs/adr/0013-backup-export-and-import.md.
sealed class ThirdPartyImportResult {
  const ThirdPartyImportResult();
}

class ThirdPartyImportSuccess extends ThirdPartyImportResult {
  final List<OtpAccount> accounts;
  const ThirdPartyImportSuccess(this.accounts);
}

/// The file is a recognised export, but its contents are encrypted with a
/// password this app does not attempt to decrypt (see ADR-0013 for why).
class ThirdPartyImportRequiresPassword extends ThirdPartyImportResult {
  const ThirdPartyImportRequiresPassword();
}

/// The file is not a recognisable export of this format at all.
class ThirdPartyImportUnrecognized extends ThirdPartyImportResult {
  const ThirdPartyImportUnrecognized();
}
