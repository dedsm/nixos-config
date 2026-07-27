# The `brain` skill

A personal "second brain" Claude Code skill: a local, git-backed markdown knowledge base tracking the status and narrative of projects, initiatives, decisions/ADRs, and other ongoing work — usable from any Claude Code session, in any repo or none.

Shipped from: [`modules/common/users/common/claude-code/skills/brain/`](../modules/common/users/common/claude-code/skills/brain/) (`SKILL.md`, `brain.py`, `templates/`), wired up by the `claude-code` home-manager module — see [`claude-code.md`](./claude-code.md).

## What's managed vs. what's yours

This repo manages exactly three things, and deliberately nothing else:

1. **The skill + CLI + canonical template** — `SKILL.md` (the mechanism: how to capture/query/update/reorganize), `brain.py` (the `brain` CLI: schema, validator, index generator, and the constrained frontmatter writers), and `templates/` (the canonical `CLAUDE.md` operating manual + store scaffold: `index.md`, `log.md`, bucket layout). `SKILL.md` + `templates/` are symlinked into `~/.claude/skills/brain/`, and `brain.py` is packaged onto `PATH` as `brain`, on every `home-manager switch`.
2. **The commit hooks** — the activation script (re)installs two hooks into `~/brain/.git/hooks` on **every** switch (for new *and* existing stores, so they always point at the current `brain`). **Nix is their sole installer** — the CLI has no `install-hooks` verb, so there is exactly one definition of each and no way for it to drift. (a) A `pre-commit` gate regenerates + stages `index.md` (the catalog can't drift — no reliance on anyone remembering to reindex) and then execs the Nix-managed `brain check --staged`, so a commit containing a schema-invalid page is rejected (for agent, hand, and Obsidian edits alike). (b) A `post-commit` hook pushes the store to its remote when one is configured, so a commit is also a backup + multi-machine sync; it never force-pushes (BatchMode so it can't hang on an SSH prompt), and a rejected/failed push is non-fatal — it prints a reconcile hint and the commit still stands. Because the hooks are thin shims, their logic only ever changes via `brain.py` / `default.nix`.
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

### Page bodies

`brain new` emits a body skeleton per kind, in which every section is marked **rewritten in place** or **appended to**. That single distinction is the point: without it, dated "current state" sections accumulate (a page carries both a June and a July "where it stands") and pages grow without bound. The shapes are drawn from what the real stores already do well — an orienting paragraph, a "so it isn't re-litigated" rationale, a rewritten current state stamped with what was checked, appended dated decisions with consequences, a shrinking "open", and a `## Drift` section for projects tracking an external design doc.

### People

`mocs/people.md` is a directory of people — a table, whose columns are suggested rather than required (a personal store holds people with no Slack handle, no work email and no title). Someone gets their own page only once they accumulate narrative that won't fit in a row: `brain new resource <slug> --person` creates it as `kind: resource` + `tags: [person]` with a person skeleton.

Person pages are **excluded from `index.md`**: `reindex` skips `tags: [person]`, so the catalog carries exactly one line — the people MOC — whether you know 2 people or 200, and the index stays constant-size as the directory grows. They stay fully inside the system (`brain check` validates them, `brain q --tag person` finds them); the lint pass knows they are catalogued by a MOC and so are not orphans.

### Version stamping

`.brain-version` records the template version the store has actually been migrated to, and `brain check` prints a note whenever it is behind the CLI — so a machine that has rebuilt but not synced says so on every commit. `brain version --stamp` writes it as the **last** step of a migration, after the page backfill has landed. Keeping the stamp out of `CLAUDE.md` (where the version comment used to be the only marker) is what makes an interrupted sync safe: the manual is replaced early, so a store could otherwise claim to be current while its pages were not, and the next sync would skip it.

### Governance: the CLI, schema, and hook are canonical here

`brain.py`, the schema it enforces, and the hook are canonical artifacts shipped from this repo; the on-machine copies are read-only Nix deployments. The manual and `SKILL.md` instruct Claude that **if a check, the schema, or a hook needs to change, it must stop and ask to update the skill in this repo**, then rebuild and `/brain --sync` — never hand-edit the deployed CLI/hook, loosen a failing check locally, or `--no-verify` past the gate. This keeps every machine's store enforcing the same rules.

## Staying in sync

Because the store is a one-time copy, it can drift from the template as the skill/CLI evolve (new schema fields, new bucket conventions, etc.). Run the skill's own sync workflow to reconcile an existing store:

```
/brain --sync
```

There is deliberately **no migration script**: sync is a procedure in `SKILL.md` that the model executes with the ordinary CLI verbs (`normalize`, `check`, `reindex`, the writers). That stays adequate as long as migrations are additive — a rename or a drop would be the point to reconsider.

It reads the canonical template shipped with the (possibly just-updated) skill, diffs it against the live `~/brain`, and reconciles in **three commits**, so a bad step can be reverted on its own (the store auto-pushes, so recovery is `git revert` of one tight commit, never a force-push):

1. **Mechanical** — create `.gitignore`, missing bucket dirs and missing scaffold files (never overwriting an existing one), replace `CLAUDE.md` with the canonical manual, `brain normalize` + `brain check`, `brain reindex`, and untrack anything the new `.gitignore` covers. Nothing is read for meaning.
2. **Backfill** — migrate page frontmatter to the current schema, showing the diff and asking first: `created`/`finished` from git history, `summary` from the existing index, and for v8 specifically `verified` from verification stamps already written in bodies, `attention` from priority-as-prose, `next` from trailing "Next step:" lines, plus re-filing `kind: adr` pages whose decision actually lives in a repo document.
3. **Stamp** — `brain version --stamp` alone, so "did the migration complete" is a single visible fact.

The commit hooks are verified but not installed here (the rebuild that precedes sync installs them). Sync never touches the substance of existing pages: trimming `mocs/now.md`, splitting an oversized page, or collapsing accumulated status sections is content work for the REVIEW and LINT passes.

## Day to day

See `SKILL.md` for the full procedure; in short: `~/brain/CLAUDE.md` is the operating manual (read it first), `brain review` is the current picture and `~/brain/index.md` the full catalog (generated by `brain reindex`), captures/updates go through the `brain` CLI (`capture`/`new`/`set`/`done`) + a dated `log.md` entry, and every change is committed to the store's own git repo (where the pre-commit gate re-validates it). Discrete personal next-actions go through `dstask` (installed via `flake.nix`'s package list) rather than as brain pages; overall initiative narrative/status belongs in a brain page. Task **notes** must go through **`dstask-note <id> "<text>"`** (`pkgs/dstask-note/`), not `dstask note`: the upstream command requires a controlling TTY and, run from a script or agent session, exits 0 without writing the note or committing anything — a silent no-op with no signal that it failed. The wrapper runs it under a pty and hides the BSD/util-linux `script(1)` syntax split, so the same invocation works on manwe and morgoth. All other dstask verbs the skill uses (`add`/`start`/`stop`/`done`/`modify`) work headlessly. Work that belongs in an external/team issue tracker is linked to, not duplicated, per the rules of whatever workspace you're in.
