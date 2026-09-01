# ADR-0017: Linux Secure-Storage Calls Can Freeze the Dart Isolate

## Status
Accepted — partial mitigation implemented; full fix deferred

## Context
ADR-0004 added `SecureStorageCanary.check()` so a missing Linux keyring daemon fails loudly at
startup instead of silently losing writes. Its own Risks section flagged that empirical validation
against a real keyring-less Linux install had not yet been performed.

Phase 7 testing built the project's Linux target for the first time (it had never been scaffolded —
`flutter create --platforms=linux` had apparently never been run despite `flutter build linux`
being documented in CLAUDE.md, ADR-0004, and ADR-0008) and ran the resulting binary under Xvfb
inside a Docker container, with a real D-Bus session and, deliberately, no keyring daemon
registered on it — the realistic version of the scenario ADR-0004 exists for (not the more extreme
case of no D-Bus at all).

The result: `store.write()` (`flutter_secure_storage`'s Linux/libsecret backend) never returned and
never threw. Confirmed with a `Timer.periodic` heartbeat print placed in `main()` — it ticked once,
then stopped entirely for the following 45 seconds, proving the underlying platform-channel call
freezes the whole Dart isolate, not just the awaited `Future`. A working, unlocked keyring in the
same environment resolved the same call correctly and quickly (confirmed via the same instrumented
build), so this is specific to the no-keyring failure path.

This matters because a Dart-level `Future.timeout()` — the obvious fix — cannot help: the timer
that would fire it never runs, because the isolate that would run it is the one that's frozen. TDD
proved this the hard way: a unit test using a `SecretStore` double whose calls never complete
correctly went RED without a timeout and GREEN once one was added (`test/core/security/secure_storage_canary_test.dart`),
but that test necessarily assumes normal async `Future` semantics — it cannot reproduce a platform
channel call that blocks the isolate itself, since the double's "hang" is just a `Completer` that
never completes, which is exactly the case a `.timeout()` *can* solve. Only the real platform
channel call has this property, and the gap here between the unit test and the real environment is
the actual finding of this ADR.

## Decision
1. Add a bounded `.timeout()` around the canary's write/read/delete round trip anyway
   (`lib/core/security/secure_storage_canary.dart`). It is a strict improvement for every failure
   mode where the underlying call actually returns or throws — slow libsecret calls, D-Bus errors
   that do come back, any future situation where the isolate isn't frozen — and it is what the
   existing regression test (correctly) exercises and guards.
2. Do **not** attempt an isolate-based redesign (dispatching the secure-storage check, and
   potentially every secure-storage call, to a background isolate via
   `BackgroundIsolateBinaryMessenger`) as part of this testing pass. That is a materially larger
   change: it would touch `vault_service.dart`, `account_repository.dart`, `backup_service.dart`,
   and any other caller of `SecretStore`, not just the startup canary, and deserves its own design
   and TDD cycle rather than being rushed in under a testing task.
3. Record this as a known, real gap rather than silently shipping the (still-useful) timeout as if
   it fully closed the risk ADR-0004 flagged. The practical exposure: on Linux, with no keyring
   daemon registered, the app does not currently show ADR-0004's intended blocking error screen —
   it hangs indefinitely on a blank/loading frame instead. That is a worse user experience than the
   error screen would have been, though not a security regression (no credential is silently
   accepted or lost; nothing is written).

## Consequences
**Positive:** The timeout fix ships now with a real regression test, closing the gap for every
failure mode that isn't this specific isolate-freeze. The freeze itself is documented precisely
enough (reproduction steps, confirmed cause) that whoever picks up the follow-up work doesn't have
to rediscover it.

**Negative:** ADR-0004's "fail loudly" guarantee is not yet fully met for the single most likely
real-world Linux failure case (keyring daemon simply not installed). Until the follow-up ships,
that class of Linux deployment sees a hang, not a message telling them what to do about it.

**Risks:** The eventual fix needs its own investigation into whether `flutter_secure_storage`'s
Linux implementation itself is issuing a synchronous/blocking D-Bus call where it should be async
(possibly worth reporting upstream), independent of whatever isolate-boundary workaround this app
adds on its own side.

## Alternatives Considered
- **Ship the timeout fix and call the risk closed** — rejected: verified directly (heartbeat test)
  that it does not fix the real-world case; documenting a false sense of closure would be worse than
  documenting the actual gap.
- **Attempt the full isolate-based fix in this same session** — rejected: the blast radius (every
  `SecretStore` caller) and the need for its own TDD cycle make it a poor fit for a testing pass;
  doing it hastily risks a worse outcome than deferring it deliberately.

## References
- ADR-0004 (Cross-Platform Secure Storage & the Linux Keyring Dependency) — the risk this ADR
  resolves the validation task for, and partially mitigates.
- Direct testing of `build/linux/x64/debug/bundle/dula_auth` under Xvfb + `dbus-launch`, with and
  without `gnome-keyring-daemon --start --components=secrets,pkcs11,ssh`, inside a
  `ghcr.io/cirruslabs/flutter` container.
- `test/core/security/secure_storage_canary_test.dart` — `_HangingSecretStore` test, documents the
  fixed case; explicitly does not (cannot) cover the isolate-freeze case.
