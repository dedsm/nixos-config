# brain

Personal tracking store maintained by Claude Code. Plain markdown + git, fully local.

- **Conventions / how it works:** see [`CLAUDE.md`](CLAUDE.md).
- **Dashboard:** [`index.md`](index.md).
- **Update it** from any Claude Code session (any repo or none): say things like
  _"track this: …"_, _"what's the state of X?"_, or invoke the `brain` skill. Claude reads
  `CLAUDE.md`, files the info, updates the index, and commits.
- **Optional GUI:** `brew install --cask obsidian` (or add `obsidian` to your config), then open
  this folder as a vault — the frontmatter and `[[links]]` render as tables/graphs with zero
  changes to the files.

Systems of record: **external / team trackers** (per the active workspace's rules) for their
issues · **dstask** (`~/.dstask`) for personal tasks · **this store** for narrative + status.
