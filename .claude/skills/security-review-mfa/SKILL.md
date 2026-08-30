---
name: security-review-mfa
description: Use before merging any change that touches lib/core/services/, lib/core/directory_auth/, lib/features/auth/, or secure-storage/crypto code in this authenticator - runs a concrete checklist specific to this project's threat model.
---

# Security Review — MFA Authenticator

This project stores and generates authentication secrets (TOTP seeds, PIN hashes, derived AES
keys) and, per ADR-0003, optionally binds enterprise directory credentials over LDAP. Changes to
this code get materially less institutional-memory protection than they did as an internal bank
project, because contributors and reviewers will not all share the same context. Run this checklist
before approving or merging any change touching:

- `lib/core/services/security_service.dart` (PIN hashing, AES key derivation, encrypt/decrypt)
- `lib/core/services/ad_service.dart`, `lib/core/directory_auth/**` (directory-auth providers)
- `lib/core/repositories/account_repository.dart`, `lib/features/auth/**` (secret storage, PIN
  policy, lockout, biometrics)
- `pubspec.yaml` (any new dependency)

## Checklist

**Secrets and storage**
- [ ] No secret (PIN, derived key, TOTP seed, directory credential) is ever written to a log,
      `print()`, or crash-report payload — search the diff for `print(`, `debugPrint(`, and any new
      logging call near the touched code.
- [ ] Every value written via `flutter_secure_storage` continues to go through OS-native secure
      storage — no new `SharedPreferences`/plain-file writes of secret material (non-secret app
      settings, e.g. lockout counters, may legitimately use `SharedPreferences` as the existing code
      already does — the distinction is whether the value could authenticate a user or decrypt
      data).
- [ ] If the change touches Linux storage paths, it respects ADR-0004: no silent fallback to a
      weaker custom store when the OS keyring is unavailable — a failure must be surfaced, not
      swallowed.

**Cryptography**
- [ ] No hand-rolled crypto primitive is introduced where `package:crypto` or `package:encrypt`
      (already project dependencies) has an equivalent — flag any new crypto library dependency for
      its own ADR per the adr-record skill.
- [ ] Any IV/nonce is freshly random per encryption call (matching the existing
      `IV.fromSecureRandom(16)` pattern in `security_service.dart`) — never reused or derived
      deterministically.
- [ ] Key derivation continues to mix a per-installation random salt, not a fixed or
      easily-guessable value.

**Directory-auth / LDAP (ADR-0003)**
- [ ] Any user-supplied value embedded in an LDAP search filter is escaped per RFC 4515 (the LDAP
      equivalent of the existing `_escapePowerShell` pattern in `ad_service.dart`) — check for raw
      string interpolation into a filter string.
- [ ] LDAPS (TLS) stays the enforced default; a plaintext-LDAP code path must not become reachable
      without an explicit, documented opt-out that a deployer chooses knowingly.
- [ ] The directory-auth gate remains opt-in / off-by-default at the application level — a change
      must not make it silently mandatory for all deployments.

**Network and telemetry (ADR-0007)**
- [ ] No new outbound network call is added anywhere in the app other than a deployer-configured
      directory-auth connection. This includes analytics, crash reporting, update checks, and
      "phone home" telemetry of any kind — all are out of scope by project policy, not oversight.
  If a PR adds one, it needs its own ADR justifying the exception before it can be merged, per the
  adr-record skill.

**Platform-capability claims (ADR-0005, ADR-0006)**
- [ ] If the change touches a platform-conditional code path (`kIsWeb`, `defaultTargetPlatform`,
      `Platform.is*`), verify the claimed capability against the actual dependency's documented
      platform support (e.g. pub.dev's platform table) rather than assuming parity — this project
      has already found real gaps here (`mobile_scanner` on Windows/Linux, `root_checker_plus` and
      `screen_protector` on every non-mobile platform).
- [ ] `docs/SECURITY_MODEL.md`'s per-platform matrix is updated if the change adds, removes, or
      changes a platform-specific protection or capability.

## Output

State explicitly, for the change under review: which checklist items apply, which were verified,
and which (if any) need a human security reviewer's sign-off before merge — this skill is a
checklist for the reviewer to run, not a substitute for one.
