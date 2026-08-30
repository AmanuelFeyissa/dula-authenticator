# ADR-0014: Remove Enterprise Directory Authentication Entirely

## Status
Proposed — supersedes ADR-0003

## Context
ADR-0003 proposed rebuilding the app's Active Directory enrollment gate as a pluggable,
cross-platform LDAP provider (`dartdap`-based), replacing the Windows-only PowerShell
implementation. That analysis correctly identified the existing implementation's problems —
Windows-only by construction, single-tenant via compiled-in constants, bypassed entirely on every
other platform — but its proposed remedy assumed the *feature itself* was worth preserving.

On review, that assumption does not hold for a general-purpose authenticator:

1. **It solves an authorization problem that doesn't belong in this app.** The gate asked "is this
   user allowed to enroll an account in this authenticator?" But the authenticator is a local tool
   that generates codes from secrets the user already possesses. If a user holds a valid
   `otpauth://` secret, the issuing service already authorized them — re-checking group membership
   in the client adds no security, because a user denied by the gate can simply use any other
   authenticator app (Google Authenticator, Aegis, a hardware token) with the same secret. **The
   control is trivially bypassable and therefore largely decorative.**
2. **It is a genuine liability, not merely dead weight.** It requires the app to collect the user's
   full domain username and password and hold them in process memory — a high-value credential the
   app has no other reason to touch. Removing the feature removes that entire attack surface.
3. **It conflicts with the project's target use cases.** A general-purpose authenticator usable by
   "any organization", offline, and in air-gapped environments should not depend on reaching a
   directory server to let a user add an account.
4. **It contradicted the app's own behavior.** The gate was already bypassed on Linux, macOS,
   Android, iOS, and Web — so for five of six platforms the feature did not exist, and the app
   functioned correctly without it. That is strong evidence it was never load-bearing.

Comparable open-source authenticators (Aegis, 2FAS, Ente Auth) have no such concept. Enterprises
that need to control *who is issued* a second factor enforce that at the identity provider, where
it is actually effective — not in the client app.

## Decision
**Remove enterprise directory authentication entirely.** Concretely, this deleted:

- `lib/core/services/ad_service.dart` (PowerShell/`System.DirectoryServices` invocation)
- `lib/core/services/ad_config.dart` (compiled-in single-tenant LDAP constants)
- `lib/features/accounts/widgets/ad_auth_dialog.dart` (credential-collection dialog)
- The `dartdap` dependency from `pubspec.yaml` (present but never actually used by the
  PowerShell implementation)
- The gate call site in `home_screen.dart`, so adding an account now navigates directly

The pluggable `DirectoryAuthProvider` interface proposed in ADR-0003 was **not** built — there is
no abstraction to preserve, because there is no longer a feature behind it. Should an adopter later
need enrollment gating, the correct place is their identity provider; if in-app gating is genuinely
required for some deployment, it should be reintroduced as an optional, deployer-configured
extension with its own ADR, not resurrected from the removed code.

## Consequences
**Positive:** Removes a Windows-only feature that never worked on five of six platforms; removes
the app's only reason to handle domain credentials; removes the app's only outbound network call,
strengthening the zero-telemetry/air-gapped guarantees of ADR-0007 to "the app makes no network
calls at all"; deletes ~500 lines including a PowerShell script-injection surface that required
careful escaping to be safe.

**Negative:** Organizations relying on the original bank deployment's enrollment gate lose it. Given
the bypassability described above, what they lose is largely the appearance of a control rather
than an effective one — but this should be stated plainly to any such adopter rather than glossed.

**Risks:** None to application correctness — the removed code was already inert on most platforms
and its removal is covered by the existing analyze/test suite, which passes.

## Alternatives Considered
- **Rebuild as cross-platform LDAP (ADR-0003's proposal)** — rejected per Context above: it would
  invest real effort into making a bypassable control work on more platforms, while keeping the
  credential-handling liability.
- **Keep the Windows-only implementation as-is** — rejected: single-tenant compiled-in constants
  make it unusable for any other organization, which contradicts the project's core goal.

## References
- ADR-0003 (superseded) — the original analysis of the AD implementation's limitations
- ADR-0007 — zero-telemetry / air-gapped operability, strengthened by this removal
- Direct review and removal of `lib/core/services/ad_service.dart`,
  `lib/core/services/ad_config.dart`, `lib/features/accounts/widgets/ad_auth_dialog.dart`
  (this session).
