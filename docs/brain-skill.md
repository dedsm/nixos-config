# The `brain` skill

A personal "second brain" Claude Code skill: a local, git-backed markdown knowledge base tracking the status and narrative of projects, initiatives, decisions/ADRs, and other ongoing work — usable from any Claude Code session, in any repo or none.

Shipped from: [`modules/common/users/common/claude-code/skills/brain/`](../modules/common/users/common/claude-code/skills/brain/) (`SKILL.md`, `brain.py`, `templates/`), wired up by the `claude-code` home-manager module — see [`claude-code.md`](./claude-code.md).

## What's managed vs. what's yours

This repo manages exactly three things, and deliberately nothing else:

1. **The skill + CLI + canonical template** — `SKILL.md` (the mechanism: how to capture/query/update/reorganize), `brain.py` (the `brain` CLI: schema, validator, index generator, and the constrained frontmatter writers), and `templates/` (the canonical `CLAUDE.md` operating manual + store scaffold: `index.md`, `log.md`, bucket layout). `SKILL.md` + `templates/` are symlinked into `~/.claude/skills/brain/`, and `brain.py` is packaged onto `PATH` as `brain`, on every `home-manager switch`.
2. **The pre-commit gate** — the activation script (re)installs a `pre-commit` hook into `~/brain/.git/hooks` on **every** switch (for new *and* existing stores, so it always points at the current `brain`). On each commit the hook regenerates + stages `index.md` (the catalog can't drift — no reliance on anyone remembering to reindex) and then execs the Nix-managed `brain check --staged`, so a commit containing a schema-invalid page is rejected (for agent, hand, and Obsidian edits alike). Because the hook is a thin shim, its logic only ever changes via `brain.py`.
3. **A one-time bootstrap** that seeds `~/brain` from the template *only if `~/brain` doesn't exist yet* (`home.activation.bootstrapBrain` in `default.nix`). It copies the template, `chmod -R u+w`s it (Nix store files are read-only), and `git init`s it — then the same activation installs the hook.

The store's actual content — pages, `index.md`, `log.md`, as they evolve — is mutable user data and is **never** touched, symlinked, or overwritten by a rebuild. Once `~/brain` exists, this repo leaves its content alone (only the hook shim is refreshed, so its store path stays current).

## Deterministic retrieval: the `brain` CLI

The store is small and plain-text by design, so retrieval is deliberately **not** a vector/RAG index (which would add a non-diffable, rebuild-on-change binary artifact and break the Obsidian-native, git-diffable model). Instead, reliability comes from making the frontmatter a trustworthy structured index and querying it directly. `brain` provides three layers:

- **Layer 1 — schema.** The allowed `kind`/`status` enums, required fields, and ISO date format are defined once, machine-readably, in `brain.py` (the manual's schema block is the human mirror).
- **Layer 2 — the gate.** `brain check` validates every page against that schema and exits non-zero on violations; the pre-commit hook runs it so malformed frontmatter physically cannot enter the store. Determinism lives in the validator + git, not in the model's diligence.
- **Layer 3 — constrained writers.** `brain new` / `brain set` / `brain done` own the YAML serialization (legal enum values, ISO dates stamped from the real clock, `updated`/`started`/`finished` maintained automatically), so the model chooses values from a constrained set and never hand-writes the shape — malformed frontmatter is unrepresentable.

**Dates come from the system clock, never the corpus.** A recurring LLM failure mode is reading a date out of `log.md` or a page and treating it as "today". The writers stamp `created`/`updated`/`started`/`finished` from the clock, `brain log "…"` dates activity entries from the clock (so the model never types the date), and `brain today` is the authoritative "now" for the rare date a caller must supply by hand (e.g. a relative `due`). The manual and `SKILL.md` make "never infer today from the corpus" an explicit guardrail.

On top of these: `brain reindex` regenerates the catalog region of `index.md` as a pure projection of the frontmatter (drift becomes a `git diff`, or a non-zero `brain reindex --check`), and `brain q` answers structured/temporal queries (`--status`, `--kind`, `--tag`, `--overdue`, `--due-before`, `--stale DAYS`) directly from frontmatter instead of the model grep-guessing.

### Governance: the CLI, schema, and hook are canonical here

`brain.py`, the schema it enforces, and the hook are canonical artifacts shipped from this repo; the on-machine copies are read-only Nix deployments. The manual and `SKILL.md` instruct Claude that **if a check, the schema, or a hook needs to change, it must stop and ask to update the skill in this repo**, then rebuild and `/brain --sync` — never hand-edit the deployed CLI/hook, loosen a failing check locally, or `--no-verify` past the gate. This keeps every machine's store enforcing the same rules.

## Staying in sync

Because the store is a one-time copy, it can drift from the template as the skill/CLI evolve (new schema fields, new bucket conventions, etc.). Run the skill's own sync workflow to reconcile an existing store:

```
/brain --sync
```

This reads the canonical template shipped with the (possibly just-updated) skill, diffs it against the live `~/brain`, and — after showing the diff and asking before anything destructive — updates `~/brain/CLAUDE.md` to the canonical manual, creates missing bucket directories, migrates page frontmatter to the current schema (backfilling `created`/`finished` from git history and `summary` from the existing index where possible), runs `brain normalize` + `brain check` to confirm validity, ensures the pre-commit gate is installed, and regenerates `index.md` with `brain reindex`. It never touches the substance of existing pages.

## Day to day

See `SKILL.md` for the full procedure; in short: `~/brain/CLAUDE.md` is the operating manual (read it first), `~/brain/index.md` is the current catalog (generated by `brain reindex`), captures/updates go through the `brain` CLI (`new`/`set`/`done`) + a dated `log.md` entry, and every change is committed to the store's own git repo (where the pre-commit gate re-validates it). Discrete personal next-actions go through `dstask` (installed via `flake.nix`'s package list) rather than as brain pages; overall initiative narrative/status belongs in a brain page. Work that belongs in an external/team issue tracker is linked to, not duplicated, per the rules of whatever workspace you're in.
