---
name: brain
description: >
  Personal tracking store ("second brain") at ~/brain — a local, git-backed markdown knowledge
  base tracking the status and narrative of projects, initiatives, decisions/ADRs, and other
  ongoing work, usable from any session in any repo or none. Use whenever the user wants to
  CAPTURE info ("track this", "remember", "note that", "log this"), QUERY state ("what's the state
  of X", "what am I tracking", "status of <project>", "what did I work on this quarter"), UPDATE a status, REORGANIZE / lint the
  store, or run `--sync` to migrate the store to the latest conventions. Also handles a personal
  task lifecycle via dstask. For work that belongs in an external
  issue tracker, link to it rather than duplicating (per the active workspace's rules).
---

# brain — personal tracking store

The store lives at `~/brain` (plain markdown + git). It is global: this skill works from **any**
session — inside a repo, another repo, or none. Always operate on the absolute `~/brain` path, not
the current working directory.

Store conventions — bucket structure, page schema, workflows — live in `~/brain/CLAUDE.md`, the
working manual to follow for day-to-day operations. The **canonical** copy of that manual and the
store scaffold ship with this skill at `~/.claude/skills/brain/templates/`; `--sync` reconciles a
store toward it. How to route work to an external/team tracker is defined by the **active
workspace's own rules** (e.g. a repo's `.claude/` rules), not here. This skill is the generic
mechanism.

## Procedure

1. **Read** `~/brain/CLAUDE.md` (the operating manual: structure, page schema, workflows,
   guardrails — the source of truth) then `~/brain/index.md` (current catalog).
2. **Act** per the matching workflow in `CLAUDE.md`:
   - **Capture/ingest** new info → file into the right bucket + relevant MOCs, set frontmatter
     (`status`; `created` on new pages; `started`/`finished` as status crosses active/done; bump
     `updated`), update `index.md`, prepend a **dated** entry to `log.md`.
   - **Query** → answer from the pages; pull open `dstask` tasks and any linked external issues
     when relevant; flag stale data; never invent. **Time-range** questions ("what did I work on
     in the past 3 months", "what shipped in Q1", "what's overdue") → filter the dated `log.md` +
     `created`/`started`/`finished`/`due` to the window (git log + dstask dates as backstops).
   - **Update status** → edit frontmatter (`status`/`progress`), bump `updated` (set `started`/`finished` when crossing active/done), reflect in index + a dated log entry.
   - **Lint/reorg** → run the health pass (split/merge/re-file/refresh-index/flag-contradictions).
3. **Personal tasks** (via dstask, driven by Bash):
   - `dstask add <desc> +<tag>` · `dstask` (list) · `dstask start|stop|done <id>` · `dstask note <id>`.
   - Cross-link: put `dstask:<id>` in the page's `links`; reference the page in the task note.
   - **Routing rule:** discrete personal next-action → dstask. Overall initiative state/narrative →
     a `~/brain` page (frontmatter + body). Work that belongs in an external/team tracker → that
     tracker, per the active workspace's own rules (e.g. its `.claude/` rules); link to it, don't
     duplicate.
4. **Commit** after any change:
   `git -C ~/brain add -A && git -C ~/brain commit -m "<concise message>"` (no AI attribution).

## Sync / migration (`/brain --sync`)

Run when invoked with `--sync` (or `sync`) — brings this machine's existing `~/brain` up to the
latest conventions after the skill/template were updated (e.g. by a rebuild).

1. **Read the canonical template** at `~/.claude/skills/brain/templates/` — especially its
   `CLAUDE.md` (the authoritative manual, structure, and page schema) and the `brain-template`
   version at its top.
2. **Compare** against the live `~/brain` (its `CLAUDE.md`, bucket layout, page frontmatter).
3. **Reconcile** — show a diff first, and ask before anything destructive:
   - Replace `~/brain/CLAUDE.md` with the canonical manual (the manual is canonical, not per-store).
   - Create any missing bucket dirs.
   - Migrate every page's frontmatter to the current schema (add/rename/drop fields). When adding
     `created` (and `finished` for done pages), backfill from git where possible —
     `git -C ~/brain log --diff-filter=A --format=%ad --date=short -- <file>` for first-commit date.
   - Regenerate `index.md` in the current format.
4. **Report** a summary, append it to `log.md`, and commit.

This touches only structure, schema, and the manual — never the substance of pages. Git is the
safety net; prefer mechanical, reversible edits.

## Guardrails

- Files are the source of truth; keep `index.md` consistent with the pages.
- Never fabricate status; mark gaps with `<!-- TODO: fill -->`.
- Never store secrets, credentials, or unnecessary PII.
