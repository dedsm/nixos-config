#!/usr/bin/env python3
"""brain — deterministic frontmatter tooling for the ~/brain tracking store.

This is the single source of truth for the store's schema and the only thing
that should ever write page frontmatter. It is Nix-managed and shipped from
nixos-config alongside the brain skill; do NOT edit the deployed copy. See the
governance note in ~/brain/CLAUDE.md before changing any rule here.

Subcommands:
  check     validate frontmatter against the schema (exits non-zero on errors)
  reindex   regenerate the generated region of index.md from frontmatter
  q         structured query over frontmatter (status/overdue/stale/tag/kind)
  review    read-only briefing: focus, attention, blocked, overdue, unverified, dstask
  new       create a schema-perfect page in the right bucket
  set       set one frontmatter field (validated), stamping dates
  unset     remove one optional frontmatter field (never a required one)
  done      mark a page done (status=done, finished=today)
  normalize repair-on-drift: canonicalise status/kind/tags in place
  capture   append a timestamped entry to raw/inbox.md (or a raw file from stdin)
  log       prepend a dated activity entry to log.md (date from the system clock)
  version   print CLI/store template version; --stamp writes .brain-version
  today     print today's date from the system clock (never infer it from the corpus)

The commit hooks (pre-commit gate + post-commit auto-push) are Nix-managed: the
nixos-config activation installs them into ~/brain/.git/hooks on every rebuild.

All dates come from the system clock, never from page/log content: the writers stamp
created/updated/started/finished automatically, `log` dates entries, and `today` is the
authoritative "now" for any date a caller must supply by hand.

Stdlib only, on purpose: no runtime dependencies to wire through Nix.
"""

from __future__ import annotations

import argparse
import datetime
import os
import re
import subprocess
import sys
from pathlib import Path

# --------------------------------------------------------------------------
# Schema — the machine-readable source of truth (Layer 1).
# The prose mirror lives in ~/brain/CLAUDE.md; both change together, via the
# Nix skill only. See the governance note there.
# --------------------------------------------------------------------------

TEMPLATE_VERSION = 9      # bump with templates/CLAUDE.md; `.brain-version` mirrors it
VERSION_FILE = ".brain-version"

KINDS = ["adr", "initiative", "project", "area", "resource", "moc"]
STATUSES = ["idea", "planned", "active", "blocked", "done", "archived"]
# Deliberately three states, not a priority ladder: `focus` = hands-on now,
# `tracking` = watching someone else's work, absent = ordinary active work.
# A four-value ladder rots faster than it informs.
ATTENTIONS = ["focus", "tracking"]
REQUIRED = ["title", "kind", "status", "created", "updated"]
DATE_FIELDS = ["created", "updated", "started", "finished", "due", "verified"]
LIST_FIELDS = ["tags", "links"]
# Canonical serialisation order. Unknown keys are preserved and emitted after.
FIELD_ORDER = [
    "title", "kind", "status", "attention", "progress", "next", "owner",
    "created", "updated", "verified", "started", "finished", "due",
    "summary", "parent", "tags", "links",
]

# Kinds with a timeline: only these warn about missing started/finished. An
# `area`/`moc`/`resource` is active without ever having "started".
TIMELINE_KINDS = {"adr", "initiative", "project"}
# Kinds that carry work, and so can be stale, blocked, overdue or unverified.
WORK_KINDS = {"adr", "initiative", "project", "area"}
# Statuses that imply motion — the only ones staleness/verification apply to.
LIVE_STATUSES = {"active", "blocked"}
# Pages tagged this are cataloged by the people MOC, not by index.md — see the
# People section of CLAUDE.md. They are still validated and still queryable.
PERSON_TAG = "person"
# `summary` is a one-line catalog description; past this it has become a changelog.
SUMMARY_MAX = 200
# Scaffold pages ship from the Nix template with this sentinel where a real date
# belongs (the template is a static copy — it can't know the seeding date).
# `normalize` restamps it, and the bootstrap runs normalize right after seeding.
SCAFFOLD_DATE = "1970-01-01"

# kind -> bucket directory used by `new` and for scope.
KIND_BUCKET = {
    "adr": "projects",
    "initiative": "projects",
    "project": "projects",
    "area": "areas",
    "resource": "resources",
    "moc": "mocs",
}

# Buckets whose top-level .md pages MUST carry valid frontmatter.
REQUIRED_BUCKETS = ["projects", "areas", "mocs", "archive"]
# Buckets where frontmatter is validated only if present (mixed reference material).
OPTIONAL_BUCKETS = ["resources"]

# status synonyms mapped to canonical values by `normalize`.
STATUS_SYNONYMS = {
    "in-progress": "active", "in_progress": "active", "wip": "active",
    "todo": "planned", "to-do": "planned", "backlog": "planned",
    "complete": "done", "completed": "done", "finished": "done",
    "cancelled": "archived", "canceled": "archived", "dormant": "archived",
}
KIND_SYNONYMS = {"decision": "adr", "note": "resource", "reference": "resource"}

DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
GEN_BEGIN = "<!-- BEGIN generated: run `brain reindex` — hand edits here are overwritten -->"
GEN_END = "<!-- END generated -->"


# --------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------

def brain_dir() -> Path:
    return Path(os.environ.get("BRAIN_DIR", str(Path.home() / "brain")))


def today() -> str:
    return datetime.date.today().isoformat()


def is_valid_date(value: str) -> bool:
    if not DATE_RE.match(value):
        return False
    try:
        datetime.date.fromisoformat(value)
        return True
    except ValueError:
        return False


def slug_of(path: Path) -> str:
    return path.stem


def rel(path: Path) -> str:
    """Path relative to the store, tolerant of symlinked/relative inputs."""
    try:
        return str(path.resolve().relative_to(brain_dir().resolve()))
    except ValueError:
        return str(path)


# --------------------------------------------------------------------------
# Frontmatter parse / serialise
# --------------------------------------------------------------------------

class Page:
    """A markdown page: ordered frontmatter fields + the body after it."""

    def __init__(self, path: Path, fields: dict, order: list, body: str, has_fm: bool):
        self.path = path
        self.fields = fields      # key -> str | list[str]
        self.order = order        # original key order (for unknown-key stability)
        self.body = body          # everything after the closing ---
        self.has_fm = has_fm

    @property
    def slug(self) -> str:
        return slug_of(self.path)


def parse_page(path: Path) -> Page:
    text = path.read_text(encoding="utf-8")
    if not text.startswith("---\n"):
        return Page(path, {}, [], text, has_fm=False)
    end = text.find("\n---", 3)
    if end == -1:
        return Page(path, {}, [], text, has_fm=False)
    fm = text[4:end]
    # body starts after the closing '---' line
    rest = text[end + 4:]
    if rest.startswith("\n"):
        rest = rest[1:]

    fields: dict = {}
    order: list = []
    lines = fm.split("\n")
    i = 0
    while i < len(lines):
        line = lines[i]
        if not line.strip() or line.lstrip().startswith("#"):
            i += 1
            continue
        m = re.match(r"^([A-Za-z0-9_]+):\s?(.*)$", line)
        if not m:
            i += 1
            continue
        key, val = m.group(1), m.group(2)
        if val == "" and i + 1 < len(lines) and re.match(r"^\s*-\s+", lines[i + 1]):
            # block list
            items = []
            i += 1
            while i < len(lines) and re.match(r"^\s*-\s+", lines[i]):
                items.append(_unquote(lines[i].split("-", 1)[1].strip()))
                i += 1
            fields[key] = items
            order.append(key)
            continue
        if val.startswith("[") and val.endswith("]"):
            inner = val[1:-1].strip()
            items = [_unquote(x.strip()) for x in inner.split(",")] if inner else []
            fields[key] = items
        else:
            fields[key] = _unquote(val.strip())
        order.append(key)
        i += 1
    return Page(path, fields, order, rest, has_fm=True)


def _unquote(s: str) -> str:
    if len(s) >= 2 and s[0] == s[-1] and s[0] in "\"'":
        return s[1:-1]
    return s


def _needs_quote(s: str) -> bool:
    return bool(s) and (s[0] in "\"'#[]{}>|*&!%@`" or ":" in s or s.strip() != s)


def _emit_scalar(s: str) -> str:
    return f'"{s}"' if _needs_quote(s) else s


def serialize(page: Page) -> str:
    keys = [k for k in FIELD_ORDER if k in page.fields]
    keys += [k for k in page.order if k not in keys and k in page.fields]
    out = ["---"]
    for k in keys:
        v = page.fields[k]
        if isinstance(v, list):
            if k == "tags":
                out.append(f"{k}: [{', '.join(_emit_scalar(x) for x in v)}]")
            elif not v:
                # Empty block-list → inline "[]" so it round-trips as a list
                # (a bare "links:" reads back as a non-list and check() rejects it).
                out.append(f"{k}: []")
            else:
                out.append(f"{k}:")
                for item in v:
                    out.append(f'  - "{item}"' if _needs_quote(item) else f"  - {item}")
        else:
            out.append(f"{k}: {_emit_scalar(v)}")
    out.append("---")
    body = page.body
    return "\n".join(out) + "\n" + ("" if body.startswith("\n") else "\n") + body


def write_page(page: Page) -> None:
    page.path.write_text(serialize(page), encoding="utf-8")


# --------------------------------------------------------------------------
# Page discovery
# --------------------------------------------------------------------------

def bucket_pages(bucket: str) -> list:
    # Recursive: nested material (e.g. resources/scripts/README.md) carries
    # frontmatter too, and used to sit outside the gate entirely — invisible to
    # check, q and reindex, which is why stores grew hand-maintained file lists.
    d = brain_dir() / bucket
    if not d.is_dir():
        return []
    return sorted(p for p in d.rglob("*.md") if p.is_file())


def all_pages(require_only: bool = False) -> list:
    buckets = REQUIRED_BUCKETS + ([] if require_only else OPTIONAL_BUCKETS)
    out = []
    for b in buckets:
        out.extend(bucket_pages(b))
    return out


def page_ref(page: "Page") -> str:
    """Wikilink target: bare slug for a top-level page, path for a nested one."""
    r = rel(page.path)
    parts = Path(r).parts
    return page.slug if len(parts) <= 2 else r[: -len(".md")]


def is_person(page: "Page") -> bool:
    return PERSON_TAG in (page.fields.get("tags") or [])


def days_since(iso: str) -> int | None:
    if not iso or not is_valid_date(str(iso)):
        return None
    return (datetime.date.today() - datetime.date.fromisoformat(str(iso))).days


def resolve_page(ref: str) -> Path:
    """Resolve a page by slug, relative path, or absolute path."""
    p = Path(ref)
    if p.is_absolute() and p.exists():
        return p
    cand = brain_dir() / ref
    if cand.exists():
        return cand
    if not ref.endswith(".md"):
        cand = brain_dir() / (ref + ".md")
        if cand.exists():
            return cand
    matches = [pg for pg in all_pages() if pg.stem == slug_of(Path(ref))]
    if len(matches) == 1:
        return matches[0]
    if not matches:
        die(f"no page matching '{ref}'")
    die(f"ambiguous ref '{ref}': {', '.join(str(m.relative_to(brain_dir())) for m in matches)}")


def die(msg: str, code: int = 1):
    print(f"brain: {msg}", file=sys.stderr)
    sys.exit(code)


# --------------------------------------------------------------------------
# check (Layer 2 — the gate)
# --------------------------------------------------------------------------

def validate_page(page: Page, required_fm: bool) -> tuple:
    """Return (errors, warnings) for one page."""
    errors, warnings = [], []
    r = rel(page.path)
    if not page.has_fm:
        if required_fm:
            errors.append(f"{r}: missing YAML frontmatter block")
        return errors, warnings

    f = page.fields
    for req in REQUIRED:
        if not f.get(req):
            errors.append(f"{r}: missing required field '{req}'")
    if "kind" in f and f["kind"] not in KINDS:
        errors.append(f"{r}: kind '{f['kind']}' not in {KINDS}")
    if "status" in f and f["status"] not in STATUSES:
        errors.append(f"{r}: status '{f['status']}' not in {STATUSES}")
    if f.get("attention") and f["attention"] not in ATTENTIONS:
        errors.append(f"{r}: attention '{f['attention']}' not in {ATTENTIONS}")
    for d in DATE_FIELDS:
        if d in f and f[d] and not is_valid_date(str(f[d])):
            errors.append(f"{r}: {d} '{f[d]}' is not an ISO YYYY-MM-DD date")
    for lf in LIST_FIELDS:
        if lf in f and not isinstance(f[lf], list):
            errors.append(f"{r}: {lf} must be a list")

    # Semantic niceties — warnings only (never block a commit).
    # started/finished only mean something for kinds with a timeline: an area,
    # MOC or resource is `active` without ever having "started", and warning on
    # those made `check --strict` permanently red (so the lint pass never ran).
    timeline = f.get("kind") in TIMELINE_KINDS
    if timeline and f.get("status") == "done" and not f.get("finished"):
        warnings.append(f"{r}: status done but no 'finished' date")
    if timeline and f.get("status") == "active" and not f.get("started"):
        warnings.append(f"{r}: status active but no 'started' date")
    summary = str(f.get("summary") or "")
    if len(summary) > SUMMARY_MAX:
        warnings.append(f"{r}: summary is {len(summary)} chars (>{SUMMARY_MAX}) — "
                        f"it has become a changelog; move detail to the body, "
                        f"the next move to 'next', and progress to 'progress'")
    if f.get("created") and f.get("updated") and is_valid_date(str(f["created"])) \
            and is_valid_date(str(f["updated"])) and f["updated"] < f["created"]:
        warnings.append(f"{r}: updated {f['updated']} precedes created {f['created']}")
    return errors, warnings


def cmd_check(args) -> int:
    if args.staged:
        paths = _staged_pages()
    elif args.paths:
        paths = [Path(p) for p in args.paths]
    else:
        paths = all_pages()

    required_buckets = set(REQUIRED_BUCKETS)
    all_errors, all_warnings = [], []
    for path in paths:
        if not path.exists():
            continue
        try:
            relp = path.resolve().relative_to(brain_dir().resolve())
        except ValueError:
            relp = path
        bucket = relp.parts[0] if len(relp.parts) > 1 else ""
        # Only enforce frontmatter for pages directly in a tracked bucket.
        if bucket not in required_buckets and bucket not in OPTIONAL_BUCKETS:
            continue
        # Nested material (resources/scripts/README.md) is validated when it has
        # frontmatter, but never required to — a subdirectory may hold non-pages.
        nested = len(relp.parts) != 2
        page = parse_page(path)
        errs, warns = validate_page(
            page, required_fm=(bucket in required_buckets and not nested))
        all_errors += errs
        all_warnings += warns

    for w in all_warnings:
        print(f"warning: {w}", file=sys.stderr)
    for e in all_errors:
        print(f"error: {e}", file=sys.stderr)

    # Version drift is a note, never an error: a rebuild ships a new CLI before
    # `/brain --sync` runs, and the pre-commit gate must not block in that window.
    sv = store_version()
    if sv != TEMPLATE_VERSION:
        seen = "unstamped" if sv is None else f"v{sv}"
        print(f"note: store is {seen}, CLI expects v{TEMPLATE_VERSION} — "
              f"run `/brain --sync`", file=sys.stderr)

    if args.strict and all_warnings:
        all_errors = all_errors + all_warnings
    if all_errors:
        print(f"brain check: {len(all_errors)} error(s)", file=sys.stderr)
        return 1
    return 0


def store_version() -> int | None:
    """The store's template version, or None if never stamped."""
    f = brain_dir() / VERSION_FILE
    if not f.exists():
        return None
    try:
        return int(f.read_text(encoding="utf-8").strip())
    except ValueError:
        return None


def cmd_version(args) -> int:
    # The stamp is written LAST by a migration, after the pages are migrated —
    # so an interrupted sync leaves the store visibly behind rather than
    # silently claiming to be current (which would make the next sync skip it).
    if args.stamp:
        (brain_dir() / VERSION_FILE).write_text(f"{TEMPLATE_VERSION}\n", encoding="utf-8")
        print(f"stamped {VERSION_FILE} = v{TEMPLATE_VERSION}")
        return 0
    sv = store_version()
    print(f"cli v{TEMPLATE_VERSION}, store {'unstamped' if sv is None else f'v{sv}'}")
    return 0 if sv == TEMPLATE_VERSION else 1


def _staged_pages() -> list:
    try:
        out = subprocess.run(
            ["git", "-C", str(brain_dir()), "diff", "--cached",
             "--name-only", "--diff-filter=ACM"],
            capture_output=True, text=True, check=True,
        ).stdout
    except (subprocess.CalledProcessError, FileNotFoundError):
        return all_pages()
    return [brain_dir() / line for line in out.splitlines() if line.endswith(".md")]


# --------------------------------------------------------------------------
# reindex
# --------------------------------------------------------------------------

STALE_DAYS = 21           # default "gone quiet" threshold for live work

SECTIONS = [
    ("Areas (ongoing)", ["areas"], None),
    ("Projects (end-stated)", ["projects"], ["idea", "planned", "active", "blocked"]),
    ("Maps of Content", ["mocs"], None),
    ("Resources", ["resources"], None),
    ("Archive", ["projects", "areas", "mocs", "resources"], ["done", "archived"]),
]


def _index_line(page: Page, indent: int = 0) -> str:
    f = page.fields
    status = f.get("status", "")
    att = f.get("attention")
    mark = f" · `{att}`" if att else ""
    summary = f.get("summary") or f.get("title") or page.slug
    stale = ""
    if f.get("status") in LIVE_STATUSES and f.get("kind") in WORK_KINDS:
        d = days_since(f.get("verified") or f.get("updated") or "")
        if d is not None and d > STALE_DAYS:
            stale = f"  ⚠ {d}d"
    pad = "  " * indent
    return f"{pad}- [[{page_ref(page)}]] — `{status}`{mark} — {summary}{stale}"


def cmd_reindex(args) -> int:
    index = brain_dir() / "index.md"
    pages_by_bucket = {b: [parse_page(p) for p in bucket_pages(b)] for b in
                       REQUIRED_BUCKETS + OPTIONAL_BUCKETS}
    missing_summary = []

    def in_section(page, statuses):
        if not page.has_fm:
            return False
        # Person pages are cataloged by the people MOC, so the index stays one
        # line long whether you know 2 people or 200. They remain fully in the
        # system — `check` validates them, `q --tag person` finds them.
        if is_person(page):
            return False
        st = page.fields.get("status", "")
        if statuses is not None:
            return st in statuses
        return st not in ("done", "archived")  # non-archive sections exclude done/archived

    blocks = []
    for title, buckets, statuses in SECTIONS:
        lines = [f"## {title}", ""]
        # Candidate pages for this section, and the set of slugs present, so a
        # child whose parent is filtered out still appears (as a top-level line).
        candidates = [pg for b in buckets for pg in pages_by_bucket.get(b, [])
                      if in_section(pg, statuses)]
        present = {pg.slug for pg in candidates}
        for page in candidates:
            if not page.fields.get("summary"):
                missing_summary.append(page.slug)
        emitted = 0
        for page in candidates:
            parent = (page.fields.get("parent") or "").strip("[]")
            if parent and parent in present:
                continue  # emitted under its parent below
            lines.append(_index_line(page))
            emitted += 1
            for child in candidates:
                if (child.fields.get("parent") or "").strip("[]") == page.slug:
                    lines.append(_index_line(child, indent=1))
        if emitted == 0:
            lines.append("_(none)_")
        blocks.append("\n".join(lines))

    generated = f"{GEN_BEGIN}\n\n" + "\n\n".join(blocks) + f"\n\n{GEN_END}"

    if index.exists():
        text = index.read_text(encoding="utf-8")
    else:
        text = "# Index — Brain Store\n\nMaster catalog. One line per page.\n\n**▶ Current focus:** [[now]]\n\n"

    if GEN_BEGIN in text and GEN_END in text:
        pre = text.split(GEN_BEGIN)[0].rstrip("\n")
        post = text.split(GEN_END, 1)[1].lstrip("\n")
        new = pre + "\n\n" + generated + ("\n\n" + post if post.strip() else "\n")
    else:
        new = text.rstrip("\n") + "\n\n" + generated + "\n"

    if args.check:
        if index.exists() and index.read_text(encoding="utf-8") == new:
            print("index.md is up to date")
            return 0
        print("brain reindex --check: index.md is stale (run `brain reindex`)", file=sys.stderr)
        return 1

    index.write_text(new, encoding="utf-8")
    print(f"reindexed {rel(index)}")
    if missing_summary:
        print(f"note: {len(missing_summary)} page(s) have no 'summary' "
              f"(used title as fallback): {', '.join(sorted(set(missing_summary)))}",
              file=sys.stderr)
    return 0


# --------------------------------------------------------------------------
# query
# --------------------------------------------------------------------------

def page_json(p: Page) -> dict:
    f = p.fields
    return {
        "ref": page_ref(p), "slug": p.slug, "title": f.get("title"),
        "kind": f.get("kind"), "status": f.get("status"),
        "attention": f.get("attention"), "progress": f.get("progress"),
        "next": f.get("next"), "due": f.get("due"),
        "updated": f.get("updated"), "verified": f.get("verified"),
        "summary": f.get("summary") or f.get("title"),
    }


def is_live_work(page: Page) -> bool:
    """A page that can go stale: work-bearing kind, in a status that implies motion."""
    f = page.fields
    return f.get("kind") in WORK_KINDS and f.get("status") in LIVE_STATUSES


def cmd_query(args) -> int:
    now = today()
    stale_before = None
    if args.stale is not None:
        cutoff = datetime.date.fromisoformat(now) - datetime.timedelta(days=args.stale)
        stale_before = cutoff.isoformat()

    rows = []
    for path in all_pages():
        page = parse_page(path)
        if not page.has_fm:
            continue
        f = page.fields
        if args.status and f.get("status") != args.status:
            continue
        if args.kind and f.get("kind") != args.kind:
            continue
        if args.tag and args.tag not in (f.get("tags") or []):
            continue
        if args.overdue:
            due = f.get("due")
            if not (due and is_valid_date(str(due)) and due < now
                    and f.get("status") not in ("done", "archived")):
                continue
        if args.due_before:
            due = f.get("due")
            if not (due and is_valid_date(str(due)) and due < args.due_before):
                continue
        if args.attention and f.get("attention") != args.attention:
            continue
        if args.unverified is not None:
            if not is_live_work(page):
                continue
            d = days_since(f.get("verified") or "")
            if d is not None and d <= args.unverified:
                continue
        if stale_before is not None:
            # Staleness only means something for live work. Without this a
            # `done` page and a people directory dominate the results, which is
            # how --stale came to return 2/3 noise.
            if not (args.all or is_live_work(page)):
                continue
            upd = f.get("updated")
            if not (upd and is_valid_date(str(upd)) and upd < stale_before):
                continue
        rows.append(page)

    rows.sort(key=lambda p: (p.fields.get("due") or "9999-99-99", p.slug))
    if args.json:
        import json  # noqa: PLC0415 — only the JSON paths pay the import
        print(json.dumps([page_json(p) for p in rows], indent=2))
        return 0
    for p in rows:
        f = p.fields
        due = f"due {f['due']}" if f.get("due") else ""
        print(f"{f.get('status',''):8} {due:14} {page_ref(p)} — "
              f"{f.get('summary') or f.get('title') or ''}")
    if not rows:
        print("(no matches)")
    return 0


# --------------------------------------------------------------------------
# Body skeletons
#
# Drawn from what the good pages in real stores already do. Each section says
# whether it is REWRITTEN in place or APPENDED to — that distinction is the
# point. Without it, "current state" sections accumulate (a page ends up with
# both "Where it stands (June)" and "Where it stands (July)") and pages grow
# without bound. Optional sections are marked; deleting is easier than
# remembering to add.
# --------------------------------------------------------------------------

_PROJECT_BODY = """
<!-- 2-4 lines: what this is, why it matters now, and what "done" looks like. REWRITE. -->
<!-- TODO: fill -->

**Next:** <!-- one concrete action; mirror it into the `next` field -->

## Why this exists

<!-- The rationale, written once so it isn't re-litigated. Touch only if the premise changes. -->

## Current state

<!-- REWRITE IN PLACE. Never add a second dated "where it stands" section.
     Stamp what you actually checked: "verified against the code 2026-07-26",
     and mirror that date into the `verified` field. -->

## Decisions

<!-- APPEND. `### <decision> — <date>`, each with why + consequences.
     Superseded ones stay, struck through, pointing at what replaced them. -->

## Open

<!-- Questions, risks, blockers. Delete lines as they close — this section should SHRINK. -->

## Tracker

<!-- Optional. One line per external issue, locally annotated. Link, don't duplicate. -->

## Drift

<!-- Optional. Where the design doc, the tracker and the code disagree. Stamp the check date. -->

## Links & sources
"""

_ADR_BODY = """
<!-- The decision in one breath. -->
<!-- TODO: fill -->

**Decision state:** proposed | accepted | superseded (<date>)
<!-- The ADR's own state. Frontmatter `status` is the *tracking* state — keep them distinct. -->

## Context

<!-- How it works today and what forces a decision. Written so it isn't re-litigated. -->

## Decision

## Consequences

<!-- What this makes easy, what it makes hard, what has to change downstream. -->

## Alternatives rejected

<!-- Each with the reason it lost. This is the section that stops re-litigation. -->

## Links & sources
"""

_AREA_BODY = """
<!-- 2-4 lines: the responsibility, and what "healthy" looks like.
     No end state — if it has one, it's a project, not an area. -->
<!-- TODO: fill -->

## The line I hold

<!-- The position you defend. Rewriting this is rare and deserves a log entry. -->

## Current state

<!-- REWRITE IN PLACE. Where adoption/health actually is, and when you last checked. -->

## Live threads

<!-- `### <thread> — <date>` per open debate: positions, who holds what, where it stands.
     Close one by moving its outcome into Decisions, then DELETE it here. -->

## Decisions

<!-- APPEND. -->

## Links & sources
"""

_MOC_BODY = """
<!-- What this map is for, and the rule for what belongs in it. -->
<!-- TODO: fill -->

<!-- If entries need a legend or grouping convention, state it in one line. -->

## Pages

- [[page]] — <its role in THIS map; index.md already carries the summary>

## Not here (and why)

<!-- Optional. Near-misses, so the boundary of the map is explicit. -->
"""

_RESOURCE_BODY = """
<!-- What this is, where it came from, and what it's useful FOR. -->
<!-- TODO: fill -->

**As of:** <date>
<!-- Reference material goes stale silently — stamp it, and mirror into `verified`. -->

## Takeaway

<!-- The compiled version. If a verbatim artifact exists, point at it; don't paraphrase it away. -->

## Relevance

<!-- Which pages consume this, and why. -->

## Source

<!-- Verbatim URL or artifact path. Never paraphrased. -->
"""

# A person is a resource by kind (no bucket of their own) but wants a different
# shape — see the People section of CLAUDE.md. Reached via `new resource --person`.
_PERSON_BODY = """
<!-- Who they are, in one line, and how you know them. -->
<!-- TODO: fill -->

- Contact: <!-- handle / email / phone — whatever exists; omit what doesn't -->

## Context

<!-- What they own, positions they hold, history worth not re-deriving.
     Keep to what you need to work with them — no PII you don't need. -->

## Where we overlap

<!-- Pages in this brain that involve them. -->

Part of [[people]].
"""

BODY_TEMPLATES = {
    "project": _PROJECT_BODY,
    "initiative": _PROJECT_BODY,
    "adr": _ADR_BODY,
    "area": _AREA_BODY,
    "moc": _MOC_BODY,
    "resource": _RESOURCE_BODY,
}


# --------------------------------------------------------------------------
# writers (Layer 3) — new / set / done
# --------------------------------------------------------------------------

def cmd_new(args) -> int:
    kind = args.kind
    if kind not in KINDS:
        die(f"kind must be one of {KINDS}")
    status = args.status or "idea"
    if status not in STATUSES:
        die(f"status must be one of {STATUSES}")
    bucket = KIND_BUCKET[kind]
    path = brain_dir() / bucket / f"{args.slug}.md"
    if path.exists():
        die(f"page already exists: {path.relative_to(brain_dir())}")
    path.parent.mkdir(parents=True, exist_ok=True)
    title = args.title or args.slug.replace("-", " ").title()
    fields = {
        "title": title, "kind": kind, "status": status, "owner": "me",
        "created": today(), "updated": today(),
    }
    if status == "active":
        fields["started"] = today()
    if status == "done":
        fields["finished"] = today()
    for opt in ("summary", "due", "parent"):
        v = getattr(args, opt, None)
        if v:
            fields[opt] = v
    tags = [t.strip() for t in (args.tags or "").split(",") if t.strip()]
    if getattr(args, "person", False):
        if kind != "resource":
            die("--person applies to `new resource` (a person page is a resource)")
        if PERSON_TAG not in tags:
            tags.append(PERSON_TAG)
    if getattr(args, "attention", None):
        if args.attention not in ATTENTIONS:
            die(f"attention must be one of {ATTENTIONS}")
        fields["attention"] = args.attention
    if args.next:
        fields["next"] = args.next
    if tags:
        fields["tags"] = sorted(dict.fromkeys(tags))
    skeleton = _PERSON_BODY if PERSON_TAG in tags else BODY_TEMPLATES.get(kind, "\n<!-- TODO: fill -->\n")
    body = f"# {title}\n{skeleton}"
    page = Page(path, fields, list(fields.keys()), body, has_fm=True)
    errs, _ = validate_page(page, required_fm=True)
    if errs:
        die("refusing to write invalid page:\n  " + "\n  ".join(errs))
    write_page(page)
    print(rel(path))
    return 0


SETTABLE = {"title", "status", "attention", "progress", "next",
            "summary", "due", "parent", "owner", "verified"}


def cmd_set(args) -> int:
    field, value = args.field, args.value
    if field not in SETTABLE and field not in ("started", "finished"):
        die(f"field '{field}' is not settable via `set` "
            f"(settable: {sorted(SETTABLE | {'started', 'finished'})})")
    path = resolve_page(args.page)
    page = parse_page(path)
    if not page.has_fm:
        die(f"{path} has no frontmatter")

    if field == "status":
        if value not in STATUSES:
            die(f"status must be one of {STATUSES}")
        page.fields["status"] = value
        if value == "active" and not page.fields.get("started"):
            page.fields["started"] = today()
        if value == "done" and not page.fields.get("finished"):
            page.fields["finished"] = today()
    elif field == "attention":
        if value not in ATTENTIONS:
            die(f"attention must be one of {ATTENTIONS} (unset it for ordinary work)")
        page.fields["attention"] = value
    elif field in DATE_FIELDS:
        # `today` is accepted as a convenience so callers never hand-type a date
        # (and so can't accidentally copy one out of the corpus).
        if value == "today":
            value = today()
        if not is_valid_date(value):
            die(f"{field} must be an ISO YYYY-MM-DD date (or 'today')")
        page.fields[field] = value
    else:
        page.fields[field] = value

    page.fields["updated"] = today()
    errs, _ = validate_page(page, required_fm=True)
    if errs:
        die("refusing to write invalid page:\n  " + "\n  ".join(errs))
    write_page(page)
    print(f"{rel(path)}: {field} = {value}")
    return 0


def cmd_unset(args) -> int:
    # Remove an optional field. Required fields are refused (deleting one would
    # produce an invalid page); the write is re-validated regardless.
    field = args.field
    if field in REQUIRED:
        die(f"cannot unset required field '{field}' (required: {REQUIRED})")
    path = resolve_page(args.page)
    page = parse_page(path)
    if not page.has_fm:
        die(f"{path} has no frontmatter")
    if field not in page.fields:
        print(f"{rel(path)}: {field} already unset")
        return 0
    del page.fields[field]
    if field in page.order:
        page.order.remove(field)
    page.fields["updated"] = today()
    errs, _ = validate_page(page, required_fm=True)
    if errs:
        die("refusing to write invalid page:\n  " + "\n  ".join(errs))
    write_page(page)
    print(f"{rel(path)}: {field} unset")
    return 0


def cmd_done(args) -> int:
    path = resolve_page(args.page)
    page = parse_page(path)
    if not page.has_fm:
        die(f"{path} has no frontmatter")
    page.fields["status"] = "done"
    if not page.fields.get("finished"):
        page.fields["finished"] = today()
    page.fields["updated"] = today()
    write_page(page)
    print(f"{rel(path)}: done ({page.fields['finished']})")
    return 0


def cmd_normalize(args) -> int:
    paths = ([Path(p).resolve() for p in args.paths] if args.paths else all_pages())
    changed = []
    for path in paths:
        if not path.exists():
            continue
        page = parse_page(path)
        if not page.has_fm:
            continue
        before = serialize(page)
        st = str(page.fields.get("status", "")).lower()
        page.fields["status"] = STATUS_SYNONYMS.get(st, st)
        kd = str(page.fields.get("kind", "")).lower()
        page.fields["kind"] = KIND_SYNONYMS.get(kd, kd)
        if isinstance(page.fields.get("tags"), list):
            page.fields["tags"] = sorted(dict.fromkeys(page.fields["tags"]))
        if not page.fields.get("owner"):
            page.fields["owner"] = "me"
        # Freshly-seeded scaffold pages carry the sentinel date; stamp them for real.
        for df in ("created", "updated"):
            if page.fields.get(df) == SCAFFOLD_DATE:
                page.fields[df] = today()
        after = serialize(page)
        if before != after:
            write_page(page)
            changed.append(rel(path))
    for c in changed:
        print(f"normalized {c}")
    if not changed:
        print("nothing to normalize")
    return 0


# --------------------------------------------------------------------------
# review — the read-only briefing
#
# Writes NOTHING. It is the generated half of a "now" page: what's in focus,
# what's gone quiet, what's blocked or overdue, what the clock says. The
# judgment half (why this ordering, what you're deliberately not doing) stays
# in mocs/now.md, which no command may rewrite.
# --------------------------------------------------------------------------

OVERSIZE_LINES = 300      # a page past this wants splitting
NOW_MAX_LINES = 60        # a `now` page past this is holding generated content


def _read_focus() -> str | None:
    index = brain_dir() / "index.md"
    if not index.exists():
        return None
    m = re.search(r"^\*\*▶ Current focus:\*\*\s*(.+)$",
                  index.read_text(encoding="utf-8"), re.M)
    return m.group(1).strip() if m else None


def _recent_log(limit: int) -> list:
    log = brain_dir() / "log.md"
    if not log.exists():
        return []
    return [ln for ln in log.read_text(encoding="utf-8").splitlines()
            if ln.startswith("- ")][:limit]


def _log_dates() -> list:
    return [m.group(1) for ln in _recent_log(10_000)
            if (m := re.match(r"^- (\d{4}-\d{2}-\d{2}) ", ln))]


def _dstask_open() -> list:
    """Open dstask tasks. dstask emits JSON when stdout isn't a TTY."""
    try:
        out = subprocess.run(["dstask"], capture_output=True, text=True,
                             timeout=10, check=True).stdout
    except (subprocess.CalledProcessError, FileNotFoundError,
            subprocess.TimeoutExpired, OSError):
        return []
    try:
        import json
        data = json.loads(out)
    except ValueError:
        return []
    return [t for t in data if t.get("status") in ("pending", "active")]


def _inbox_count() -> int:
    inbox = brain_dir() / "raw" / "inbox.md"
    if not inbox.exists():
        return 0
    return sum(1 for ln in inbox.read_text(encoding="utf-8").splitlines()
               if ln.startswith("- "))


def _page_lines(page: Page) -> int:
    try:
        return len(page.path.read_text(encoding="utf-8").splitlines())
    except OSError:
        return 0


def _collect(stale_days: int) -> dict:
    pages = [parse_page(p) for p in all_pages()]
    pages = [p for p in pages if p.has_fm]
    live = [p for p in pages if is_live_work(p)]
    now = today()

    def quiet(p):
        # `verified` is the real signal — when the page's claims were last
        # checked against reality. `updated` moves on a typo fix, so it is only
        # the fallback for pages that have never been verified.
        return days_since(p.fields.get("verified") or p.fields.get("updated") or "")

    return {
        "focus_pointer": _read_focus(),
        "focus": [p for p in live if p.fields.get("attention") == "focus"],
        "working": [p for p in live if not p.fields.get("attention")],
        "tracking": [p for p in live if p.fields.get("attention") == "tracking"],
        "blocked": [p for p in pages if p.fields.get("status") == "blocked"],
        "overdue": [p for p in pages
                    if (d := p.fields.get("due")) and is_valid_date(str(d))
                    and d < now and p.fields.get("status") not in ("done", "archived")],
        "quiet": sorted(((p, q) for p in live if (q := quiet(p)) is not None
                         and q > stale_days), key=lambda t: -t[1]),
        "unverified": [p for p in live if not p.fields.get("verified")],
        "oversized": sorted(((p, n) for p in pages
                             if (n := _page_lines(p)) > OVERSIZE_LINES),
                            key=lambda t: -t[1]),
        "pages": pages,
    }


def _now_warning() -> str | None:
    now_page = brain_dir() / "mocs" / "now.md"
    if not now_page.exists():
        return None
    lines = len(now_page.read_text(encoding="utf-8").splitlines())
    page = parse_page(now_page)
    upd = page.fields.get("updated") if page.has_fm else None
    dates = _log_dates()
    behind = None
    if upd and dates and is_valid_date(str(upd)) and is_valid_date(dates[0]):
        behind = (datetime.date.fromisoformat(dates[0])
                  - datetime.date.fromisoformat(str(upd))).days
    if lines <= NOW_MAX_LINES and not (behind and behind > 14):
        return None
    tail = f", {behind}d behind the newest log entry" if behind and behind > 14 else ""
    return (f"now.md — {lines} lines{tail}\n"
            f"   ⚠ likely holds content `brain review` now generates; keep only "
            f"why this ordering and what you're deliberately not doing")


def _fmt(p: Page, width: int) -> str:
    f = p.fields
    bits = f"{page_ref(p):{width}} {f.get('status',''):8}"
    q = days_since(f.get("verified") or f.get("updated") or "")
    seen = "verified" if f.get("verified") else "updated"
    bits += f" {seen} {q}d" if q is not None else ""
    if f.get("due"):
        bits += f" · due {f['due']}"
    if f.get("progress"):
        bits += f" · {f['progress']}"
    line = bits.rstrip()
    if f.get("next"):
        line += f"\n{' ' * 4}→ {f['next']}"
    return line


def cmd_review(args) -> int:
    if args.since is not None:
        return _review_window(args)
    d = _collect(args.stale)
    if args.json:
        import json
        print(json.dumps({
            "date": today(),
            "focus_pointer": d["focus_pointer"],
            **{k: [page_json(p) for p in d[k]]
               for k in ("focus", "working", "tracking", "blocked", "overdue",
                         "unverified")},
            "quiet": [dict(page_json(p), quiet_days=n) for p, n in d["quiet"]],
            "oversized": [dict(page_json(p), lines=n) for p, n in d["oversized"]],
            "dstask_open": len(_dstask_open()),
            "inbox_pending": _inbox_count(),
        }, indent=2))
        return 0

    refs = [page_ref(p) for p in d["pages"]] or [""]
    w = min(max(len(r) for r in refs), 34)
    out = [f"brain — {today()}"]
    if d["focus_pointer"]:
        out += ["", f"▶ Focus  {d['focus_pointer']}"]

    for title, key in (("Focus", "focus"), ("Working", "working"),
                       ("Tracking", "tracking")):
        if d[key]:
            out += ["", f"{title} ({len(d[key])})"]
            out += [f"  {_fmt(p, w)}" for p in d[key]]

    for title, key in (("Blocked", "blocked"), ("Overdue", "overdue")):
        out += ["", f"{title} ({len(d[key])})"]
        out += [f"  {_fmt(p, w)}" for p in d[key]] or ["  (none)"]

    out += ["", f"Gone quiet > {args.stale}d ({len(d['quiet'])})"]
    out += [f"  {_fmt(p, w)}" for p, _ in d["quiet"]] or ["  (none)"]

    if d["unverified"]:
        shown = [page_ref(p) for p in d["unverified"][:8]]
        more = len(d["unverified"]) - len(shown)
        out += ["", f"Never verified ({len(d['unverified'])})",
                "  " + ", ".join(shown) + (f", … {more} more" if more else "")]
    if d["oversized"]:
        out += ["", f"Oversized > {OVERSIZE_LINES} lines ({len(d['oversized'])})"]
        out += [f"  {page_ref(p):{w}} {n} lines" for p, n in d["oversized"]]

    nw = _now_warning()
    if nw:
        out += ["", nw]

    recent = _recent_log(args.log)
    if recent:
        out += ["", f"Log (last {len(recent)})"] + [f"  {ln[2:]}" for ln in recent]

    tasks = _dstask_open()
    if tasks:
        out += ["", f"dstask ({len(tasks)} open)"]
        out += [f"  {t.get('id'):>3}  {'+' + ' +'.join(t.get('tags') or []):16} "
                f"{t.get('summary','')}" for t in tasks[:10]]
        if len(tasks) > 10:
            out.append(f"  … {len(tasks) - 10} more")

    pending = _inbox_count()
    if pending:
        out += ["", f"Inbox: {pending} pending — process with /brain"]

    print("\n".join(out))
    return 0


def _review_window(args) -> int:
    """The weekly cut: what moved inside a window, and what didn't."""
    cutoff = (datetime.date.today() - datetime.timedelta(days=args.since)).isoformat()
    pages = [p for p in (parse_page(x) for x in all_pages()) if p.has_fm]

    def within(field):
        return [p for p in pages if (v := p.fields.get(field))
                and is_valid_date(str(v)) and str(v) >= cutoff]

    started, finished = within("started"), within("finished")
    touched = within("updated")
    entries = [ln for ln in _recent_log(10_000)
               if (m := re.match(r"^- (\d{4}-\d{2}-\d{2}) ", ln)) and m.group(1) >= cutoff]
    untouched = [p for p in pages if is_live_work(p) and p not in touched]

    if args.json:
        import json
        print(json.dumps({
            "window_start": cutoff, "window_end": today(),
            "started": [page_json(p) for p in started],
            "finished": [page_json(p) for p in finished],
            "touched": [page_json(p) for p in touched],
            "untouched_live": [page_json(p) for p in untouched],
            "log_entries": len(entries),
        }, indent=2))
        return 0

    def names(ps):
        return ", ".join(page_ref(p) for p in ps) or "(none)"

    untouched_lines = [f"  {page_ref(p)}" for p in untouched] or ["  (none)"]
    print("\n".join([
        f"Window {cutoff} → {today()}",
        "",
        f"Started ({len(started)})    {names(started)}",
        f"Finished ({len(finished)})   {names(finished)}",
        f"Touched ({len(touched)})    {names(touched)}",
        f"Log entries  {len(entries)}",
        "",
        f"Live but untouched in window ({len(untouched)})",
        *untouched_lines,
    ]))
    return 0


# --------------------------------------------------------------------------
# capture — the zero-friction inbox
# --------------------------------------------------------------------------

def cmd_capture(args) -> int:
    text = sys.stdin.read() if args.text == "-" else args.text
    if not text.strip():
        die("nothing to capture (empty input)")
    raw = brain_dir() / "raw"
    raw.mkdir(parents=True, exist_ok=True)

    if args.title:
        # Substantial source material: its own immutable raw file, never edited.
        path = raw / f"{today()}-{args.title}.md"
        if path.exists():
            die(f"{rel(path)} already exists (raw captures are immutable)")
        path.write_text(text if text.endswith("\n") else text + "\n", encoding="utf-8")
        print(f"wrote {rel(path)} ({len(text)} bytes)")
        return 0

    # Time comes from the clock like every other date in this store.
    stamp = f"{today()} {datetime.datetime.now().strftime('%H:%M')}"
    entry = f"- {stamp} — {' '.join(text.split())}"
    inbox = raw / "inbox.md"
    if not inbox.exists():
        inbox.write_text(
            "# Inbox\n\nUnprocessed captures. Compile into pages, then delete the "
            "line.\n\n" + entry + "\n", encoding="utf-8")
    else:
        body = inbox.read_text(encoding="utf-8").rstrip("\n")
        inbox.write_text(body + "\n" + entry + "\n", encoding="utf-8")
    print(f"raw/inbox.md ← 1 entry ({_inbox_count()} pending)")
    return 0


def cmd_today(args) -> int:
    # Authoritative "now" from the system clock — so callers never infer the
    # date from corpus content (log.md / page dates are data, not "today").
    print(today())
    return 0


def cmd_log(args) -> int:
    log = brain_dir() / "log.md"

    if args.for_page:
        # This page's slice of the timeline, so page bodies don't need to
        # re-narrate what log.md already records.
        ref = resolve_page(args.for_page)
        slug = slug_of(ref)
        hits = [ln for ln in _recent_log(10_000)
                if f"[[{slug}]]" in ln or f"[[{rel(ref)[:-3]}]]" in ln]
        for extra in (brain_dir() / "log-archive").glob("*.md") \
                if (brain_dir() / "log-archive").is_dir() else []:
            hits += [ln for ln in extra.read_text(encoding="utf-8").splitlines()
                     if ln.startswith("- ") and f"[[{slug}]]" in ln]
        print("\n".join(sorted(set(hits), reverse=True)) or f"(no log entries for {slug})")
        return 0

    if not args.message:
        die("log needs a message (or --for <page> to read a page's entries)")
    # Prepend a dated activity entry, dating it from the system clock so the
    # date is never hand-typed (and thus never inferred from the corpus).
    entry = f"- {today()} — {args.message}"
    if not log.exists():
        log.write_text(f"# Log\n\nAppend-only activity log. Newest first.\n\n{entry}\n",
                       encoding="utf-8")
        print(entry)
        return 0
    lines = log.read_text(encoding="utf-8").splitlines()
    idx = next((i for i, ln in enumerate(lines) if ln.startswith("- ")), None)
    if idx is None:
        while lines and not lines[-1].strip():
            lines.pop()
        lines += ["", entry]
    else:
        lines.insert(idx, entry)  # newest first, above existing entries
    log.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(entry)
    return 0


# --------------------------------------------------------------------------
# CLI
# --------------------------------------------------------------------------

def main() -> int:
    p = argparse.ArgumentParser(prog="brain", description=__doc__.splitlines()[0])
    sub = p.add_subparsers(dest="cmd", required=True)

    c = sub.add_parser("check", help="validate frontmatter (the gate)")
    c.add_argument("paths", nargs="*")
    c.add_argument("--staged", action="store_true", help="only git-staged pages")
    c.add_argument("--strict", action="store_true", help="treat warnings as errors")
    c.set_defaults(func=cmd_check)

    r = sub.add_parser("reindex", help="regenerate index.md's generated region")
    r.add_argument("--check", action="store_true", help="exit non-zero if stale, don't write")
    r.set_defaults(func=cmd_reindex)

    q = sub.add_parser("q", help="structured query over frontmatter")
    q.add_argument("--status", choices=STATUSES)
    q.add_argument("--kind", choices=KINDS)
    q.add_argument("--tag")
    q.add_argument("--overdue", action="store_true", help="due before today and not done")
    q.add_argument("--due-before", metavar="YYYY-MM-DD")
    q.add_argument("--attention", choices=ATTENTIONS)
    q.add_argument("--stale", type=int, metavar="DAYS",
                   help="live work updated more than DAYS ago (add --all for every kind)")
    q.add_argument("--unverified", type=int, nargs="?", const=0, metavar="DAYS",
                   help="live work not verified within DAYS (default: ever)")
    q.add_argument("--all", action="store_true",
                   help="with --stale, don't restrict to live work")
    q.add_argument("--json", action="store_true")
    q.set_defaults(func=cmd_query)

    rv = sub.add_parser("review", help="read-only briefing (writes nothing)")
    rv.add_argument("--since", type=int, metavar="DAYS",
                    help="window mode: what moved in the last DAYS")
    rv.add_argument("--stale", type=int, default=STALE_DAYS, metavar="DAYS",
                    help=f"gone-quiet threshold (default {STALE_DAYS})")
    rv.add_argument("--log", type=int, default=5, metavar="N",
                    help="how many log entries to show (default 5)")
    rv.add_argument("--json", action="store_true")
    rv.set_defaults(func=cmd_review)

    n = sub.add_parser("new", help="create a schema-perfect page")
    n.add_argument("kind", choices=KINDS)
    n.add_argument("slug")
    n.add_argument("--title")
    n.add_argument("--status", choices=STATUSES)
    n.add_argument("--attention", choices=ATTENTIONS)
    n.add_argument("--summary")
    n.add_argument("--next", help="the single next concrete move")
    n.add_argument("--due")
    n.add_argument("--parent")
    n.add_argument("--tags", help="comma-separated")
    n.add_argument("--person", action="store_true",
                   help="a person page (resource + tags:[person], person skeleton)")
    n.set_defaults(func=cmd_new)

    s = sub.add_parser("set", help="set one frontmatter field (validated)")
    s.add_argument("page")
    s.add_argument("field")
    s.add_argument("value")
    s.set_defaults(func=cmd_set)

    u = sub.add_parser("unset", help="remove one optional frontmatter field")
    u.add_argument("page")
    u.add_argument("field")
    u.set_defaults(func=cmd_unset)

    d = sub.add_parser("done", help="mark a page done")
    d.add_argument("page")
    d.set_defaults(func=cmd_done)

    nm = sub.add_parser("normalize", help="repair-on-drift in place")
    nm.add_argument("paths", nargs="*")
    nm.set_defaults(func=cmd_normalize)

    cp = sub.add_parser("capture", help="append to raw/inbox.md (or '-' from stdin)")
    cp.add_argument("text", help="the capture, or '-' to read stdin")
    cp.add_argument("--title", metavar="SLUG",
                    help="write raw/YYYY-MM-DD-SLUG.md instead of an inbox line")
    cp.set_defaults(func=cmd_capture)

    lg = sub.add_parser("log", help="prepend a dated activity entry (date from the clock)")
    lg.add_argument("message", nargs="?")
    lg.add_argument("--for", dest="for_page", metavar="PAGE",
                    help="read this page's log entries instead of writing one")
    lg.set_defaults(func=cmd_log)

    vs = sub.add_parser("version", help="CLI/store template version")
    vs.add_argument("--stamp", action="store_true",
                    help="write .brain-version (do this LAST in a migration)")
    vs.set_defaults(func=cmd_version)

    td = sub.add_parser("today", help="print today's date (system clock) — don't infer it")
    td.set_defaults(func=cmd_today)

    args = p.parse_args()
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
