---
name: security-review-mfa
description: Use before merging any change that touches lib/core/{crypto,vault,security,otp,backup}/ or lib/features/auth/ in this authenticator - runs a concrete checklist specific to this project's threat model.
---

# Security Review — MFA Authenticator

This project stores and generates authentication secrets (TOTP/HOTP seeds, credential verifiers,
derived vault keys). Changes here get materially less institutional-memory protection than they did
as a single-team project, because contributors and reviewers will not all share the same context.
Run this checklist before approving or merging any change touching:

- `lib/core/crypto/` — Argon2id derivation, AES-256-GCM sealing, the versioned vault record
- `lib/core/vault/` — vault lifecycle, re-keying, the `SecretStore` abstraction
- `lib/core/security/` — PIN/passphrase policy, credential kind, lockout, the Linux storage canary
- `lib/core/otp/` — RFC 6238/4226 generation and `otpauth://` parsing
- `lib/core/backup/` — encrypted export/import and the Google Authenticator / Aegis / 2FAS parsers,
  which consume **untrusted, attacker-controllable input** (a scanned code or an imported file)
- `lib/core/repositories/account_repository.dart`, `lib/features/auth/**` — secret storage,
  credential policy, biometrics
- `lib/core/config/deployment_config.dart` — deployer-tunable security policy; a change here alters
  runtime security behaviour for every deployment that sets it
- `pubspec.yaml` — any new dependency

## Checklist

**Secrets and storage**
- [ ] No secret (PIN, passphrase, derived key, OTP seed) is ever written to a log, `print()`,
      `debugPrint()`, or crash-report payload — search the diff for those calls near touched code.
- [ ] Every secret value still goes through `SecretStore` to OS-native secure storage. No new
      `SharedPreferences`/plain-file writes of secret material. Non-secret settings (lockout
      counters, auto-lock preference) may legitimately use `SharedPreferences`, as they already do —
      the test is whether the value could authenticate a user or decrypt data.
- [ ] Linux storage paths respect ADR-0004: no silent fallback to a weaker custom store when the OS
      keyring is unavailable. Failure must be surfaced, not swallowed. Note the open gap in
      ADR-0017 before adding new startup-path storage calls.

**Cryptography**
- [ ] No hand-rolled crypto primitive where `package:cryptography` (Argon2id, AES-GCM) already has
      an equivalent. Any new crypto dependency needs its own ADR per the `adr-record` skill.
- [ ] Every AES-GCM nonce is freshly random per seal, never reused or derived deterministically —
      nonce reuse under one key is catastrophic for GCM specifically.
- [ ] Key derivation keeps a per-vault random salt and stays at or above the Argon2id cost floor in
      `deployment_config.dart`; a config value must not be able to weaken it below the shipped
      default.
- [ ] The vault record stays versioned, and any format change keeps the migration path covered by
      tests (ADR-0010).

**Untrusted input (ADR-0013)**
- [ ] Import parsers treat every field as hostile: no unbounded allocation from a length field, no
      trusting a declared count, malformed input rejected with an error rather than a partial import.
- [ ] A malformed or hostile file/code cannot corrupt or partially overwrite an existing vault —
      import is never a silent overwrite.

**Network and telemetry (ADR-0007)**
- [ ] No outbound network call is added anywhere, for any reason. Analytics, crash reporting, update
      checks, and "phone home" telemetry are all out of scope by project policy, not oversight. The
      app currently makes none at all, and that is a guarantee air-gapped adopters depend on. Adding
      one requires its own ADR justifying the exception before merge.

**Platform-capability claims (ADR-0005, ADR-0006)**
- [ ] Any platform-conditional path (`kIsWeb`, `defaultTargetPlatform`, `Platform.is*`) is checked
      against the dependency's actual documented platform support rather than assumed parity. This
      project has repeatedly found real gaps here — `mobile_scanner` has no Windows/Linux camera,
      `root_checker_plus` and `screen_protector` are mobile-only, and `local_auth` needs a
      `FlutterFragmentActivity` on Android or it silently never prompts.
- [ ] `docs/SECURITY_MODEL.md`'s per-platform matrix is updated if the change adds, removes, or
      changes a platform-specific protection — and it must not claim a protection that does not
      actually fire.

## Output

State explicitly, for the change under review: which checklist items apply, which were verified, and
which (if any) need a human security reviewer's sign-off before merge. This skill is a checklist for
a reviewer to run, not a substitute for one.
