# Security Model

What Dula Authenticator protects, what it does not, and where those guarantees differ by platform.

This document is required by [ADR-0005](adr/0005-device-integrity-scope.md) and
[ADR-0011](adr/0011-authentication-and-unlock-model.md), and must be updated whenever a change
alters a guarantee below.

## What is being protected

One thing: the **OTP shared secrets**. Anyone holding those can generate valid codes for your
accounts indefinitely, without your device and without leaving a trace on it.

Everything else here exists to serve that.

## Threat model

### Defended against

| Threat | Defence |
|---|---|
| Someone picks up your unlocked device | Auto-lock (configurable, default 30s in background) |
| Someone steals the device and reads app storage | Secrets are AES-256-GCM sealed under an Argon2id-derived key; the credential is never stored |
| Someone guesses your PIN or passphrase interactively | Strength policy plus escalating lockout (default 30s / 5min / 1h, deployer-configurable — [ADR-0016](adr/0016-deployment-configuration.md)) |
| Someone copies the vault and attacks it offline | Argon2id at OWASP-minimum parameters by default (m=19456 KiB, t=2, p=1, deployer-configurable) makes each guess expensive |
| Someone tampers with stored ciphertext | AES-GCM authenticates; a modified record is isolated as a per-account error (surfaced via `loadError`, [ADR-0015](adr/0015-account-management.md)) rather than decrypting to garbage or blocking the rest of the vault |
| A network observer | There is no network. The app makes no outbound calls of any kind ([ADR-0007](adr/0007-air-gapped-operability.md)) |

### Not defended against

Stated plainly rather than implying coverage:

- **A compromised operating system.** Malware with the privileges to read another process's memory
  can read the vault key while the app is unlocked. No app-level measure fixes this.
- **A compromised device at rest on a platform with weak secret storage** — see the platform table.
- **Shoulder-surfing of displayed codes**, and **the clipboard**: copying a code puts it on the
  system clipboard, where any other application can read it.
- **Physical coercion.** There is no duress credential.
- **Loss of the device with no backup taken.** Encrypted backup and restore exist
  ([ADR-0013](adr/0013-backup-export-and-import.md)), but nothing creates one automatically —
  a device lost before the user ever exported a backup means lost secrets. There is
  deliberately no "forgot PIN" reset that keeps your accounts — such a thing could not exist
  without a second copy of the key.
- **A password-protected Aegis or 2FAS export.** This app does not implement either app's
  encryption scheme (see "Backups" below) — it recognises such a file and asks for it to be
  re-exported without a password, rather than guessing at an unverified decrypt.

## The credential

At registration the user picks a **6-digit PIN** or a **passphrase**
([ADR-0011](adr/0011-authentication-and-unlock-model.md)). Both feed the same Argon2id derivation;
they are not equally strong, and the app does not pretend otherwise:

- A **PIN** is a 10<sup>6</sup> keyspace. Argon2id makes each attempt expensive and the blocklist
  removes the values attackers try first, but a determined offline attacker with the vault and
  serious hardware will get through a 6-digit PIN eventually. It is a reasonable choice for a
  personal device unlocked many times a day; it is not a good choice for a vault protecting
  high-value accounts on a machine other people can reach.
- A **passphrase** of at least 12 characters, checked against predictable values and rated on
  length and character variety, is the stronger option and the right one on desktop.

The credential kind is recorded in the vault metadata (`vault_meta`, field `cred`), not in
preferences, so the lock screen can present the right input before anything is decrypted and a
cleared preferences file cannot strand the user. An unreadable value resolves to *passphrase*,
because a text field can type six digits while a numeric keypad cannot type a passphrase.

Rate limiting (`mfa_failed_attempts`, `mfa_lockout_until`) lives in the **secure store**, not in
preferences: a lockout an attacker can clear by deleting a plain file is not a lockout.

Forced periodic credential rotation exists as a setting but is **off by default**: NIST SP 800-63B
advises against mandatory rotation of user-chosen secrets absent evidence of compromise, because it
drives predictable increment-the-last-digit patterns.

## Biometrics — the honest version

Biometrics **cannot derive a key**. When biometric unlock is enabled, the app caches the derived
vault key in platform secure storage (`mfa_biometric_master_key`) and the biometric prompt gates
reading it back.

**Therefore: with biometrics enabled, the vault is exactly as strong as the platform's secure
storage — and no stronger.** It is not equivalent to deriving the key from your passphrase every
time.

Consequences the implementation honours:

- Biometrics are **off until the user turns them on**, and the key is cached **only** while they
  are on. Switching them off deletes the cached key.
- Changing the credential re-keys the vault and refreshes the cache, so biometric unlock cannot
  quietly break.
- The PIN or passphrase **always** works. A failed sensor, an OS-level biometric lockout, or a new
  device can never make the vault unopenable.

A future improvement is binding the key to a biometric-gated hardware keystore entry (Android
StrongBox/TEE, iOS Secure Enclave) rather than a plain secure-storage read. That needs per-platform
verification and is not claimed today.

## Backups

An exported backup is a single encrypted file: `{v, app, kdf, salt, payload}`, sealed with the
same Argon2id + AES-256-GCM primitives as the vault itself, under a passphrase the user chooses
at export time.

**The export passphrase is independent of the unlock credential, and is never a PIN — this is
enforced in code, not just suggested in the UI.** Once a backup file leaves the device, none of
the on-device protections apply (no secure storage, no lockout): the attacker has the file
offline and can guess against it at whatever rate their hardware allows. A 6-digit PIN's
10<sup>6</sup> keyspace is not adequate protection for an offline file regardless of KDF cost, so
`BackupService.export` refuses a passphrase that fails policy rather than encrypting anyway —
even if the vault's own unlock credential is a PIN.

There is no cloud sync, by design ([ADR-0007](adr/0007-air-gapped-operability.md),
[ADR-0013](adr/0013-backup-export-and-import.md)): nothing about backup ever calls out to a
network. The user chooses where the file goes and is responsible for it from there.

**Import from Aegis and 2FAS supports their unencrypted export only.** Both apps also offer a
password-protected export; decrypting either without a reference implementation or a real
encrypted fixture to validate against — this project had neither — risks a subtly wrong decrypt
of someone's OTP vault, which is worse than declining to support it. A password-protected file
from either app is recognised and the user is told to re-export without a password, rather than
being told the file is simply unrecognised.

## Platform capabilities — verified, not assumed

Support differs per platform, and the app must not imply protection it does not have.

| Capability | Android | iOS | Windows | macOS | Linux | Web |
|---|---|---|---|---|---|---|
| OS-backed secret storage | Keystore | Keychain | DPAPI | Keychain | libsecret — **requires a running keyring daemon** ([ADR-0004](adr/0004-secure-storage-linux-keyring.md)) | **None** |
| Biometric unlock (`local_auth`) | yes | yes | yes (Hello) | yes | **no implementation** | **no implementation** |
| Camera QR enrollment (`mobile_scanner`) | yes | yes | **no** | yes | **no** | yes |
| Screenshot / recording block (`screen_protector`) | yes | yes | **no** | **no** | **no** | **no** |
| Root / jailbreak detection (`root_checker_plus`) | yes | yes | **no** | **no** | **no** | **no** |
| Backup file save (`file_picker`) | yes | yes | yes | yes | yes\* | yes (download) |

\* `file_picker`'s `saveFile(bytes: ...)` convenience is
[documented as broken on Linux](https://github.com/miguelpruivo/flutter_file_picker/issues/1907)
(package 10.3.3, Nov 2025): the call reports success but writes nothing. This app never relies on
it — `saveFile()` is used only to obtain a destination path, and `dart:io` writes the bytes, which
has no such bug. Web has no filesystem, so it is the one platform where passing `bytes` is both
necessary and correct.

Notes on the gaps:

- **Linux and Web have no biometric path.** Those users unlock with their credential, which is why
  ADR-0011 requires the credential to remain available everywhere. The settings screen says so
  rather than showing a switch that does nothing.
- **Windows and Linux have no camera enrollment.** Manual entry is the universal path
  ([ADR-0006](adr/0006-no-camera-enrollment-parity.md)), and it exposes every `otpauth://`
  parameter, so a no-camera user is not limited to default credentials.
- **Screenshot protection and root detection are mobile-only.** On desktop, assume codes on screen
  can be captured.
- **Web is the weakest deployment.** There is no OS keystore in a browser; stored data is protected
  only by the browser's origin isolation. Treat the web build as a convenience, not as a place to
  keep secrets that matter.

## Cryptography

| Element | Choice | Rationale |
|---|---|---|
| Key derivation | Argon2id, m=19456 KiB, t=2, p=1 by default, 32-byte random salt | OWASP-recommended parameters ([ADR-0010](adr/0010-vault-cryptography-modernization.md)); the cost parameters (not the algorithm) are deployer-configurable per [ADR-0016](adr/0016-deployment-configuration.md) — see [docs/CONFIGURATION.md](CONFIGURATION.md) |
| Encryption | AES-256-GCM, fresh nonce per record | Authenticated — tampering is detected, not silently decrypted |
| Credential check | Verifier derived from the Argon2id output, constant-time compared | The credential itself is never stored |
| Format | Versioned `vault_meta` recording version and KDF cost | A newer format is refused rather than guessed at; cost can be raised later without stranding vaults |

Measured unlock cost at production parameters on a current desktop: ~120 ms.

## Reporting a vulnerability

Open a private security advisory on the repository rather than a public issue.
