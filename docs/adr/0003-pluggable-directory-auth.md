# ADR-0003: Pluggable, Cross-Platform Enterprise Directory Authentication

## Status
**Superseded by ADR-0014 — directory authentication was removed entirely.**

The analysis below (that the PowerShell/AD gate was Windows-only, single-tenant, and unusable on
every other platform) remains accurate and is retained as the record of *why* the feature could not
simply be carried forward. Its conclusion — to rebuild the gate as a pluggable cross-platform LDAP
provider — was not adopted. The project owner determined that an enterprise directory gate on
account *enrollment* is not a feature a general-purpose authenticator should have at all, so the
feature was deleted rather than rebuilt. See ADR-0014.

## Context
The current "AD authorization" gate (`lib/core/services/ad_service.dart`) works by shelling out to
Windows PowerShell and `System.DirectoryServices.AccountManagement` to validate credentials and
check group membership against one specific Active Directory. This is:

1. **Windows-only by construction** — `Process.run('powershell', ...)` does not exist on Linux,
   macOS, Android, iOS, or Web. The app already bypasses this check entirely on non-Windows
   platforms (`AdAuthDialog.showAndVerify`, `HomeScreen._navigateToAddAccount`), which means today
   the feature simply does not exist outside Windows.
2. **Single-tenant by construction** — connection details (`ldapHost`, `domainSuffix`,
   `searchBaseDN`, `requiredGroupDN`) are compiled-in constants in `ad_config.dart`, not runtime
   configuration, so a rebuild is required per organization even on Windows.
3. Not every adopter uses Active Directory at all — many organizations use plain LDAP, Azure AD /
   Entra ID via OIDC, Okta, or no enterprise directory gate whatsoever (a personal or small-team
   deployment). A generic project cannot assume AD.

Research confirms a pure-Dart, cross-platform path exists: **`dartdap`**, an LDAPv3 client library
already listed as a dependency in `pubspec.yaml` (`dartdap: ^0.11.4`) but never actually used by
`ad_service.dart`. Since Active Directory is LDAPv3-compatible, `dartdap` can perform the same
"bind as the user, search for group membership" flow that the PowerShell script does today, but
via a plain TCP/TLS socket — which works on every Dart VM target (Windows, Linux, macOS, Android,
iOS desktop/mobile). The one documented gap is **Flutter Web**: browsers do not expose raw TCP
sockets, so a `dartdap`-based provider cannot run in a browser tab; this is a platform limitation
of the web, not of `dartdap` specifically, and matches the existing bypass-on-non-Windows behavior
that already excludes this gate from other platforms today.

## Decision
Introduce a `DirectoryAuthProvider` abstract interface (`lib/core/directory_auth/`) with:

- A `NoDirectoryAuth` implementation (default) — the gate is skipped entirely, matching how most
  adopters who don't use an enterprise directory will run the app.
- An `LdapDirectoryAuthProvider` implementation built on `dartdap`, performing the same three-step
  flow as today's PowerShell script (bind with user credentials, search by identifying attribute,
  check `memberOf` against a configured required-group DN) but over LDAP/LDAPS directly, and
  working identically on Windows, Linux, macOS, and mobile.
- All connection parameters (`ldapHost`, `port`, `useSSL`, `searchBaseDN`, `domainSuffix`,
  `requiredGroupDN`) move from compile-time constants into the same runtime configuration
  mechanism established in ADR-0002, so one build artifact can be reconfigured per deployment
  without a rebuild.
- **Web remains unsupported for direct LDAP** and is documented as a known, permanent platform
  limitation (not a bug to fix) — an organization that needs directory-gated enrollment on the web
  build would need a thin backend proxy, which is explicitly out of scope for this project and
  noted as a "if you need this, here's the extension point" doc rather than built-in.
- The existing PowerShell/`System.DirectoryServices` implementation is kept, behind the same
  interface, as an optional `WindowsNativeAdProvider` for organizations that specifically want
  Windows-native credential validation semantics (e.g. domain password-policy enforcement
  behavior that differs subtly from a raw LDAP bind) — not removed, but no longer the only option
  and no longer assumed to be the default.
- The directory-auth gate stays **opt-in and disabled by default**, since assuming every adopter
  runs Active Directory (or any directory) would recreate the single-tenant assumption this ADR
  exists to remove.

## Consequences
**Positive:** Directory-gated enrollment becomes a real, working feature on Linux, macOS, and
mobile for the first time, not just Windows. One codebase, one config file, works for any LDAPv3
directory (AD, OpenLDAP, FreeIPA), not one specific company's domain. Air-gapped orgs that run
their own internal LDAP can use this without any external network dependency — it only ever talks
to the directory server the deployer configures.

**Negative:** LDAP credential binding sends the user's plaintext password to the app process
memory (same trust boundary as today's PowerShell approach) — LDAPS (TLS) must be the documented,
enforced default to avoid credentials on the wire in plaintext; `useSSL = false` should not be the
shipped default in the new config, unlike today's placeholder config. Requires new test coverage
against a real or mocked LDAP server (e.g. an OpenLDAP test container in CI), which the project
does not currently have.

**Risks:** LDAP injection in the search filter must be handled the same way `ad_service.dart`
already carefully handles PowerShell-string escaping (`_escapePowerShell`) — the LDAP equivalent
(RFC 4515 filter escaping) must be implemented and tested before this ships, not assumed away
because `dartdap` is "just a library."

## Alternatives Considered
- **Keep PowerShell/Windows-only, document non-Windows as unsupported for directory auth** —
  rejected: contradicts the explicit goal that this project must work "for any company" including
  Linux shops, where an enterprise directory gate is just as relevant as on Windows.
- **Build a full OIDC/SAML SSO integration instead of LDAP** — valuable, but a materially larger
  scope (requires a redirect-capable auth flow, which conflicts with the offline/air-gapped goal
  for organizations without external IdP reachability) and not something the current PowerShell
  code does today; tracked as a possible future ADR/extension point, not part of this migration.
- **Drop directory auth entirely as out of scope for an open-source project** — rejected: several
  of the project's actual target adopters (banks, enterprises) specifically want directory-gated
  enrollment; removing it would drop a real differentiator versus generic consumer authenticator
  apps (Aegis, 2FAS, Ente Auth) that have no such concept.

## References
- [dartdap — Dart package](https://pub.dev/packages/dartdap)
- [dartdap GitHub — LDAP client for Dart](https://github.com/tj800x/dartdap)
- [LDAP login in Flutter web is not working — dartdap issue #45](https://github.com/wstrange/dartdap/issues/45)
- Direct review of `lib/core/services/ad_service.dart`, `lib/core/services/ad_config.dart`,
  `lib/features/accounts/widgets/ad_auth_dialog.dart` (this session's platform-recovery pass).
