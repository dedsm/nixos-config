---
trigger: model_decision
description: "How to put a working session into the brain: find where it belongs, sort what it produced, propose a filing plan, discuss it, then apply. Read when the user asks to save, file or record a session or conversation in the brain."
---

# FILE A SESSION — "put this session in the brain"

A working session (in any repo, any harness, tracked or not) produced something worth keeping.
It is rarely just a summary, so this is a **conversation about where things go**, not a template.

1. **Find where it belongs.** `brain where` names the page that owns this workspace, if any; then
   search the store (`brain q`, `rg`, `index.md`, the people and org directories) for the pages
   the session actually touched — it may belong somewhere other than the repo you are in.
2. **Sort what the session produced** into the store's existing homes: a decision and its reasoning
   → that page's `## Decisions`; where things now stand → `brain set` (`status`, `next`,
   `verified`) and `## Current state`; reusable knowledge → a `resources/` page; something new
   worth tracking → a new project or a goal idea; things to do → dstask; the occasion itself (a
   design session, a negotiation prep) → an event page linking where everything else went;
   material exchanged → `raw/`; nothing durable → say so, and stop.
3. **Propose a filing plan**: the concrete writes (page, section, the text, why), plus the
   questions you can't settle alone ("part of [[x]], or a new project?"). Nothing is written yet.
4. **Discuss and revise** — the user may move, merge, split or drop items.
5. **Apply exactly what was agreed**, then `brain commit --log` with only those files. The
   session reference the session-start hook gave (`harness:id`), if any, goes on the page that
   anchors the session — the event page when there is one — so it can be reopened later.

If the workspace is untracked, this is also the natural moment to settle its workspace (`workspaces.md`).
