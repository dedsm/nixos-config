---
trigger: model_decision
description: "Governance: the CLI, schema and hooks are Nix-managed in nixos-config; the duty to report CLI bugs; how conventions change and reach each machine (template versions, brain sync). Read before proposing any change to rules, schema or hooks, or when the CLI misbehaves."
---

# ⚠️ Governance — the CLI, schema, and hook are Nix-managed (do not edit here)

`brain.py`, the schema it enforces, and the pre-commit hook are **canonical artifacts shipped
from nixos-config** (`~/Develop/personal/nixos-config`, at
`modules/home/agent-harness/skills/brain/`). The copies on this machine are
Nix-store deployments.

**If a check, the schema, or a hook needs to change** — a new `status`/`kind` value, a new field,
a relaxed rule, a different hook — **STOP and ask David to update the skill in nixos-config**, then
rebuild and run `/brain --sync`. Never:

- hand-edit the deployed `brain` binary or the `pre-commit` hook,
- work around a failing `brain check` by loosening/deleting the rule locally, or
- `git commit --no-verify` to bypass the gate to force a malformed page in.

A failing gate means either the page is wrong (fix the page) or the schema should change (a
nixos-config change David makes) — never a local workaround.

There is deliberately **no test suite for `brain` — real usage is the test**. The flip side of
that deal is a duty to notice: if the CLI itself ever misbehaves — mangled frontmatter after a
write, a wrong date, a corrupted index or log, an exit code that contradicts what actually
happened — **treat it as a bug, not as something to work around**. Stop, tell David exactly what
you observed (command, input, expected vs actual), and propose the fix as a `brain.py` change in
nixos-config. Never silently hand-repair what a writer got wrong without flagging it.

# Maintaining the conventions (keep machines in sync)

This manual, the `brain` CLI, and the store scaffold are the **canonical brain template**,
version-controlled with the skill in the nixos-config repo (`~/Develop/personal/nixos-config`):

- **Template (canonical):** `modules/home/agent-harness/skills/brain/templates/`
  — this manual (`AGENTS.md`, plus the `CLAUDE.md` stub that imports it for Claude Code) + the
  empty scaffold. Deployed read-only as the skill's `templates/` in each agent harness.
- **CLI + schema (mechanism):** `modules/home/agent-harness/skills/brain/brain.py`
  — packaged to `PATH` as `brain`. The commit hooks (pre-commit gate + post-commit auto-push) are
  defined in the agent-harness module's `brain.nix` and installed by its activation on rebuild — Nix is their sole
  installer.
- **Skill (mechanism):** `modules/home/agent-harness/skills/brain/SKILL.md`

The store's **content** (pages, `index.md`, `log.md`) is never templated — only the
scaffold/manual/CLI.

**To change the conventions** — buckets, page schema/frontmatter, the `brain` CLI or its checks,
the hook, workflows, guardrails, or the skill's behavior:

1. Edit the template/CLI/`SKILL.md` here; bump the `brain-template` version comment at the top of
   this file **and `TEMPLATE_VERSION` in `brain.py`** (they must match); commit nixos-config.
2. Rebuild each machine — Nix propagates the updated template + CLI and reinstalls the hooks everywhere.
3. On each machine, run **`brain sync`** — the CLI refreshes the store mechanically (this manual,
   missing buckets/scaffold, normalize, reindex, untrack) and stamps, **unless** the version gap
   crosses a registered judgment migration, in which case it stops before stamping and
   **`/brain --sync`** finishes the job (diff-and-ask frontmatter backfill, then stamp last).
   (The rebuild in step 2 — not sync — installs/refreshes the hooks.)

`brain check` prints a note whenever the store's `.brain-version` is behind the CLI, so a machine
that has rebuilt but not synced says so on every commit. The stamp is written **last**, after the
migration succeeds — an interrupted sync therefore leaves the store visibly behind rather than
silently claiming to be current (which would make the next sync skip it).

The bootstrap only *creates* a missing store (and installs the hooks); it never updates an existing
store's content — `brain sync` (plus `/brain --sync` when a judgment backfill is pending) is how
existing stores catch up. Pure content edits (adding/updating pages) need none of this.
