---
trigger: model_decision
description: "The recurring REVIEW pass and the LINT/REORG pass: working review's signals, trimming now.md, the oversized-page ladder, archiving, and splitting a page into a hub and children. Read before reviewing the store, archiving, or reorganising pages."
---

# Workflows — review and lint

### 4. REVIEW — the recurring pass ("what's the state of things", start of a work session)

Read-only detection, then judgment. Nothing here is automatic: `brain review` finds, you decide.

1. **`brain review`** (or `--since 7` for the weekly cut). Then work the signals:
   - **Gone quiet / never verified** → for each, ask *is this still true?* Re-check the claims,
     update the body, and **`brain set <page> verified today`**. If it's genuinely dormant, say so
     — change `status`, or `attention: tracking`, rather than leaving it looking live.
   - **Blocked** → is it still blocked, and on what? A blocker with no named owner is a task.
   - **Orphaned / stalled goals** → the weekly touch in `goals.md`: wire `parent` on the
     work that serves an orphaned goal (or admit nothing does), and triage a stalled one as
     Reschedule / Delegate / Delete.
   - **Contradictions** → where two pages disagree, or a page disagrees with its own `## Drift`
     section, flag it in the body and to the user. Resolve by rewriting the stale one, not by
     appending a newer paragraph beside it.
   - **Oversized pages** → propose a split (see the LINT pass).
2. **Trim `mocs/now.md` (and `mocs/goals.md` — same rule).** Anything `review` now generates —
   per-page status, tier listings, a copied dstask snapshot, dates — is dead weight there and
   rots within days. Sort its content into *generated* (delete), *judgment* (keep: why this
   ordering, what you're deliberately not doing), and *obsolete* (delete). Show the proposed deletions and ask before applying.
3. Roll `index.md`'s `▶ Current focus:` pointer if it has moved; re-set `attention` where the
   real answer changed.
4. **`brain log`** a one-line summary of what the review changed, `brain check`, commit.

### 5. LINT / REORG — the self-reorganization pass (on request or when the store has grown)

Run a health pass and fix:

- **`brain check --strict`** for schema/consistency issues (warnings become actionable here);
  stale `updated` dates vs `log.md`; over-long `summary` fields that have become changelogs; and
  the whole-store **state-reading** report (step 2 below is where you work it down).
- Oversized pages → work the ladder below, cheapest first. **Splitting is the last resort, not the
  first move** — most oversized pages are carrying weight they should not be carrying at all, and
  three of these four steps only delete.
  1. **Delete what a tool now generates.** Hand-maintained status prose, "next action" lists and
     link inventories are superseded by the `next` frontmatter, `brain review`, and
     `links:`. Keeping a copy guarantees it goes stale.
  2. **Delete what duplicates a system of record.** A section restating a Notion page, a tracker
     issue or a repo doc is drift waiting to happen — link it and cut the copy. This is the step
     **Pages hold the design; the tracker holds the standings** (`tracker-standings.md`) sharpens: strip the status
     words and the tallies, keep the identifiers, and move the references into `## Tracker`. The
     backlog is enumerated for you — `brain check --strict` lists every state reading in the store,
     which is the half the commit gate deliberately does not block. Work a page at a time and
     re-run it. Its blind spot is yours to cover here: **prose** that restates a tracker without
     an issue key or a status word passes the check and still has to go.
  3. **Delete superseded body sections**, noting the asymmetry: a superseded *decision* stays in
     `## Decisions`, struck through, pointing at what replaced it — that trail is the point. A
     superseded *analysis* in the body goes, because the section that superseded it already
     carries the conclusion.
  4. **Collapse accumulated status.** Two "where it stands" sections, one per month, become one
     rewritten `## Current state`; the history moves to `## Decisions` or `log.md`.
  5. **Split into a hub + children** (below) — only if it is *still* oversized, which means the
     page holds several different **kinds** of content rather than too much of one.
- Orphan pages (in no MOC and no index line) → file them. **Person and org pages are not
  orphans** (their directory MOC catalogs them), and neither are events or digests that carry a
  `parent` — `check` warns on one that doesn't.
- `raw/` files that are notes you wrote for yourself → `brain mv … --event` (see **Structure** in `AGENTS.md`). Heavy raw
  files `review` lists as undigested → digest the ones the agent keeps re-reading.
- **`brain links`** for anything the gate predates (broken/ambiguous wikilinks, relative-path
  warnings); pages whose `status` is `done`/`archived` → **`brain mv <page> archive/<slug>`**
  (it rewrites every `[[reference]]`, including path-qualified ones, and reindexes).
- Contradictions between pages → flag in the body and to the user.
- `log.md` past ~400 lines → run **`brain rotate-log`** (mechanical, verbatim, no approval needed;
  `health` flags this too — react to the flag by running it, don't wait for a lint pass).
- **`brain reindex`**; append a summary of changes to `log.md`; commit.

Prefer mechanical, reversible edits. Ask before destructive merges. Git is the safety net.

#### Splitting a page into a hub + children

For a page that stays oversized after steps 1–4 above — it has become a project's whole filing
cabinet. Do the deletions first: they are cheaper, they are not destructive of anything the store
still needs, and they often make the split unnecessary. The goal is a **hub** that answers "what is true now" in one screen, with the
reference material behind it. Propose the split before doing it; this deletes from a page you cannot
reconstruct from memory.

1. **Pin a restore point.** `git -C ~/brain rev-parse --short HEAD` *before* touching anything. It
   goes in the hub, with the command to read the old page:
   `git -C ~/brain show <sha>:projects/<page>.md`. Nothing summarised is ever actually lost.
2. **Classify sections by nature, not by date.** Three buckets: *live* (status, open, decisions —
   stays on the hub), *reference* (the worked-out design, invariants, runbooks — moves to a child),
   *event narrative* (meetings, reviews, one-off passes — gets summarised).
3. **Move verbatim, by line range.** Extract with `sed -n 'A,Bp'` and concatenate; never rewrite a
   section in the same step as relocating it. Rewriting while moving is how content goes missing
   without anyone noticing.
4. **Children carry `parent: "[[hub]]"`, and their kind follows their lifecycle.** A workstream
   that can close while the hub stays open (the equity terms of a negotiation, say) is a
   `kind: project`: it nests under the hub in `index.md`, and `review` tracks its freshness and
   `next` on their own. Reference material is a `kind: resource`; `reindex` groups by bucket, so it
   does **not** nest under a `project` hub — the hub's `## Sub-pages` section is its directory.
   Never pick a kind to game the index. `brain q --under <hub>` lists every child either way.
5. **Summarise only what is genuinely spent.** An event narrative whose rulings already live in
   `## Decisions` or a child page compresses to a paragraph; keep whatever it alone records. Link
   the restore commit from the summary.
6. **Verify nothing was lost.** Diff the heading sets:
   `git show <sha>:<page> | grep -E '^#{2,3} ' | sort` against the same over the hub plus every
   child. The only headings that may disappear are the ones you deliberately summarised — anything
   else is an extraction bug.
7. **Commit in stages** (mechanical → collapse → split), so a bad step reverts on its own.

**Abandon a merge that stops making sense.** Sections whose titles look redundant often are not —
"the invariants" and "the worked-out design" cover the same ground at different altitudes and for
different readers. If reading them shows a merge would cost content for a cosmetic gain, say so and
stop, rather than completing an approved plan you no longer believe in.
