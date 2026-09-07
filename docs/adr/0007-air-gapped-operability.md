# ADR-0007: Air-Gapped Operability & Zero-Telemetry Stance

## Status
Partially implemented. The zero-telemetry rule is in force and verified — the app makes no outbound
network calls, and the now-unused Android `INTERNET` permission was removed. The release-engineering
half (SBOM, signed releases, a documented offline build path) is still outstanding.

## Context
A second explicit target use case is fully air-gapped networks: no outbound internet access at
all, ever, by policy. Research into air-gapped software distribution practice (Sonatype's
air-gapped governance guidance, OpenSSF's Zarf tooling writeups, Replicated's air-gap distribution
docs) converges on the same requirements regardless of ecosystem: **reproducible, deterministic
build artifacts**; **offline signing and verification** (SHA-256 checksums plus GPG signatures);
**a Software Bill of Materials (SBOM)** covering every dependency, generated on the connected side
before artifacts cross the air gap; and **no runtime dependency on reaching an external
registry or service** once deployed.

Auditing the current app against these requirements:
- **Runtime network calls**: none exist today except the (Windows-only, PowerShell-based) AD check,
  which only ever talks to the deployer's own domain controller — never an external service. No
  telemetry, crash reporting, or analytics SDK is present anywhere in `pubspec.yaml`. This is
  already air-gap-compatible behavior and should be preserved as an explicit, tested guarantee
  rather than an accident of the current feature set — future contributions (e.g. crash reporting
  "to help us improve the app") must be rejected or made strictly opt-in and off by default,
  because silently adding a phone-home call would break the air-gapped use case for every existing
  adopter without their explicit knowledge.
- **Build-time network dependency**: real and currently unaddressed. `flutter pub get` and
  `flutter build` both fetch from `pub.dev` (and, for Android, Gradle fetches from Google's/Maven
  Central's repositories) by default — an air-gapped build machine cannot do this unless the pub
  cache and Gradle dependencies are pre-vendored and transferred across the air gap ahead of time.
- **No SBOM or signed-release process exists today.**

## Decision
1. **Codify a "no telemetry, ever, by default" rule** as a hard project constraint, stated in
   `CLAUDE.md` and enforced by the security-review skill introduced alongside this migration (see
   the governance ADR) — any PR adding an analytics/crash-reporting/telemetry SDK, or any outbound
   network call not explicitly configured by the deployer (e.g. the opt-in LDAP directory-auth
   provider from ADR-0003), must be rejected by default and would require its own ADR to justify
   before merging.
2. Publish a `docs/AIRGAPPED_BUILD.md` runbook documenting: how to pre-fetch the full `pub` and
   platform-native (Gradle/CocoaPods/NuGet-equivalent) dependency set on a connected machine
   (`flutter pub get` + a documented Gradle offline-cache export step), how to transfer that cache
   across the air gap, and how to build fully offline (`flutter build ... --offline` plus a
   Gradle `--offline` flag) from the transferred cache — this is a documentation and tooling task,
   not a code change to the app itself.
3. Add a release pipeline step that generates a **CycloneDX SBOM** for every tagged release (Dart
   has first-party tooling support for this via `dart pub deps --json` plus a CycloneDX converter,
   or the `cyclonedx` Dart package) and publishes SHA-256 checksums plus a detached GPG signature
   alongside every release artifact, so an air-gapped operator can verify integrity and provenance
   of a binary carried across the air gap without needing network access to do so.
4. Explicitly scope **out** of this migration: mirroring a full offline package registry (e.g. a
   Zarf-style bundle or a self-hosted pub mirror) — that is an operational choice for adopters with
   their own infrastructure, and the project's job is to make offline building *possible and
   documented*, not to run infrastructure for every adopter.

## Consequences
**Positive:** Air-gapped adopters get a real, documented, testable path to build and verify the app
without any network access at deployment time — matching this project's most demanding target use
case. Zero-telemetry is enforced as policy, not left implicit, which also matters for
privacy-sensitive adopters that are not literally air-gapped.

**Negative:** Adds release-process overhead (SBOM generation, signing) that the project does not
have today; adds a documentation maintenance burden (the offline-build runbook must be kept in sync
with Flutter/Gradle version bumps).

**Risks:** The offline-build runbook must be validated end-to-end (build on a genuinely
network-isolated VM) before being published as a guarantee, not just written from documentation —
tracked as a Phase 5 validation task, not assumed to work from research alone.

## Alternatives Considered
- **No formal air-gapped build story, just "it happens to have no telemetry"** — rejected: matches
  today's accidental state, not the explicit "air-gapped networks" requirement, and gives adopters
  no actual guidance for the hardest part (offline dependency resolution).
- **Adopt a full air-gap bundling tool (e.g. Zarf) as a project dependency** — rejected as
  disproportionate: Zarf and similar tools solve a broader Kubernetes/infrastructure air-gap
  problem this desktop/mobile app doesn't have; a documented manual pub/Gradle offline-cache
  process is sufficient and keeps the project's own dependency surface smaller.

## References
- [Software Governance in Air-Gapped Environments — Sonatype](https://www.sonatype.com/blog/mastering-software-governance-in-air-gapped-critical-mission-environments)
- [Air-Gapped Deployment SBOM: Securing Software in Isolated Environments](https://hoop.dev/blog/air-gapped-deployment-sbom-securing-software-in-isolated-environments)
- [Simplifying DevSecOps in Air-Gapped Environments with Zarf — OpenSSF](https://openssf.org/blog/2025/11/18/tech-talk-recap-simplifying-devsecops-in-air-gapped-environments-with-zarf/)
- [Air-Gapped Deployments: How to Deploy to Servers Without Internet Access — Semaphore](https://semaphore.io/blog/air-gapped-deployments-how-to-deploy-to-servers-without-internet-access-complete-guide)
- Direct review of `pubspec.yaml` (no telemetry/analytics dependencies present today).
