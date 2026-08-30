# DulaAuth

An open-source, cross-platform (Windows, Linux, macOS, Android, iOS, Web) Time-based One-Time
Password (TOTP) authenticator, built with Flutter.

DulaAuth started as an internal authenticator for a bank's Windows desktop fleet and has been
migrated into a generic project any organization can adopt. See `CLAUDE.md` and `docs/adr/` for
the full history and reasoning behind every architectural decision made along the way.

## Who this is for

DulaAuth is designed around four target deployment scenarios, not just "a phone app":

- **Any organization** — no company name, logo, or internal system is hardcoded; see
  `docs/BRANDING.md` (coming in a later phase) for how to re-skin it for your own organization.
- **Air-gapped networks** — zero telemetry, ever, by policy (see `docs/adr/0007-air-gapped-operability.md`).
- **Offices that ban personal phones / restrict cameras** — every platform has a working
  camera-free enrollment path: manual secret entry, QR image import, and clipboard paste
  (see `docs/adr/0006-no-camera-enrollment-parity.md`).
- **Linux, not just Windows and mobile** — including headless/kiosk deployments
  (see `docs/adr/0004-secure-storage-linux-keyring.md` and `docs/adr/0008-linux-packaging.md`).

## Features

- **TOTP code generation** — RFC 6238 compliant, SHA-1 / SHA-256 / SHA-512.
- **Secure storage** — TOTP secrets encrypted with AES-256-CBC (random IV per value) and stored via
  each OS's native secure credential store (Windows Credential Manager, Android Keystore,
  iOS/macOS Keychain, Linux libsecret/keyring — see `docs/adr/0004-secure-storage-linux-keyring.md`
  for the Linux keyring dependency this implies).
- **PIN protection** — 6-digit app PIN, SHA-256 hashed with a per-installation salt, brute-force
  lockout, 90-day rotation policy, and a blocklist of common/sequential/repeating PINs.
- **Biometric unlock** — optional, where the platform supports it.
- **Optional enterprise directory authorization** — pluggable LDAP/Active Directory group-membership
  gate before adding a new account, off by default (see `docs/adr/0003-pluggable-directory-auth.md`).
- **QR code enrollment** — camera scan (where supported), drag-and-drop image, clipboard paste, and
  manual secret entry (always available, on every platform).
- **Privacy overlay** — screen blur when the app loses focus; OS-level screenshot prevention and
  root/jailbreak detection on Android/iOS (see `docs/adr/0005-device-integrity-scope.md` for exactly
  what is and isn't covered on each platform).

## Platform support

| Platform | Status |
|---|---|
| Windows | Fully supported |
| Web | Fully supported |
| Android | Fully supported |
| Linux | Supported — requires a running secret-service keyring (`gnome-keyring`/`kwallet`); see ADR-0004 |
| iOS | Supported — build requires macOS + Xcode (not buildable from Windows or Linux) |

## Building

```powershell
flutter pub get
flutter analyze
flutter test

flutter build windows --debug
flutter build android --debug
flutter build web
flutter build linux            # requires libsecret-dev at build time
flutter build ios              # macOS + Xcode only
```

See `CLAUDE.md` for architecture, security-sensitive areas of the codebase, and the project's ADR
practice before making changes.

## License

Apache License 2.0 — see `LICENSE` and `NOTICE`. See `docs/adr/0001-license-selection.md` for why.

## Origin

This project originated as an internal authenticator developed by the Information Security /
Identity and Access Management team at a bank, and was open-sourced with that organization's
approval. See `NOTICE` for attribution.
