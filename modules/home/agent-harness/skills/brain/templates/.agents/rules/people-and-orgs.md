---
trigger: model_decision
description: "The people and organisations directories, person and org pages, and the generated Where-they-appear column. Read before adding or editing a person or a company, or their directory rows."
---

# People and organisations

A **directory of people you know** — not a work roster. This is a personal store: it will hold
people with no Slack handle, no work email, and no job title.

- **`mocs/people.md`** is the directory: a table by default. Columns are **suggested, never
  required** — a name, a contact handle *if one exists*, and where they appear in this brain.
  Add or drop columns per store; empty cells are fine. Grouping (by team, by context, or not at
  all) is likewise store-local. The one generated part: for every row whose first cell links a
  `[[person-page]]`, **`reindex` rewrites the "Where they appear" cell** from the link graph (the
  pages that `[[link]]` that person) — hand-maintained reverse indexes rot, so don't edit those
  cells; a row for someone *without* a page keeps whatever is typed. Don't put piped
  `[[links|labels]]` in this table — the pipe fights the table syntax.
- **Promote to a page** when someone accumulates narrative that won't fit in a cell — decisions
  they own, positions they hold, history worth not re-deriving. Until then a table row is enough.
- A person page is **`brain new resource <slug> --person`**: `kind: resource`, `tags: [person]`,
  filed in `resources/`, with the person body skeleton.
- **They are excluded from `index.md`.** `reindex` skips `tags: [person]`, so the catalog carries
  exactly one line — the people MOC — whether you know 2 people or 200. Index → MOC → person page.
  They remain fully in the system: `brain check` validates them and `brain q --tag person` finds
  them. Excluded from the catalog is not excluded from the gate.
- **Maintenance rule:** whenever a person appears in a page, make sure they're in the directory,
  and — if they have a page — **`[[link]]` them from the page where they appear**: the generated
  where-they-appear column reflects the link graph, so a bare name-mention is invisible to it.
  Do this on every brain update, not only on meeting captures.
- **Organisations work the same way** (since v16): `mocs/orgs.md` is the directory table, a
  company that recurs across pages gets **`brain new resource <slug> --org`** (`tags: [org]`,
  org skeleton: context, the current relationship, a dated history), its "Where they appear" cell
  is generated, and you `[[link]]` it where it appears instead of re-explaining it on every page.
- **PII:** keep to what you actually need in order to work with them. A personal directory is the
  place in this store where the "no PII you don't need" guardrail actually bites — addresses,
  phone numbers, birthdays, health details.
