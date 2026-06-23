# Brain — Personal Tracking Store

<!-- brain-template v2 — bump when conventions change, then rebuild + run `/brain --sync` per machine -->

Operating manual for this store. **Read this before any operation here.** The files are the
source of truth; this manual tells an agent how to maintain them.

## What this is

A local, git-tracked markdown "second brain" that Claude Code maintains. It tracks the **status
and narrative** of your projects, initiatives, decisions/ADRs, and other ongoing work — across
every session, from any repo or none. Plain markdown: durable, diffable, hand-editable, and
openable directly in Obsidian with zero changes.

Pattern: agent-compiled knowledge base (Karpathy "LLM-wiki"). Moving parts: raw inputs →
compiled pages → a maintained `index.md`, plus an append-only `log.md` and a periodic
self-reorganization (`lint`) pass.

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
  from here into pages.
- `index.md` — master catalog, one line per page. Keep current.
- `log.md` — append-only activity log, newest first. **Every entry is dated** — `- YYYY-MM-DD — <what changed> — [[page]]` — making it the canonical "what happened when" timeline.

## Page schema (YAML frontmatter)

Every page begins with:

```yaml
---
title: Human title
kind: adr | initiative | project | area | resource | moc
status: idea | planned | active | blocked | done | archived
progress: "optional, e.g. 12/40 services or 30%"
owner: me
created: YYYY-MM-DD          # ISO date — set once on creation, never changed
updated: YYYY-MM-DD          # ISO date — refresh on every edit
started: YYYY-MM-DD          # optional — set when status → active
finished: YYYY-MM-DD         # optional — set when status → done
due: YYYY-MM-DD              # optional — target date, if any
tags: [example, tag]
links:                       # cross-references
  - "[[other-page]]"
  - "ISSUE-123 https://your-tracker.example/ISSUE-123"   # external issue, per workspace rules
  - "dstask:abc123"
---
```

- `status` is the kanban state — the field a GUI (Obsidian Bases/Kanban) or a query reads. Keep
  it accurate.
- For ADRs, record the ADR decision state (proposed/accepted/superseded) in the body; map
  `status` to the tracking state (e.g. accepted-but-rolling-out → `active`).
- Internal links use `[[wikilinks]]` (Obsidian-native). External links are plain URLs.
- **Dates** are ISO `YYYY-MM-DD`. `created` is set once and never changes; `updated` tracks the
  last edit. `started`/`finished`/`due` apply mainly to `project`/`initiative` pages and drive
  time-range queries — set `started` when `status` → `active`, `finished` when `status` → `done`.

## Workflows

### 1. CAPTURE / INGEST — "track this", "remember", an info dump

1. If the input is substantial source material, save it verbatim to `raw/YYYY-MM-DD-slug.md`
   (skip for trivial one-liners).
2. Create or update the relevant page under the right PARA bucket. Fill/refresh frontmatter: set
   `created` once on new pages, refresh `updated`, and set `started`/`finished` as `status` crosses
   `active`/`done`.
3. Wire cross-references: add `[[links]]`, and add the page to every relevant MOC.
4. If the input implies a personal next-action → create a dstask task and link it. If it is an
   issue that belongs in a team tracker → reference it there (per the active workspace's rules);
   do not duplicate.
5. Update `index.md`. Prepend a **dated** entry to `log.md`: `- YYYY-MM-DD — <what changed> — [[page]]`.
6. Commit: `git -C ~/brain add -A && git -C ~/brain commit -m "<concise message>"`.

### 2. QUERY — "what's the state of X", "what am I tracking"

Read `index.md` first, then the relevant page(s)/MOC; grep as needed. Pull open dstask tasks and
referenced external issues when relevant. Answer with current status. Never invent — if a field is
stale, say so and offer to refresh.

**Time-range queries** ("what did I work on in the past 3 months", "what shipped in Q1", "what's
overdue") are answered from the dated `log.md` and the `created`/`started`/`finished`/`due`
frontmatter, filtered to the window — with `git -C ~/brain log --since=…` as a backstop, plus
dstask's resolved-task dates for personal tasks.

### 3. UPDATE STATUS

Edit the page's frontmatter (`status`, `progress`) and body, bump `updated` (and set `started`
when moving to `active`, `finished` when moving to `done`), reflect in `index.md`, append a dated
`log.md` entry, commit.

### 4. LINT / REORG — the self-reorganization pass (on request or when the store has grown)

Run a health pass and fix:

- Stale `updated` dates vs `log.md`; missing required frontmatter fields.
- Oversized pages → split; thin/duplicate pages → merge.
- Orphan pages (in no MOC and no index line) → file them.
- Broken `[[links]]`; pages whose `status` is `done`/`archived` → move to `archive/`.
- Contradictions between pages → flag in the body and to the user.
- Regenerate `index.md`; append a summary of changes to `log.md`; commit.

Prefer mechanical, reversible edits. Ask before destructive merges. Git is the safety net.

## Guardrails

- Files are the source of truth; always leave `index.md` consistent with the pages.
- Never fabricate status. Mark gaps with `<!-- TODO: fill -->`.
- Commit after every change set. No AI attribution in commit messages.
- Never store secrets, credentials, or PII you don't need.

## Maintaining the conventions (keep machines in sync)

This manual and the store scaffold are the **canonical brain template**, version-controlled with
the skill in the nixos-config repo (`~/Develop/personal/nixos-config`):

- **Template (canonical):** `modules/common/users/common/claude-code/skills/brain/templates/`
  — this manual + the empty scaffold. Deployed read-only to `~/.claude/skills/brain/templates/`.
- **Skill (mechanism):** `modules/common/users/common/claude-code/skills/brain/SKILL.md`

The store's **content** (pages, `index.md`, `log.md`) is never templated — only the scaffold/manual.

**To change the conventions** — buckets, page schema/frontmatter, workflows, guardrails, or the
skill's behavior:

1. Edit the template here (and `SKILL.md` if behavior changes); bump the `brain-template` version
   comment at the top of this file; commit nixos-config.
2. Rebuild each machine — Nix propagates the updated template + skill everywhere.
3. On each machine, run **`/brain --sync`** — the skill migrates that machine's existing `~/brain`
   to the canonical template (updates this manual, creates missing buckets, migrates page
   frontmatter, regenerates the index), showing a diff and committing.

The bootstrap only *creates* a missing store; it never updates an existing one — `/brain --sync`
is how existing stores catch up. Pure content edits (adding/updating pages) need none of this.
