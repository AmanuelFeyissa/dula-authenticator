# ADR-0001: Open-Source License — Apache License 2.0

## Status
Proposed

## Context
This project is being open-sourced from a bank-internal codebase so that any organization —
commercial, non-profit, or government — can adopt, fork, and modify it, including for
security-sensitive deployments (air-gapped networks, regulated industries). The license choice
determines who can legally use, modify, and redistribute the code, and how much legal risk
adopters take on.

Research into current (2026) open-source licensing practice shows two realistic candidates for a
permissive, enterprise-friendly license: MIT and Apache-2.0.

- MIT is shorter and simpler, but contains no explicit patent grant.
- Apache-2.0 includes an express patent license from every contributor to every user, plus a
  patent-retaliation clause (if you sue a contributor over patents on the covered code, your
  license terminates). It requires preserving a NOTICE file and stating changes made to modified
  files, which is a small amount of extra ceremony.
- Industry commentary (RedMonk's State of Open Source Licensing coverage, multiple 2026 license
  guides) converges on the same point: Apache-2.0 is the license enterprises reach for when patent
  risk is a live concern, because the explicit patent grant and retaliation clause remove a class
  of legal uncertainty that MIT leaves silent. Roughly three-quarters of GitHub's open-source
  components now use permissive licenses, and Apache-2.0 is consistently cited as the default
  recommendation "when you're in an enterprise environment where patents are a real risk."
- This project's origin (a bank's internal security tool) and target audience (other companies'
  IT/security teams, some in regulated industries) make patent risk a real, not theoretical,
  concern — an adopting company's legal team is far more likely to approve Apache-2.0 without
  escalation than a license with no patent language at all.
- Copyleft licenses (GPL/AGPL) were ruled out early: they would require any company that modifies
  the app and distributes it internally (arguably not "distribution" under GPL, but AGPL's network
  clause is a real risk for any future server component) to release their modifications. That is
  precisely the kind of friction that would stop banks and other regulated adopters from using the
  project at all, which contradicts the stated goal of "any company can use this."

## Decision
License the project under **Apache License 2.0**.

Concretely, this means:
- Add a root `LICENSE` file with the standard Apache-2.0 text.
- Add a `NOTICE` file listing the original copyright holder (with the bank's permission /
  after legal review — see Phase 1 in the migration plan) and any required third-party notices.
- Add an SPDX license header (`SPDX-License-Identifier: Apache-2.0`) to source files as they are
  touched during the de-branding pass, rather than a big-bang rewrite of every file at once.
- Audit every dependency in `pubspec.yaml` for license compatibility with Apache-2.0 redistribution
  (tracked as its own task in Phase 1 — see the migration plan) before the first public release,
  since a permissive project license does not override an incompatible dependency license.

## Consequences
**Positive:** Lowest-friction option for enterprise legal review; explicit patent protection for
both the project and downstream adopters; well understood by every major open-source foundation
and corporate legal department.

**Negative:** Slightly more file-header ceremony than MIT (NOTICE file, stating changes to
modified files). Does not compel downstream modifications to be shared back (a deliberate
trade-off, not an oversight — see above).

**Risks:** The original bank-internal code was never released publicly; before applying an
open-source license at all, the bank's legal/compliance team must explicitly approve open-sourcing
and confirm no proprietary AD/network details remain (this is a prerequisite gate in Phase 1, not
something this ADR can resolve on its own).

## Alternatives Considered
- **MIT** — simpler, but no patent grant; rejected because patent protection is specifically
  valuable given the project's enterprise/regulated-industry target audience.
- **GPL-3.0 / AGPL-3.0** — rejected: copyleft obligations (especially AGPL's network clause) would
  deter the exact adopters (banks, regulated enterprises) this project is aimed at.
- **BSD-3-Clause** — comparable permissiveness to MIT without a patent grant; rejected for the same
  reason as MIT.

## References
- [Open Source Licenses Comparison: MIT vs Apache vs GPL vs BSD](https://safeguard.sh/resources/blog/open-source-license-comparison-mit-apache-gpl-bsd)
- [Apache 2.0 vs MIT: Who rules open source in 2026](https://psyll.com/articles/technology/open-source/apache-20-vs-mit-who-rules-open-source-in-2026)
- [Selecting Licenses Like Apache 2.0 or MIT — A Software Architect's Perspective](https://roshancloudarchitect.me/selecting-licenses-like-the-apache-2-0-1ea1408ebe1f)
- [Comparison of Apache 2.0 and MIT open source licenses](https://mikatuo.com/blog/apache-20-vs-mit-licenses/)
