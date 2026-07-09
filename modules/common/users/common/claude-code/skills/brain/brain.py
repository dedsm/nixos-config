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
  new       create a schema-perfect page in the right bucket
  set       set one frontmatter field (validated), stamping dates
  done      mark a page done (status=done, finished=today)
  normalize repair-on-drift: canonicalise status/kind/tags in place
  log       prepend a dated activity entry to log.md (date from the system clock)
  today     print today's date from the system clock (never infer it from the corpus)
  install-hooks  install the pre-commit gate into ~/brain/.git/hooks

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

KINDS = ["adr", "initiative", "project", "area", "resource", "moc"]
STATUSES = ["idea", "planned", "active", "blocked", "done", "archived"]
REQUIRED = ["title", "kind", "status", "created", "updated"]
DATE_FIELDS = ["created", "updated", "started", "finished", "due"]
LIST_FIELDS = ["tags", "links"]
# Canonical serialisation order. Unknown keys are preserved and emitted after.
FIELD_ORDER = [
    "title", "kind", "status", "progress", "owner",
    "created", "updated", "started", "finished", "due",
    "summary", "parent", "tags", "links",
]

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
    d = brain_dir() / bucket
    if not d.is_dir():
        return []
    return sorted(p for p in d.glob("*.md") if p.is_file())


def all_pages(require_only: bool = False) -> list:
    buckets = REQUIRED_BUCKETS + ([] if require_only else OPTIONAL_BUCKETS)
    out = []
    for b in buckets:
        out.extend(bucket_pages(b))
    return out


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
    for d in DATE_FIELDS:
        if d in f and f[d] and not is_valid_date(str(f[d])):
            errors.append(f"{r}: {d} '{f[d]}' is not an ISO YYYY-MM-DD date")
    for lf in LIST_FIELDS:
        if lf in f and not isinstance(f[lf], list):
            errors.append(f"{r}: {lf} must be a list")

    # Semantic niceties — warnings only (never block a commit).
    if f.get("status") == "done" and not f.get("finished"):
        warnings.append(f"{r}: status done but no 'finished' date")
    if f.get("status") == "active" and not f.get("started"):
        warnings.append(f"{r}: status active but no 'started' date")
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
        if len(relp.parts) != 2:  # skip nested files like resources/scripts/*
            continue
        page = parse_page(path)
        errs, warns = validate_page(page, required_fm=bucket in required_buckets)
        all_errors += errs
        all_warnings += warns

    for w in all_warnings:
        print(f"warning: {w}", file=sys.stderr)
    for e in all_errors:
        print(f"error: {e}", file=sys.stderr)

    if args.strict and all_warnings:
        all_errors = all_errors + all_warnings
    if all_errors:
        print(f"brain check: {len(all_errors)} error(s)", file=sys.stderr)
        return 1
    return 0


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
    summary = f.get("summary") or f.get("title") or page.slug
    pad = "  " * indent
    return f"{pad}- [[{page.slug}]] — `{status}` — {summary}"


def cmd_reindex(args) -> int:
    index = brain_dir() / "index.md"
    pages_by_bucket = {b: [parse_page(p) for p in bucket_pages(b)] for b in
                       REQUIRED_BUCKETS + OPTIONAL_BUCKETS}
    missing_summary = []

    def in_section(page, statuses):
        if not page.has_fm:
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
        if stale_before is not None:
            upd = f.get("updated")
            if not (upd and is_valid_date(str(upd)) and upd < stale_before):
                continue
        rows.append(page)

    rows.sort(key=lambda p: (p.fields.get("due") or "9999-99-99", p.slug))
    if args.json:
        import json
        print(json.dumps([{
            "slug": p.slug, "status": p.fields.get("status"),
            "kind": p.fields.get("kind"), "due": p.fields.get("due"),
            "updated": p.fields.get("updated"),
            "summary": p.fields.get("summary") or p.fields.get("title"),
        } for p in rows], indent=2))
        return 0
    for p in rows:
        f = p.fields
        due = f"due {f['due']}" if f.get("due") else ""
        print(f"{f.get('status',''):8} {due:14} {p.slug} — "
              f"{f.get('summary') or f.get('title') or ''}")
    if not rows:
        print("(no matches)")
    return 0


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
    if args.tags:
        fields["tags"] = [t.strip() for t in args.tags.split(",") if t.strip()]
    body = f"# {title}\n\n<!-- TODO: fill -->\n"
    page = Page(path, fields, list(fields.keys()), body, has_fm=True)
    errs, _ = validate_page(page, required_fm=True)
    if errs:
        die("refusing to write invalid page:\n  " + "\n  ".join(errs))
    write_page(page)
    print(rel(path))
    return 0


SETTABLE = {"title", "status", "progress", "summary", "due", "parent", "owner"}


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
    elif field in DATE_FIELDS:
        if not is_valid_date(value):
            die(f"{field} must be an ISO YYYY-MM-DD date")
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
        after = serialize(page)
        if before != after:
            write_page(page)
            changed.append(rel(path))
    for c in changed:
        print(f"normalized {c}")
    if not changed:
        print("nothing to normalize")
    return 0


def cmd_today(args) -> int:
    # Authoritative "now" from the system clock — so callers never infer the
    # date from corpus content (log.md / page dates are data, not "today").
    print(today())
    return 0


def cmd_log(args) -> int:
    # Prepend a dated activity entry, dating it from the system clock so the
    # date is never hand-typed (and thus never inferred from the corpus).
    log = brain_dir() / "log.md"
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


def cmd_install_hooks(args) -> int:
    hooks = brain_dir() / ".git" / "hooks"
    if not (brain_dir() / ".git").is_dir():
        die(f"{brain_dir()} is not a git repo (run `git init` first)")
    hooks.mkdir(parents=True, exist_ok=True)
    py = sys.executable
    script = os.path.abspath(__file__)
    hook = hooks / "pre-commit"
    hook.write_text(
        f"#!/bin/sh\n# Installed by `brain install-hooks` — Nix-managed gate.\n"
        f"exec {py} {script} check --staged\n", encoding="utf-8")
    hook.chmod(0o755)
    print(f"installed {hook}")
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
    q.add_argument("--stale", type=int, metavar="DAYS", help="updated more than DAYS ago")
    q.add_argument("--json", action="store_true")
    q.set_defaults(func=cmd_query)

    n = sub.add_parser("new", help="create a schema-perfect page")
    n.add_argument("kind", choices=KINDS)
    n.add_argument("slug")
    n.add_argument("--title")
    n.add_argument("--status", choices=STATUSES)
    n.add_argument("--summary")
    n.add_argument("--due")
    n.add_argument("--parent")
    n.add_argument("--tags", help="comma-separated")
    n.set_defaults(func=cmd_new)

    s = sub.add_parser("set", help="set one frontmatter field (validated)")
    s.add_argument("page")
    s.add_argument("field")
    s.add_argument("value")
    s.set_defaults(func=cmd_set)

    d = sub.add_parser("done", help="mark a page done")
    d.add_argument("page")
    d.set_defaults(func=cmd_done)

    nm = sub.add_parser("normalize", help="repair-on-drift in place")
    nm.add_argument("paths", nargs="*")
    nm.set_defaults(func=cmd_normalize)

    lg = sub.add_parser("log", help="prepend a dated activity entry (date from the clock)")
    lg.add_argument("message")
    lg.set_defaults(func=cmd_log)

    td = sub.add_parser("today", help="print today's date (system clock) — don't infer it")
    td.set_defaults(func=cmd_today)

    ih = sub.add_parser("install-hooks", help="install the pre-commit gate")
    ih.set_defaults(func=cmd_install_hooks)

    args = p.parse_args()
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
