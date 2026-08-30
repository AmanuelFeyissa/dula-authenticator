# ADR-0006: QR-Less Enrollment Parity for No-Camera / Air-Gapped Offices

## Status
Proposed

## Context
One of the four explicit target use cases for this project is offices that ban personal phones and
sites that restrict cameras (many bank branches, secure government facilities, air-gapped labs).
An authenticator whose *only* enrollment path is "scan a QR code with a camera" would be unusable
there by definition — the enrollment flow itself needs a camera-free path, on every platform, not
just desktop.

Auditing the current app and researching comparable open-source authenticators (Aegis, 2FAS, Ente
Auth) confirms manual/no-camera enrollment is table stakes in this space, and the current codebase
already implements three camera-free paths on desktop in `add_account_screen.dart`:
manual secret-key text entry, drag-and-drop of a QR image file, and clipboard image paste (decoded
locally via `zxing2` — no network call). These are gated to
`!kIsWeb && (windows || macOS || linux)` today.

Two gaps were found during this review:
1. **`mobile_scanner`'s own published platform-support table lists Linux and Windows as
   unsupported** for camera scanning. The current UI shows the "Scan QR Code with Camera" button
   unconditionally on every platform, including Windows — meaning on the very platform this project
   originally shipped for, that button may never have worked, and nobody would necessarily notice
   in a bank office where cameras are restricted and manual entry / image paste is the natural
   workflow anyway. This needs empirical verification (does the currently-installed `mobile_scanner`
   version actually work on Windows?), not an assumption in either direction.
2. **Clipboard image paste and drag-and-drop are only offered on desktop**, not mobile — but a
   no-camera-office user on Android/iOS today has *only* manual secret-key entry, no image-import
   fallback, even though most mobile OSes support copying an image to the clipboard from a
   received file/screenshot. This is a real enrollment-parity gap on the mobile side, not a
   desktop one.

## Decision
1. Gate the "Scan QR Code with Camera" button by actual platform capability
   (`!kIsWeb && (android || iOS || macOS) || kIsWeb`, matching `mobile_scanner`'s real support
   matrix) instead of showing it unconditionally — verified empirically against the installed
   `mobile_scanner` version as a Phase 4 task before the gating logic is finalized, since pub.dev's
   table and a specific pinned version can, in principle, diverge.
2. Extend clipboard-image-paste (already implemented and network-free via `zxing2` local decoding)
   to Android and iOS, since `Pasteboard.image` is not inherently desktop-only — this closes the
   mobile no-camera gap identified above.
3. Treat **manual secret-key entry as the one guaranteed-available enrollment path on every
   platform**, and make sure the UI never implies a camera is required (e.g. no "point your camera
   at the code" language without an equally prominent manual-entry option) — this is a UX
   requirement, not just a technical one, since a no-camera office's users still need to be told
   confidently that they can enroll without one.
4. Document, in `docs/SECURITY_MODEL.md` alongside ADR-0005, the per-platform enrollment-method
   matrix (camera scan / image import / clipboard paste / manual entry, per platform) so IT teams
   deploying to a no-camera site know exactly what will and won't be available before rollout.

## Consequences
**Positive:** Every platform has at least one, and on most platforms multiple, camera-free
enrollment paths — the actual requirement behind "offices that don't allow cell phones." Removes a
misleading always-visible camera button on platforms where it may not function.

**Negative:** Slightly more conditional UI logic in `add_account_screen.dart`; requires new manual
testing on real Android/iOS devices for the extended clipboard-paste path.

**Risks:** None security-relevant — this is a UX/availability correctness fix, not a change to how
secrets are stored or transmitted (all decoding already happens locally, no network calls, in both
today's and the proposed implementation).

## Alternatives Considered
- **Leave the camera button visible everywhere regardless of actual support** — rejected: actively
  misleading in a no-camera-office context, where users need confidence that alternatives exist and
  work, not a button that silently does nothing on their platform.
- **Drop camera scanning entirely and go manual-only** — rejected: camera scanning is the fastest,
  most error-free enrollment method where cameras *are* allowed (the common case for most adopters,
  who are not all in restricted offices), so removing it would regress the majority use case to fix
  a minority one that's already solvable by gating instead of removing.

## References
- [mobile_scanner — pub.dev platform support table](https://pub.dev/packages/mobile_scanner)
  (confirmed Linux/Windows unsupported for camera scanning)
- Direct review of `lib/features/accounts/screens/add_account_screen.dart` (existing
  drag-and-drop/paste/manual-entry implementation and current platform gating).
