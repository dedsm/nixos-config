---
trigger: model_decision
description: "The shape of page bodies: which sections are rewritten in place and which are appended to, and what each recurring section is for. Read before writing or restructuring a page body."
---

# Page bodies — rewrite vs. append

`brain new` writes a skeleton for the page's kind. The section comments are not decoration: each
says whether it is **rewritten in place** or **appended to**, and that distinction is the whole
point. Without it, "current state" sections accumulate — a page ends up carrying both
`## Where it stands (June)` and `## Where it stands (July)`, and grows without bound.

The recurring shape, across kinds:

- **An orienting paragraph** under the H1 — what this is, why it matters, what "done" looks like.
  Rewritten. Priority does **not** belong here as bold prose; that's what `attention` is for.
- **Why this exists / Context / The line I hold** — the rationale, written once **so it isn't
  re-litigated**. This is the highest-value thing a page does. Touch it only if the premise changes.
- **Current state** — *rewritten in place*, with a stamp of what you actually checked and when
  (mirrored into `verified`).
- **Decisions** — *appended*, dated, each with its reasoning and consequences. Superseded entries
  stay, struck through, pointing at what replaced them.
- **Open** — questions, risks, blockers. This section should **shrink**; delete lines as they close.
- **Tracker** (optional) — the external issues this page follows: **links and stable identifiers
  only, never status**. See the stanza shape in `tracker-standings.md`. One of the five
  sections where naming a status is permitted, because quoting the tracker is the section's job.
- **Drift** (projects tracking an external doc) — where the doc, the tracker and the code disagree.
  Exempt from the state-reading rule for the same reason: the disagreement cannot be recorded
  without quoting both sides.
- **Execution log** (optional) — *appended*, dated: a record of operations **actually performed**
  ("2026-09-17 — steps 2 and 4 done; nothing else touched"). A past action, not a present reading,
  which is why it is exempt from the state-reading rule and why it is never rewritten. Keep it for
  a page driving a multi-step change through another system; delete it when the change is over.
- **Milestones** (goals) — *appended and checked off*: `- [ ]` lines that `review` counts at read
  time and never writes back.
- **Wins** (optional, on an area page — a career area, typically) — *appended*, dated, each with
  its evidence link: what you delivered, written while it's fresh, for the review or negotiation
  where you'll need it. Exempt from the state-reading rule: "merged PR #812" is the record itself.

Delete the sections a page doesn't need. An unfilled section is worse than an absent one.
