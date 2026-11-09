# Brain — Personal Tracking Store

<!-- brain-template v18 — bump when conventions change, then rebuild + run `/brain --sync` per machine -->
<!-- The store's own copy of this version lives in `.brain-version`, written by
     `brain version --stamp` as the LAST step of a migration. -->


Operating manual for this store. **Read this before any operation here.** The files are the
source of truth; this manual tells an agent how to maintain them.

## What this is

A local, git-tracked markdown "second brain" that your coding agents (Claude Code, Antigravity)
maintain through the `brain` skill. It tracks the **status
and narrative** of your goals, projects, initiatives, and other ongoing work — across
every session, from any repo or none. Plain markdown: durable, diffable, hand-editable, and
openable directly in Obsidian with zero changes.

Pattern: agent-compiled knowledge base (Karpathy "LLM-wiki"). Moving parts: raw inputs →
compiled pages → a **generated** `index.md`, plus an append-only `log.md` and a periodic
self-reorganization (`lint`) pass. A small Nix-managed CLI (`brain`) owns the schema, so
frontmatter is deterministic instead of hand-typed — see **Tooling** below and `.agents/rules/tooling.md`.

## Systems of record (do not duplicate)

- **External / team trackers** — actionable issues that belong in a project's tracker stay there.
  Which tracker, and how to reference it, follows the **active workspace's own rules** (e.g. a
  repo's `.claude/` rules) — not this file. Link to those issues here; never copy them in.
- **dstask** (`~/.dstask`, driven via Bash) — the **personal** task lifecycle (start/pause/done)
  for next-actions that don't belong in a team tracker. Link tasks to pages here.
- **This store** — the narrative and overall status that neither of the above captures: why an
  initiative exists, its rollout state, decisions, and cross-cutting maps.

## Structure (PARA + Maps of Content)

- `goals/` — the quarter's 3–5 outcome goals: the pages that explain why everything below them
  exists, catalogued first in `index.md`. See `.agents/rules/goals.md`.
- `projects/` — initiatives with an end state and a finish line.
- `areas/` — ongoing responsibilities with no end (a job, a career, a homelab, admin/finance,
  standards to maintain). **The durable layer:** every live goal names its area in `parent`, and
  every live project names the goal it serves — or its area when no goal covers it — so
  `brain q --under <area>` returns a responsibility's whole tree (leaving a job is one query,
  not a hunt). An area nobody would ever open isn't worth creating.
- `resources/` — reference material, not actionable. Four tagged shapes live here too, each
  with its own skeleton and **out of `index.md`**: people and organisations (cataloged by
  `mocs/people.md` / `mocs/orgs.md`, see `.agents/rules/people-and-orgs.md`), and **events** and
  **digests** (reached from their `parent`):
  - an **event** is a dated note you wrote for yourself about one occasion — a call script,
    meeting notes, prep for a conversation. `brain new resource <slug> --event --parent <page>` (the filename
    gets the date; `status: done`, or `--status planned` for prep). Point-in-time, so it is
    frozen once the occasion is over; its decisions move to the parent's `## Decisions`.
  - a **digest** is the compiled reading of one heavy `raw/` file: key facts with locators
    (§, clause, page), and what they mean for the parent. `brain new resource <slug>
    --digest-of raw/<file> --parent <page>` pins `source` + `sha256`, so `check` notices if
    the source ever changed. Read the digest, and open the source only to verify a claim.
- `archive/` — completed or dormant items moved out of the buckets above.
- `mocs/` — Maps of Content: index notes linking a topic's pages. Use for **cross-cutting**
  themes that span many pages (one page may belong to several MOCs — folders cannot express this).
- `raw/` — immutable records of what was **exchanged**: what you received (documents,
  transcripts, exports, research output, pasted text) and what you sent, frozen as sent (the
  questions another party then answers). Never edit — **the commit gate refuses an in-place
  edit** (since v16); compile from here into pages. A note you wrote **for yourself** — prep, a
  call script, meeting notes — is not raw: it is an event page. A note mis-filed here leaves
  only via **`brain mv raw/<file> resources/<slug> --event --parent <page>`**. A PDF is kept beside
  its `-fulltext.md` extraction, which is what links and digests point at. Any raw markdown file of
  16 KiB or more without a digest is listed by `brain review` (and by `health` after a week).
  `raw/inbox.md` is the one exception: an append-only list of one-line
  captures written by **`brain capture`**, from which lines are *deleted* as they're processed.
- `mocs/now.md` — the **judgment** behind the current ordering. The generated view (what's live,
  blocked, overdue, gone quiet, open tasks) is **`brain review`** — never hand-maintain that here.
  This page holds only why this order, and what you're deliberately not doing.
- `mocs/goals.md` — the same split at quarter scale: why this quarter's ordering, the NOT-doing
  list with reasons, what's deferred. The generated rollup (children, milestones, what's orphaned
  or stalled) is `brain review`'s Goals section — never hand-maintain it here either.
- `index.md` — master catalog. The section list is **generated** between the
  `<!-- BEGIN generated -->` / `<!-- END generated -->` markers — never hand-edit inside them.
  The pre-commit hook regenerates it from frontmatter on **every commit**, so it can't drift; you
  can also run `brain reindex` explicitly to preview. Everything outside the markers (preamble, the
  `▶ Current focus` pointer, hand-listed reference files) is preserved.
- `log.md` — append-only activity log, newest first. **Every entry is dated** — `- YYYY-MM-DD — <what changed> — [[page]]` — making it the canonical "what happened when" timeline. When it grows
  past ~400 lines, run **`brain rotate-log`** — it moves the older tail verbatim into
  `log-archive/YYYY.md` and keeps the recent window hot (`health` flags this; the rotation is
  mechanical, so just run it and commit); `git log` remains the ultimate backstop timeline.
  One sanctioned mechanical touch besides rotation: **`brain mv` retargets `[[links]]`** inside
  entries when a page moves/renames — the entry's text never changes, only where its link points
  (same spirit as rotate-log: verbatim content, kept resolvable).

## Page schema (YAML frontmatter)

This schema is **enforced** by `brain check` — its machine-readable definition lives in the
`brain` CLI (`brain.py`, shipped from nixos-config); the block below is the human mirror. Every
page begins with:

```yaml
---
title: Human title
kind: goal | initiative | project | area | resource | moc
status: idea | planned | active | blocked | done | archived
attention: focus | tracking  # optional — omit for ordinary active work
progress: "optional — and ONLY on a page with no tracker: see .agents/rules/tracker-standings.md"
next: "optional — the single next concrete move"
owner: me
created: YYYY-MM-DD          # ISO date — set once on creation, never changed
updated: YYYY-MM-DD          # ISO date — refresh on every edit
verified: YYYY-MM-DD         # optional — when this page's claims were last checked
started: YYYY-MM-DD          # optional — set when status → active
finished: YYYY-MM-DD         # optional — set when status → done
due: YYYY-MM-DD              # optional — target date, if any
summary: "one-line catalog description — what index.md shows for this page"
parent: "[[parent-page]]"    # optional — nests this page under another in index.md; a goal's
                             #   names its area, a project's its goal (or area)
source: "[[raw/2026-11-03-x]]"  # digests only — the raw/ file compiled (written by --digest-of)
sha256: <64 hex>             # digests only — the source's hash when it was digested
repos:                       # optional — the workspaces this page owns (written by `brain track`)
  - github.com/owner/repo    #   see .agents/rules/workspaces.md: a remote, git:<root-commit>, ~/path, or repo//subfolder
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

Field-by-field meanings, the link model, and page-vs-section: `.agents/rules/schema.md`.

## Tooling — the `brain` CLI (prefer it over hand-editing frontmatter)

`brain` is a Nix-managed command on `PATH` and is the **deterministic gate** for this store: it
owns the schema, so a malformed heading can't slip in. Use it for every frontmatter write and
query; only drop to hand-editing page **bodies** (prose below the frontmatter).

```bash
brain new <kind> <slug> [--title T --status S --attention A --summary "…" --next "…"
                         --due D --parent P --tags a,b
                         --person | --org | --event | --digest-of raw/<file>]
                              # create a schema-perfect page, with a body skeleton for its kind;
                              # <slug> may carry subdirectories (new resource scripts/deploy);
                              # the four shape flags are `new resource` only
brain set <page> <field> <value>   # set one field, validated; stamps updated (+ started/finished)
                                   # date fields accept `today` so you never hand-type one
brain unset <page> <field>         # remove one optional field (never a required one); stamps updated
brain done <page>                  # status=done + finished=today + updated=today
brain reindex                      # regenerate index.md's generated region from frontmatter,
                                   # + people.md's generated "Where they appear" column
brain links [--strict] [--json]    # lint internal links — broken/ambiguous [[wikilinks]] are
                                   # errors (the gate runs this); relative markdown paths warn
brain links --to <page>            # backlinks: list the pages that link to <page>
brain mv <page> <bucket>/<slug>    # move/rename a page, rewriting [[references]] store-wide
                                   # (the archive lifecycle: brain mv <page> archive/<slug>)
brain mv raw/<file> resources/<slug> --event [--parent P]
                                   # adopt a note for yourself, mis-filed in raw/, as an event page
brain review [--since DAYS] [--stale DAYS] [--log N] [--json]
                                   # READ-ONLY briefing; --since gives the window ("what moved")
brain q [--status S | --kind K | --tag T | --attention A | --overdue | --due-before D
         | --stale DAYS [--all] | --unverified [DAYS] | --under PAGE] [--json]
                                   # --under: everything whose parent chain reaches PAGE
brain check [--staged] [--strict]  # validate frontmatter + links + state readings (the gate);
                                   # --staged judges state readings only on the lines a commit
                                   # ADDS; --strict promotes the whole-store backlog to errors
brain normalize [paths…]           # repair-on-drift: lowercase status/kind, map synonyms, sort tags
brain capture "<text>" | - [--title SLUG]   # append to raw/inbox.md, or write a raw file from stdin
brain log "<what changed> — [[page]]"  # prepend a dated log.md entry (date from the clock)
brain log --for <page>             # read that page's log entries (don't re-narrate them in the body)
brain rotate-log [--keep N]        # move log.md's older tail into log-archive/YYYY.md, verbatim
brain health [--json] [--no-fetch] # one-line vitals; SILENT + exit 0 when clean (surfaced ambiently)
brain sync [--dry-run]             # mechanical template refresh + stamp; stops before stamping
                                   # when the version gap needs a judgment backfill (/brain --sync)
brain version [--stamp]            # CLI vs store template version; --stamp writes .brain-version
brain today                        # today's date from the system clock — never infer it
brain commit -m "<msg>" [--log "<entry>"] <paths…>
                                   # commit ONLY these paths (+ your log entry) — see Committing
brain where [--dir D] [--json | --all]   # which page this directory's project belongs to
brain track <page> [--dir D] [--subdir]  # claim this repo (or its subfolder) for <page>
brain ignore [--dir D] | brain snooze [--dir D] [--days N]
                                   # never ask about this workspace / ask again in N days (30)
```

What each command guarantees, the gate, auto-push and `brain health`: `.agents/rules/tooling.md`.

## Committing — other sessions may be writing too

Assume another agent session — another terminal, another harness, the other machine's clone
after a pull — may be editing this store right now. So:

- **Commit only the files you wrote, with `brain commit`.** Keep a list as you go: every writer
  prints the path it wrote (`brain new`, `set`, `done`, `track`, `ignore`/`snooze` →
  `workspaces.md`), `brain mv` prints the destination and every file whose links it rewrote, and
  pages you hand-edit are yours too. For a move, pass both sides — the old path stages the
  deletion. Then: `brain commit -m "<msg>" --log "<what changed> — [[page]]" <paths…>`.
- **Never `git add -A`, `git add .` or `git commit -a`** — they commit other sessions' half-done
  work, and the auto-push publishes it.
- **Your log entry goes through `--log`, not `brain log` + commit.** `log.md` is shared: every
  session prepends to it. `--log` writes your entry into the staged version as well as the working
  file, so other sessions' uncommitted entries stay theirs. Wherever this manual says "`brain log`
  …, then commit", do it as one `brain commit --log`. (`brain log` alone is for a store no one
  else is touching — and `log.md` is passed as a path only after `brain rotate-log`.)
- **If `brain commit` says other changes are already staged**, they are not yours: don't commit,
  unstage or "clean up" them. Tell the user, and commit once that session has.
- **`brain sync` refuses a dirty tree** — with concurrent sessions that is a feature: wait, or ask.

## Topic rules — read the matching one before acting

This file is the always-loaded core. The rest of the manual is split by topic under
`.agents/rules/` (Antigravity's rules convention: each file carries a `trigger` and a
`description`, and its body is loaded when the task matches). **Whatever the harness: before
doing one of the things below, read that file** — `~/brain/.agents/rules/<file>`.

| Before you… | Read |
|---|---|
| capture or ingest information, answer a question about the store, update a status | `capture-and-query.md` |
| run a review, trim `now.md`, archive, or reorganise / split pages | `review-and-lint.md` |
| put a session in the brain ("save this session") | `file-a-session.md` |
| create a page, change a field, add links, or decide page vs. section | `schema.md` |
| write a page body | `page-bodies.md` |
| write anything citing issues, PRs or tracker projects | `tracker-standings.md` |
| create, review or change goals | `goals.md` |
| add or edit a person or a company | `people-and-orgs.md` |
| act on a session-start workspace message, or run `brain track`/`ignore`/`snooze` | `workspaces.md` |
| need to know why a command, the gate or a health flag behaves as it does | `tooling.md` |
| want a rule, the schema or a hook changed — or the CLI misbehaves | `maintaining.md` |

**The one rule you need before reading any of them:** outside `## Tracker`, `## Decisions`,
`## Drift`, `## Execution log` and `## Wins`, do not put a status word next to an issue key — the
tracker holds the standings, this store holds the design (`tracker-standings.md`; the commit gate
enforces it on the lines you add).

**Governance, in one line:** the CLI, schema and hooks are Nix-managed in nixos-config — if a
check or rule should change, stop and ask David; never edit the deployed copies, loosen a check
locally or `--no-verify` past the gate. If the CLI itself misbehaves, report it as a bug
(`maintaining.md`).

## Guardrails

- Files are the source of truth; **`brain reindex`** keeps `index.md` and people.md's generated
  column consistent with the pages — don't hand-maintain either.
- **Never write a `[[link]]` to a page that doesn't exist** (the gate rejects it), and **move or
  rename pages only with `brain mv`** — a hand `mv` breaks every path-qualified reference.
- **Write frontmatter through the `brain` CLI**, not by hand — that's what keeps it schema-valid.
- **Don't restate the tracker.** Cite the identifier, never the status — see `tracker-standings.md` (**Pages hold the
  design; the tracker holds the standings**). `<!-- state-ok -->` silences the check for one line;
  it is not a way to keep a ledger, and every use is greppable for the LINT pass.
- **Run `brain check` before committing**; never bypass the pre-commit gate (`--no-verify`) or
  loosen a rule locally. To change a rule, see `maintaining.md` (ask David → change nixos-config).
- **The store auto-pushes** to its remote (post-commit hook) when one exists, auto-reconciling a
  moved remote (`pull --rebase` + retry, never force). If it reports real conflicts, reconcile by
  hand with `git -C ~/brain pull --rebase`, resolve, push — never force-push, and never disable
  the hooks.
- **Dates come from the system clock, never inferred from the corpus.** Let the writers and
  `brain log` stamp dates; use `brain today` for any date you must supply. A date seen in `log.md`
  or a page is a recorded fact, not "today".
- **`brain review` writes nothing, and no command rewrites a page body.** Trimming `now.md`,
  splitting an oversized page, or resolving a contradiction is a supervised edit you propose and
  the user approves — never a side effect of a read.
- Never fabricate status. Mark gaps with `<!-- TODO: fill -->`.
- Commit after every change set — **only your own files, with `brain commit`**, never
  `git add -A` (other sessions may be mid-edit; see **Committing** above). No AI attribution in commit
  messages.
- Never store secrets, credentials, or PII you don't need.
