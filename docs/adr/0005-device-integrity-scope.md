# ADR-0005: Device-Integrity & Screen-Privacy Feature Scope

## Status
Accepted — implemented. Verified on a physical Android device: the compromise screen fires on a
developer-mode device, and screenshot blocking is strong enough that `adb screencap` returns
nothing while the app is in the foreground.

## Context
`AppLifecycleWrapper` currently provides two protective features, both implemented via
mobile-only plugins:

- **Root/jailbreak detection** via `root_checker_plus`, which shows a hard "SECURITY ALERT" block
  screen and exits the app.
- **Screenshot prevention / privacy blur** via `screen_protector`.

Pub.dev's published platform-support tables (verified directly, not inferred) confirm both
packages support **Android and iOS only** — no Windows, macOS, Linux, or Web implementation exists
for either. The current code already handles this correctly for the *root-detection* path (gated
to `TargetPlatform.android` / `TargetPlatform.iOS` after this session's web-compatibility fixes)
and for *screen-protector* it is already wrapped in a bare `try/catch` that silently no-ops on
unsupported platforms.

The open question this ADR resolves is not "how do we fix a bug" — there is none, the code already
degrades safely — but **what to document and whether to pursue equivalents on Linux/Windows/macOS**,
since a security-focused open-source project should be explicit about what protection exists on
each platform rather than let users assume parity that isn't there.

Linux desktop equivalents exist in principle (compositor-level screenshot-blocking is
window-manager-specific and unreliable across GNOME/KDE/i3/sway; there is no single cross-desktop
API comparable to Android's `FLAG_SECURE` or iOS's screen-recording detection), but building and
maintaining a per-desktop-environment implementation is a materially larger, lower-value effort
than the rest of this migration, and would only work reliably on a subset of Linux desktops anyway.

## Decision
1. Keep root/jailbreak detection and screenshot/privacy-blur as **Android/iOS-only features**,
   explicitly documented as such (not silently degraded) in a new `docs/SECURITY_MODEL.md` that
   states, per platform, exactly which protections are active — this is the actual deliverable of
   this ADR: honest documentation of a real platform gap, not new code.
2. On Linux, Windows, and macOS, the existing lifecycle-based "privacy overlay" (blurring the
   account list behind a solid cover when the app loses focus — implemented directly in Dart in
   `AppLifecycleWrapper`, not via a plugin) already provides a same-process mitigation for
   shoulder-surfing during app-switching, and is kept as the desktop-tier privacy protection.
   This is *not* equivalent to OS-level screenshot prevention and must not be described as such in
   documentation.
3. Root/compromise detection on desktop platforms is explicitly **out of scope** for this
   migration: unlike mobile root/jailbreak detection (a well-understood, purpose-built check),
   "is this desktop OS compromised" is a fundamentally different and much larger problem
   (endpoint detection and response territory) that this project should not claim to solve.

## Consequences
**Positive:** No wasted engineering effort chasing unreliable per-desktop-environment screenshot
blocking; users and adopting IT teams get accurate, platform-specific security documentation
instead of an implied (and false) guarantee of parity across platforms.

**Negative:** Desktop users (including the Windows build that was this project's original target)
get no OS-level screenshot prevention or compromise detection — this was already true before this
migration and is not a regression, but it is worth stating plainly since it may surprise adopters
coming from mobile-first authenticator apps.

**Risks:** None introduced — this ADR changes documentation and scope framing, not behavior.

## Alternatives Considered
- **Build a Linux screenshot-prevention plugin** — rejected as disproportionate effort for
  inconsistent, desktop-environment-dependent results; revisit only if a specific adopter sponsors
  the work for a specific desktop environment.
- **Silently say nothing and let users assume parity** — rejected: false security assumptions are
  worse than no assumptions for a security tool.

## References
- [screen_protector — pub.dev platform support](https://pub.dev/packages/screen_protector)
  (confirmed Android/iOS only)
- [root_checker_plus — pub.dev platform support](https://pub.dev/packages/root_checker_plus)
  (confirmed Android/iOS only; Web/Windows/macOS/Linux explicitly unsupported)
- Direct review of `lib/core/widgets/app_lifecycle_wrapper.dart` (this session's web-compatibility
  fix pass, which already gates these calls by platform).
