---
trigger: model_decision
description: "How the brain maps repos and directories to pages (tracked, ignored, snoozed, undecided) and what to do in each at session start and at checkpoints. Read when a session-start message mentions a workspace, or before brain track, ignore or snooze."
---

# Workspaces

Which page a session's work belongs to, decided once per project and remembered on every machine.

- **Identity is machine-independent**, so every worktree and clone of a repo is the same project:
  a git repo with a remote is its normalised remote (`github.com/owner/repo`), one without a
  remote is its first commit (`git:3f9c2a1b0c4d`), anything else is its path from home
  (`~/Documents/taxes`). A claim can name a subfolder (`github.com/owner/mono//services/api`),
  and the most specific claim wins — an area can own a repo several of its projects share, while
  a project owns its subfolder.
- **Tracked** = a live page lists it in `repos:` (`brain track <page>`). One live page per
  identity (`check` rejects a second), and finishing or archiving the page releases it.
  **Ignored** / **snoozed** = `workspaces.md`, written by `brain ignore` / `brain snooze`
  (30 days by default). Anything else is **undecided**.
- **At session start**, the harness's hook runs `brain where` for the session's directory and
  tells you what to do — nothing at all when the workspace is ignored, snoozed or the store itself.
  **A harness without that hook:** run `brain where` yourself once when you start working in a
  repo, and act on it the same way.
  - **Tracked:** at natural checkpoints (a commit, a PR, a decision, the end of a task) **offer**
    a one-line brain update — a log entry, a new `next`, `verified today`, a decision — and write
    it only on a yes. Never mid-task, never unasked.
  - **Undecided:** ask **once**, at the first natural pause after the user's request is handled:
    track it (under which page — `brain where` suggests some), ignore it, or decide later. Record
    the answer with `brain track` / `brain ignore` / `brain snooze` and commit it. No answer →
    drop it for the session.
