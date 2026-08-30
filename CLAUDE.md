# CLAUDE.md

Guidance for Claude Code (and any AI assistant reading `AGENTS.md`-style context) working in this
repository. Read this before making architecture-level changes.

## What this project is

**Dula Authenticator** — an open-source, cross-platform (Windows / Linux / macOS / Android / iOS /
Web) OTP authenticator built with Flutter, created by **Amanuel Feyissa Kussa** and licensed under
Apache-2.0. It began as an internal tool for one organization and is being modernized (see
`docs/adr/`) into a general-purpose authenticator usable by **anyone**, with four explicit target
use cases that every design decision must accommodate:

1. Any company, not one specific organization's branding/identity/directory (ADR-0002, ADR-0003).
2. Fully air-gapped networks — no runtime telemetry, ever; documented offline build path
   (ADR-0007).
3. Offices that ban personal phones / restrict cameras — every platform must have a working
   camera-free enrollment path (ADR-0006).
4. Linux systems, including headless/kiosk deployments, not just Windows/mobile (ADR-0004,
   ADR-0008).

**If a change would conflict with any of the four use cases above, stop and write an ADR (see
below) before proceeding — do not silently narrow scope back to a single-company assumption.**

## Architecture

- **State management**: Riverpod (`flutter_riverpod` + `hooks_riverpod`). Providers live beside
  their feature (`lib/features/<feature>/providers/`) or in `lib/core/` for cross-cutting state.
- **Feature-folder layout**: `lib/features/<feature>/{screens,providers,repositories,widgets}/`.
  Shared, non-feature-specific code lives in `lib/core/{models,repositories,services,widgets}/`.
- **Security-sensitive core** (extra scrutiny required — see the `security-review-mfa` skill):
  - `lib/core/totp_engine.dart` — RFC 6238/4226 code generation.
  - `lib/core/services/security_service.dart` — PIN hashing, AES-256-CBC key derivation/encryption.
  - `lib/core/repositories/account_repository.dart`, `lib/features/auth/**` — secret storage, PIN
    policy/lockout, biometrics.
- **No backend, no network.** Everything runs locally on-device. Since directory authentication
  was removed (ADR-0014), the app makes **no outbound network calls at all**. This is a deliberate,
  enforced constraint (ADR-0007), not an accident — see "Zero telemetry" below.

## The ADR practice

Every architecture-level decision in this project is recorded in `docs/adr/` as a numbered
Architecture Decision Record. **Before making a change that touches architecture, a security
boundary, or a cross-platform behavior difference, read the relevant existing ADRs first**, and
use the `adr-record` skill (`.claude/skills/adr-record/`) to draft a new one if the change
introduces a new decision or reverses an old one. This exists specifically because the project's
original single-company, Windows-only design choices were never written down anywhere, which made
them invisible until an explicit code review surfaced them (see ADR-0009) — don't repeat that.

Current ADR index (see each file for full context/decision/consequences):

| ADR | Decision |
|---|---|
| [0001](docs/adr/0001-license-selection.md) | Apache License 2.0 |
| [0002](docs/adr/0002-white-label-branding.md) | Runtime branding config + build-time flavors; remove all hardcoded org identity |
| [0003](docs/adr/0003-pluggable-directory-auth.md) | ~~Pluggable directory auth~~ — **superseded by ADR-0014** |
| [0004](docs/adr/0004-secure-storage-linux-keyring.md) | Linux secure storage requires a real keyring daemon; fail loudly, never silently degrade |
| [0005](docs/adr/0005-device-integrity-scope.md) | Root/jailbreak + screenshot protection stay Android/iOS-only; documented, not silently assumed elsewhere |
| [0006](docs/adr/0006-no-camera-enrollment-parity.md) | Manual entry is the universal enrollment path; camera button gated by real platform support |
| [0007](docs/adr/0007-air-gapped-operability.md) | Zero telemetry by policy; documented offline build + SBOM + signed releases |
| [0008](docs/adr/0008-linux-packaging.md) | AppImage + .deb + .rpm; Flatpak deferred; Snap out of scope permanently |
| [0009](docs/adr/0009-ai-contribution-workflow.md) | This file + the ADR practice + the security-review skill |
| [0010](docs/adr/0010-vault-cryptography-modernization.md) | Argon2id + AES-256-GCM, versioned vault, auto-migrate on unlock |
| [0011](docs/adr/0011-authentication-and-unlock-model.md) | Biometric-first unlock; PIN **or** passphrase fallback chosen at registration |
| [0012](docs/adr/0012-pluggable-otp-types.md) | Pluggable OTP generators: TOTP, HOTP, Steam Guard; honor `otpauth://` parameters |
| [0013](docs/adr/0013-backup-export-and-import.md) | Local encrypted backup (passphrase-protected); import from Google Authenticator/Aegis/2FAS; no cloud sync |
| [0014](docs/adr/0014-remove-directory-authentication.md) | Enterprise directory auth removed entirely (supersedes 0003) |

## Attribution — hard constraint

This project was created by **Amanuel Feyissa Kussa**. Author attribution must be retained in
`LICENSE`, `NOTICE`, the About dialog (`developerName` in `assets/branding/branding.json`), and
platform copyright metadata. Deployers may add their own organization details alongside it, never
in place of it. See `docs/BRANDING.md`.

## Zero telemetry — hard constraint

No analytics, crash reporting, update-check pings, or any other outbound network call may be added
without its own ADR justifying the exception (ADR-0007). This is not a style preference — it is a
functional requirement for the air-gapped target use case, and adding one silently breaks the app's
guarantee for every existing air-gapped adopter.

## Platform capability — verify, don't assume

This project has already found real, documented gaps between "the package claims cross-platform
support" and actual behavior (`mobile_scanner` has no Windows/Linux camera support;
`root_checker_plus` and `screen_protector` are Android/iOS-only; `flutter_secure_storage` on Linux
depends on a keyring daemon that isn't guaranteed present). **Before writing a platform-conditional
code path, check the dependency's actual documented platform support** rather than assuming parity.
See ADR-0005 and ADR-0006 for the current state of this, and keep `docs/SECURITY_MODEL.md` (per
ADR-0005) in sync with any change.

## Before merging

Run the `security-review-mfa` skill (`.claude/skills/security-review-mfa/`) against any change
touching the security-sensitive files listed above. It is a checklist for a human reviewer to
apply, not a substitute for review.

## Building and testing

```bash
flutter pub get
flutter analyze
flutter test
flutter build windows --debug   # or: android, ios (macOS/Xcode only), web, linux
```

Platform notes: `ios` builds require macOS/Xcode and cannot be built or run on Windows or Linux.
`android` requires the Android SDK with cmdline-tools and accepted licenses. `linux` requires
`libsecret` (and a running keyring service — see ADR-0004) at runtime for secure storage to work.
