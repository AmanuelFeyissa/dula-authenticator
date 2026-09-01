# ADR-0004: Cross-Platform Secure Storage & the Linux Keyring Dependency

## Status
Accepted — implemented (Phase 7)

## Context
The app already uses `flutter_secure_storage` for the PIN hash, salt, cached master key, and
encrypted TOTP secrets. This package is already cross-platform in principle (Windows Credential
Manager, Android Keystore, iOS/macOS Keychain, and — relevant to this migration — Linux via
`libsecret`, plus a web implementation backed by WebCrypto/IndexedDB already in use).

Research into the Linux backend surfaces a deployment-relevant constraint the Windows-only version
never had to consider: `flutter_secure_storage` on Linux depends on **`libsecret`** (both the
runtime library and a running keyring *service* — GNOME Keyring or KDE's KWallet) being present
and unlocked. This is normally true on a standard GNOME/KDE desktop session, but is **not
guaranteed** on:
- Minimal/headless Linux installs (common on kiosks and hardened air-gapped workstations, which are
  explicitly a target use case for this project).
- Some window-manager-only setups (i3, sway, etc.) without a keyring daemon auto-started.
- Fresh sessions before the keyring has been unlocked (a real, previously-reported failure mode:
  "Failed to unlock the keyring" in `flutter_secure_storage` issue trackers).

If secure storage silently fails to read/write on such a system, the practical effect is severe for
this specific app: a user could be locked out of their own PIN/TOTP secrets, or — worse — a failed
write could be swallowed by the existing broad `catch (_)` blocks in `AccountRepository` and
`AuthRepository`, giving a false impression that data was saved. This is exactly the kind of
silent-failure risk that matters most for a security tool aimed at hardened/air-gapped
environments, where "it looked like it worked" is not an acceptable failure mode.

## Decision
1. Keep `flutter_secure_storage` (libsecret-backed) as the default Linux storage backend — it is
   the correct choice for any Linux desktop with a functioning keyring, and matches the trust model
   already used on every other platform (OS-native credential store, not a custom encrypted file).
2. Add an explicit **startup capability check** on Linux: attempt a canary read/write to secure
   storage during app init; if it fails, show a blocking, explicit error screen ("This system has
   no accessible secure credential store — install/enable `gnome-keyring` or `kwallet`, or contact
   your IT administrator") rather than silently continuing into a state where writes may be lost.
   This replaces today's broad `catch (_) { return false / return []; }` pattern for this specific
   startup check only — normal runtime error handling elsewhere is unaffected by this ADR.
3. Document the `libsecret` + keyring-daemon runtime dependency prominently in the Linux
   installation docs (Phase 3/6 of the migration plan) and in the AppImage/.deb/.rpm package
   metadata as a required or recommended dependency, so IT teams provisioning hardened/kiosk Linux
   images know to include a keyring service before deployment — this is a documentation and
   packaging fix, not a code workaround, because silently working around a missing OS-level secret
   store would undermine the security guarantee the app is trying to provide.
4. Do **not** add a fallback to a custom encrypted-file store when no keyring is present. A
   home-grown fallback would be weaker than the OS-native store (the whole reason
   `flutter_secure_storage` is used instead of writing raw encrypted files) and would create two
   silently different security postures depending on what happened to be installed — worse for a
   security-focused open-source project than requiring the dependency and failing loudly when it's
   missing.

## Consequences
**Positive:** No silent data loss on Linux; the app's actual security guarantees stay consistent
with what's advertised (OS-native secret storage everywhere) instead of quietly degrading on some
Linux configurations. IT teams get a clear, actionable checklist item during provisioning.

**Negative:** Some minimal/headless Linux deployments will need one extra package installed
(`gnome-keyring` or equivalent) before the app is usable — an explicit requirement, not a
silent gap.

**Risks:** The canary-check UX needs real testing against at least one keyring-less Linux
environment (e.g. a minimal Debian netinstall without a desktop environment) before this ships,
tracked as a Phase 3 validation task. Update (Phase 7): this validation was performed and found a
real gap in the canary's failure handling — see ADR-0017.

## Alternatives Considered
- **Custom AES-encrypted file fallback when no keyring is detected** — rejected per point 4 above:
  weakens the security model inconsistently across environments, which is worse than a clear
  hard-fail for a project whose entire value proposition is credential security.
- **Silently ignore the risk (status quo)** — rejected: unacceptable for a security tool
  specifically targeting air-gapped/hardened environments where this failure mode is most likely.

## References
- [flutter_secure_storage — pub.dev](https://pub.dev/packages/flutter_secure_storage)
- [flutter_secure_storage GitHub — Linux libsecret/keyring requirements](https://github.com/juliansteenbakker/flutter_secure_storage)
- ["Failed to unlock the keyring" — flutter_secure_storage issue #778](https://github.com/juliansteenbakker/flutter_secure_storage/issues/778)
- Direct review of `lib/core/repositories/account_repository.dart`,
  `lib/features/auth/repositories/auth_repository.dart` (existing broad `catch` behavior).

## Implementation
`lib/core/security/secure_storage_canary.dart` adds `SecureStorageCanary.check(SecretStore)` — a
write/read-back/delete round trip, returning `false` on any exception or mismatch — plus
`secureStorageCanaryAppliesOn(TargetPlatform)`, scoped to Linux only per Decision item 2 (every
other platform's store does not depend on an optional daemon the way libsecret does, so the extra
startup latency isn't justified elsewhere). `lib/core/widgets/app_lifecycle_wrapper.dart` runs the
check in `initState` on Linux and, on failure, blocks with an explicit full-screen error naming
`gnome-keyring`/`kwallet` and offering Retry or Close — taking precedence over the normal
setup/lock/unlocked flow, mirroring the existing device-compromise gate. `secureStoreProvider`
(`Provider<SecretStore>`) makes the store injectable so this is testable without a real platform
channel: `test/core/security/secure_storage_canary_test.dart` covers the round trip against
`InMemorySecretStore` and failure doubles; `test/core/widgets/app_lifecycle_wrapper_test.dart`
covers the blocking screen end-to-end with `debugDefaultTargetPlatformOverride` and an
in-memory-backed `AuthRepository`, avoiding any real secure-storage or biometrics plugin channel.
Empirical validation against a real keyring-less Linux install (the Risk flagged above) was
performed in Phase 7 (Docker + Xvfb + `dbus-launch`, with and without `gnome-keyring-daemon`
running). It confirmed the round trip and the blocking screen both work correctly when the
underlying platform call actually completes, and found `check()` had no timeout for the case where
it doesn't — fixed with a bounded `.timeout()` (`_HangingSecretStore` test). Testing also found that
fix is necessary but not sufficient: a real no-keyring `flutter_secure_storage_linux` call can
freeze the whole Dart isolate rather than returning or throwing, which no Dart-level timeout can
recover from. See ADR-0017 for the full finding and the decision to defer the isolate-based fix that
would fully close it.
