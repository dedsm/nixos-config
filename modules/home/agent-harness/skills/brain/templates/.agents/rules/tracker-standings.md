---
trigger: model_decision
description: "What a page may say about external tracker state — issue and project statuses, PR states, tallies, `progress` — and where tracker references belong. Read before writing or editing any page body that cites issues, PRs or tracker projects."
---

# Pages hold the design; the tracker holds the standings

The sharp edge of **Systems of record** in `AGENTS.md`, and **enforced** since v14. A page stops restating external
state: no story counts, no project statuses, no PR ledgers, no `progress` mirroring a tracker
number. What stays is what no other system holds — invariants, decisions and their reasoning,
counting rules, orderings that are unrecoverable if got wrong, and cross-system correspondences
neither system can answer alone.

Why it is worth a gate rather than a good intention: a tracker reorganisation can invalidate a
dozen carefully-verified readings across six pages in one afternoon. A page that mirrors a tracker
is wrong from the next merge onward, and a **recent `verified:` stamp makes it more dangerous, not
less**, because the stamp invites trust. On a page written this way `verified:` comes to mean *the
design still holds* — a question measured in months rather than merges.

**The rule in one sentence: outside `## Tracker`, `## Decisions`, `## Drift`,
`## Execution log` and `## Wins`, do not put a status word next to an issue key.** Cite the identifier alone and
the sentence stays true forever.

- **`## Tracker` is the sanctioned home for tracker references: links and stable identifiers only,
  never status.** The shape:
  > Initiative `Foundation · Platform & IaC Kit` · five milestone projects named `IaC Kit · …` ·
  > stories PLT-42–PLT-63 under epics PLT-134–PLT-153. Structure: [[kits-structure]].
- **What makes ID-only citation safe** — this is the load-bearing assumption, so know it: Linear
  guarantees **identifiers never change on a move**. Renaming a project or initiative preserves
  both the id and the URL (a renamed project still resolves from its old slug). A tracker without
  that guarantee needs its own convention before this rule can be trusted there.
- **How it is enforced.** `brain check --staged` (the commit gate) rejects a state reading on a
  line the commit **adds**, and only there — the pre-existing backlog is a `brain check --strict`
  warning for the LINT pass to work down, because a gate that blocks every commit until a backlog
  clears is a gate that gets switched off. It reads page **bodies**; `progress` has its own rule,
  `summary` its length warning, and `next` is exempt as judgment.
- **Its blind spot, stated rather than discovered later: it catches tokens, not claims.** Prose
  that restates a tracker with no issue key, PR number, status word or tally — "the kit is filed
  and the platform team has picked it up" — passes by construction. Catching *that* is the LINT
  and REVIEW passes' job (`review-and-lint.md`); the gate is deliberately mechanical because it runs in a
  pre-commit hook, where a model would be slow, non-deterministic, cost money per commit and fail
  open offline — and a gate that passes for unreproducible reasons is worse than none, because it
  still looks green.
- **The escape, for a citation the rules misread** (a third-party issue whose state is the fact
  itself, a PR cited as evidence for a design claim): end the line with `<!-- state-ok -->`. It is
  greppable on purpose, so the LINT pass can audit every use. Reach for it after checking that the
  line is not simply a standings copy.
