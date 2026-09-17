# Changelog

Notable changes to Dula Authenticator. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] — 2026-09-17

First public release. The app began as an internal, Windows-only tool for a
single organization and was rebuilt as a general-purpose authenticator; the
reasoning behind each decision is in [`docs/adr/`](docs/adr/).

### Codes

- TOTP (RFC 6238), HOTP (RFC 4226) and Steam Guard, with SHA-1/256/512.
- Digits and period are honoured from the `otpauth://` URI rather than forced
  to defaults ([ADR-0012](docs/adr/0012-pluggable-otp-types.md)).

### Security

- Vault sealed with AES-256-GCM under an Argon2id-derived key at OWASP cost,
  with a versioned record and a tested migration path
  ([ADR-0010](docs/adr/0010-vault-cryptography-modernization.md)).
- Unlock with a PIN **or** a passphrase, chosen at setup, with optional
  biometrics over the top and the credential always available as a fallback
  ([ADR-0011](docs/adr/0011-authentication-and-unlock-model.md)).
- Lockout with escalating backoff, counters held in secure storage so they
  cannot be cleared from outside the app.
- Screenshot blocking and root/jailbreak detection on mobile, documented as
  mobile-only rather than silently assumed everywhere
  ([ADR-0005](docs/adr/0005-device-integrity-scope.md)).
- **Zero telemetry.** No analytics, crash reporting or update checks; the app
  makes no outbound network call at all, enforced as project policy
  ([ADR-0007](docs/adr/0007-air-gapped-operability.md)).

### Getting accounts in and out

- Camera scan, clipboard image, drag-and-drop, or manual entry — each gated by
  what the platform's plugins actually support, so no button appears that
  cannot work ([ADR-0006](docs/adr/0006-no-camera-enrollment-parity.md)).
- Import from Google Authenticator, Aegis and 2FAS; encrypted local backup with
  its own passphrase, and no cloud sync by design
  ([ADR-0013](docs/adr/0013-backup-export-and-import.md)).
- Import parsers treat every field as hostile: malformed input is rejected
  rather than partially applied, and cannot overwrite an existing vault.

### Living with accounts

- Search, tags, favourites, drag-to-reorder and editing.
- A single corrupt account is isolated instead of failing the whole list
  ([ADR-0015](docs/adr/0015-account-management.md)).

### Deployment

- White-label: app name, logo, colours and organization details come from
  `assets/branding/branding.json` with no Dart changes
  ([ADR-0002](docs/adr/0002-white-label-branding.md)).
- Security policy — PIN length, passphrase rules, Argon2id cost, lockout
  backoff, auto-lock — is deployer-tunable in
  `assets/config/deployment_config.json`
  ([ADR-0016](docs/adr/0016-deployment-configuration.md)).
- Linux packages in three formats: AppImage for the copy-it-across-the-air-gap
  case, `.deb` and `.rpm` for managed fleets. Snap is permanently out of scope
  ([ADR-0008](docs/adr/0008-linux-packaging.md)).
- Releases carry a CycloneDX SBOM, SHA-256 checksums, and a keyless Sigstore
  signature; see [docs/RELEASING.md](docs/RELEASING.md) for verification,
  including offline.

### Fixed during hardening

- **Android biometrics never prompted.** `local_auth` needs a
  `FlutterFragmentActivity`; with a plain `FlutterActivity` every call threw and
  was silently mapped to "failed", so the prompt simply never appeared.
- **A scanned QR left the camera surface over the form.** The scanner now owns
  its own screen and returns the scanned value, instead of being swapped in
  mid-`build()`.
- **A missing Linux keyring froze the app** instead of showing the intended
  error. The cause was a *synchronous* libsecret call on the platform thread —
  the thread the Dart UI isolate runs on — so no timeout or background isolate
  could rescue it. Every Linux secure-storage call now passes a bounded D-Bus
  availability check first, and an unreachable store is reported as such rather
  than mistaken for a vault that does not exist yet
  ([ADR-0017](docs/adr/0017-linux-secure-storage-isolate-freeze.md),
  [ADR-0018](docs/adr/0018-linux-secret-service-gate.md)).
- **The Windows build failed on current toolchains.** `local_auth_windows`
  compiles with MSVC's deprecated `/await`, which MSVC 14.51 turned into a hard
  error.
- **The Linux `.rpm` installed and then crashed.** `libepoxy` dlopens the GL
  libraries, so no dependency generator could see them; found by installing on
  a minimal Fedora rather than on a machine that already had a GL stack.
- The home screen no longer tells desktop users to "scan a QR code" on
  platforms with no camera support.

### Platform status

Windows, Android, Web and Linux are built, run and covered by the automated
suites. iOS and macOS are scaffolded but untested — they need macOS and Xcode.

[1.0.0]: https://github.com/AmanuelFeyissa/dula-authenticator/releases/tag/v1.0.0
