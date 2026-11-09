---
trigger: model_decision
description: "How the brain CLI behaves: the writers, dates from the clock, review, capture, reindex, the pre-commit gate and what it rejects, auto-push, and brain health's flags and remedies. Read when a command's behaviour, a gate rejection or a health flag needs explaining."
---

# The `brain` CLI — how it behaves

The command list is in `AGENTS.md`; this is what the commands guarantee.

- **Writers** (`new`/`set`/`unset`/`done`) are the reason frontmatter stays clean: they only ever
  emit legal enum values and ISO dates, and stamp `updated`/`started`/`finished` for you. Reach for
  them instead of typing YAML — including `unset` to drop an optional field (it refuses required
  ones), rather than hand-deleting a line.
- **Dates come from the clock, never from the corpus.** The writers and `brain log` date
  everything from the system clock; `brain today` is the authoritative "now". **Never read a date
  out of `log.md`, git history, or a page and treat it as today** — those are recorded facts, not
  the current date. If you must write a date by hand (e.g. a relative `due` like "next Friday"),
  get today from `brain today` (or `date +%F`) and compute from it.
- **`review` writes nothing.** It is the generated half of a "now" page — the goals rollup
  (children, milestones, orphaned/stalled), focus, work grouped by `attention`, blocked, overdue,
  what's gone quiet, oversized pages, recent log, open dstask, pending inbox. Start any session
  on this store with it. Because it produces that picture on demand and always current, there is
  no reason left to hand-maintain a copy of it anywhere.
- **`capture` is the zero-friction path in.** One line from any terminal, no session, no schema —
  which matters because second brains die at capture, not at retrieval. Substantial material
  (`- --title <slug>`) lands as its own immutable `raw/` file instead of an inbox line.
- **`reindex`** makes `index.md` — and the directories' "Where they appear" columns — a
  projection of the pages. You rarely call it by hand: the pre-commit hook regenerates and stages
  them on every commit, from the *staged* tree (`reindex --staged`). Run it explicitly only to preview the catalog, or use
  `brain reindex --check` (exits non-zero if stale) as a drift detector.
- **The gate**: a `pre-commit` hook in `~/brain/.git/hooks` regenerates `index.md` and the
  directories' generated columns **from what is staged**, stages them, then runs
  `brain check --staged` against the staged versions — so a commit with a malformed page is
  **rejected**, and the catalog is always fresh, for LLM edits, hand edits, and Obsidian edits
  alike. Building from the staged tree is what keeps another session's unsaved pages out of your
  commit's catalog; a working copy of a generated file is updated only where it had no unstaged
  edits. Run `brain check` yourself before committing for fast feedback.
  `check` reports enum / required-field / date-format problems **and broken/ambiguous internal
  links** (a whole-store link pass — a staged deletion can break another file's inbound links;
  under `--staged` links resolve against the *git index*, so an untracked draft can't satisfy
  one) as **errors** (blocking), and softer issues (done without `finished`, relative markdown
  paths, etc.) as **warnings** (non-blocking). Two consequences: **create a page before linking
  it** (`brain new`, then link), and **stage a new page together with the pages that link it**.
  It also rejects a **state reading** (a status word beside an issue key, a PR ledger, an issue
  tally) — but under `--staged`, only on the lines the commit **adds**, so an existing page's
  backlog never blocks unrelated work; the whole store is a `--strict` warning instead. See
  `tracker-standings.md` for the rule, its five exempt
  sections, its blind spot and the `<!-- state-ok -->` escape.
  Link errors **always** block, including in the rebuild→sync window: every store is link-clean, so
  the deferral that once softened them there is gone. Deferrals now cover exactly what a pending
  migration is *about* — a `kind` the schema no longer knows (v12), and `progress` plus the state
  readings (v14) — each demoting to a warning until the store is stamped, because otherwise
  `brain sync`'s own mechanical commit could not pass its own gate.
- **Auto-push**: a `post-commit` hook pushes the store to its remote when one is configured, so a
  commit is also a backup and multi-machine sync — no reliance on remembering `git push`. If the
  push is rejected because the remote moved (another machine pushed first), the hook **reconciles
  automatically**: `pull --rebase`, then push again. Only real conflicts stop it — the rebase is
  aborted (the store stays exactly as committed) and it prints a hint to reconcile by hand with
  `git -C ~/brain pull --rebase`. It **never force-pushes**, and an unreachable remote is non-fatal
  (the commit stands; `health` will report unpushed commits). It also never stashes or rebases
  over **uncommitted changes**, which are usually another session's work in progress: then it
  leaves the commit unpushed and says so, and a later commit from a clean tree pushes it. **Both hooks are Nix-managed** — the
  nixos-config activation installs them on every rebuild; the CLI has no install verb (so they
  can't drift).
- **Ambient vitals — `brain health`**: every detector above is pull-only; `health` compresses them
  (version drift, overdue, stalled/orphaned goals, gone-quiet, never-verified, aged inbox, quiet
  or oversized log, broken links, `now.md` rot, ahead/behind the remote) into **one line**,
  printing nothing and exiting 0 when all is well.
  It is surfaced without anyone asking: each agent harness's SessionStart hook injects the line into new
  sessions, and a weekly timer raises a desktop notification — covering the weeks when no session
  happens at all. React
  to it: oversized log → `brain rotate-log` and commit (mechanical, no approval needed); behind the
  remote → `git -C ~/brain pull --rebase` **before** writing anything; the rest → the REVIEW pass.
