---
name: adr-record
description: Use when a change touches architecture, a security boundary, a cross-platform behavior difference, or reverses a prior decision in docs/adr/ - drafts a properly numbered ADR before or alongside the code change.
---

# ADR Record

This repository records every architecture-level decision as an Architecture Decision Record (ADR)
under `docs/adr/`, numbered sequentially (`0001-...md`, `0002-...md`, ...). See ADR-0009 for why
this practice exists: without it, a contributor unfamiliar with the project's history can
accidentally "simplify" away a deliberate decision (e.g. re-hardcoding a single company's identity,
or reintroducing a Windows-only assumption) simply because the reasoning was never written down.

## When to use this skill

Invoke it whenever a change:
- Introduces or changes a cross-platform capability difference (something that works on some
  platforms and not others, or a decision about *why* it doesn't need to).
- Adds, removes, or changes a security-relevant mechanism (crypto, secret storage, auth flow,
  directory/LDAP integration).
- Adds a new runtime or build-time dependency, especially anything that could touch network access
  (see ADR-0007's zero-telemetry constraint — any such change needs an ADR to justify it before
  merging, not after).
- Reverses or narrows a decision recorded in an existing ADR.

Do **not** use it for routine bug fixes, refactors that don't change behavior or architecture, or
UI copy changes — not every change needs an ADR, only ones a future contributor would need the
"why" for.

## How to draft one

1. Read the existing ADRs in `docs/adr/` first (at minimum, skim the `## Decision` and
   `## Consequences` sections of each) to check whether the change conflicts with, extends, or
   supersedes an existing decision. If it supersedes one, say so explicitly in the new ADR's
   Context section and update the old ADR's `## Status` to `Superseded by ADR-00NN`.
2. Determine the next sequential number by checking the highest-numbered file in `docs/adr/`.
3. Write the ADR using this structure (mirror the existing files in `docs/adr/` for exact
   formatting):

```markdown
# ADR-00NN: <short, decision-focused title>

## Status
Proposed | Accepted | Superseded by ADR-00MM

## Context
What problem or requirement forced this decision. Cite specific files/behavior in *this* codebase
where relevant, not just general principles. If research informed the decision (a library's actual
platform support, a comparable project's approach, a documented best practice), say what was found
and link the source — a decision record without evidence is just an opinion with a template around
it.

## Decision
The actual decision, stated concretely enough that a reader knows exactly what to build or avoid
building. Prefer specifics (file/module names, interface shapes) over abstractions.

## Consequences
**Positive:** ...
**Negative:** ...
**Risks:** ... (what could still go wrong, and what would need to be validated before shipping)

## Alternatives Considered
Each rejected alternative, with the specific reason it was rejected — not a token mention.

## References
Links to research sources, or "Direct review of `path/to/file.dart`" for findings grounded in this
codebase itself.
```

4. Do not mark a new ADR `Accepted` yourself unless the change has already been reviewed and
   merged — draft ADRs stay `Proposed` until a maintainer approves the associated change.
