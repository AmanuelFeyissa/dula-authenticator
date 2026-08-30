# ADR-0008: Linux Packaging & Distribution Formats

## Status
Proposed

## Context
The project needs a real Linux distribution story, not just a Linux *build* — a build artifact
sitting in `build/linux/` is not something an IT team can hand to end users or provision onto
kiosk machines. Research into current (2026) Linux packaging practice identifies three realistic
formats, each with different trade-offs directly relevant to this project's target use cases:

- **Flatpak**: the strongest general-purpose Linux desktop format in 2026 by adoption and
  sandboxing quality (Flathub passed 3,200 apps / 433M downloads in 2025), with genuine
  cross-distro sandboxing via Bubblewrap. Flathub itself is open-source and self-hostable, but
  installing a Flatpak still requires the `flatpak` runtime and (for the common case) reaching
  Flathub's servers — relevant for air-gapped sites, since a Flatpak *bundle* file (`.flatpak`,
  single-file, offline-installable) is possible but less commonly documented than the Flathub-store
  workflow.
- **Snap**: rejected outright — while `snapd`/`snapcraft` tooling is open-source, the Snap Store
  backend is closed-source and Canonical-run with no ability to self-host or fork an independent
  store, which is a poor fit for an open-source project whose adopters may specifically want to
  avoid vendor lock-in to a single company's infrastructure (a real concern already raised by this
  project's air-gapped/regulated target audience).
- **AppImage**: single portable executable file, no installation step, no package manager or
  network access required to run it — the closest match to "copy this file across the air gap on a
  USB drive and run it," with the trade-off that it has no built-in sandboxing and no auto-update
  mechanism (both are actually acceptable, even desirable, constraints for an air-gapped/hardened
  deployment where auto-update-from-the-internet is not wanted anyway).
- **.deb / .rpm**: native package-manager formats for Debian/Ubuntu and Fedora/RHEL-family
  distributions respectively — the format most enterprise Linux IT teams already have tooling and
  policy around (internal package mirrors, patch management), which matters for adopters who want
  to fold this app into an existing managed-Linux-fleet process rather than distribute a standalone
  binary.

## Decision
Ship three formats, in this priority order:

1. **AppImage** as the primary, always-available format — matches the air-gapped "single file,
   copy it over, run it, no install step, no network" requirement most directly, and requires the
   least new tooling (a documented `appimagetool` packaging step in CI).
2. **.deb and .rpm** as native-package options for IT teams that want managed-fleet distribution
   through their own internal repositories — built via a documented, scripted packaging step (e.g.
   `dpkg-deb`/`rpmbuild` wrapping the same Flutter Linux build output), not a separate app rewrite.
3. **Flatpak (Flathub listing) as a stretch goal**, explicitly deferred out of the initial
   open-source migration scope — valuable for reaching general desktop-Linux users who prefer
   Flathub, but not required for any of the four target use cases (any company / air-gapped / no
   phones / Linux) this migration is actually solving for, and Flathub's review/publishing process
   is a non-trivial ongoing commitment better taken on after the project has an established
   contributor base.
4. **Snap is explicitly out of scope, permanently** (not just deferred) — the closed Snap Store
   backend conflicts with this project's open-source and self-hostable-infrastructure goals.

All three initial formats are built from the same Flutter Linux build output (`flutter build
linux`), which this session already validated compiles cleanly (see the platform-recovery session
this migration follows) — packaging is a wrapping step around an already-working build, not new
application code.

## Consequences
**Positive:** Air-gapped/kiosk deployers get the single-file AppImage they actually need; regular
enterprise Linux IT teams get the .deb/.rpm formats their existing tooling expects; no dependency
on Canonical's closed Snap Store infrastructure.

**Negative:** Three packaging pipelines to maintain in CI instead of one; Flatpak/Flathub users (a
real, sizeable audience per the research) are not served in the initial release.

**Risks:** AppImage's lack of a sandbox means it inherits whatever OS-level permissions the running
user has — no different from running any other native Linux binary directly, but worth stating
explicitly in `docs/SECURITY_MODEL.md` (see ADR-0005) alongside the platform-by-platform protection
matrix, so it isn't assumed to have Flatpak-equivalent sandboxing.

## Alternatives Considered
- **Flatpak-only** — rejected as the sole format: best general-purpose choice, but the
  Flathub-centric installation workflow is the weakest fit for the air-gapped use case that most
  distinguishes this project's requirements from a typical consumer Linux app.
- **Snap** — rejected per Context above (closed store backend).
- **Source-only distribution ("just `flutter build linux` yourself")** — rejected: contradicts the
  goal of being usable by "any company," many of whom do not have Flutter toolchain expertise
  in-house and need a ready-to-run artifact.

## References
- [Build and release a Linux app to the Snap Store — Flutter docs](https://docs.flutter.dev/deployment/linux)
- [Linux Packaging Formats: Deb, RPM, Flatpak, Snap & AppImage](https://daily.dev/posts/linux-packaging-formats-deb-rpm-flatpak-snap-appimage-apkdn6gmm)
- [Flatpak vs Snap vs AppImage: which Linux package format should you use?](https://botmonster.com/self-hosting/flatpak-vs-snap-vs-appimage-definitive-linux-packaging-comparison/)
- [Snap vs Flatpak vs AppImage: Choosing the Right Universal Package on Linux](https://www.pudn.club/linux/snap-vs-flatpak-vs-appimage-choosing-the-right-universal-package-on-linux/)
