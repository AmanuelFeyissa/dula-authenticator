# ADR-0002: White-Label Branding & Configuration Architecture

## Status
Accepted — implemented (`assets/branding/branding.json`, `lib/core/branding/`).

## Context
The codebase this project grew out of was written for a single deployment, and that deployment's
identity was hardcoded throughout the app rather than confined to a logo file:

- App name and package/bundle identifiers, in the Android Gradle config and the MSIX packaging
  metadata in `pubspec.yaml`.
- Visual identity: a logo asset and a theme color scheme, plus a product name string repeated across
  `main.dart`, `home_screen.dart`, `app_lock_screen.dart`, `add_account_screen.dart`,
  `web/index.html`, and `web/manifest.json`.
- Organizational text: the About dialog hardcoded an organization name and department names.
- A specific third-party SSO/IAM product name was baked into two user-facing strings in
  `app_lock_screen.dart`, instructing the user to go to that product to re-enroll. That is one
  vendor's integration detail, not a general concept, and had no place in a project meant to be
  reused by others.

An open-source project usable by "any organization" cannot ship with someone else's name, logo, and
internal product references baked into compiled strings — every adopter would have to fork and
hand-edit Dart source just to remove another organization's name from their own deployment, which is
exactly the friction open-sourcing is supposed to remove.

Two architectural options exist:
1. **Compile-time flavors** (Flutter's `--dart-define` / flavor mechanism): each deployer bakes
   their branding into their own build. No runtime branding file to protect, but every deployer
   needs a build pipeline.
2. **Runtime branding config**: a single `assets/branding/branding.json` (or similar) read at
   startup, supplying app name, logo asset path, primary/seed color, and organization display
   fields (name, department, support contact) used by the About dialog — with the AD/SSO product
   name field made fully generic ("your enterprise directory system") instead of naming a specific
   vendor.

## Decision
Use a **hybrid**: compile-time flavors for anything that must be fixed per platform build artifact
(app name shown in OS launchers, package/bundle identifiers, app icon — these are baked into the
Android/iOS/Windows/Linux packaging metadata regardless, so there is no avoiding a build step to
change them), plus a **runtime branding config object** (`lib/core/branding/branding_config.dart`,
backed by a JSON asset) for everything the UI displays: app title text, logo widget, theme seed
color, and the About-dialog organization fields. The generic build ships with a neutral default
branding config (placeholder name, placeholder logo, no specific vendor names anywhere), and the
vendor-specific SSO strings are rewritten generically ("your organization's enterprise directory")
with the product name removed entirely rather than moved into config — a per-vendor SSO product name
is not a general concept this project should model.

This means every hardcoded brand string identified above becomes either a compile-time identifier
(package name, MSIX identity) documented in a `docs/BRANDING.md` "how to re-skin this app" guide,
or a field in `branding_config.dart` read via a Riverpod provider, with no source-code edits
required for a new deployer to rebrand.

## Consequences
**Positive:** Any company can rebrand the app (name, logo, color, org info) by editing one JSON
asset and re-running the existing platform build scripts, with no Dart changes. Removes all
third-party product name leakage.

**Negative:** Adds one more layer of indirection (a config-reading provider) to screens that
previously hardcoded strings directly — a small, worthwhile complexity increase for a project whose
entire purpose is being reused by others.

**Risks:** Must audit *all* platform manifests (Android `AndroidManifest.xml`/`build.gradle.kts`,
iOS `Info.plist`, Windows MSIX config, web `manifest.json`/`index.html`) for leftover identifiers
from the original deployment, not just Dart source — package identifiers live in generated platform
artifacts and are easy to miss, and had to be replaced with neutral ones (`com.dulaauth.totp`).

## Alternatives Considered
- **Compile-time-only flavors for everything** — rejected as the sole mechanism because it forces
  every deployer to maintain a Flutter build toolchain just to change a display string or logo,
  which is a much higher bar than editing a JSON file, and works against the "no cell phone /
  restricted office" audience who may only have a pre-built binary to work with.
- **Leave branding hardcoded and rely on forks** — rejected: this was the status quo and is exactly
  the friction open-sourcing is meant to remove; it also risks every fork silently carrying the
  original deployment's name and vendor references forward by omission.

## References
- Findings from direct code review of `lib/features/home/screens/home_screen.dart`,
  `lib/features/auth/screens/app_lock_screen.dart`, `pubspec.yaml` (`msix_config`),
  `android/app/build.gradle.kts` (this session's platform-recovery pass).
