# Brain — Personal Tracking Store

<!-- brain-template v8 — bump when conventions change, then rebuild + run `/brain --sync` per machine -->
<!-- The store's own copy of this version lives in `.brain-version`, written by
     `brain version --stamp` as the LAST step of a migration. -->


Operating manual for this store. **Read this before any operation here.** The files are the
source of truth; this manual tells an agent how to maintain them.

## What this is

A local, git-tracked markdown "second brain" that Claude Code maintains. It tracks the **status
and narrative** of your projects, initiatives, decisions/ADRs, and other ongoing work — across
every session, from any repo or none. Plain markdown: durable, diffable, hand-editable, and
openable directly in Obsidian with zero changes.

Pattern: agent-compiled knowledge base (Karpathy "LLM-wiki"). Moving parts: raw inputs →
compiled pages → a **generated** `index.md`, plus an append-only `log.md` and a periodic
self-reorganization (`lint`) pass. A small Nix-managed CLI (`brain`) owns the schema, so
frontmatter is deterministic instead of hand-typed — see **Tooling** below.

## Systems of record (do not duplicate)

- **External / team trackers** — actionable issues that belong in a project's tracker stay there.
  Which tracker, and how to reference it, follows the **active workspace's own rules** (e.g. a
  repo's `.claude/` rules) — not this file. Link to those issues here; never copy them in.
- **dstask** (`~/.dstask`, driven via Bash) — the **personal** task lifecycle (start/pause/done)
  for next-actions that don't belong in a team tracker. Link tasks to pages here.
- **This store** — the narrative and overall status that neither of the above captures: why an
  initiative exists, its rollout state, decisions, and cross-cutting maps.

## Structure (PARA + Maps of Content)

- `projects/` — initiatives with an end state and a finish line.
- `areas/` — ongoing responsibilities with no end (perpetual rollouts, standards to maintain).
- `resources/` — reference material, not actionable.
- `archive/` — completed or dormant items moved out of the three above.
- `mocs/` — Maps of Content: index notes linking a topic's pages. Use for **cross-cutting**
  themes that span many pages (one page may belong to several MOCs — folders cannot express this).
- `raw/` — immutable captured inputs (pasted text, links) before compilation. Never edit; compile
  from here into pages. `raw/inbox.md` is the one exception: an append-only list of one-line
  captures written by **`brain capture`**, from which lines are *deleted* as they're processed.
- `mocs/now.md` — the **judgment** behind the current ordering. The generated view (what's live,
  blocked, overdue, gone quiet, open tasks) is **`brain review`** — never hand-maintain that here.
  This page holds only why this order, and what you're deliberately not doing.
- `index.md` — master catalog. The section list is **generated** between the
  `<!-- BEGIN generated -->` / `<!-- END generated -->` markers — never hand-edit inside them.
  The pre-commit hook regenerates it from frontmatter on **every commit**, so it can't drift; you
  can also run `brain reindex` explicitly to preview. Everything outside the markers (preamble, the
  `▶ Current focus` pointer, hand-listed reference files) is preserved.
- `log.md` — append-only activity log, newest first. **Every entry is dated** — `- YYYY-MM-DD — <what changed> — [[page]]` — making it the canonical "what happened when" timeline. When it grows
  large (say past ~400 lines), rotate the older tail into `log-archive/YYYY.md` (or `-QN`) and keep
  the recent window hot; `git log` remains the ultimate backstop timeline.

## Page schema (YAML frontmatter)

This schema is **enforced** by `brain check` — its machine-readable definition lives in the
`brain` CLI (`brain.py`, shipped from nixos-config); the block below is the human mirror. Every
page begins with:

```yaml
---
title: Human title
kind: adr | initiative | project | area | resource | moc
status: idea | planned | active | blocked | done | archived
attention: focus | tracking  # optional — omit for ordinary active work
progress: "optional, e.g. 12/40 services or 30%"
next: "optional — the single next concrete move"
owner: me
created: YYYY-MM-DD          # ISO date — set once on creation, never changed
updated: YYYY-MM-DD          # ISO date — refresh on every edit
verified: YYYY-MM-DD         # optional — when this page's claims were last checked
started: YYYY-MM-DD          # optional — set when status → active
finished: YYYY-MM-DD         # optional — set when status → done
due: YYYY-MM-DD              # optional — target date, if any
summary: "one-line catalog description — what index.md shows for this page"
parent: "[[parent-page]]"    # optional — nests this page under another in index.md
tags: [example, tag]
links:                       # cross-references
  - "[[other-page]]"
  - "ISSUE-123 https://your-tracker.example/ISSUE-123"   # external issue, per workspace rules
  - "dstask:abc123"
---
```

- **Required** (enforced, commit-blocking if missing/invalid): `title`, `kind`, `status`,
  `created`, `updated`. `kind`/`status` must be from the sets above; date fields must be ISO
  `YYYY-MM-DD`. Everything else is optional.
- `status` is the kanban state — the field a GUI (Obsidian Bases/Kanban) or a query reads. Keep
  it accurate.
- `attention` is **not** a priority ladder — deliberately three states. `focus` = hands-on right
  now; `tracking` = watching work that is someone else's; **absent** = ordinary active work. A
  finer ladder rots faster than it informs. `brain review` groups on this.
- `summary` is what `brain reindex` prints for the page in `index.md` (falls back to `title` if
  absent). **One crisp line** — `brain check` warns past 200 characters, because at that point it
  has become a changelog. Progress belongs in `progress`, the next move in `next`, detail in the body.
- `next` is the single next concrete move, in one line, and it's what makes `brain review`
  actionable rather than a status dump. Distinguish it from its neighbours: `progress` = how far
  along ("11/14 stories"), `next` = the next move ("start STO-496"), **dstask** = actions you will
  personally do. A `next` may well be someone else's action or a decision, which is why it isn't
  a task.
- `verified` is **when this page's claims were last checked against reality** — code read, tracker
  reconciled, person asked. It is not `updated`, which moves on a typo fix. This is the field
  staleness should be judged on, so a page nobody edited but that you re-checked yesterday doesn't
  read as rotten. Mirror it in the body where you record what you checked
  ("verified against the code 2026-07-26").
- Internal links use `[[wikilinks]]` (Obsidian-native). External links are plain URLs. A page in a
  subdirectory is linked by path (`[[resources/scripts/README]]`), which is what `reindex` emits.

### `adr` vs `project` — where does the decision live?

Both shapes exist and they get confused, so the test is a single question: **is the decision
recorded here, or somewhere else?**

- **Recorded here** — no repo ADR/RFC or tracker document owns it; this page *is* the record →
  `kind: adr`, and use the ADR body template (Context / Decision / Consequences / Alternatives
  rejected). Record the ADR's own state (proposed/accepted/superseded) in the body; frontmatter
  `status` stays the *tracking* state (e.g. accepted-but-rolling-out → `active`).
- **Recorded elsewhere** — a repo ADR/RFC owns the decision and you are tracking its rollout,
  its gaps, or its drift → `kind: project`. Link the document, don't restate it, and use the
  project template's optional `## Drift` section for where the doc, the tracker and the code
  disagree. Copying the decision content in would break "link, don't duplicate" above.
- **Dates** are ISO `YYYY-MM-DD`. `created` is set once and never changes; `updated` tracks the
  last edit. `started`/`finished`/`due` apply mainly to `project`/`initiative` pages and drive
  time-range queries — set `started` when `status` → `active`, `finished` when `status` → `done`.

## Tooling — the `brain` CLI (prefer it over hand-editing frontmatter)

`brain` is a Nix-managed command on `PATH` and is the **deterministic gate** for this store: it
owns the schema, so a malformed heading can't slip in. Use it for every frontmatter write and
query; only drop to hand-editing page **bodies** (prose below the frontmatter).

```bash
brain new <kind> <slug> [--title T --status S --attention A --summary "…" --next "…"
                         --due D --parent P --tags a,b --person]
                              # create a schema-perfect page, with a body skeleton for its kind
brain set <page> <field> <value>   # set one field, validated; stamps updated (+ started/finished)
                                   # date fields accept `today` so you never hand-type one
brain unset <page> <field>         # remove one optional field (never a required one); stamps updated
brain done <page>                  # status=done + finished=today + updated=today
brain reindex                      # regenerate index.md's generated region from frontmatter
brain review [--since DAYS] [--stale DAYS] [--log N] [--json]
                                   # READ-ONLY briefing; --since gives the window ("what moved")
brain q [--status S | --kind K | --tag T | --attention A | --overdue | --due-before D
         | --stale DAYS [--all] | --unverified [DAYS]] [--json]
brain check [--staged] [--strict]  # validate frontmatter (the gate); exits non-zero on errors
brain normalize [paths…]           # repair-on-drift: lowercase status/kind, map synonyms, sort tags
brain capture "<text>" | - [--title SLUG]   # append to raw/inbox.md, or write a raw file from stdin
brain log "<what changed> — [[page]]"  # prepend a dated log.md entry (date from the clock)
brain log --for <page>             # read that page's log entries (don't re-narrate them in the body)
brain version [--stamp]            # CLI vs store template version; --stamp writes .brain-version
brain today                        # today's date from the system clock — never infer it
```

- **Writers** (`new`/`set`/`unset`/`done`) are the reason frontmatter stays clean: they only ever
  emit legal enum values and ISO dates, and stamp `updated`/`started`/`finished` for you. Reach for
  them instead of typing YAML — including `unset` to drop an optional field (it refuses required
  ones), rather than hand-deleting a line.
- **Dates come from the clock, never from the corpus.** The writers and `brain log` date
  everything from the system clock; `brain today` is the authoritative "now". **Never read a date
  out of `log.md`, git history, or a page and treat it as today** — those are recorded facts, not
  the current date. If you must write a date by hand (e.g. a relative `due` like "next Friday"),
  get today from `brain today` (or `date +%F`) and compute from it.
- **`review` writes nothing.** It is the generated half of a "now" page — focus, work grouped by
  `attention`, blocked, overdue, what's gone quiet, oversized pages, recent log, open dstask,
  pending inbox. Start any session on this store with it. Because it produces that picture on
  demand and always current, there is no reason left to hand-maintain a copy of it anywhere.
- **`capture` is the zero-friction path in.** One line from any terminal, no session, no schema —
  which matters because second brains die at capture, not at retrieval. Substantial material
  (`- --title <slug>`) lands as its own immutable `raw/` file instead of an inbox line.
- **`reindex`** makes `index.md` a projection of the pages. You rarely call it by hand: the
  pre-commit hook regenerates and stages it on every commit. Run it explicitly only to preview the
  catalog, or use `brain reindex --check` (exits non-zero if stale) as a drift detector.
- **The gate**: a `pre-commit` hook in `~/brain/.git/hooks` regenerates `index.md`, stages it, then
  runs `brain check --staged` — so a commit with a malformed page is **rejected**, and the catalog is
  always fresh, for LLM edits, hand edits, and Obsidian edits alike. Run `brain check` yourself before
  committing for fast feedback. `check` reports enum / required-field / date-format problems as
  **errors** (blocking) and softer issues (done without `finished`, etc.) as **warnings** (non-blocking).
- **Auto-push**: a `post-commit` hook pushes the store to its remote when one is configured, so a
  commit is also a backup and multi-machine sync — no reliance on remembering `git push`. It **never
  force-pushes**; if a push is rejected (the remote diverged — e.g. another machine pushed) or the
  remote is unreachable, it prints a hint and the commit still stands — reconcile with
  `git -C ~/brain pull --rebase`, then push again. **Both hooks are Nix-managed** — the nixos-config
  activation installs them on every rebuild; the CLI has no install verb (so they can't drift).

### ⚠️ Governance — the CLI, schema, and hook are Nix-managed (do not edit here)

`brain.py`, the schema it enforces, and the pre-commit hook are **canonical artifacts shipped
from nixos-config** (`~/Develop/personal/nixos-config`, at
`modules/common/users/common/claude-code/skills/brain/`). The copies on this machine are
Nix-store deployments.

**If a check, the schema, or a hook needs to change** — a new `status`/`kind` value, a new field,
a relaxed rule, a different hook — **STOP and ask David to update the skill in nixos-config**, then
rebuild and run `/brain --sync`. Never:

- hand-edit the deployed `brain` binary or the `pre-commit` hook,
- work around a failing `brain check` by loosening/deleting the rule locally, or
- `git commit --no-verify` to bypass the gate to force a malformed page in.

A failing gate means either the page is wrong (fix the page) or the schema should change (a
nixos-config change David makes) — never a local workaround.

## Workflows

### 1. CAPTURE / INGEST — "track this", "remember", an info dump

0. **Process the inbox first if it has entries.** `raw/inbox.md` holds one-line captures made
   outside a session with **`brain capture`**. For each: route it (update an existing page, create
   one, file a dstask, reference an external issue, or drop it), then **delete that line** — the
   pending count is the backlog, so nothing else needs tracking.
1. If the input is substantial source material, save it verbatim to `raw/YYYY-MM-DD-slug.md`
   (**`brain capture - --title <slug>`** does this from stdin) — skip for trivial one-liners.
2. Create or update the page: **`brain new <kind> <slug> --summary "…" [--status …]`** for a new
   page, or **`brain set <page> <field> <value>`** to update fields on an existing one. Edit the
   page **body** by hand. The writers set `created`/`updated`/`started`/`finished` for you.
3. Wire cross-references: add `[[links]]` in the body, and add the page to every relevant MOC.
4. If the input implies a personal next-action → create a dstask task and link it. If it is an
   issue that belongs in a team tracker → reference it there (per the active workspace's rules);
   do not duplicate.
5. Record it: **`brain log "<what changed> — [[page]]"`** (it dates the entry from the clock —
   don't hand-type the date). (`index.md` is refreshed by the commit hook; run `brain reindex`
   first only if you want to read the updated catalog now.)
6. **`brain check`**, then commit: `git -C ~/brain add -A && git -C ~/brain commit -m "<msg>"`
   (the pre-commit hook reindexes + re-checks; a clean `check` means it passes).

### 2. QUERY — "what's the state of X", "what am I tracking"

For "what's going on" as a whole, run **`brain review`** — that's the question it answers.

For a specific thing: read `index.md` first, then the relevant page(s)/MOC; use **`brain q …`** for structured cuts
(`--status`, `--kind`, `--tag`, `--overdue`, `--due-before`, `--stale DAYS`) and `grep`/`rg` for
free-text. Pull open dstask tasks and referenced external issues when relevant. Answer with
current status. Never invent — if a field is stale, say so and offer to refresh.

**Time-range queries** ("what did I work on in the past 3 months", "what shipped in Q1", "what's
overdue") — start with `brain q --overdue` / `--stale`, then the dated `log.md` (+ `log-archive/`)
and the `created`/`started`/`finished`/`due` frontmatter filtered to the window, with
`git -C ~/brain log --since=…` and dstask's resolved-task dates as backstops.

### 3. UPDATE STATUS

**`brain set <page> status <value>`** (or `brain done <page>`) — it bumps `updated` and stamps
`started`/`finished` as the status crosses `active`/`done`. Edit the body for narrative, record it
with **`brain log "…"`**, `brain check`, commit.

### 4. REVIEW — the recurring pass ("what's the state of things", start of a work session)

Read-only detection, then judgment. Nothing here is automatic: `brain review` finds, you decide.

1. **`brain review`** (or `--since 7` for the weekly cut). Then work the signals:
   - **Gone quiet / never verified** → for each, ask *is this still true?* Re-check the claims,
     update the body, and **`brain set <page> verified today`**. If it's genuinely dormant, say so
     — change `status`, or `attention: tracking`, rather than leaving it looking live.
   - **Blocked** → is it still blocked, and on what? A blocker with no named owner is a task.
   - **Contradictions** → where two pages disagree, or a page disagrees with its own `## Drift`
     section, flag it in the body and to the user. Resolve by rewriting the stale one, not by
     appending a newer paragraph beside it.
   - **Oversized pages** → propose a split (see the LINT pass).
2. **Trim `mocs/now.md`.** Anything `review` now generates — per-page status, tier listings, a
   copied dstask snapshot, dates — is dead weight there and rots within days. Sort its content
   into *generated* (delete), *judgment* (keep: why this ordering, what you're deliberately not
   doing), and *obsolete* (delete). Show the proposed deletions and ask before applying.
3. Roll `index.md`'s `▶ Current focus:` pointer if it has moved; re-set `attention` where the
   real answer changed.
4. **`brain log`** a one-line summary of what the review changed, `brain check`, commit.

### 5. LINT / REORG — the self-reorganization pass (on request or when the store has grown)

Run a health pass and fix:

- **`brain check --strict`** for schema/consistency issues (warnings become actionable here);
  stale `updated` dates vs `log.md`; over-long `summary` fields that have become changelogs.
- Oversized pages → split. A page grows past ~300 lines when dated status sections **accumulate**
  instead of being rewritten (two "where it stands" sections, one per month). Collapse them into
  one rewritten `## Current state` and move the history into `## Decisions` or `log.md`.
- Orphan pages (in no MOC and no index line) → file them. **Person pages are not orphans**: they
  are deliberately absent from `index.md` and cataloged by the people MOC instead.
- Broken `[[links]]`; pages whose `status` is `done`/`archived` → move to `archive/`.
- Contradictions between pages → flag in the body and to the user.
- Rotate `log.md` if it has grown past ~400 lines (older tail → `log-archive/YYYY.md`).
- **`brain reindex`**; append a summary of changes to `log.md`; commit.

Prefer mechanical, reversible edits. Ask before destructive merges. Git is the safety net.

## Page bodies — rewrite vs. append

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
- **Drift** (projects tracking an external doc) — where the doc, the tracker and the code disagree.

Delete the sections a page doesn't need. An unfilled section is worse than an absent one.

## People

A **directory of people you know** — not a work roster. This is a personal store: it will hold
people with no Slack handle, no work email, and no job title.

- **`mocs/people.md`** is the directory: a table by default. Columns are **suggested, never
  required** — a name, a contact handle *if one exists*, and where they appear in this brain.
  Add or drop columns per store; empty cells are fine. Grouping (by team, by context, or not at
  all) is likewise store-local.
- **Promote to a page** when someone accumulates narrative that won't fit in a cell — decisions
  they own, positions they hold, history worth not re-deriving. Until then a table row is enough.
- A person page is **`brain new resource <slug> --person`**: `kind: resource`, `tags: [person]`,
  filed in `resources/`, with the person body skeleton.
- **They are excluded from `index.md`.** `reindex` skips `tags: [person]`, so the catalog carries
  exactly one line — the people MOC — whether you know 2 people or 200. Index → MOC → person page.
  They remain fully in the system: `brain check` validates them and `brain q --tag person` finds
  them. Excluded from the catalog is not excluded from the gate.
- **Maintenance rule:** whenever a person is mentioned in any page or log entry, make sure they're
  in the directory, and append that page to where-they-appear. Do this on every brain update, not
  only on meeting captures — this is the entry most prone to silent drift.
- **PII:** keep to what you actually need in order to work with them. A personal directory is the
  place in this store where the "no PII you don't need" guardrail actually bites — addresses,
  phone numbers, birthdays, health details.

## Guardrails

- Files are the source of truth; **`brain reindex`** keeps `index.md` consistent with the pages —
  don't hand-maintain the generated region.
- **Write frontmatter through the `brain` CLI**, not by hand — that's what keeps it schema-valid.
- **Run `brain check` before committing**; never bypass the pre-commit gate (`--no-verify`) or
  loosen a rule locally. To change a rule, see Governance above (ask David → change nixos-config).
- **The store auto-pushes** to its remote (post-commit hook) when one exists. If a push is rejected,
  reconcile with `git -C ~/brain pull --rebase` and push again — never force-push, and never disable
  the hooks.
- **Dates come from the system clock, never inferred from the corpus.** Let the writers and
  `brain log` stamp dates; use `brain today` for any date you must supply. A date seen in `log.md`
  or a page is a recorded fact, not "today".
- **`brain review` writes nothing, and no command rewrites a page body.** Trimming `now.md`,
  splitting an oversized page, or resolving a contradiction is a supervised edit you propose and
  the user approves — never a side effect of a read.
- Never fabricate status. Mark gaps with `<!-- TODO: fill -->`.
- Commit after every change set. No AI attribution in commit messages.
- Never store secrets, credentials, or PII you don't need.

## Maintaining the conventions (keep machines in sync)

This manual, the `brain` CLI, and the store scaffold are the **canonical brain template**,
version-controlled with the skill in the nixos-config repo (`~/Develop/personal/nixos-config`):

- **Template (canonical):** `modules/common/users/common/claude-code/skills/brain/templates/`
  — this manual + the empty scaffold. Deployed read-only to `~/.claude/skills/brain/templates/`.
- **CLI + schema (mechanism):** `modules/common/users/common/claude-code/skills/brain/brain.py`
  — packaged to `PATH` as `brain`. The commit hooks (pre-commit gate + post-commit auto-push) are
  defined and installed by the module's `default.nix` activation on rebuild — Nix is their sole
  installer.
- **Skill (mechanism):** `modules/common/users/common/claude-code/skills/brain/SKILL.md`

The store's **content** (pages, `index.md`, `log.md`) is never templated — only the
scaffold/manual/CLI.

**To change the conventions** — buckets, page schema/frontmatter, the `brain` CLI or its checks,
the hook, workflows, guardrails, or the skill's behavior:

1. Edit the template/CLI/`SKILL.md` here; bump the `brain-template` version comment at the top of
   this file **and `TEMPLATE_VERSION` in `brain.py`** (they must match); commit nixos-config.
2. Rebuild each machine — Nix propagates the updated template + CLI and reinstalls the hooks everywhere.
3. On each machine, run **`/brain --sync`** — the skill migrates that machine's existing `~/brain`
   to the canonical template (updates this manual, creates missing buckets and scaffold files,
   migrates page frontmatter, regenerates the index), showing a diff and committing in stages.
   (The rebuild in step 2 — not sync — installs/refreshes the hooks.)

`brain check` prints a note whenever the store's `.brain-version` is behind the CLI, so a machine
that has rebuilt but not synced says so on every commit. The stamp is written **last**, after the
migration succeeds — an interrupted sync therefore leaves the store visibly behind rather than
silently claiming to be current (which would make the next sync skip it).

The bootstrap only *creates* a missing store (and installs the hooks); it never updates an existing
store's content — `/brain --sync` is how existing stores catch up. Pure content edits
(adding/updating pages) need none of this.
