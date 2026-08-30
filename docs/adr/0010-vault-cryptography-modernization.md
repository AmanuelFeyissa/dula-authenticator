# ADR-0010: Vault Cryptography Modernization (Argon2id + AES-256-GCM)

## Status
**Accepted — implemented.**

Delivered in `lib/core/crypto/` (`vault_crypto.dart`, `vault_meta.dart`) and `lib/core/vault/`
(`secret_store.dart`, `vault_service.dart`), wired through `AuthRepository`, `AuthNotifier` and
`AccountRepository`. Covered by 54 unit tests plus 8 end-to-end tests that drive the real widget
tree against the platform credential store.

**Amendment — no legacy migration.** The project owner confirmed there are no v1 installs in the
field: this is a fresh build, never released. The v1 compatibility layer and the v1→v2 migration
path described below were therefore **not retained** — `LegacyVaultCrypto`, the migration logic,
and the old `SecurityService` crypto were deleted, and the `encrypt` (AES-CBC) dependency was
dropped. What *is* retained is the versioned vault envelope and the KDF parameters stored in the
vault header, so a future release can raise the Argon2id cost or change scheme without stranding
data. `VaultService.unlock` refuses a vault whose recorded version it does not recognise rather
than guessing at the format. The migration design below stands as the reference for that future
work.

Measured cost of the OWASP default parameters: **~400–670 ms** per derivation on a desktop host
(pure Dart; `cryptography_flutter` delegates to native APIs on Android/iOS).
`test/core/crypto/kdf_performance_test.dart` and an end-to-end timing check guard against a
parameter change making unlock unusable.

## Context
The current cryptography in `lib/core/services/security_service.dart` has two concrete weaknesses
that a security review of this codebase surfaced:

1. **PIN hashing and key derivation use a single unsalted-iteration SHA-256 pass.**
   `hashPin()` computes `SHA-256(pin + salt)` and `deriveKeyFromPin()` computes
   `SHA-256(pin + salt + domainConstant)`. A per-installation random salt is used (good), but
   SHA-256 is a *fast* hash — it is designed to be quick, which is precisely wrong for a password/PIN
   KDF. An attacker who obtains the vault can try billions of candidate PINs per second on
   commodity GPU hardware. With a 6-digit PIN (10^6 = 1,000,000 possible values), the entire
   keyspace is exhausted essentially instantly.

2. **AES-256-CBC provides confidentiality but not authenticity.** `encryptData()`/`decryptData()`
   use CBC mode with a fresh random IV per call (correct, and CWE-329 is properly avoided), but CBC
   has no authentication tag. Ciphertext modification is undetectable; `decryptData()` catches the
   resulting exception and silently returns `''`, so tampering surfaces as "empty secret" rather
   than "someone modified your vault."

Research into current practice:
- **OWASP's Password Storage Cheat Sheet** recommends **Argon2id** as its primary choice, with a
  minimum configuration of **m=19456 KiB (19 MiB), t=2, p=1**, and higher (128 MiB, t=3–5) for
  security-conscious deployments.
- **Aegis Authenticator** — the most respected open-source authenticator in this space — originally
  used scrypt (N=2^15, r=8, p=1) with AES-256-**GCM**, and has since moved to **Argon2id**,
  citing its resistance to side-channel and time-memory-tradeoff attacks and its ability to tune
  memory-hardness and CPU-hardness independently (scrypt couples both into one `N` parameter).
- The Dart **`cryptography`** package implements both **AES-GCM** and **Argon2id (RFC 9106)**, and
  its companion **`cryptography_flutter`** delegates to native Android/iOS/macOS platform APIs
  where available, falling back to pure Dart elsewhere — giving hardware acceleration on mobile
  without a platform-specific code path in this project.

## Decision
1. **Replace SHA-256 key derivation with Argon2id**, parameterized at OWASP's recommended baseline
   (m=19456 KiB, t=2, p=1) as a floor, with the parameters **stored in the vault header** so they
   can be raised over time without breaking existing vaults.
2. **Replace AES-256-CBC with AES-256-GCM** for all secret-at-rest encryption, so tampering is
   detected and rejected rather than silently degraded to an empty string.
3. **Introduce a versioned vault envelope** rather than a bare base64 blob:
   ```
   { "version": 2, "kdf": { "alg": "argon2id", "m": 19456, "t": 2, "p": 1, "salt": "<b64>" },
     "nonce": "<b64>", "ciphertext": "<b64>", "tag": "<b64>" }
   ```
   The existing format becomes implicit `version: 1`.
4. **Auto-migrate on unlock.** When a `version: 1` vault is opened with a correct PIN/passphrase,
   the app derives the old key, decrypts, re-derives a new Argon2id key, re-encrypts under
   AES-GCM, and writes back `version: 2` — transparently, with no user action and no data loss.
   This was chosen over a clean break because an authenticator that resets and loses a user's
   enrolled accounts is worse than almost any other failure mode: those accounts may be the only
   way the user can log into the services they protect.
5. **Migration must be atomic and fail-safe**: the v2 vault is written and verified (decrypt-and-
   compare round trip) *before* the v1 vault is replaced. A crash mid-migration must leave the
   user with a working v1 vault, never a half-written one.
6. **PIN keyspace is explicitly acknowledged as the limiting factor**, not the KDF. Argon2id makes
   each guess expensive, but 10^6 candidates is a small keyspace regardless. This is mitigated by
   (a) offering a passphrase alternative (ADR-0011), (b) the existing brute-force lockout, and
   (c) OS-keystore-backed storage that keeps the vault off-disk-readable on a healthy device.
   **For exported backup files (ADR-0013), where none of those mitigations apply because the
   attacker holds the file offline, a passphrase is required — a 6-digit PIN must not be accepted
   as the sole protection for an export.**

## Consequences
**Positive:** Brings the app's cryptography to current OWASP/industry standard. Tampering becomes
detectable. Vault format becomes upgradeable without future migrations being breaking changes.

**Negative:** Argon2id at 19 MiB is deliberately slow — unlock will take noticeably longer
(hundreds of milliseconds) than the current near-instant SHA-256. This is the intended trade-off,
but it must be tested on low-end Android hardware to ensure it stays tolerable; parameters may need
a documented per-platform floor. Adds the `cryptography`/`cryptography_flutter` dependencies and
lets the existing `encrypt` package be dropped once migration is complete.

**Risks:** Migration is the highest-risk change in this entire modernization. It touches the code
path that protects every user's enrolled accounts. It requires dedicated round-trip tests
(v1 encrypt → migrate → v2 decrypt → compare plaintext) and a simulated-crash test before shipping.

## Alternatives Considered
- **scrypt instead of Argon2id** — a reasonable choice and Aegis's original one, but Argon2id is
  OWASP's current primary recommendation and allows independent memory/CPU tuning; no reason to
  adopt the older option for a greenfield migration.
- **PBKDF2** — widely available and FIPS-friendly, but not memory-hard, so far weaker against
  GPU/ASIC attack; only worth revisiting if a specific adopter has a FIPS-140 requirement, which
  would warrant its own ADR.
- **AES-CBC + separate HMAC (encrypt-then-MAC)** — would fix authenticity while keeping CBC, but
  hand-assembling encrypt-then-MAC is a classic source of implementation bugs when a vetted AEAD
  mode (GCM) is available in the same library.
- **Clean break with no migration** — rejected per point 4 above.

## References
- [OWASP Password Storage Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html)
- [Aegis vault format documentation](https://github.com/beemdevelopment/Aegis/blob/master/docs/vault.md)
- [cryptography — Dart package (AES-GCM, Argon2id/RFC 9106)](https://pub.dev/packages/cryptography)
- [cryptography_flutter — native platform delegation](https://pub.dev/documentation/cryptography_flutter/latest/cryptography_flutter/FlutterCryptography-class.html)
- Direct review of `lib/core/services/security_service.dart` (this session).
