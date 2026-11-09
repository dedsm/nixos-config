---
trigger: model_decision
description: "The quarterly goals layer: goal pages, linkage through parent, the generated rollup, the quarterly pass, the weekly touch and mid-quarter refinement. Read before creating, reviewing or changing goals."
---

# Goals

The quarterly layer — the top of the work hierarchy, built from fields that already exist. A
goal is a **quarterly outcome**: 3–5 live at a time, `due` set to quarter end, falsifiable
success criteria and milestone checkboxes in the body. **`brain new goal <slug>`** files it in
`goals/` — catalogued first in `index.md` — with the goal skeleton (Why this goal / Success
criteria / Milestones / Decisions / Open).

- **Linkage is `parent`, both ways:** a project's or initiative's `parent` names the goal it
  serves; a goal's `parent` names its area (`check` warns on a live goal without one).
  `review` shows each goal's area on its line. Tasks stay in dstask, referenced via
  `links: dstask:<id>` — never duplicated onto the goal page.
- **Weekly focus is `attention`** — the same three states. No priority ladder here either.
- **Success criteria are falsifiable** — checkable at quarter end, not aspirations. Milestones
  are `- [ ]` lines under `## Milestones`, checked off in supervised body edits; `review` counts
  them at read time and **never writes them back** — no stored progress percentage exists.
- **The rollup is generated.** `brain review` opens with a Goals section computed per live goal:
  its live children (the pages whose `parent` resolves to it), the milestone count, and two
  flags — **orphaned** (zero live children) and **stalled** (goal and every live child untouched,
  `verified` else `updated`, for more than 14 days). `health` carries one token for these. Never
  hand-maintain any of it; `mocs/goals.md` holds only the judgment.
- A live goal without a `due` can never trip the overdue detector, so `check` warns on one.

**The quarterly pass** — the REVIEW pass at a longer cadence, not a new ceremony:

1. **`brain review --since 90`** for the quarter cut — what started, finished, went quiet, per goal.
2. Work the captured backlog — **`brain q --kind goal --status idea`** — promoting or archiving
   each candidate, with a reason.
3. Judge **every** current goal — the forced trichotomy: **rewrite** (still right — restate the
   success criteria), **archive as legacy** (`brain set <goal> status archived` plus a dated
   closing decision in the body), or **surgical edit**. Skipping a goal is not an option; that
   is the anti-rot mechanism.
4. Set the quarter: 3–5 goals worked backwards from impact — falsifiable criteria and milestones
   in the body, `due` = quarter end, `parent` = area. Wire `parent` on the live projects that
   serve them (`review` shows what's left orphaned). The NOT-doing list, with reasons, goes to
   `mocs/goals.md`.
5. **`brain log`** the plan, `brain check`, commit — the plan is queryable state, not a document.

**The weekly touch:** read `review`'s Goals section; flip `attention` so at most 1–2 goals carry
`focus`; triage anything flagged stalled — each gets **Reschedule** (new `next:` + `due`),
**Delegate** (link the owner, `attention: tracking`), or **Delete** (archive, with a reason);
update `next:` lines. No weekly file is written — the plan is the store's state, and the diff is
the artifact.

**Mid-quarter refinement:** when reality disagrees with a goal, apply the same moves the day you
know it, not at the boundary — restate `## Success criteria` in place, append a dated entry to
`## Decisions` recording the cut and why, adjust `next:`/`due` via `brain set`. A goal that no
longer deserves the quarter is archived with a closing decision now, not at the next pass.
