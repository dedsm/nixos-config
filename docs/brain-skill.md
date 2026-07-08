# The `brain` skill

A personal "second brain" Claude Code skill: a local, git-backed markdown knowledge base tracking the status and narrative of projects, initiatives, decisions/ADRs, and other ongoing work — usable from any Claude Code session, in any repo or none.

Shipped from: [`modules/common/users/common/claude-code/skills/brain/`](../modules/common/users/common/claude-code/skills/brain/) (`SKILL.md` + `templates/`), wired up by the `claude-code` home-manager module — see [`claude-code.md`](./claude-code.md).

## What's managed vs. what's yours

This repo manages exactly two things, and deliberately nothing else:

1. **The skill + its canonical template** — `SKILL.md` (the mechanism: how to capture/query/update/reorganize) and `templates/` (the canonical `CLAUDE.md` operating manual + store scaffold: `index.md`, `log.md`, bucket layout). Both are symlinked into `~/.claude/skills/brain/` on every `home-manager switch`.
2. **A one-time bootstrap** that seeds `~/brain` from the template *only if `~/brain` doesn't exist yet* (`home.activation.bootstrapBrain` in `default.nix`). It copies the template, `chmod -R u+w`s it (Nix store files are read-only), and `git init`s it.

The store's actual content — pages, `index.md`, `log.md`, as they evolve — is mutable user data and is **never** touched, symlinked, or overwritten by a rebuild. Once `~/brain` exists, this repo leaves it alone.

## Staying in sync

Because the store is a one-time copy, it can drift from the template as the skill evolves (new page schema fields, new bucket conventions, etc.). Run the skill's own sync workflow to reconcile an existing store:

```
/brain --sync
```

This reads the canonical template shipped with the (possibly just-updated) skill, diffs it against the live `~/brain`, and — after showing the diff and asking before anything destructive — updates `~/brain/CLAUDE.md` to the canonical manual, creates missing bucket directories, migrates page frontmatter to the current schema (backfilling `created`/`finished` from git history where possible), and regenerates `index.md`. It never touches the substance of existing pages.

## Day to day

See `SKILL.md` for the full procedure; in short: `~/brain/CLAUDE.md` is the operating manual (read it first), `~/brain/index.md` is the current catalog, captures/updates go through the matching bucket + frontmatter + a dated `log.md` entry, and every change is committed to the store's own git repo. Discrete personal next-actions go through `dstask` (installed via `flake.nix`'s package list) rather than as brain pages; overall initiative narrative/status belongs in a brain page. Work that belongs in an external/team issue tracker is linked to, not duplicated, per the rules of whatever workspace you're in.
