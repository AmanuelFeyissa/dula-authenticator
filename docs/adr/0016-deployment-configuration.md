# ADR-0016: Centralized Deployment Configuration for Security Policy, UI Tunables, and Backup Naming

## Status
**Accepted — implemented.**

Delivered as `lib/core/config/deployment_config.dart` (`DeploymentConfig`, `LockoutStep`,
`deploymentConfigProvider`) reading `assets/config/deployment_config.json`, loaded in `main()`
alongside `BrandingConfig` and pushed into five call sites via mutable `configure*` statics:
`PinPolicy.configure`, `PassphrasePolicy.configure`, `KdfParams.configureDefault`, the new
`lib/core/security/lockout_policy.dart` (`LockoutPolicy.configure`, replacing the inline lockout
if/else chain in `AuthNotifier`), and `AppSettings.configureDefaults` (which required dropping
`AppSettings`'s `const` constructor — every `const AppSettings()` call site across the settings
provider and its tests was updated). UI-layer values with an existing `WidgetRef` read
`deploymentConfigProvider` directly: the rotation-period dropdown (`settings_screen.dart`), the
backup file name prefix (`backup_export_screen.dart`, deriving a slug from `branding.appName` when
unconfigured), and the "copied to clipboard" snackbar duration (`home_screen.dart`).

Everything in the Decision section below shipped as designed, with one refinement: `PinPolicy`
originally only planned to skip the *common-PIN blocklist* at a non-default `pinLength`, but two of
the sequential/repeating-pattern helpers (`_hasMixedSequentialRepeating`, `_hasRepeatingGroup`)
slice the input into fixed-size pairs assuming exactly 6 characters and would throw a `RangeError`
at any other length — caught by a new test before it could ship as a crash. All 6-digit-specific
checks (blocklist and every pattern heuristic) are now skipped together whenever `pinLength != 6`;
length, digits-only, and same-digit-repeated checks still apply at any length. `docs/CONFIGURATION.md`
documents this trade-off explicitly.

The two About-dialog bugs found during the same audit were fixed alongside this: both
`home_screen.dart` and `settings_screen.dart` had their own independent `'Version 1.0.0'` literal
(the audit found the second one after the first draft of this record); both now read a single
`packageInfoProvider` (`lib/core/app_version.dart`, loaded once in `main()` from
`PackageInfo.fromPlatform()`, the same load-once-inject-via-provider pattern as branding and
deployment config) instead of duplicating the fetch or the literal. The dialog title also dropped
the hardcoded `' Authenticator'` suffix that duplicated the word for any deployer following
`docs/BRANDING.md`'s own `appName` example.

A second refinement, found during a `security-review-mfa` pass on the finished change rather than
planned upfront: `DeploymentConfig.parse` originally only type-checked each field, with no floor —
a deployer's typo (`argon2MemoryKiB: 194` instead of `19456`) would have silently shipped a weaker
KDF than the app's own default with no warning. `DeploymentConfig.parse` now rejects `pinLength`
below 4, `passphraseMinLength` below 8 (the NIST SP 800-63B floor), and any `argon2*` field below
the OWASP minimum, falling back to the default the same way an unreadable field already does.

A third refinement, also found during the `security-review-mfa` pass: two UI copy strings still
hardcoded "6" independently of `PinPolicy.pinLength` after the initial implementation —
`credential_setup_screen.dart`'s "Create 6-Digit PIN" heading, and `CredentialKind.pin`'s `label`
field (`'6-digit PIN'`, shown across `change_credential_screen.dart` and
`credential_setup_screen.dart`). Both now read `PinPolicy.pinLength`; `CredentialKind.label` moved
from a stored `const` enum field to a computed getter to allow this (enum constructor arguments
must be compile-time constants). `CredentialKind.passphrase`'s explanation text ("Harder to guess
than six digits") was also reworded to stop assuming the PIN is six digits.

A fourth: `DeploymentConfig`'s own `_parseLockoutSteps` treated an empty `lockoutSteps: []` in
`deployment_config.json` as malformed and fell back to the default steps — silently ignoring a
deployer's deliberate choice to disable lockout entirely, which is exactly the configuration
`LockoutPolicy.configure([])` was built to support. Fixed to accept an explicit empty list as
"lockout disabled," while a genuinely malformed entry (e.g. missing `attempts` or `seconds`) still
falls back.

A new `docs/CONFIGURATION.md` documents every field including these floors, mirroring
`docs/BRANDING.md`'s structure, and `docs/SECURITY_MODEL.md`'s Cryptography and "Defended against"
tables were updated to note the new configurability and to correct a stale reference to
`VaultDecryptionException` (removed in ADR-0015, before this ADR). 301 unit tests pass (up from 268
at the end of ADR-0015; +33 for this ADR — `DeploymentConfig` including its safety-floor and
lockout-disable tests, `LockoutPolicy`, and the `configure()` paths on
`PinPolicy`/`PassphrasePolicy`/`KdfParams`/`AppSettings`), `flutter analyze` is clean, and the
existing end-to-end suite was re-verified
against the new `deploymentConfigProvider` override required in
`integration_test/app_flow_test.dart`'s `pumpApp` harness.

## Context
ADR-0002 already made visual/organizational identity (`appName`, logo, seed color, org name,
developer name, directory label) runtime-configurable via `assets/branding/branding.json` — a
deployer forking this project to ship as their own product edits one JSON file and rebuilds, no
Dart knowledge required. Everything else a deployer might reasonably want to change is still a
literal scattered across `lib/`.

A direct audit of `lib/core/` and `lib/features/` (this session) found roughly thirty such literals
and sorted them into two groups:

**True constants — correctly left fixed, not addressed by this ADR:** RFC-mandated OTP defaults
(`digits=6`, `period=30`, SHA-1 default per ADR-0012), `otpauth://` URI parsing clamps (input
sanitization against a hostile QR code, not a policy choice), the Steam Guard alphabet/length
(dictated by Steam's own format), internal secure-storage/SharedPreferences key names (opaque,
already namespaced per-app by the OS per ADR-0004), the backup envelope's format marker and version
(`appIdentifier`/`formatVersion` in `backup_service.dart` — a file-format compatibility marker, not
branding), the vault format version (`VaultMeta.currentVersion`), and the Apache-2.0 license string
(a legal requirement of the fork model itself per `docs/BRANDING.md`, not a stylistic choice).

**Product/policy hardcodes — the subject of this ADR:**
1. `PinPolicy.pinLength` (`lib/core/security/pin_policy.dart:8`) — fixed at 6.
2. `PassphrasePolicy.minLength/recommendedLength/maxLength`
   (`lib/core/security/passphrase_policy.dart:26,30,34`) — fixed at 12/15/256.
3. Argon2id tuning (`KdfParams.owaspDefault` in `lib/core/crypto/vault_crypto.dart:25-26`) — fixed
   at the OWASP minimum (19456 KiB, 2 iterations, parallelism 1). The *algorithm* (Argon2id) stays
   fixed per ADR-0010 — only the cost parameters are in scope here.
4. Failed-unlock lockout thresholds/durations, inlined as an if/else chain in
   `lib/features/auth/providers/auth_provider.dart:216-222` (3 attempts → 30s, 5 → 5min, 10 → 1hr).
5. `AppSettings.defaultAutoLock/defaultRotationDays/minRotationDays/maxRotationDays`
   (`lib/core/settings/app_settings.dart:52-55`) and the rotation-period dropdown's fixed option
   list `[30, 60, 90, 180, 365]` (`lib/features/settings/screens/settings_screen.dart:224`).
6. The backup export file name prefix `dula-auth-backup-` (`backup_export_screen.dart:76`) — brand
   name baked into an exported file name independent of `branding.json`'s `appName`.
7. The "copied to clipboard" snackbar duration (`home_screen.dart:489`), currently 1 second network-
   wide with no override.

Two related bugs surfaced during the same review, unrelated to configurability but fixed alongside
it since they were found in the same files:
- The About dialog hardcodes `'Version 1.0.0'` independently in two places
  (`home_screen.dart:274`, `settings_screen.dart:148`), disconnected from `pubspec.yaml`'s real
  `version:` — a deployer who bumps their own release version sees a stale number forever.
- The About dialog title concatenates `'${branding.appName} Authenticator'`
  (`home_screen.dart:270`), which duplicates the word "Authenticator" for any deployer who follows
  `docs/BRANDING.md`'s own example (`appName: "Acme Authenticator"`), producing "Acme Authenticator
  Authenticator".

## Decision

1. **A second runtime config file, `assets/config/deployment_config.json`, loaded the same way as
   `branding.json`** — `DeploymentConfig.load()` in `lib/core/config/deployment_config.dart` reads
   the asset, falls back to a `DeploymentConfig.fallback` constant matching every value's current
   hardcoded default on any parse error (same fail-safe pattern as `BrandingConfig`, so a typo in
   the file can never brick the app), and is loaded in `main()` before `runApp` alongside branding.
   Kept as a **separate file from `branding.json`**, not merged into it: branding is visual/identity
   and is meant to be trivially editable by a non-technical deployer with no security implications;
   this file changes security policy (lockout, PIN length, KDF cost) and should read as a distinct,
   more consequential kind of edit — accidentally weakening lockout while just trying to change a
   logo is exactly the failure mode of merging the two.

2. **Constructors that used the affected values as compile-time-`const` default parameters are
   restructured to accept them as runtime overrides instead.** Concretely:
   - `AppSettings`'s constructor stops being `const` and stops using `defaultAutoLock`/
     `defaultRotationDays` as literal default-parameter values; those become mutable static fields
     read via `??` in the initializer list, settable once at startup via
     `AppSettings.configureDefaults(...)`. Every `const AppSettings()` call site (the settings
     provider and its tests) becomes `AppSettings()`.
   - `KdfParams` gains a mutable `KdfParams.deploymentDefault` static (initialized to
     `owaspDefault`, the fixed OWASP floor, and overridable via `KdfParams.configureDefault(...)`).
     `VaultService`'s and `BackupService.export`'s `KdfParams params = KdfParams.owaspDefault`
     default-parameter values become nullable (`KdfParams? params`) with
     `params ?? KdfParams.deploymentDefault` resolved in the constructor/method body, since a
     mutable static cannot be a default-parameter *literal*.
   - `PinPolicy.pinLength` and `PassphrasePolicy.minLength/recommendedLength/maxLength` become
     mutable `static int` fields (not `const`) with a `configure(...)` static method, rather than
     being threaded as constructor parameters — both classes are stateless static utilities called
     directly from many UI call sites (`PinPolicy.validate(pin)`, `PinDots(length:
     PinPolicy.pinLength)`) with no existing dependency-injection path; adding a mutable,
     once-at-startup-configured static preserves every existing call site unchanged while still
     making the value deployer-configurable. `PinPolicy` additionally skips its curated
     common-6-digit-PIN blocklist whenever `pinLength != 6`, since that blocklist is meaningless
     (and would silently mismatch) at any other length — documented in the field's doc comment as a
     real trade-off a deployer changing `pinLength` should know about.
   - The lockout if/else chain in `auth_provider.dart` moves into a new
     `lib/core/security/lockout_policy.dart` (`LockoutPolicy.steps`, mutable, and
     `LockoutPolicy.durationFor(int attempts)`), the same mutable-static-with-`configure()` pattern,
     giving it its own unit tests independent of the auth notifier's broader test setup.

3. **UI-layer values that already have a `WidgetRef`/`BuildContext` in scope read
   `deploymentConfigProvider` directly** rather than going through a static — the rotation-period
   dropdown options (`settings_screen.dart`), the backup file name prefix
   (`backup_export_screen.dart`, falling back to a slug of `branding.appName` when the config
   field is null), and the clipboard-copied snackbar duration (`home_screen.dart`). These have no
   `const`-default-parameter constraint and already sit inside Riverpod widgets, so there is no
   reason to route them through mutable global state too.

4. **The two About-dialog bugs are fixed as part of this change, not deferred:** the version string
   now reads from `package_info_plus` (`PackageInfo.fromPlatform().version`) instead of two
   independent literals, and the About dialog title drops the hardcoded `' Authenticator'` suffix,
   showing `branding.appName` alone (consistent with `docs/BRANDING.md`'s own example already
   including the word where a deployer wants it).

5. **Explicitly out of scope, deferred:**
   - Making the *set* of `AutoLockDelay` options itself configurable (e.g. letting a deployer remove
     "Never" as a choice, or add custom delays) — the enum's five fixed members are adequate for
     every use case surfaced so far, and turning it into a dynamic list is a materially larger
     change (the enum backs a `SharedPreferences`-persisted name, per its own doc comment) for
     unclear demand. Only the *default* moves.
   - The hardcoded dark-navy `0xFF1E1B4B` background color, present in six call sites independent
     of `branding.json`'s `primarySeedColorHex` — this is a visual-theming gap, not a policy one,
     and Phase 6 (UI/UX redesign, already planned per `CLAUDE.md`'s pending-work list, explicitly
     scoped to include "fixing the hardcoded purple background in `lib/main.dart`") is the right
     place for it rather than duplicating that work here.
   - Internal storage key names, the backup format marker/version, and the vault format
     version — these are compatibility-load-bearing infrastructure, not deployer policy; renaming
     them per-deployment would be pure churn with real correctness risk (cross-fork backup
     recognition, forward-compatible vault migration) for no user-visible benefit.

## Consequences
**Positive:** A deployer forking this project can now tune every genuine security/product policy
decision (PIN length, passphrase floor, Argon2id cost, lockout backoff, auto-lock/rotation
defaults, backup file naming) the same way they already rebrand — edit
`assets/config/deployment_config.json`, rebuild. Two latent About-dialog bugs (stale version,
duplicated "Authenticator") are fixed as a side effect of the same review.

**Negative:** `AppSettings` loses its `const` constructor, touching every call site that constructed
one as a compile-time constant (mechanical, but real diff surface). `PinPolicy`, `PassphrasePolicy`,
`KdfParams`, and the new `LockoutPolicy` now carry mutable static state configured once at startup —
a deliberate, scoped exception to this project's general preference for explicit dependency
injection over globals, justified by those classes' existing call-site shape (see Decision item 2).

**Risks:** Mutable static configuration state must be set exactly once, before any code reads it —
`main()` calls every `configure*` method immediately after `DeploymentConfig.load()` and before
`runApp`. Tests that rely on the default values must not leak configuration across test files;
each affected class gets a `resetForTesting()` (or equivalent) used in `tearDown`/`setUp` by any
test that calls `configure(...)`, and the existing test suite's use of the *unconfigured* defaults
(matching `DeploymentConfig.fallback`) continues to exercise today's exact values. A deployer who
sets `pinLength` away from 6 forfeits the curated common-PIN blocklist (see Decision item 2) —
called out explicitly in `docs/CONFIGURATION.md` so it is a known trade-off, not a silent
regression. This touches `lib/core/security/`, `lib/core/crypto/`, and
`lib/features/auth/providers/auth_provider.dart` — all flagged in `CLAUDE.md` as security-sensitive
core requiring extra scrutiny — so this ships with the existing test suite kept green throughout
plus new unit coverage for every new/changed unit (`DeploymentConfig`, `LockoutPolicy`, the
`configure()` paths on `PinPolicy`/`PassphrasePolicy`/`KdfParams`/`AppSettings`), not bolted on
after, and should get a pass under the `security-review-mfa` skill before merging.

## Alternatives Considered
- **A single centralized `lib/core/config/deployment_defaults.dart` of `static const` fields**
  (edit Dart, rebuild) instead of a JSON file — lower implementation risk (no `const`-constructor
  restructuring needed anywhere), but does not match `branding.json`'s no-Dart-knowledge-required
  UX, which is the explicit target this ADR is asked to match. Rejected in favor of full runtime
  configurability, at the accepted cost of the mutable-static pattern above.
- **Merging this into `branding.json` as additional fields** — rejected: conflates a purely
  cosmetic, safe-to-edit-by-anyone file with one that changes security policy; see Decision item 1.
- **Threading `DeploymentConfig` as an explicit constructor parameter through `PinPolicy`,
  `PassphrasePolicy`, `KdfParams`, and `LockoutPolicy`** instead of mutable statics — more
  idiomatic, but every existing call site of these stateless static-utility classes (used directly
  from widget code with no DI container reaching them) would need to change to pass the config
  through, a much larger and riskier diff across security-sensitive UI code for the same runtime
  behavior. Rejected in favor of the narrower mutable-static-configured-once-at-startup pattern,
  with `resetForTesting()` used to keep test isolation.
- **Making `AutoLockDelay`'s option set itself dynamic** (deployer-defined list of delays) —
  rejected as materially larger scope for unclear demand; see Decision item 5.

## References
- `docs/adr/0002-white-label-branding.md` — the branding pattern this ADR extends to a second,
  security-relevant config surface.
- `docs/adr/0010-vault-cryptography-modernization.md`, `docs/adr/0011-authentication-and-unlock-model.md`
  — the algorithm/mechanism choices (Argon2id, PIN-or-passphrase) that stay fixed; only tuning
  parameters and thresholds move.
- Direct review of `lib/core/security/pin_policy.dart`, `lib/core/security/passphrase_policy.dart`,
  `lib/core/crypto/vault_crypto.dart`, `lib/features/auth/providers/auth_provider.dart`,
  `lib/core/settings/app_settings.dart`, `lib/features/settings/screens/settings_screen.dart`,
  `lib/features/backup/screens/backup_export_screen.dart`, `lib/features/home/screens/home_screen.dart`
  (this session).
