# Dependency License Audit

Performed as part of Phase 1 of the open-source migration (see `docs/adr/0001-license-selection.md`).
Every direct runtime and dev dependency in `pubspec.yaml` was checked against its actual shipped
`LICENSE` file in the local pub cache (not just the pub.dev badge, which can lag).

| Package | License | Compatible with Apache-2.0 redistribution? |
|---|---|---|
| cupertino_icons | MIT | Yes |
| flutter_secure_storage | BSD-3-Clause | Yes |
| flutter_riverpod | MIT | Yes |
| hooks_riverpod | MIT | Yes |
| flutter_hooks | MIT | Yes |
| local_auth | BSD-3-Clause (Flutter Authors) | Yes |
| crypto | BSD-3-Clause (Dart project) | Yes |
| base32 | MIT | Yes |
| screen_protector | Apache-2.0 | Yes |
| mobile_scanner | BSD-3-Clause | Yes |
| go_router | BSD-3-Clause (Flutter Authors) | Yes |
| shared_preferences | BSD-3-Clause (Flutter Authors) | Yes |
| zxing2 | BSD-3-Clause | Yes |
| image | MIT | Yes |
| cross_file | BSD-3-Clause (Flutter Authors) | Yes |
| pasteboard | Apache-2.0 | Yes |
| super_drag_and_drop | MIT | Yes |
| encrypt | BSD-3-Clause | Yes |
| root_checker_plus | MIT-style permissive | Yes |
| dartdap | BSD-3-Clause | Yes |
| flutter_lints (dev) | BSD-3-Clause (Flutter Authors) | Yes |
| flutter_launcher_icons (dev) | MIT | Yes |
| msix (dev) | MIT | Yes |

## Result

**No blockers.** Every direct dependency uses a permissive license (MIT, BSD-3-Clause, or
Apache-2.0) with no copyleft obligations, so Apache-2.0 project licensing (ADR-0001) is clear to
proceed for all currently-used dependencies.

## Ongoing obligation

This audit covers dependencies as of this migration. Per the `security-review-mfa` skill, any PR
adding a new dependency should re-check its license before merging — this is a one-time snapshot,
not a standing guarantee for future dependency additions. Transitive dependencies were not
individually audited in this pass (all are pulled in by the above permissively-licensed direct
dependencies from the standard Flutter/Dart package ecosystem, which does not typically carry
copyleft transitive dependencies, but a full transitive audit is recommended before the first
public release as a Phase 7 task).
