# Branding Guide — Re-skinning Dula Authenticator

Dula Authenticator is white-label by design. Any organization can rebrand it without editing a
single line of Dart. This guide covers what you can change, where, and what you must keep.

This file covers visual/organizational identity only. For security policy and other product
tunables (PIN length, lockout backoff, Argon2id cost, backup file naming, and more), see
[`docs/CONFIGURATION.md`](CONFIGURATION.md) — kept as a separate file and a separate guide because
those changes affect security behavior, not just appearance.

## Quick start: the 60-second rebrand

Everything the UI displays comes from one file: **`assets/branding/branding.json`**.

```json
{
  "appName": "Acme Authenticator",
  "logoAssetPath": "assets/branding/logo.png",
  "primarySeedColorHex": "#1D4ED8",
  "organizationName": "Acme Corporation",
  "organizationDepartment": "Information Security",
  "developerName": "Amanuel Feyissa Kussa"
}
```

1. Replace `assets/branding/logo.png` with your own logo (square PNG, 512×512 or larger,
   transparent background recommended).
2. Edit the fields above.
3. Rebuild: `flutter build <platform>`.

That's it. No source changes, no forking.

### Field reference

| Field | What it controls | Notes |
|---|---|---|
| `appName` | App bar title, lock screen title, window title, About dialog | Keep it short — it appears in constrained UI |
| `logoAssetPath` | Logo on lock screen, app bar, About dialog | Set to `null` to fall back to a built-in shield icon |
| `primarySeedColorHex` | Material 3 color scheme seed + app bar/background | `#RRGGBB` or `#AARRGGBB` |
| `organizationName` | About dialog | Your organization |
| `organizationDepartment` | About dialog | e.g. "IT", "Information Security" |
| `developerName` | About dialog — original author credit | **Must be retained** — see Attribution below |

If `branding.json` is missing or malformed, the app falls back to safe built-in defaults rather
than failing to start — a typo in your branding file will never brick the app.

## Attribution — what you must keep

Dula Authenticator is licensed under **Apache License 2.0** and was created by
**Amanuel Feyissa Kussa**.

You may freely rebrand, modify, redistribute, and deploy it commercially. In exchange, Section 4
of the license requires that you:

- Retain the `LICENSE` and `NOTICE` files in your distribution.
- Retain the original copyright and attribution notices.
- State any significant changes you made to the source.

Practically: **keep the `developerName` field pointing at the original author**, and add your own
organization via `organizationName`/`organizationDepartment` rather than replacing the author
credit. If you want to also credit your own team in the UI, extend the About dialog — don't
overwrite the attribution that's already there.

## Platform-level branding (requires a build step)

Some identifiers are baked into each platform's package metadata by the OS, not read at runtime.
Changing these requires editing platform files and rebuilding — there is no way around this, it's
how the operating systems work.

| Platform | File | What to change |
|---|---|---|
| Android | `android/app/build.gradle.kts` | `namespace`, `applicationId` (e.g. `com.acme.authenticator`) |
| Android | `android/app/src/main/AndroidManifest.xml` | `android:label` |
| Android | `android/app/src/main/kotlin/.../MainActivity.kt` | `package` must match `applicationId` |
| iOS | `ios/Runner/Info.plist` | `CFBundleDisplayName`, `CFBundleName` |
| iOS | `ios/Runner.xcodeproj/project.pbxproj` | `PRODUCT_BUNDLE_IDENTIFIER` |
| Windows | `windows/runner/main.cpp` | Window title, single-instance mutex name |
| Windows | `windows/runner/Runner.rc` | `CompanyName`, `ProductName`, `FileDescription`, `LegalCopyright` |
| Windows | `windows/CMakeLists.txt` | `project()` name, `BINARY_NAME` |
| Web | `web/index.html`, `web/manifest.json` | `<title>`, PWA name, description, theme color |

> **Android note:** if you change `applicationId`, you must move `MainActivity.kt` to a directory
> matching the new package or the app crashes at launch with `ClassNotFoundException`.

### App launcher icons

Launcher icons are generated per-platform, not read from `branding.json`. Add a
`flutter_launcher_icons` block to `pubspec.yaml` pointing at your logo and run
`dart run flutter_launcher_icons`. See the
[flutter_launcher_icons docs](https://pub.dev/packages/flutter_launcher_icons).

### Windows MSIX packaging

No `msix_config` ships by default (the original deployment-specific packaging config was removed). To
build an MSIX installer, add your own block to `pubspec.yaml`:

```yaml
msix_config:
  display_name: Acme Authenticator
  publisher_display_name: Acme Corporation
  identity_name: com.acme.authenticator
  msix_version: 1.0.0.0
  logo_path: assets/branding/logo.png
  install_scope: user
  desktop_shortcut: true
```

## Verifying your rebrand

```bash
flutter analyze
flutter test
flutter build windows --debug   # or your target platform
```

Then launch the app and confirm: window title, lock screen logo and name, and the About dialog
(settings menu → About) all show your branding, with the original author still credited.
