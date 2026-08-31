# ADR-0013: Encrypted Backup, Export, and Import

## Status
**Accepted — implemented.**

Delivered in `lib/core/backup/` (`backup_service.dart`, `backup_file_io.dart`,
`google_authenticator_migration.dart`, `aegis_import.dart`, `twofas_import.dart`,
`import_merge.dart`, `import_source_detector.dart`, `third_party_import_result.dart`)
and `lib/features/backup/screens/` (export, import, and import-review screens),
wired into Settings. 90 unit tests and 4 new end-to-end tests pass (252 unit /
25 end-to-end total for the app).

What shipped against the decision below:

1. **Local encrypted file, self-describing envelope** — done. The export file is
   `{v, app, kdf, salt, payload}`, reusing the vault's own Argon2id + AES-256-GCM
   primitives (ADR-0010). `v` and `app` let a future version recognise and refuse
   a file it does not understand, rather than guessing.
2. **Export passphrase independent of the unlock credential, never a PIN** —
   done. `BackupService.export` runs the export value through
   `PassphrasePolicy.validate` unconditionally, so a weak export passphrase is
   refused in code, not merely discouraged in the UI, satisfying this ADR's own
   Risks section.
3. **Import priority order** — done for three of the four: plain `otpauth://`
   URIs, Google Authenticator `otpauth-migration://` protobuf payloads, and this
   app's own encrypted export. Aegis and 2FAS import is **scoped to their
   unencrypted export** — see the deviation below.
4. **No plaintext export by default** — unchanged; this app never writes an
   unencrypted export at all, which is stricter than the ADR required.
5. **No cloud sync** — unchanged; nothing added here calls out to a network.
6. **Non-destructive merge with duplicate detection and review** — done via
   `ImportMerge` (duplicate = identical issuer + account name + secret,
   case/whitespace-insensitive) and `BackupImportReviewScreen`, which
   pre-selects new accounts and pre-deselects duplicates but commits only
   whatever the user leaves checked. Nothing is ever overwritten; a duplicate
   the user re-selects is added as an additional entry, never merged over the
   existing one.

Deviations, both deliberate and both driven by the same principle — an
unverified crypto implementation is worse than a documented gap:

- **Aegis and 2FAS import supports their unencrypted export only.** Both apps
  also offer a password-protected export (Aegis: scrypt-derived key wrapping,
  AES-256-GCM; 2FAS: PBKDF2-HMAC-SHA256, AES-GCM). Implementing either without
  a reference decoder or a real encrypted fixture to validate against — unlike
  the Steam Guard algorithm in ADR-0012, which was cross-checked against the
  reference `steam-totp` implementation — risks a subtly wrong decrypt of
  someone's OTP vault, which is a worse outcome than declining to support it.
  `AegisImport`/`TwoFasImport` recognise an encrypted file and tell the user to
  re-export without a password, rather than rejecting it as unrecognised or,
  worse, attempting an unverified decrypt.
- **The Google Authenticator migration decoder is hand-written**, not built on
  the `protobuf` package: the schema is two small, fixed messages, and this
  keeps the air-gap-friendly dependency footprint down (ADR-0007). Validated
  against a fixture built independently from the documented wire format — not
  derived from the decoder's own code — covering multi-entry batches, every
  enum value, and hostile input (truncated buffers, dangling varints, unknown
  fields).
- **No camera scanning for a migration QR code.** Add Account already owns
  camera scanning for single `otpauth://` credentials; teaching it to also
  recognise `otpauth-migration://` is left as a follow-up rather than a second
  scanner implementation in the import screen. Today, a migration payload must
  be pasted as text or supplied as a file.
- **File-based import cannot be end-to-end tested.** `file_picker`'s native OS
  dialog cannot be driven by an automated test without hanging the runner, so
  the pasted-code path is covered end-to-end and the file-based parsers
  (`BackupService`, `AegisImport`, `TwoFasImport`) are covered by unit tests
  against real-shaped fixtures instead.

## Context
The app currently has **no backup or export capability whatsoever**. Every TOTP secret lives in one
device's OS credential store and nowhere else. The practical consequence is severe and easy to
overlook: if the device is lost, wiped, reset, or the keyring is cleared, **every enrolled account
is permanently unrecoverable from this app** — and since those accounts are second factors for
other services, the user may be locked out of the very services the app was protecting. The
existing "Forgot PIN?" flow makes this explicit ("will delete ALL your registered accounts"), which
is honest, but it means the only recovery path is re-enrolling every account by hand at each
service.

This is the single largest functional gap in the application.

Research into the landscape:
- **Aegis** stores its vault AES-256-GCM-encrypted and offers export to encrypted or plaintext
  JSON, with encryption explicitly disable-able for cross-app migration.
- **Ente Auth** offers the broadest import support — 2FAS, Aegis, andOTP, Bitwarden, Google
  Authenticator, LastPass, Proton, Raivo — which is effectively the interoperability bar in this
  space.
- **Google Authenticator** exports via a proprietary `otpauth-migration://` URI whose `data`
  parameter is a **base64-encoded protobuf** (`MigrationPayload` containing repeated
  `OtpParameters` with secret, name, issuer, algorithm, digits, type, counter). The format is
  publicly documented and multiple open-source decoders exist, making it the highest-value import
  path since Google Authenticator has the largest installed base.

## Decision
**Local encrypted file backup only. No cloud sync.**

1. **Export produces a single encrypted file** using the same AES-256-GCM + Argon2id envelope as
   the vault (ADR-0010), with a self-describing header so a future version can read an older
   export. The user chooses where it goes; the app never transmits it anywhere.
2. **Export requires a passphrase, never a PIN.** Per ADR-0010 §6, once the file leaves the device
   the attacker holds it offline, and none of the on-device mitigations (secure storage, lockout,
   OS protection) apply. A 6-digit PIN's 10^6 keyspace is not adequate protection for an offline
   file regardless of KDF cost. The export passphrase is **independent of the unlock credential**,
   so a user with a PIN-based unlock can still produce a properly protected backup.
3. **Import supports**, in priority order:
   - Plain `otpauth://` URIs (universal, via QR or paste)
   - **Google Authenticator `otpauth-migration://`** protobuf payloads (largest installed base)
   - This app's own encrypted export
   - **Aegis** and **2FAS** JSON exports (the two most common open-source sources)
4. **No plaintext export ships by default.** Aegis offers one, and it is genuinely useful for
   migrating *away* from the app — but writing every OTP secret unencrypted to disk is a serious
   footgun, and the user chose encrypted-only. If added later it must be behind an explicit,
   clearly-worded confirmation that names the risk, and it needs its own ADR.
5. **Cloud sync is explicitly out of scope, permanently, for this project.** It would require a
   backend service, breaking the app's no-backend design, its zero-telemetry guarantee (ADR-0007),
   and its air-gapped usability. Users who want cross-device sync can copy an encrypted export
   themselves through whatever channel their organization permits.
6. **Import must be non-destructive**: importing merges into the existing vault, with duplicate
   detection (same issuer + account + secret) and an explicit review step before committing —
   never a silent overwrite of existing accounts.

## Consequences
**Positive:** Closes the app's most serious functional gap. Users can survive device loss. The
encrypted-only default keeps the security posture consistent with the rest of the app. Import
support means adopting this app doesn't require re-enrolling every account by hand, which is
otherwise the main practical barrier to switching authenticators.

**Negative:** Adds parsing code for third-party formats (including a protobuf decoder for the
Google Authenticator payload) — each is a maintenance commitment and a potential source of parsing
bugs against untrusted input. Requires file-picker integration across six platforms with differing
file-access models (notably Web and Android scoped storage).

**Risks:** **All import parsers consume untrusted, attacker-controllable input** — a malicious QR
code or export file is a realistic attack vector. Every parser must be fuzz-tested and must fail
closed on malformed input rather than partially importing. Export is the one operation that
deliberately moves secrets outside the app's protection, so the passphrase-strength requirement
must be enforced in code, not merely suggested in the UI.

## Alternatives Considered
- **Cloud/E2EE sync (Ente model)** — genuinely the best user experience, and rejected only because
  it is incompatible with this project's no-backend, zero-telemetry, air-gap-capable design. That
  is a deliberate product trade-off, not an oversight.
- **Plaintext export alongside encrypted** — deferred per §4; convenience does not justify writing
  unencrypted OTP secrets to disk by default in a security tool.
- **No backup at all (status quo)** — rejected: permanent, unrecoverable data loss on device
  failure is not an acceptable design for an authenticator.

## References
- [Aegis vault format documentation](https://github.com/beemdevelopment/Aegis/blob/master/docs/vault.md)
- [Google Authenticator export format (otpauth-migration protobuf)](https://zwyx.dev/blog/google-authenticator-export-format)
- [otpauth — Google Authenticator migration decoder](https://github.com/dim13/otpauth)
- [Migrating from other providers — Ente Auth](https://ente.com/help/auth/migration/import)
- [Which imports are supported in the 2FAS app](https://2fas.com/support/2fas-auth-mobile-app/which-imports-are-supported-in-the-2fas-app/)
- Direct review of `lib/core/repositories/account_repository.dart`,
  `lib/features/auth/screens/app_lock_screen.dart` (reset flow) (this session).
