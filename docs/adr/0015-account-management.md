# ADR-0015: Account Management — Tags, Favorites, Ordering, Search, Edit, Corrupt-Account Isolation

## Status
**Accepted — implemented.**

Delivered in `lib/core/models/otp_account.dart` (`tags`, `isFavorite`, transient `loadError`
fields), `lib/core/repositories/account_repository.dart` (per-account decrypt isolation,
`reorderAccounts`), `lib/features/home/providers/home_provider.dart` (`updateAccount`,
`toggleFavorite`, `setTags`, `reorder`), a rewritten `lib/features/home/screens/home_screen.dart`
(search, tag/favorite filter chips, drag-reorder, corrupted-account card), and
`lib/features/accounts/screens/add_account_screen.dart` (edit mode via an optional `existing`
parameter). 279 unit tests and 31 end-to-end tests pass (was 264 / 25 before this phase).

What shipped against the decision below, in order:

1–2. **Tags and favorites** — done exactly as decided: `tags: List<String>` (default `[]`),
   `isFavorite: bool` (default `false`), both filtered via chips in the app bar area rather than
   sorted automatically. One refinement made during implementation: the favorite field's doc
   comment originally said "pinned to the top of the list," which would have fought manual
   drag-reorder (item 3) — corrected to "a filter, not an automatic sort" before any code depended
   on the wrong reading.
3. **No explicit sort field** — done; `AccountRepository.reorderAccounts(orderedIds)` rewrites the
   stored array to match the given order and refuses (returns `false`, changes nothing) unless
   `orderedIds` names every currently-stored account exactly once, so a partial or malformed order
   can never silently drop an account.
4. **No format-version bump** — done; verified by a dedicated test asserting a stored record with
   neither field present still loads with the documented defaults.
5. **Search** — done as a pure `HomeScreen` filter over `issuer`, `accountName`, and `tags`.
6. **Edit reuses `AddAccountScreen`** — done via an optional `existing: OtpAccount?` parameter;
   the QR scan/paste/drag-drop entry paths are hidden in edit mode since there is nothing to scan
   when editing text fields already on screen.
7. **Corrupt-account isolation** — done. `AccountRepository.getAccounts` no longer throws
   `VaultDecryptionException` (the class is removed); a decrypt failure is reported per-account via
   the new `loadError` field instead. `HomeScreen` renders a corrupted account as a distinct,
   minimal, still-deletable card. Both existing tests that asserted the old throwing behavior were
   rewritten to assert the new isolation contract rather than left broken, and a new test proves
   one corrupted account among several does not block the others from loading.

One implementation-time finding beyond the decisions above: reordering a filtered or searched
view has no unambiguous mapping back onto the full stored array (which item lands where?), so
`HomeScreen` disables drag-reorder — falling back to a plain, non-draggable list — whenever a
search or filter is active, and only offers `ReorderableListView` against the unfiltered list.
This was not anticipated in the original decision and is recorded here as the actual behavior.

Two testing notes:

- A real end-to-end interaction was found and fixed during this phase: `WidgetTester.drag()` does
  not reliably register as a `ReorderableListView` reorder gesture — it needs a held pointer with
  staged `moveBy` calls, the same pattern Flutter's own reorderable-list tests use. A single
  instantaneous drag silently did nothing.
- The corrupted-account deletion end-to-end test needed a short real-time wait (not just widget
  frames) before its out-of-band verification read, to avoid a write/read timing race against
  Windows' native secure-storage backend between the app's own write and a second, independently
  constructed `AccountRepository` reading the same file immediately afterward. The delete itself —
  confirmed correct by the pre-existing, timing-independent repository unit tests — was never in
  question; this was specifically about two separate storage-plugin instances observing the same
  file from outside the app's own read/write ordering.

## Context

## Context
Every phase so far has treated the account list as a flat, unordered, add/delete-only collection.
That was adequate at ten accounts; it stops being adequate well before a hundred, which is a
realistic count for anyone who has migrated in bulk via ADR-0013's import path. Direct review of
`lib/features/home/screens/home_screen.dart` and `lib/core/repositories/account_repository.dart`
in this session found five concrete gaps:

1. **No search.** `HomeScreen` renders every account in a single `ListView.builder` with no
   filter. Past a few dozen accounts, finding one means scrolling.
2. **No grouping.** There is no way to separate "work" accounts from "personal" ones, or from the
   handful a user actually reaches for daily.
3. **No manual ordering.** Accounts render in whatever order `AccountRepository.getAccounts`
   returns them — the order they were added, with no way to put frequently-used ones first.
4. **No edit.** `AddAccountScreen` only creates. Fixing a mistyped issuer, or a `digits`/`period`
   value that turned out wrong, means deleting the account and re-enrolling it from scratch —
   which is not always possible (the original QR code may be long gone).
5. **One corrupt account takes down the whole list.** `AccountRepository.getAccounts` throws
   `VaultDecryptionException` on the *first* secret that fails to decrypt (line 57), which means a
   single tampered or corrupted record makes every other account unreachable too — the opposite of
   "isolate the damage," and a serious usability regression for something that ADR-0013's fuzz
   testing concern says will eventually happen to *someone's* vault.

Research into comparable open-source authenticators' organization model, to avoid inventing
something bespoke:
- **Aegis** models this as `groups`: each entry carries a list of group UUIDs, so an entry can
  belong to more than one group at once (multi-membership), and `ImportSourceDetector`/
  `AegisImport` (ADR-0013) already ignores that field on import since this app had no equivalent.
- **2FAS** models a single `groupId` per service (one folder per account, not multiple).
- Multi-membership (Aegis's model) is strictly more expressive than single-folder (2FAS's) at
  comparable implementation cost — a single-selection UI can be built on top of multi-membership
  data trivially, but not the reverse — so building on the more expressive model costs nothing now
  and avoids a data-model migration if multi-tag support is ever wanted later.

## Decision

1. **Tags, not a single folder field.** `OtpAccount` gains `List<String> tags` (freeform,
   user-created, default `[]`). The UI presents these as "folders" via a single-select filter chip
   row (tap a tag to show only accounts carrying it, tap again to clear) — matching the mental
   model most users expect from "folders" — while the underlying data model allows an account to
   carry more than one tag, matching Aegis's more expressive model at no extra implementation cost.
2. **Favorites are a plain boolean.** `OtpAccount` gains `bool isFavorite` (default `false`). No
   separate "favorites" collection — it is a filter over the same list, exactly like a tag, so it
   does not need its own storage or its own code path.
3. **No explicit sort-order field.** The persisted order of the `vault_accounts` JSON array *is*
   the account order — drag-reorder rewrites that array via the existing
   `AccountRepository`/`VaultService` save path, exactly as `updateAccount` and `deleteAccount`
   already do. An explicit `sortOrder: int` field was considered and rejected (see Alternatives):
   it would have to be kept in sync with array position for no benefit, since nothing else needs
   to reference an account by position.
4. **No vault format-version bump.** `OtpAccount.fromMap` already defaults every field a stored
   record lacks (see the existing `?? 6`, `?? 0`, `OtpType.fromName(null)` pattern for
   `digits`/`period`/`type`); `tags` defaults to `[]` and `isFavorite` defaults to `false` under
   the same mechanism. This is consistent with how every previous account-shape addition
   (`type`, `digits`, `period`, `algorithm`, `counter` in ADR-0012) was handled — only the
   *cryptographic envelope* bumps `VaultMeta.currentVersion` (ADR-0010), not the account shape
   inside it. This is a fresh build with no v1 data regardless (per the project's standing
   instruction), so there is no existing installation to consider anyway.
5. **Search is a pure UI-layer filter** — case-insensitive substring match over `issuer`,
   `accountName`, and `tags` — computed from the already-loaded, already-decrypted account list.
   No storage or provider-shape change; it is state local to `HomeScreen`.
6. **Edit reuses `AddAccountScreen`, in an edit mode, rather than a second form.** The screen
   accepts an optional `existing: OtpAccount?`; when present, every field is pre-filled, the QR
   scanner/paste/drag-drop entry paths are hidden (there is nothing to scan when editing text
   fields), and saving calls `AccountRepository.updateAccount` instead of `addAccount`. One form
   to keep in sync with `OtpUri`'s parameter set, not two.
7. **Corrupt-account isolation.** `AccountRepository.getAccounts` no longer throws on the first
   decryption failure. Each account is decrypted independently; one that fails authentication is
   returned with its ciphertext left in `secret` and a new transient (never persisted, never
   round-tripped through `toMap`/`fromMap`) `String? loadError` field set to a human-readable
   reason. `HomeScreen`'s `_AccountCard` already has an "Invalid secret" error presentation for a
   `FormatException` from `generateCode()` (ADR-0012) — it is extended to check `loadError` first,
   so a corrupted account renders as a clearly-marked, deletable row instead of a
   `VaultDecryptionException` that blanks the whole screen. A corrupted account (identified by
   `loadError != null`) is excluded from backup export (`BackupExportScreen`) and from
   `ImportMerge`'s duplicate matching, since neither operation can meaningfully act on a secret
   that is not actually plaintext.

## Consequences
**Positive:** The account list scales past the size any of the previous phases assumed. Fixing a
mistyped account no longer requires re-enrollment. A single corrupted record — the exact failure
mode ADR-0013's own Risks section flags as inevitable given fuzzable import input — no longer
takes the rest of the vault down with it.

**Negative:** `_AccountCard` and `HomeScreen` grow more state (search query, active tag filter,
edit navigation) and more render branches (corrupted vs. normal, favorite vs. not). `OtpAccount`
gains two fields every existing call site that constructs one (tests, importers) is unaffected by,
since both default — but every future account-shape review has two more fields to reason about.

**Risks:** Drag-reorder writing the whole account array on every drop is O(n) per reorder, which
is fine at realistic list sizes (hundreds, not thousands) but would need revisiting if this app
ever needed to support truly large lists. The corrupt-account isolation change touches
`AccountRepository.getAccounts`, which is exercised by every existing test and screen that reads
the account list — regression risk is real and is why this ships with full unit coverage of the
new isolation behavior plus the existing suite kept green throughout, not bolted on after.

## Alternatives Considered
- **A single `folder: String?` field instead of `tags: List<String>`** — simpler, and closer to
  2FAS's model, but strictly less expressive for no implementation savings (a single-select filter
  UI is trivial to build over multi-membership data; the reverse would require a data migration
  later). Rejected in favor of the more expressive model.
- **An explicit `sortOrder: int` field** — considered so accounts could be sorted without relying
  on array position, but nothing in this app needs to reference an account's position independent
  of the array itself, and keeping a redundant field in sync on every insert/delete/reorder is
  exactly the kind of bug source ADR-0010's "no unnecessary state" philosophy already avoids
  elsewhere. Rejected.
- **A separate "favorites" list/table** — rejected as unnecessary indirection; a boolean filtered
  client-side does the same job with no extra storage shape.
- **Keep `VaultDecryptionException` thrown, but catch it in the UI layer per-account** — would
  require the repository to expose per-account decrypt state some other way (e.g. returning a
  result type instead of a plain list), which is a larger interface change than adding one
  transient field to the existing model. Rejected in favor of the smaller, additive change.

## References
- [Aegis vault format — `groups`](https://github.com/beemdevelopment/Aegis/blob/master/docs/vault.md)
  (multi-membership group model), reviewed in ADR-0013.
- Direct review of `lib/features/home/screens/home_screen.dart`,
  `lib/core/repositories/account_repository.dart`,
  `lib/features/accounts/screens/add_account_screen.dart` (this session).
