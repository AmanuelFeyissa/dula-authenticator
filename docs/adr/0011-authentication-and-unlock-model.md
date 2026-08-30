# ADR-0011: Authentication & Unlock Model (Biometric-First, PIN or Passphrase)

## Status
Proposed

## Context
The current model makes a **6-digit PIN the primary and mandatory secret**. Biometrics exist but
are strictly a convenience layer bolted on top: `unlockWithBiometrics()` retrieves a
**base64-encoded copy of the master key that was persisted to secure storage** during PIN unlock,
so biometrics never actually derive anything — they just gate access to a stored key.

Three problems follow from that design:

1. **A 6-digit PIN is a 10^6 keyspace.** Even with Argon2id (ADR-0010) making each guess
   expensive, a million candidates is small. The PIN is acceptable *only* because the derived key
   is held in OS-native secure storage on a healthy device and the app enforces lockout — but it is
   the weakest link, and it is the *only* link today because there is no alternative.
2. **The user has no choice.** Some users (especially on desktop, where typing is easy) would
   happily use a strong passphrase; the app doesn't offer one.
3. **Biometrics are not optional-by-design.** They're enabled via a preference, but the flow
   assumes PIN-first setup, so a user who wants biometric-primary still creates and remembers a PIN
   as the main credential.

Research context: modern authenticators and current MFA UX guidance converge on
**biometric-first with a strong fallback** — biometrics for the common case (fast, no typing, no
shoulder-surfing) with a knowledge factor behind it for recovery, device changes, and cases where
biometrics fail or are unavailable (Linux desktop, for instance, where `local_auth` support is
limited).

## Decision
**Biometric-first unlock, with a user-chosen knowledge-factor fallback selected at registration.**

1. **At first run (registration), the user chooses their fallback credential**: a **6-digit PIN**
   (familiar, fast, what most users expect from an authenticator) or a **passphrase** (stronger,
   better for desktop and for anyone protecting high-value accounts). Both feed Argon2id
   (ADR-0010). The choice is presented plainly with an honest one-line explanation of the
   trade-off — not buried in settings, and not framed so that the "secure" option feels punitive.
2. **Biometric unlock is offered immediately after** on platforms that support it, and is the
   default unlock path once enabled. It remains **fully optional and can be disabled at any time**
   in settings, per the requirement that security features be toggleable rather than forced.
3. **The fallback credential is always available**, even when biometrics are enabled — biometrics
   can fail (wet fingers, new device, OS-level lockout), and an authenticator that can become
   permanently unopenable is unacceptable.
4. **The knowledge factor can be changed later** (PIN → passphrase or vice versa) without resetting
   the vault: the vault is re-keyed using the same verified-then-swap procedure as the ADR-0010
   migration.
5. **Configurable auto-lock**: the current hardcoded 30-second background lock becomes a user
   setting (immediate / 30s / 1min / 5min / never), because a 30-second lock is right for a shared
   bank workstation and actively annoying on a personal desktop. Default stays conservative (30s).
6. **PIN policy is retained but relaxed in one respect**: the existing strength rules (blocklist,
   sequential/repeating detection) still apply to PINs. The 90-day forced rotation is
   **reconsidered** — NIST SP 800-63B explicitly advises *against* mandatory periodic rotation of
   user-chosen secrets absent evidence of compromise, because it drives predictable
   increment-the-last-digit patterns. It becomes an **optional, off-by-default policy toggle** for
   organizations whose compliance regime demands it, rather than behavior forced on every user.

## Consequences
**Positive:** Users get a fast, modern unlock (biometric) without the app depending on it. Users
who want real security get a passphrase. Enterprises that need rotation can still enforce it.
Nobody is locked out by a failed fingerprint sensor.

**Negative:** More onboarding surface (a choice screen), more state to test (PIN vs passphrase ×
biometrics on/off × auto-lock settings). Changing the rotation default is a behavior change for
the original deployment's policy — hence making it a toggle rather than deleting it.

**Risks:** The biometric implementation currently stores the derived master key in secure storage
so biometrics can restore it. That remains necessary (biometrics cannot themselves derive a key),
but it means **biometric security is exactly as strong as the platform's secure storage** — this
must be stated honestly in `docs/SECURITY_MODEL.md` rather than implied to be equivalent to
deriving from the passphrase. On platforms where hardware-backed keystore is available
(Android StrongBox/TEE, iOS Secure Enclave), the key should be bound to biometric-gated keystore
entries rather than plain secure-storage reads; this needs per-platform verification, not
assumption.

## Alternatives Considered
- **Keep PIN as the sole primary secret** — rejected: it's the current design and the weakest part
  of the security model, with no upgrade path for users who want better.
- **Passphrase-only (drop PIN entirely)** — rejected: a 6-digit PIN is what users expect from an
  authenticator app, and forcing passphrase entry on a phone many times a day would push users to
  weak passphrases or to abandoning the app.
- **Device-credential delegation (let the OS lock screen be the only gate)** — simpler, but gives
  up app-level protection entirely: anyone who can unlock the device gets every OTP secret. Wrong
  trade-off for a security tool.

## References
- [OWASP Password Storage Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html)
- [UX best practices for MFA — WorkOS](https://workos.com/blog/ux-best-practices-for-mfa)
- [2FA UX patterns: setup flows for SMS, authenticator apps, and biometrics — LogRocket](https://blog.logrocket.com/ux-design/2fa-user-flow-best-practices/)
- Direct review of `lib/features/auth/providers/auth_provider.dart`,
  `lib/features/auth/repositories/auth_repository.dart` (this session).
