---
trigger: model_decision
description: "What each frontmatter field means (status, attention, summary, progress, next, verified, parent, links, repos), the internal/external link model, where a decision's record lives, and when a topic earns its own page. Read before creating pages, changing fields or adding links."
---

# Page schema — field by field

The YAML block itself is in `AGENTS.md`; this is what each field means and how it is used.

- `status` is the kanban state — the field a GUI (Obsidian Bases/Kanban) or a query reads. Keep
  it accurate.
- `attention` is **not** a priority ladder — deliberately three states. `focus` = hands-on right
  now; `tracking` = watching work that is someone else's; **absent** = ordinary active work. A
  finer ladder rots faster than it informs. `brain review` groups on this.
- `summary` is what `brain reindex` prints for the page in `index.md` (falls back to `title` if
  absent). **One crisp line** — `brain check` warns past 200 characters, because at that point it
  has become a changelog. The next move belongs in `next`, detail in the body — and a tally
  belongs in the tracker, not in `summary` and not in `progress` (see `tracker-standings.md`).
- `progress` is **an error on any page whose `links:` name a tracker** — `brain check` rejects it,
  and `brain set` refuses to write it. A tally is a reading of someone else's system, so a copy of
  it here is wrong from the next merge onward. It survives only on a page with no system of record
  for its standings ("first sweep reclaimed 3.5 TB, flat for 27d"). What counts as a tracker link:
  a URL on a tracker host, a forge URL on an `/issues/`, `/pull/` or `/milestone/` path, or a
  `links:` entry in the `ISSUE-123 https://…` form. The CLI holds the list (`TRACKER_HOSTS`).
- `next` is the single next concrete move, in one line, and it's what makes `brain review`
  actionable rather than a status dump. Distinguish it from its neighbours: `next` = the next move
  ("start STO-496"), **dstask** = actions you will personally do. A `next` may well be someone
  else's action or a decision, which is why it isn't a task. `next` is judgment, so it may name an
  issue key — it is the one frontmatter field the state-reading rule (`tracker-standings.md`) does not read.
- `verified` is **when this page's claims were last checked against reality** — code read, tracker
  reconciled, person asked. It is not `updated`, which moves on a typo fix. This is the field
  staleness should be judged on, so a page nobody edited but that you re-checked yesterday doesn't
  read as rotten. Mirror it in the body where you record what you checked
  ("verified against the code 2026-07-26").
- **The link model — internal vs external is the load-bearing distinction:**
  - **Internal** links are `[[wikilinks]]` (Obsidian-native): a bare slug (`[[page]]`, resolved
    store-wide by filename) or a store path for a page in a subdirectory
    (`[[resources/scripts/README]]`, which is what `reindex` emits). This is the **only**
    sanctioned internal form, and therefore checkable: `brain links` lints them, and a broken or
    ambiguous one is an **error the commit gate rejects**. Move/rename pages with **`brain mv`**,
    which rewrites references — never by hand, which breaks them. Filename stems are
    **store-unique**: `new` and `mv` both refuse to mint a second page with an existing stem, so
    a bare `[[slug]]` can never silently change meaning.
  - **External** links carry a scheme (`https://…`, `dstask:6`, `mailto:`) — plain full URLs.
    Never checked, never rewritten.
  - A **relative markdown path** (`[text](../repo/doc.md)`) is neither and always **warns**: it
    breaks silently when either side moves. Make it a `[[wikilink]]` (if it's a store page) or an
    explicit external form — a full URL, or an inline-code path like `` `repo/docs/adr.md` ``
    (code spans and code blocks are never treated as links).
- **Dates** are ISO `YYYY-MM-DD`. `created` is set once and never changes; `updated` tracks the
  last edit. `started`/`finished`/`due` apply mainly to `goal`/`project`/`initiative` pages and
  drive time-range queries — set `started` when `status` → `active`, `finished` when `status` → `done`.

### Decisions — where does the record live?

Not here. A decision's record belongs in its **external system of record** — the ADR/RFC doc in
the repo it governs, or the tracker document — and what this store holds is `kind: project`:
tracking the decision's rollout, its gaps, or its drift. Link the document, don't restate it,
and use the project template's optional `## Drift` section for where the doc, the tracker and
the code disagree — copying the decision content in would break "link, don't duplicate" (**Systems of record** in `AGENTS.md`).
A decision with no external home **gets one** (record it in the repo it governs); it does not
become a brain page.

### Where knowledge lives — page, or section?

The split ladder (LINT) cures pages that grew too big; this rule prevents the opposite failure,
minting a page per stray thought. A topic earns its **own page** when:

1. **two or more existing pages need to `[[link]]` it**, or
2. **it has an independent lifecycle** — its status can change while its would-be parent's doesn't.

Otherwise it is a **section on the page that owns it**. Two corollaries:

- **Never write a `[[link]]` to a page that doesn't exist** — create the target properly
  (`brain new`, real frontmatter) or don't link it.
- **Don't force-merge broader material into a narrower page.** If new material outgrows the
  page's slug, create a sibling and cross-link rather than stretching a page past its title.

Durable **reference knowledge** — a how-to, a learned fact, a worked-out explanation that no
other system of record holds — lives as a `resources/` page (see the CAPTURE routing), not
crammed into a project body where the LINT ladder will later delete it as superseded analysis.
