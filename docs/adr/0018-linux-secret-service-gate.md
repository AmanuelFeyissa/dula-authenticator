# ADR-0018: Gate Every Linux Secure-Storage Call Behind a D-Bus Availability Check

## Status
Accepted — supersedes the open item in ADR-0017. Verified in the Linux container in both
directions: no usable keyring → blocking screen; unlocked keyring → gate opens and the full
31-test E2E passes with the gate live in the startup canary.

## Context
ADR-0017 established that on Linux with no Secret Service daemon, a `flutter_secure_storage`
call does not return, throw, or time out — it freezes the whole app. Its follow-up work item was
an `IsolatedSecretStore` routing every `SecretStore` call through a background isolate, on the
theory that the freeze was a Dart-isolate problem.

Before building that, the plugin source was read
(`flutter_secure_storage_linux-3.0.0/linux/include/Secret.hpp`). It calls
`secret_password_storev_sync` and `secret_password_lookupv_sync` — the **synchronous** libsecret
API — directly inside the method-channel handler. Method-channel handlers run on the platform
thread, which on Linux is the GTK main loop. And on Flutter's desktop embedders the Dart UI isolate
is scheduled on that same platform thread. That is the mechanism behind ADR-0017's heartbeat
observation: a Dart `Timer` stopped ticking because the thread that runs Dart timers was inside a
blocking D-Bus call.

This rules out the planned fix. A call issued from a background isolate is still dispatched to the
platform thread to reach the plugin, so it blocks the same thread; the isolate boundary only moves
where the `await` sits, not where the work happens. ADR-0017's own update had already observed
that the isolate-hosted canary "worked but did not fix the freeze" — this ADR records *why*, and
that the reason applies to any isolate-based design, not just the partial one that was tried.

A first version of the gate checked only that `org.freedesktop.secrets` was owned or could be
activated. It did not work: the container test still hung. Diagnosis on the bus showed why:
activation succeeds *instantly* (`StartServiceByName` → `(uint32 1,)`, a `gnome-keyring-daemon
--components=secrets` appears) but the resulting service has **no default collection** —
`ReadAlias default` returns `/`, and `Collections` lists only the in-memory `session` one. The
plugin stores into `SECRET_COLLECTION_DEFAULT`, so the daemon raises a *create/unlock prompt*
(`org.gnome.keyring.SystemPrompter`), and with nobody to answer it the synchronous call blocks. The
freeze was never "no daemon"; it is "a daemon that needs a prompt in a session that has no one to
show it to". A locked login keyring produces the same prompt, so it is the same case.

The design question ADR-0017 deferred — "what does the app do when a secret read times out
mid-flight?" — also changes shape. There is no mid-flight timeout to handle, because a Dart-side
timeout can never fire while the platform thread is blocked. The only safe moment to decide is
*before* the call.

## Decision
1. **Never enter libsecret unless the Secret Service is known to be reachable.**
   `lib/core/security/linux_secret_service_probe.dart` asks the session bus, via a bounded
   `gdbus` (falling back to `dbus-send`) subprocess, whether `org.freedesktop.secrets` has an
   owner; if not, it asks the bus to activate one (`StartServiceByName`, bounded at 10 s). It then
   requires that `ReadAlias default` names a real collection (not `/`) **and** that the
   collection's `Locked` property is `false` — the condition under which the plugin's store call
   returns without a prompt. `dart:io` `Process` is fully asynchronous, so a hung subprocess is
   killed at its timeout and cannot take the platform thread with it. No D-Bus client dependency
   is added for three yes/no questions.
2. **One gate, every call.** `SecretStoreGate` (`lib/core/vault/gated_secret_store.dart`)
   memoises that verdict; `GatedSecretStore` wraps `FlutterSecretStore` and throws
   `SecretStoreUnavailableException` from `read`/`write`/`delete` without touching the backend
   while the gate is closed. `secretStoreProvider` (`lib/core/vault/secret_store_provider.dart`)
   is now the single production store shared by `AuthRepository`, `AccountRepository`, and the
   startup canary, so nothing constructs `FlutterSecretStore` directly any more. The gate is
   installed on Linux only; other platforms get `SecretStoreGate.alwaysOpen`, which costs nothing.
3. **Unreachable is not empty.** `AuthNotifier._checkInitialState` catches
   `SecretStoreUnavailableException` and sets `AuthState.isStorageUnavailable`, leaving
   `isSetupRequired` false. `AppLifecycleWrapper` shows the existing ADR-0004 blocking screen for
   that state exactly as it does for a failed canary. RETRY resets the gate, re-runs the canary, and
   calls `AuthNotifier.retryStartup()`; app resume also resets the gate. A `null` read means "no
   value"; an exception means "unknowable" — the two are never conflated.
4. **Remove `IsolatedSecureStorageProbe`.** It could not help for the reason above, and keeping a
   second mechanism that looks like a fix invites the next contributor to extend it.
5. **Empty-state copy follows enrollment capability.** The home screen's "Scan a QR code to begin"
   hint now reads "Paste a QR image or enter a key to begin" where
   `EnrollmentCapabilities.cameraScanning` is false (ADR-0006) — found while screenshotting the
   Windows build.

## Consequences
**Positive:** On Linux with no usable keyring the app reaches the blocking screen within the
probe's bounds (a few 3 s queries, +10 s if activation is attempted) instead of hanging on a blank
frame, which is the guarantee ADR-0004 promised. The check is a few milliseconds when the daemon is running. The
auth flow can no longer mistake an unreadable vault for a missing one. The freeze's root cause is
now understood and written down, so it will not be re-attacked with another isolate.

**Negative:** A subprocess per gate check (once per launch, plus RETRY/resume) is an unusual
dependency on `gdbus`/`dbus-send` being on `PATH`. If neither exists the verdict is *unknown* and
the gate opens — refusing to run on a possibly-working machine was judged the worse failure — which
reintroduces the freeze only on systems that lack both tools *and* a keyring. A daemon that dies
mid-session is not caught until the next resume or RETRY.

**Risks:** The gate checks the *default* collection because that is what the plugin uses; a
Secret Service implementation that answers `ReadAlias default` incorrectly would be misjudged in
either direction. KWallet's Secret Service bridge has not been tested against it. Upstream, `flutter_secure_storage_linux` should be
using the async libsecret API or a worker thread; that is the real fix and worth an issue.

## Alternatives Considered
- **`IsolatedSecretStore` (ADR-0017's plan)** — rejected: cannot work, per the mechanism above.
- **Add the `dbus` pub package and query the bus in-process** — rejected for now: a new runtime
  dependency, with its own ADR-0007 review, to ask one question a shipped binary already answers.
  Revisit if the subprocess approach proves brittle on real distributions.
- **Patch or vendor the plugin to use `secret_password_storev` (async)** — the correct long-term
  fix, rejected for this pass because it forks a security-sensitive dependency; recorded as the
  upstream item under Risks.
- **Only gate the startup path** — rejected: ADR-0017 found the freeze on the auth read, not the
  canary, precisely because only the canary had been protected. Gating one call site at a time is
  how that happened.

## Verification recipe
Both scenarios run in the `dula-linux-test` container (Ubuntu + Flutter + Xvfb + gnome-keyring),
with the repository mounted read-only and copied inside so the container's `.dart_tool` never
clobbers the host's:

```bash
Xvfb :99 -screen 0 1280x800x24 & export DISPLAY=:99
eval "$(dbus-launch --sh-syntax)"

# No usable keyring: the gate must close and the blocking screen must appear.
flutter test integration_test/linux_no_keyring_test.dart -d linux     --dart-define=DULA_EXPECT_NO_KEYRING=true

# Healthy keyring: the gate must open and the full E2E must pass.
# Exactly ONE daemon, started with the password so it creates and unlocks
# login.keyring, and its control socket exported before anything else runs.
#   - `gnome-keyring-daemon --unlock --start` in one call starts a daemon with
#     NO default collection (ReadAlias default -> '/').
#   - `--unlock` followed by a separate `--start` without exporting
#     GNOME_KEYRING_CONTROL in between starts a SECOND daemon that races the
#     first for org.freedesktop.secrets and only has the keyring as a locked
#     file, so the gate (correctly) reports Locked=true on some runs.
# Both are the trap this ADR guards against, and both were hit while writing it.
eval $(echo -n 'testpass' | gnome-keyring-daemon --unlock --components=secrets 2>&1)
export GNOME_KEYRING_CONTROL
flutter test integration_test/linux_keyring_ok_test.dart -d linux     --dart-define=DULA_EXPECT_KEYRING=true
flutter test integration_test/app_flow_test.dart -d linux
```

## References
- Direct review of `flutter_secure_storage_linux-3.0.0/linux/include/Secret.hpp` (sync libsecret
  calls in the channel handler, `SECRET_COLLECTION_DEFAULT`) and `flutter_secure_storage_linux_plugin.cc`.
- Bus diagnosis in the `dula-linux-test` container (Xvfb + `dbus-launch`, no daemon started):
  `NameHasOwner` → `(false,)`; `StartServiceByName` → `(uint32 1,)` in 0 s; `NameHasOwner` →
  `(true,)`; `Collections` → `[…/collection/session]` only; `ReadAlias default` → `objectpath '/'`.
- ADR-0017 — the heartbeat measurement this explains; ADR-0004 — the guarantee this restores;
  ADR-0006 — the empty-state copy.
- `test/core/vault/gated_secret_store_test.dart`, `test/core/security/linux_secret_service_probe_test.dart`,
  `test/features/auth/auth_notifier_test.dart` ("unreachable credential store"),
  `test/core/widgets/app_lifecycle_wrapper_test.dart`, `test/features/home/home_empty_state_test.dart`.
- `integration_test/linux_no_keyring_test.dart` and `integration_test/linux_keyring_ok_test.dart`
  — the real-platform proofs in both directions, opt-in via `--dart-define=DULA_EXPECT_NO_KEYRING=true`
  / `--dart-define=DULA_EXPECT_KEYRING=true`.
