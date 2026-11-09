---
trigger: model_decision
description: "Workflows for capturing or ingesting information, answering questions about the store (including time-range questions and filing an expensive synthesis back), and updating a page's status. Read before any capture, query or status update."
---

# Workflows — capture, query, update

### 1. CAPTURE / INGEST — "track this", "remember", an info dump

0. **Process the inbox first if it has entries.** `raw/inbox.md` holds one-line captures made
   outside a session with **`brain capture`**. For each: route it (update an existing page, create
   one, file a dstask, reference an external issue, save it as reference knowledge in `resources/`,
   or drop it), then **delete that line** — the pending count is the backlog, so nothing else needs
   tracking.
1. If the input is substantial source material, save it verbatim to `raw/YYYY-MM-DD-slug.md`
   (**`brain capture - --title <slug>`** does this from stdin) — skip for trivial one-liners.
2. Create or update the page: **`brain new <kind> <slug> --summary "…" [--status …]`** for a new
   page, or **`brain set <page> <field> <value>`** to update fields on an existing one. Edit the
   page **body** by hand. The writers set `created`/`updated`/`started`/`finished` for you.
3. Wire cross-references: add `[[links]]` in the body, and add the page to every relevant MOC.
4. If the input implies a personal next-action → create a dstask task and link it. If it is an
   issue that belongs in a team tracker → reference it there (per the active workspace's rules);
   do not duplicate. If it is **durable reference knowledge** — a how-to, a learned fact, a
   worked-out explanation with no other system of record — give it a `resources/` page
   (`brain new resource <slug>`; tag it something queryable like `howto`), or an APPEND section on
   the single page that owns it when it's small. The systems-of-record rule already admits
   anything neither dstask nor a tracker captures; don't drop it just because it isn't status.
   A **goal idea** ("this should be a quarterly goal") → `brain new goal <slug> --status idea` —
   it queues for the quarterly pass, findable via `brain q --kind goal --status idea`.
5. **`brain check`**, then commit and record it in one step — only the files you wrote (see
   **Committing** in `AGENTS.md`): `brain commit -m "<msg>" --log "<what changed> — [[page]]" <paths…>`. The
   entry is dated from the clock (don't hand-type the date); the pre-commit hook reindexes and
   re-checks, so a clean `check` means it passes.

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

**File the answer back when it earned it.** If producing an answer required synthesizing across
3+ pages or external systems (code, trackers, dstask) and the result is durable knowledge recorded
on no single page, **offer** to file it — ask first, never as a side effect of a read:
`brain new resource <slug> --summary "…"`, the body carrying the synthesis plus an "Informed by"
list of `[[page]]` links and external references; then `brain set <slug> verified today` (earned —
the claims were just checked to produce the answer), `brain log`, commit. An expensive cross-page
synthesis that vanishes into chat history is compounding lost. Trivia doesn't qualify.

### 3. UPDATE STATUS

**`brain set <page> status <value>`** (or `brain done <page>`) — it bumps `updated` and stamps
`started`/`finished` as the status crosses `active`/`done`. Edit the body for narrative, record it
with **`brain log "…"`**, `brain check`, commit.
