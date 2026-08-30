# ADR-0009: AI-Assisted Contribution Workflow (CLAUDE.md, ADRs, Security-Review Skill)

## Status
Proposed

## Context
This project is being prepared for contributions from people outside the original bank team,
plausibly using AI coding assistants (Claude Code among them) at very different levels of context
about the project's history and security constraints than the original authors had. Two risks
follow directly from that:

1. A contributor (human or AI-assisted) unfamiliar with why a design choice was made (e.g. "why is
   directory auth pluggable and off-by-default instead of just calling AD directly") could
   "simplify" it back into the single-tenant, Windows-only shape this migration is deliberately
   moving away from, simply because the reasoning wasn't recorded anywhere durable.
2. Security-sensitive code in this project (PIN hashing/storage, AES key derivation, secure storage,
   directory-auth credential handling) is exactly the code where a well-intentioned but
   under-informed change is most costly — and unlike the original single-team internal project,
   an open-source project cannot rely on institutional memory or a fixed reviewer roster to catch
   this every time.

A repo-root `CLAUDE.md` is the standard mechanism Claude Code (and, by the same convention,
`AGENTS.md`-reading tools) uses to load durable, repo-specific context automatically at the start
of a session — this directly addresses risk 1 by making the ADR trail and architectural
constraints discoverable without a human having to paste them in every time. A project-local skill
under `.claude/skills/` is the mechanism for encoding a *repeatable checklist* (not just narrative
context) that should run specifically when security-sensitive files are touched — this addresses
risk 2. Both must be **self-contained within this repository** and must not assume any particular
person's private Claude Code plugin set is installed, since external contributors will not have
this bank's internal tooling — a constraint that ruled out relying on any organization-specific
skill/agent infrastructure for this project's own guidance.

## Decision
1. Add a root `CLAUDE.md` (this migration's companion deliverable) covering: project purpose and
   the four target use cases, architecture overview (feature-folder layout, Riverpod state
   management conventions already established in the codebase), the ADR practice with a pointer to
   `docs/adr/`, the zero-telemetry constraint from ADR-0007, per-platform capability matrix from
   ADR-0005/0006, and explicit instructions to write a new ADR for any future architecture-level
   decision rather than silently deciding in a PR description.
2. Add a project-local skill, `.claude/skills/adr-record/SKILL.md`, that any Claude Code session
   working in this repo can invoke to draft a properly-formatted ADR (using the template
   established by ADR-0001 through ADR-0008) whenever a change touches architecture, a security
   boundary, or a cross-platform behavior difference — making the *practice* of writing ADRs
   actionable, not just described in prose in `CLAUDE.md`.
3. Add a second project-local skill, `.claude/skills/security-review-mfa/SKILL.md`, encoding a
   concrete checklist (secret handling, crypto usage, injection risks in the directory-auth
   provider, telemetry/network-call additions, platform-capability claims) to be run before merging
   any change touching `lib/core/services/`, `lib/core/directory_auth/`, or `lib/features/auth/` —
   the specific set of directories this review identified as most security-sensitive.
4. Both skills ship in-repo (not as a reference to a private plugin), so they work identically for
   any contributor's Claude Code session regardless of what else is installed on their machine.

## Consequences
**Positive:** New contributors (and their AI assistants) get the "why," not just the "what,"
automatically; the two riskiest classes of regression this ADR identifies (silently reverting a
deliberate architecture decision, and under-reviewed security-sensitive changes) each get a
concrete, repeatable mechanism rather than relying on a maintainer catching them in review by
memory.

**Negative:** `CLAUDE.md` and the ADR log need active maintenance discipline — a stale `CLAUDE.md`
that no longer matches the code is worse than none, because it actively misleads. This is a
process cost the project takes on deliberately.

**Risks:** None of this is enforceable by tooling alone (nothing blocks a human from merging a PR
without running the security-review skill) — it is a norm-setting mechanism, not a technical
control, and should be paired with human code review as the actual enforcement point (see the
governance phase of the migration plan for branch-protection/review-requirement recommendations).

## Alternatives Considered
- **Rely on PR descriptions and issue comments for design rationale instead of ADRs** — rejected:
  the whole reason the original codebase's Windows-only, single-tenant AD design was invisible
  until this review is that it was never recorded anywhere durable; PR history does not scale as
  project-level documentation the way a `docs/adr/` directory does.
- **Put the security checklist only in `CONTRIBUTING.md` as prose** — rejected as the sole
  mechanism: prose in a contributing guide is easy to skim past; a skill that a contributor's own
  AI assistant can invoke directly against the diff is more likely to actually run.

## References
- Direct synthesis from this migration's own findings (ADR-0002 through ADR-0008) about which
  parts of the codebase are most at risk of well-intentioned regression.
