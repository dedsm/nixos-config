# The `brain` skill

A personal "second brain" Claude Code skill: a local, git-backed markdown knowledge base tracking the status and narrative of projects, initiatives, decisions/ADRs, and other ongoing work — usable from any Claude Code session, in any repo or none.

Shipped from: [`modules/common/users/common/claude-code/skills/brain/`](../modules/common/users/common/claude-code/skills/brain/) (`SKILL.md`, `brain.py`, `templates/`), wired up by the `claude-code` home-manager module — see [`claude-code.md`](./claude-code.md).

## What's managed vs. what's yours

This repo manages exactly three things, and deliberately nothing else:

1. **The skill + CLI + canonical template** — `SKILL.md` (the mechanism: how to capture/query/update/reorganize), `brain.py` (the `brain` CLI: schema, validator, index generator, and the constrained frontmatter writers), and `templates/` (the canonical `CLAUDE.md` operating manual + store scaffold: `index.md`, `log.md`, bucket layout). `SKILL.md` + `templates/` are symlinked into `~/.claude/skills/brain/`, and `brain.py` is packaged onto `PATH` as `brain`, on every `home-manager switch`.
2. **The commit hooks** — the activation script (re)installs two hooks into `~/brain/.git/hooks` on **every** switch (for new *and* existing stores, so they always point at the current `brain`). **Nix is their sole installer** — the CLI has no `install-hooks` verb, so there is exactly one definition of each and no way for it to drift. (a) A `pre-commit` gate regenerates + stages `index.md` (the catalog can't drift — no reliance on anyone remembering to reindex) and then execs the Nix-managed `brain check --staged`, so a commit containing a schema-invalid page is rejected (for agent, hand, and Obsidian edits alike). (b) A `post-commit` hook pushes the store to its remote when one is configured, so a commit is also a backup + multi-machine sync; when the remote has moved (the other machine pushed first) it **reconciles automatically** — `pull --rebase`, push again — and only real conflicts stop it (the rebase is aborted, a hint is printed, the commit stands). It never force-pushes (BatchMode so it can't hang on an SSH prompt), and an unreachable remote is non-fatal. Because the hooks are thin shims, their logic only ever changes via `brain.py` / `default.nix`.
3. **A one-time bootstrap** that seeds `~/brain` from the template *only if `~/brain` doesn't exist yet* (`home.activation.bootstrapBrain` in `default.nix`). It copies the template, `chmod -R u+w`s it (Nix store files are read-only), and `git init`s it — then runs `brain normalize` (scaffold pages such as `mocs/now.md` ship with a sentinel date, since a static template can't know the seeding date) and `brain version --stamp`, so a fresh store isn't reported as behind. The same activation installs the hooks.

The store's actual content — pages, `index.md`, `log.md`, as they evolve — is mutable user data and is **never** touched, symlinked, or overwritten by a rebuild. Once `~/brain` exists, this repo leaves its content alone (only the hook shims are refreshed, so their store paths stay current).

## Deterministic retrieval: the `brain` CLI

The store is small and plain-text by design, so retrieval is deliberately **not** a vector/RAG index (which would add a non-diffable, rebuild-on-change binary artifact and break the Obsidian-native, git-diffable model). Instead, reliability comes from making the frontmatter a trustworthy structured index and querying it directly. `brain` provides three layers:

- **Layer 1 — schema.** The allowed `kind`/`status` enums, required fields, and ISO date format are defined once, machine-readably, in `brain.py` (the manual's schema block is the human mirror).
- **Layer 2 — the gate.** `brain check` validates every page against that schema and exits non-zero on violations; the pre-commit hook runs it so malformed frontmatter physically cannot enter the store. Determinism lives in the validator + git, not in the model's diligence.
- **Layer 3 — constrained writers.** `brain new` / `brain set` / `brain unset` / `brain done` own the YAML serialization (legal enum values, ISO dates stamped from the real clock, `updated`/`started`/`finished` maintained automatically), so the model chooses values from a constrained set and never hand-writes the shape — malformed frontmatter is unrepresentable. `brain unset` drops an optional field (refusing required ones) so clearing a field never means hand-deleting a line either.

**Dates come from the system clock, never the corpus.** A recurring LLM failure mode is reading a date out of `log.md` or a page and treating it as "today". The writers stamp `created`/`updated`/`started`/`finished` from the clock, `brain log "…"` dates activity entries from the clock (so the model never types the date), and `brain today` is the authoritative "now" for the rare date a caller must supply by hand (e.g. a relative `due`). The manual and `SKILL.md` make "never infer today from the corpus" an explicit guardrail.

On top of these: `brain reindex` regenerates the catalog region of `index.md` as a pure projection of the frontmatter (drift becomes a `git diff`, or a non-zero `brain reindex --check`), and `brain q` answers structured/temporal queries (`--status`, `--kind`, `--tag`, `--attention`, `--overdue`, `--due-before`, `--stale DAYS`, `--unverified`) directly from frontmatter instead of the model grep-guessing.

### `brain review` — the generated half of a "now" page

`brain review` is a **read-only** briefing: current focus, live work grouped by `attention`, what's blocked or overdue, what has gone quiet, oversized pages, the recent `log.md` window, open `dstask` (parsed from its JSON output), and the pending `raw/inbox.md` count. `--since DAYS` switches to a window ("what moved this week, and what didn't"); `--json` makes it consumable by other tooling.

It exists because the alternative is a hand-maintained "now" page, and those rot: they duplicate the index, the per-page statuses and a copied task list, and they go stale within days while still reading as authoritative. Splitting that page in two — *generated* (this command, always current) and *judgment* (`mocs/now.md`: why this ordering, what you're deliberately not doing) — removes the incentive to maintain the rotting half at all. `review` therefore **writes nothing**; trimming `now.md` is a supervised edit in the REVIEW workflow, never a side effect of a read.

Two schema fields make the briefing sharp rather than a status dump:

- **`verified`** — when the page's *claims* were last checked against reality, as distinct from `updated`, which moves on a typo fix. Staleness is judged on `verified` (falling back to `updated`), so a page nobody edited but that you re-checked yesterday no longer reads as rotten, and one that was edited cosmetically no longer reads as fresh. It fails in the safe direction: forgetting to bump it makes a page look *more* stale, which prompts a check.
- **`attention`** — deliberately three states (`focus`, `tracking`, absent) rather than a priority ladder, because the finer the ladder the faster it rots. It replaces priority-as-bold-prose in `summary`, which no query could see.

`brain capture "<text>"` is the matching entry point: one line into `raw/inbox.md` from any terminal, no session and no schema, because second brains die at capture rather than at retrieval. `brain capture - --title <slug>` writes substantial piped material to its own immutable `raw/` file instead.

### Ambient surfacing: `brain health`

Every detector above is pull-only — `review` answers only when someone runs it, and the observed v9 failure mode was exactly that: version drift, an aging inbox and a silent log, all flagged somewhere, none seen for weeks. `brain health` compresses those signals (version drift, overdue, gone-quiet, never-verified live work, aged inbox, quiet or oversized log, `now.md` rot, ahead/behind the remote) into **one line**, printing nothing and exiting 0 when clean — shaped for ambient consumers rather than hands. Two are wired by the claude-code module:

- A **Claude Code SessionStart hook** (`claude-brain-health.sh`, in `managedSettings`) runs it on session start/resume/clear (not compact) and injects any output as context. Fail-open — it always exits 0, so a broken store can never block a session.
- A **weekly timer** (systemd user timer on Linux, launchd agent on Darwin; Mon 10:00, persistent so a sleeping laptop fires on wake) raises a desktop notification (notify-send / cli-notify) when health exits non-zero — covering the days when no session happens at all, which is precisely when a store rots.

The ahead/behind check is the store's first *pull*-side signal: a short-timeout, BatchMode, fail-soft `git fetch` (skippable with `--no-fetch`), so a stale clone announces itself before anything writes against old state. `brain rotate-log` is the mechanical fix for one of health's flags: past ~400 lines it moves `log.md`'s older tail verbatim into `log-archive/YYYY.md` (newest-first preserved, continuation lines kept with their entries, no judgment involved) — the manual tells the agent to run it on sight, no approval needed.

### Page bodies

`brain new` emits a body skeleton per kind, in which every section is marked **rewritten in place** or **appended to**. That single distinction is the point: without it, dated "current state" sections accumulate (a page carries both a June and a July "where it stands") and pages grow without bound. The shapes are drawn from what the real stores already do well — an orienting paragraph, a "so it isn't re-litigated" rationale, a rewritten current state stamped with what was checked, appended dated decisions with consequences, a shrinking "open", and a `## Drift` section for projects tracking an external design doc.

### People

`mocs/people.md` is a directory of people — a table, whose columns are suggested rather than required (a personal store holds people with no Slack handle, no work email and no title). Someone gets their own page only once they accumulate narrative that won't fit in a row: `brain new resource <slug> --person` creates it as `kind: resource` + `tags: [person]` with a person skeleton.

Person pages are **excluded from `index.md`**: `reindex` skips `tags: [person]`, so the catalog carries exactly one line — the people MOC — whether you know 2 people or 200, and the index stays constant-size as the directory grows. They stay fully inside the system (`brain check` validates them, `brain q --tag person` finds them); the lint pass knows they are catalogued by a MOC and so are not orphans.

### Version stamping

`.brain-version` records the template version the store has actually been migrated to, and `brain check` prints a note whenever it is behind the CLI — so a machine that has rebuilt but not synced says so on every commit. `brain version --stamp` writes it as the **last** step of a migration, after the page backfill has landed. Keeping the stamp out of `CLAUDE.md` (where the version comment used to be the only marker) is what makes an interrupted sync safe: the manual is replaced early, so a store could otherwise claim to be current while its pages were not, and the next sync would skip it.

### Governance: the CLI, schema, and hook are canonical here

`brain.py`, the schema it enforces, and the hook are canonical artifacts shipped from this repo; the on-machine copies are read-only Nix deployments. The manual and `SKILL.md` instruct Claude that **if a check, the schema, or a hook needs to change, it must stop and ask to update the skill in this repo**, then rebuild and `/brain --sync` — never hand-edit the deployed CLI/hook, loosen a failing check locally, or `--no-verify` past the gate. This keeps every machine's store enforcing the same rules.

There is deliberately **no test suite for `brain.py`: real usage is the test.** The manual and `SKILL.md` make the agent the harness — if the CLI misbehaves (mangled frontmatter after a write, a wrong date, a corrupted index or log, an exit code contradicting what happened), the instruction is to stop, report the exact observation, and propose the fix here in nixos-config — never to silently hand-repair the damage and move on.

## Staying in sync

Because the store is a one-time copy, it can drift from the template as the skill/CLI evolve (new schema fields, new bucket conventions, etc.). **`brain sync` is the migration behavior**, and it is mechanical-first:

- The verb executes the judgment-free phase itself — replace `CLAUDE.md` with the canonical manual (the template's Nix store path is baked into the CLI at build time; `BRAIN_TEMPLATE_DIR` overrides it for development), create missing bucket dirs and scaffold files (never overwriting an existing one), `normalize`, `reindex`, untrack anything newly `.gitignore`d — as **one tight commit**. It refuses to start on a dirty tree, so the commit stays cleanly revertible (the store auto-pushes, so recovery is `git revert`, never a force-push).
- It then **stamps `.brain-version` in a second commit if and only if the gap is safe**: `brain.py` carries a `JUDGMENT_MIGRATIONS` registry of versions whose upgrade needs a model-executed, diff-and-ask backfill (v8 — `verified`/`attention`/`next` lifted out of prose — is the registered example; purely additive bumps don't register). When the store's gap crosses one of those, or the store was never stamped, `sync` stops before stamping, prints what's left, and exits non-zero — **`/brain --sync`** (the skill procedure) finishes the backfill and stamps last.

This revises the original "deliberately no migration script" stance, on evidence: both real stores sat a full template version behind for weeks with the drift note printing on every commit, because even the judgment-free phase required a supervised session. The revision is scoped to exactly that phase — the CLI never stamps across work it didn't do, so stamp-last and "an interrupted sync stays visibly behind" survive unchanged. The commit hooks are still installed by the rebuild, never by sync.

Sync never touches the substance of existing pages: trimming `mocs/now.md`, splitting an oversized page, or collapsing accumulated status sections is content work for the REVIEW and LINT passes.

## Day to day

See `SKILL.md` for the full procedure; in short: `~/brain/CLAUDE.md` is the operating manual (read it first), `brain review` is the current picture and `~/brain/index.md` the full catalog (generated by `brain reindex`), captures/updates go through the `brain` CLI (`capture`/`new`/`set`/`done`) + a dated `log.md` entry, and every change is committed to the store's own git repo (where the pre-commit gate re-validates it). Since v10, three workflow lanes close the "knowledge doesn't compound" gap: QUERY **offers to file expensive cross-page syntheses back** as `resources/` pages (ask-first, stamped `verified today`), CAPTURE routes **durable reference knowledge** (how-tos, learned facts with no other system of record) to `resources/` as a first-class destination, and the manual's **"Where knowledge lives"** rule decides when a topic earns a page at all (2+ linkers, or an independent lifecycle — otherwise it's a section). `brain new` accepts subdirectory slugs (`new resource scripts/deploy`) so nested pages are created by the constrained writer rather than by hand. Discrete personal next-actions go through `dstask` (installed via `flake.nix`'s package list) rather than as brain pages; overall initiative narrative/status belongs in a brain page. Task **notes** must go through **`dstask-note <id> "<text>"`** (`pkgs/dstask-note/`), not `dstask note`: the upstream command requires a controlling TTY and, run from a script or agent session, exits 0 without writing the note or committing anything — a silent no-op with no signal that it failed. The wrapper runs it under a pty and hides the BSD/util-linux `script(1)` syntax split, so the same invocation works on manwe and morgoth. All other dstask verbs the skill uses (`add`/`start`/`stop`/`done`/`modify`) work headlessly. Work that belongs in an external/team issue tracker is linked to, not duplicated, per the rules of whatever workspace you're in.
