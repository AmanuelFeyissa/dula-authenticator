# ADR-0012: Pluggable OTP Types (TOTP, HOTP, Steam Guard, Custom Parameters)

## Status
**Accepted — implemented.**

Delivered in `lib/core/otp/` (`otp_type.dart`, `otp_algorithm.dart`,
`otp_generator.dart`, `otp_uri.dart`) and `lib/core/models/otp_account.dart`, replacing
`totp_engine.dart` and `totp_account.dart`, which were deleted.

Validation: HOTP against all ten RFC 4226 Appendix D vectors; TOTP against the RFC 6238 SHA-1,
SHA-256 and SHA-512 vectors including the 64-bit-counter case; Steam cross-validated against the
reference JS implementation (npm `steam-totp`) rather than against this project's own output.
98 unit tests and 11 end-to-end tests pass.

The parameter-dropping bug described below is fixed: all `otpauth://` parsing now goes through
`OtpUri`, and an end-to-end test asserts that an 8-digit SHA-256 credential is stored and rendered
with those parameters intact. `OtpUri` also clamps out-of-range values and rejects unparseable
input outright rather than storing an account that could never generate a valid code.

Two deviations from the plan below, both deliberate:

- **Per-type settings toggles were not built.** Type selection lives in the Add Account screen's
  advanced section, which serves the same purpose without a settings surface that does not yet
  exist. A deployment-level "only expose TOTP" switch belongs with the rest of the settings work.
- **mOTP remains excluded**, as planned.

## Context
`lib/core/totp_engine.dart` implements RFC 6238 TOTP correctly — including the RFC 4226 HOTP
dynamic-truncation core in `generateCodeFromCounter()`, and SHA-1/SHA-256/SHA-512 support — but the
app only ever exposes **time-based** codes. `TotpAccount` has no notion of an OTP *type*, so:

- **HOTP (RFC 4226, counter-based)** cannot be enrolled, even though the underlying algorithm is
  already implemented and merely needs a persisted, incrementable counter instead of a time-derived
  one. Hardware tokens and some enterprise systems issue HOTP credentials.
- **Steam Guard** — Steam's variant using a 5-character custom alphabet instead of digits — is not
  supported. It is supported by Aegis and 2FAS and is one of the most commonly requested
  non-standard types in consumer authenticators.
- **Non-default parameters** are modelled (`digits`, `period` fields exist on `TotpAccount`) but
  hardcoded at the enrollment site: `add_account_screen.dart` always constructs accounts with
  `TotpAlgorithm.sha1` and default digits/period, discarding the `digits`, `period`, and
  `algorithm` values that a scanned `otpauth://` URI may specify. **This is a live bug, not just a
  missing feature**: scanning a valid 8-digit or SHA-256 QR code today silently produces wrong
  codes, because the parsed parameters are dropped and defaults are used instead.

Research confirms the default in production remains 6 digits / 30s / SHA-1, with SHA-256 and
SHA-512 variants existing but interoperating unevenly outside the issuing service's own app — so
correct parsing matters more than picking a "better" default.

## Decision
1. **Refactor `TotpEngine` into a pluggable `OtpGenerator` abstraction** with concrete
   implementations: `TotpGenerator` (RFC 6238), `HotpGenerator` (RFC 4226), and
   `SteamGuardGenerator`. The existing dynamic-truncation code is shared, not duplicated — it is
   already correct and RFC-conformant.
2. **Add an `OtpType` field to the account model** (`totp` / `hotp` / `steam`), persisted in the
   vault and round-tripped through import/export (ADR-0013).
3. **Fix the parameter-dropping bug**: `add_account_screen.dart` must honor `digits`, `period`,
   `algorithm`, `counter`, and `type` parsed from the `otpauth://` URI rather than overriding them
   with defaults. This ships in the same phase as the type work because they touch the same code
   path, and shipping the refactor without the fix would leave a known-wrong result in place.
4. **HOTP counter handling**: HOTP codes do not auto-refresh; the UI shows the current code with an
   explicit "generate next" action, and the counter is incremented and persisted atomically on use.
   Counter desynchronization (the classic HOTP failure mode) is surfaced to the user with a
   resync affordance rather than silently producing invalid codes.
5. **Non-standard types are individually toggleable in settings**, defaulting to standard TOTP/HOTP
   visible and Steam Guard available but not prominent — per the requirement that added
   capabilities be enable/disable-able rather than forced on every user. An organization deploying
   this internally can ship with only TOTP exposed if that's all they issue.
6. **Manual entry gains an advanced section** exposing type, digits, period, and algorithm, so a
   no-camera user (ADR-0006) can enroll a non-default credential without a QR code — otherwise the
   camera-free path would only support the default parameters, which would undermine ADR-0006's
   guarantee.

## Consequences
**Positive:** Fixes a real correctness bug affecting any non-default QR code. Brings feature parity
with the mainstream open-source authenticators (Aegis, 2FAS) for the types users actually
encounter. The generator abstraction makes any future type (e.g. a new vendor variant) an additive
change rather than a refactor.

**Negative:** More surface to test — each generator needs its own RFC test vectors, and Steam Guard
needs verification against known-good reference values since it has no RFC. The account model gains
fields, which must be handled in the vault migration (ADR-0010) so existing accounts default
cleanly to `totp`.

**Risks:** Silent code-generation errors are the worst failure mode for an authenticator — a wrong
code looks identical to a right one until the user is locked out of the service. Every generator
must be covered by published test vectors (RFC 4226 Appendix D for HOTP, RFC 6238 Appendix B for
TOTP, community reference values for Steam) before this ships, and the existing TOTP vectors must
keep passing throughout the refactor.

## Alternatives Considered
- **Keep TOTP-only and just fix the parameter bug** — smaller, but leaves the app unable to enroll
  credentials users genuinely hold (hardware HOTP tokens, Steam), which is a real gap against every
  comparable open-source authenticator.
- **Add mOTP (Mobile-OTP)** — supported by andOTP, but effectively legacy; deliberately excluded to
  avoid maintaining a generator almost nobody will enroll. Can be added later via the same
  abstraction if an adopter needs it.

## References
- [RFC 6238 — TOTP: Time-Based One-Time Password Algorithm](https://www.rfc-editor.org/rfc/rfc6238.html)
- [RFC 4226 — HOTP: An HMAC-Based One-Time Password Algorithm](https://www.ietf.org/rfc/rfc4226.txt)
- [Ente Auth vs 2FAS vs Aegis — feature comparison](https://ente.com/compare/ente-auth-vs-others/)
- Direct review of `lib/core/totp_engine.dart`, `lib/core/models/totp_account.dart`,
  `lib/features/accounts/screens/add_account_screen.dart` (this session).
