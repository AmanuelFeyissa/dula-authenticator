# Configuration Guide — Security Policy and Product Tunables

Dula Authenticator's visual identity is configured via `assets/branding/branding.json`
(see [`docs/BRANDING.md`](BRANDING.md)). Everything else a deployer might reasonably want to
change — PIN length, passphrase rules, Argon2id cost, lockout backoff, auto-lock and rotation
defaults, backup file naming, and a couple of UI tunables — lives in a second file:
**`assets/config/deployment_config.json`**.

It is deliberately a *separate* file from branding: branding is cosmetic and safe for anyone to
edit; this file changes security behaviour, and keeping it distinct means you can't accidentally
weaken lockout while just trying to change a logo. See
[ADR-0016](adr/0016-deployment-configuration.md) for the full reasoning.

## Quick start

Edit `assets/config/deployment_config.json`, then rebuild. No Dart knowledge required. Every field
is optional — anything you omit, or the whole file if it's missing or malformed, falls back to the
values below (i.e. today's shipped behaviour), so a typo never breaks the app.

```json
{
  "security": {
    "pinLength": 6,
    "passphraseMinLength": 12,
    "passphraseRecommendedLength": 15,
    "passphraseMaxLength": 256,
    "argon2MemoryKiB": 19456,
    "argon2Iterations": 2,
    "argon2Parallelism": 1,
    "lockoutSteps": [
      { "attempts": 3, "seconds": 30 },
      { "attempts": 5, "seconds": 300 },
      { "attempts": 10, "seconds": 3600 }
    ],
    "defaultAutoLock": "thirtySeconds",
    "credentialRotationDefaultDays": 90,
    "credentialRotationMinDays": 1,
    "credentialRotationMaxDays": 3650,
    "credentialRotationOptionsDays": [30, 60, 90, 180, 365]
  },
  "backup": {
    "fileNamePrefix": null
  },
  "ui": {
    "copiedToClipboardSnackbarSeconds": 1
  }
}
```

### Field reference

| Field | What it controls | Notes |
|---|---|---|
| `security.pinLength` | Required PIN digit count | Rejected below 4 (falls back to the default). Changing this away from 6 disables the curated common-6-digit-PIN blocklist and the sequential/repeating-pattern checks (they're built for exactly 6 digits) — you keep length, digits-only, and same-digit-repeated enforcement at any length. |
| `security.passphraseMinLength` / `recommendedLength` / `maxLength` | Passphrase acceptance floor, the length shown as "recommended" guidance, and the input cap | `passphraseMinLength` is rejected below 8 (NIST SP 800-63B's own floor; falls back to the default of 12 if you try). |
| `security.argon2MemoryKiB` / `Iterations` / `Parallelism` | Argon2id cost for newly created vaults | The *algorithm* (Argon2id) is fixed — only these tuning parameters move, and each is rejected below the OWASP Password Storage Cheat Sheet minimum (19456 KiB / 2 iterations / parallelism 1) — a value below the floor falls back to the default rather than silently shipping a weaker KDF. Raise them for a device class that can afford slower unlocks. Existing vaults keep the parameters they were created with (recorded per-vault) — this only affects vaults created after the change. |
| `security.lockoutSteps` | Failed-unlock backoff: at N consecutive wrong attempts, lock out for S seconds | A list of `{attempts, seconds}`, evaluated in order — list them ascending by `attempts`. An empty list disables lockout entirely. |
| `security.defaultAutoLock` | Default grace period before a backgrounded app locks itself | One of `immediate`, `thirtySeconds`, `oneMinute`, `fiveMinutes`, `never`. Users can still change this in Settings — this only sets what a fresh install starts with. |
| `security.credentialRotationDefaultDays` / `MinDays` / `MaxDays` | Default and allowed range for forced periodic credential rotation | Off by default (NIST advises against mandatory rotation absent evidence of compromise); these only matter for deployments that turn it on. |
| `security.credentialRotationOptionsDays` | The rotation-period choices shown in Settings | E.g. a compliance regime standardized on 45/90/180 days only. |
| `backup.fileNamePrefix` | Prefix for exported backup file names | `null` (default) derives it from `branding.json`'s `appName` instead of a hardcoded brand name. |
| `ui.copiedToClipboardSnackbarSeconds` | How long the "Code copied to clipboard" confirmation stays visible | Consider a longer value for accessibility. |

## What stays fixed, and why

A few values found during the same audit that produced this file were deliberately **not** made
configurable — see ADR-0016's Context/Decision sections for the full list, summarized here:

- **RFC-mandated OTP defaults** (6 digits, 30-second period, SHA-1 default) — these are
  interoperability defaults from RFC 6238/6234 and Google Authenticator's own convention, not a
  product choice. Per-account overrides already work via `otpauth://` URI parameters.
- **`otpauth://` URI parsing bounds, the Steam Guard format** — input sanitization and a
  third-party format's fixed shape, not policy.
- **Internal secure-storage key names, the backup format marker/version, the vault format
  version** — compatibility-load-bearing infrastructure. Changing these per-deployment would break
  cross-fork backup recognition and forward-compatible vault migration for no user-visible benefit.
- **The Apache-2.0 license string shown in the About dialog** — a legal requirement of the
  fork/rebrand model itself (see the Attribution section of `docs/BRANDING.md`), not a stylistic
  choice.
- **The set of `AutoLockDelay` options itself** (only the *default* is configurable) and the
  hardcoded dark-navy theme background — both deliberately out of scope for this file; see
  ADR-0016.

## Precedence and safety

`assets/config/deployment_config.json` is read once at startup, the same way as
`assets/branding/branding.json`. If the file is missing, unreadable, or any individual field is the
wrong type, that field (or the whole file) silently falls back to the documented default — a broken
deployment config can never prevent the app from starting or corrupt existing data.

Changing `security.argon2*` only affects vaults created *after* the change; a vault already on disk
keeps the KDF parameters it was created with, recorded in its own metadata, and continues to unlock
normally.
