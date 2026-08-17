#!/usr/bin/env python3
"""brain — deterministic frontmatter tooling for the ~/brain tracking store.

This is the single source of truth for the store's schema and the only thing
that should ever write page frontmatter. It is Nix-managed and shipped from
nixos-config alongside the brain skill; do NOT edit the deployed copy. See the
governance note in ~/brain/CLAUDE.md before changing any rule here.

Subcommands:
  check     validate frontmatter + internal links (exits non-zero on errors)
  reindex   regenerate index.md's generated region and the people directory's
            generated "Where they appear" column from the pages
  q         structured query over frontmatter (status/overdue/stale/tag/kind)
  links     lint internal links (broken/ambiguous wikilinks are errors, relative
            markdown paths warn); --to PAGE lists the pages linking to PAGE
  mv        move/rename a page and rewrite [[references]] across the store
  review    read-only briefing: goals, focus, attention, blocked, overdue, unverified, dstask
  new       create a schema-perfect page in the right bucket
  set       set one frontmatter field (validated), stamping dates
  unset     remove one optional frontmatter field (never a required one)
  done      mark a page done (status=done, finished=today)
  normalize repair-on-drift: canonicalise status/kind/tags in place
  capture   append a timestamped entry to raw/inbox.md (or a raw file from stdin)
  log       prepend a dated activity entry to log.md (date from the system clock)
  rotate-log  move log.md's older tail into log-archive/YYYY.md (mechanical)
  health    one-line store vitals; exits non-zero when something needs attention
  sync      mechanical template refresh + stamp (stops before stamping when a
            registered judgment migration is pending — finish via /brain --sync)
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

TEMPLATE_VERSION = 13     # bump with templates/CLAUDE.md; `.brain-version` mirrors it
VERSION_FILE = ".brain-version"

# `goal` is the quarterly outcomes layer: 3-5 live at a time, due = quarter
# end, children linked via the existing `parent` field. Deliberately no new
# fields or verbs — goals ride the schema as-is, and review/health derive the
# rollup (milestones, orphaned/stalled) at read time.
KINDS = ["goal", "initiative", "project", "area", "resource", "moc"]
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
TIMELINE_KINDS = {"goal", "initiative", "project"}
# Kinds that carry work, and so can be stale, blocked, overdue or unverified.
WORK_KINDS = {"goal", "initiative", "project", "area"}
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
    "goal": "goals",
    "initiative": "projects",
    "project": "projects",
    "area": "areas",
    "resource": "resources",
    "moc": "mocs",
}

# Buckets whose top-level .md pages MUST carry valid frontmatter.
REQUIRED_BUCKETS = ["goals", "projects", "areas", "mocs", "archive"]
# Buckets where frontmatter is validated only if present (mixed reference material).
OPTIONAL_BUCKETS = ["resources"]

# status synonyms mapped to canonical values by `normalize`.
STATUS_SYNONYMS = {
    "in-progress": "active", "in_progress": "active", "wip": "active",
    "todo": "planned", "to-do": "planned", "backlog": "planned",
    "complete": "done", "completed": "done", "finished": "done",
    "cancelled": "archived", "canceled": "archived", "dormant": "archived",
}
# A tracked decision is a project page: the decision text itself belongs in
# its external system of record; the brain page follows the rollout.
KIND_SYNONYMS = {"decision": "project", "note": "resource", "reference": "resource"}

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


def page_ref(page: "Page", ambiguous: frozenset = frozenset()) -> str:
    """Wikilink target: bare slug for a top-level page, path for a nested one.
    `ambiguous` (duplicated stems, see _dup_stems) forces the path form — a
    generated file must never emit a bare link the gate would then reject."""
    r = rel(page.path)
    parts = Path(r).parts
    if len(parts) <= 2 and page.slug not in ambiguous:
        return page.slug
    return r[: -len(".md")]


def _dup_stems() -> frozenset:
    """Filename stems shared by more than one store file. `new` and `mv`
    refuse to mint these, but a hand-created file or a two-machine merge still
    can — and the generators must stay unambiguous regardless."""
    seen: dict = {}
    for p in _store_md_files():
        seen[p.stem] = seen.get(p.stem, 0) + 1
    return frozenset(s for s, n in seen.items() if n > 1)


def is_person(page: "Page") -> bool:
    return PERSON_TAG in (page.fields.get("tags") or [])


def days_since(iso: str) -> int | None:
    if not iso or not is_valid_date(str(iso)):
        return None
    return (datetime.date.today() - datetime.date.fromisoformat(str(iso))).days


def resolve_page(ref: str) -> Path:
    """Resolve a page by slug, relative path, or absolute path. Files only —
    a directory is never a page (and half the verbs would corrupt one)."""
    p = Path(ref)
    if p.is_absolute() and p.is_file():
        return p
    cand = brain_dir() / ref
    if cand.is_file():
        return cand
    if not ref.endswith(".md"):
        cand = brain_dir() / (ref + ".md")
        if cand.is_file():
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
# Links — the store's link model
#
# Internal vs external is the load-bearing distinction:
#   internal — [[wikilinks]]: bare slug (resolved store-wide by filename) or
#              store-relative path ([[resources/scripts/deploy]]). The one
#              sanctioned internal form, therefore checkable and checked: a
#              broken or ambiguous one is an ERROR (gate-blocking via check).
#   external — anything with a scheme (https://…, mailto:, dstask:6, …).
#              Never resolved, never rewritten, never an error.
# A relative markdown path ([text](../repo/doc.md)) is neither: it silently
# breaks when either side moves and the linter can't vouch for it. Always a
# WARNING — make it a [[wikilink]] (internal) or a full URL (external).
# --------------------------------------------------------------------------

# Wikilink target; the anchor (#…) and label (|…) are consumed but not captured.
WIKILINK_RE = re.compile(r"\[\[([^\]|\n#]+)(?:#[^\]|\n]*)?(?:\|[^\]\n]*)?\]\]")
# Markdown link target; (?<!!) skips images.
MD_LINK_RE = re.compile(r"(?<!!)\[[^\]\n]*\]\(<?([^)\s>]+)>?(?:\s+\"[^\"]*\")?\)")
SCHEME_RE = re.compile(r"^[A-Za-z][A-Za-z0-9+.-]*:")

# Sources the linter never reads: the manual and README carry intentional
# example links ([[page]], [[hub]]); log*.md is append-only history whose links
# may legitimately outlive their targets; raw/ is immutable by definition.
_LINT_EXEMPT_FILES = {"CLAUDE.md", "README.md", "log.md"}
_LINT_EXEMPT_DIRS = ("raw", "log-archive")


def _verbatim_spans(text: str) -> list:
    """(start, end) spans of code fences, HTML comments and inline code — the
    regions that are never links. The linter and mv's rewriter share this, so
    a quoted example neither lints nor gets rewritten. Fences follow
    CommonMark: ``` or ~~~, closer same char and at least as long with nothing
    after it, an unclosed fence runs to EOF."""
    spans = []
    pos, fence, fence_start = 0, None, 0
    for line in text.split("\n"):
        m = re.match(r" {0,3}(`{3,}|~{3,})", line)
        if fence is None:
            if m:
                fence = (m.group(1)[0], len(m.group(1)))
                fence_start = pos
        elif m and m.group(1)[0] == fence[0] and len(m.group(1)) >= fence[1] \
                and not line[m.end():].strip():
            spans.append((fence_start, pos + len(line)))
            fence = None
        pos += len(line) + 1
    if fence is not None:
        spans.append((fence_start, len(text)))

    def outside(i):
        return not any(s <= i < e for s, e in spans)

    for pat, flags in ((r"<!--.*?-->", re.S), (r"`[^`\n]*`", 0)):
        for m in re.finditer(pat, text, flags=flags):
            if outside(m.start()):
                spans.append(m.span())
    return sorted(spans)


def _lintable(text: str) -> str:
    """Body text with the verbatim regions blanked (newlines kept, so nothing
    shifts): an example `[[link]]` in code or a comment never counts."""
    out = list(text)
    for s, e in _verbatim_spans(text):
        for i in range(s, e):
            if out[i] != "\n":
                out[i] = " "
    return "".join(out)


def _sub_outside_verbatim(pat, repl: str, text: str) -> tuple:
    """pat.subn over text, skipping the verbatim regions — returns
    (new_text, count). What the linter promises isn't a link, mv won't touch."""
    out, n, last = [], 0, 0
    for s, e in _verbatim_spans(text):
        s = max(s, last)
        if e <= last:
            continue
        seg, k = pat.subn(repl, text[last:s])
        out.append(seg)
        n += k
        out.append(text[s:e])
        last = e
    seg, k = pat.subn(repl, text[last:])
    out.append(seg)
    n += k
    return "".join(out), n


def _page_wiki_targets(page: Page) -> set:
    """Every wikilink target a page carries: `parent`, `links` items, body."""
    parent = str(page.fields.get("parent") or "").strip()
    text = parent + "\n"
    text += "\n".join(str(x) for x in (page.fields.get("links") or []))
    text += "\n" + _lintable(page.body)
    targets = {t for m in WIKILINK_RE.finditer(text) if (t := m.group(1).strip())}
    # A hand-written bare `parent: hub` (no brackets) is still a reference —
    # reindex honours it for nesting, so the gate must see it too. The writers
    # and normalize wrap it in [[ ]]; this covers a page they haven't touched.
    if parent and "[[" not in parent:
        targets.add(parent)
    return targets


def _store_md_files() -> list:
    """Every markdown file in the store — the wikilink resolution universe.
    Hidden directories are out: .git, .obsidian, and Obsidian's .trash (a
    deleted page must not keep satisfying the linter from the trash)."""
    root = brain_dir()
    return [p for p in root.rglob("*.md")
            if p.is_file()
            and not any(part.startswith(".")
                        for part in p.relative_to(root).parts[:-1])]


def _lint_sources() -> list:
    """The files whose outgoing links are linted: all pages, plus index.md."""
    sources = all_pages()
    index = brain_dir() / "index.md"
    return sources + [index] if index.exists() else sources


def _staged_universe() -> list | None:
    """Store-relative .md paths of the tree a pre-commit run is about to
    record: the git index — staged additions in, untracked drafts out. A link
    satisfied only by an uncommitted file must fail the gate, or the commit
    ships a broken link to every other machine. None on git trouble (caller
    falls back to the on-disk universe)."""
    try:
        out = subprocess.run(
            ["git", "-C", str(brain_dir()), "ls-files", "--cached", "--", "*.md"],
            capture_output=True, text=True, check=True).stdout
    except (subprocess.CalledProcessError, FileNotFoundError, OSError):
        return None
    return [ln for ln in out.splitlines() if ln]


def _link_lint(universe: list | None = None) -> tuple:
    """(errors, warnings) across the store. Deterministic and whole-store:
    inbound links break when a *different* file is deleted or renamed, so
    linting a subset can never vouch for anything. `universe` overrides what
    counts as existing (store-relative paths) — the gate passes the git index."""
    if universe is None:
        universe = [rel(p) for p in _store_md_files()]
    stems: dict = {}
    path_refs = set()
    for r in universe:
        if not r.endswith(".md"):
            continue
        path_refs.add(r[: -len(".md")])
        stems.setdefault(Path(r).stem, []).append(r)

    errors, warnings = [], []
    for path in _lint_sources():
        r = rel(path)
        if r in _LINT_EXEMPT_FILES or r.startswith(tuple(d + "/" for d in _LINT_EXEMPT_DIRS)):
            continue
        try:
            page = parse_page(path)
        except (OSError, UnicodeDecodeError):
            continue  # health/check already surface unreadable pages
        for target in sorted(_page_wiki_targets(page)):
            if "/" in target:
                if target not in path_refs:
                    errors.append(f"{r}: broken link [[{target}]] — no such page")
            else:
                hits = stems.get(target, [])
                if not hits:
                    errors.append(f"{r}: broken link [[{target}]] — no such page")
                elif len(hits) > 1:
                    errors.append(f"{r}: ambiguous link [[{target}]] — matches "
                                  f"{', '.join(sorted(hits))}; use the path form")
        for m in MD_LINK_RE.finditer(_lintable(page.body)):
            target = m.group(1)
            if SCHEME_RE.match(target) or target.startswith("#"):
                continue  # external / in-page anchor — not ours to check
            warnings.append(
                f"{r}: relative markdown link ({target}) — internal links are "
                f"[[wikilinks]], external ones full URLs; a relative path "
                f"breaks silently when either side moves")
    return errors, warnings


def cmd_links(args) -> int:
    if args.to:
        # Backlinks: who references this page. Powers the people directory's
        # generated column too (reindex) — this is the on-demand form.
        path = resolve_page(args.to)
        stem, ref = path.stem, rel(path)[: -len(".md")]
        hits = []
        for p in all_pages():
            if p.resolve() == path.resolve():
                continue
            try:
                pg = parse_page(p)
            except (OSError, UnicodeDecodeError):
                continue  # health/check already surface unreadable pages
            if {stem, ref} & _page_wiki_targets(pg):
                hits.append(page_ref(pg))
        print("\n".join(sorted(hits)) or f"(no pages link to {stem})")
        return 0

    errors, warnings = _link_lint()
    if args.json:
        import json  # noqa: PLC0415 — only the JSON paths pay the import
        print(json.dumps({"errors": errors, "warnings": warnings}, indent=2))
    else:
        for w in warnings:
            print(f"warning: {w}", file=sys.stderr)
        for e in errors:
            print(f"error: {e}", file=sys.stderr)
        if errors:
            print(f"brain links: {len(errors)} broken/ambiguous internal link(s)",
                  file=sys.stderr)
        elif not warnings:
            print("links ok")
    return 1 if errors or (args.strict and warnings) else 0


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
    if f.get("kind") == "goal" and f.get("status") in LIVE_STATUSES and not f.get("due"):
        warnings.append(f"{r}: live goal with no 'due' — a goal is a quarterly "
                        f"outcome; due is the quarter end")
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
    synced = store_version() == TEMPLATE_VERSION
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
        # A kind the schema no longer knows is exactly what a pending
        # migration re-files. Until the store is stamped current it demotes
        # to a warning — otherwise sync's own mechanical commit could never
        # pass the gate. This is now the *only* deferral: link errors used to
        # take the same stance, but every store is link-clean, so they gate
        # hard in the rebuild→sync window too.
        if not synced:
            stale_kind = [e for e in errs if ": kind '" in e]
            if stale_kind:
                errs = [e for e in errs if e not in stale_kind]
                warns = warns + [e + "  [deferred until the store is synced]"
                                 for e in stale_kind]
        all_errors += errs
        all_warnings += warns

    # Link integrity rides the same gate. Always whole-store (even --staged):
    # a staged deletion or rename breaks OTHER files' inbound links, so a
    # staged-only pass could never vouch for anything. Skipped only when the
    # caller asked about specific paths. Broken/ambiguous wikilinks are
    # errors; relative markdown paths warn — see the link model in `links`.
    # Under --staged, links must resolve against the git index, not the
    # worktree: an untracked draft satisfying a link would commit a broken
    # store and auto-push it to every other machine.
    if not args.paths:
        lerrs, lwarns = _link_lint(_staged_universe() if args.staged else None)
        all_errors += lerrs
        all_warnings += lwarns

    for w in all_warnings:
        print(f"warning: {w}", file=sys.stderr)
    for e in all_errors:
        print(f"error: {e}", file=sys.stderr)

    # Version drift is a note, never an error: a rebuild ships a new CLI before
    # `brain sync` runs, and the pre-commit gate must not block in that window.
    sv = store_version()
    if sv != TEMPLATE_VERSION:
        seen = "unstamped" if sv is None else f"v{sv}"
        print(f"note: store is {seen}, CLI expects v{TEMPLATE_VERSION} — "
              f"run `brain sync`", file=sys.stderr)

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
# Two weeks of no movement across a goal AND every live child stalls it — the
# week-plan threshold: one touched page anywhere in the tree clears the flag.
GOAL_STALL_DAYS = 14

SECTIONS = [
    ("Goals (this quarter)", ["goals"], ["idea", "planned", "active", "blocked"]),
    ("Areas (ongoing)", ["areas"], None),
    ("Projects (end-stated)", ["projects"], ["idea", "planned", "active", "blocked"]),
    ("Maps of Content", ["mocs"], None),
    ("Resources", ["resources"], None),
    # archive/ pages belong here whatever their status says (`mv` warns on the
    # mismatch; a page that is invisible in every section would be worse).
    ("Archive", ["goals", "projects", "areas", "mocs", "resources", "archive"],
     ["done", "archived"]),
]


def _parent_slug(page: Page) -> str:
    """The bare slug of a page's `parent` ref, whatever form it carries:
    "[[hub]]", "[[bucket/dir/hub]]" (mv's rewrite), padded, or bare."""
    v = str(page.fields.get("parent") or "").strip().strip("[]").strip()
    return v.split("#")[0].split("|")[0].rsplit("/", 1)[-1].strip()


def _index_line(page: Page, indent: int = 0,
                ambiguous: frozenset = frozenset()) -> str:
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
    return f"{pad}- [[{page_ref(page, ambiguous)}]] — `{status}`{mark} — {summary}{stale}"


def cmd_reindex(args) -> int:
    index = brain_dir() / "index.md"
    pages_by_bucket = {b: [parse_page(p) for p in bucket_pages(b)] for b in
                       REQUIRED_BUCKETS + OPTIONAL_BUCKETS}
    missing_summary = []

    def in_section(page, statuses, bucket):
        if not page.has_fm:
            return False
        # Person pages are cataloged by the people MOC, so the index stays one
        # line long whether you know 2 people or 200. They remain fully in the
        # system — `check` validates them, `q --tag person` finds them.
        if is_person(page):
            return False
        st = page.fields.get("status", "")
        if statuses is not None:
            # The archive/ bucket only appears in the Archive section's bucket
            # list, and a page filed there is archived by location.
            return bucket == "archive" or st in statuses
        return st not in ("done", "archived")  # non-archive sections exclude done/archived

    dup = _dup_stems()
    blocks = []
    for title, buckets, statuses in SECTIONS:
        lines = [f"## {title}", ""]
        # Candidate pages for this section, and the set of slugs present, so a
        # child whose parent is filtered out still appears (as a top-level line).
        candidates = [pg for b in buckets for pg in pages_by_bucket.get(b, [])
                      if in_section(pg, statuses, b)]
        present = {pg.slug for pg in candidates}
        for page in candidates:
            if not page.fields.get("summary"):
                missing_summary.append(page.slug)
        emitted = 0
        for page in candidates:
            parent = _parent_slug(page)
            if parent and parent in present:
                continue  # emitted under its parent below
            lines.append(_index_line(page, ambiguous=dup))
            emitted += 1
            for child in candidates:
                if _parent_slug(child) == page.slug:
                    lines.append(_index_line(child, indent=1, ambiguous=dup))
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

    all_parsed = [pg for pages in pages_by_bucket.values() for pg in pages]
    people = _people_render(all_parsed, dup)

    if args.check:
        stale = []
        if not (index.exists() and index.read_text(encoding="utf-8") == new):
            stale.append("index.md")
        if people and people[1] != people[2]:
            stale.append("mocs/people.md")
        if not stale:
            print("index.md is up to date")
            return 0
        print(f"brain reindex --check: {', '.join(stale)} stale (run `brain reindex`)",
              file=sys.stderr)
        return 1

    index.write_text(new, encoding="utf-8")
    print(f"reindexed {rel(index)}")
    if people and people[1] != people[2]:
        people[0].write_text(people[1], encoding="utf-8")
        print("refreshed 'Where they appear' in mocs/people.md")
    if missing_summary:
        print(f"note: {len(missing_summary)} page(s) have no 'summary' "
              f"(used title as fallback): {', '.join(sorted(set(missing_summary)))}",
              file=sys.stderr)
    return 0


# --------------------------------------------------------------------------
# people.md — the generated half of the directory
#
# The table itself is judgment (who's listed, their role, how to reach them);
# the "Where they appear" column is a pure projection of the link graph, and
# hand-maintained reverse indexes rot. `reindex` regenerates that one column
# for every row whose first cell is a [[person-page]] link — a row for someone
# without a page keeps whatever is typed (there is no page to compute from).
# --------------------------------------------------------------------------

PEOPLE_COL_RE = re.compile(r"where\s+they\s+appear", re.I)
_TABLE_SEP_RE = re.compile(r"^[\s|:-]+$")


def _table_cells(row: str) -> list:
    """Split a table row on pipes, tolerating pipes inside [[wiki|links]] and
    markdown's escaped pipe (\\|) — both must round-trip through the join."""
    masked = row.replace("\\|", "\x01")
    masked = re.sub(r"\[\[[^\]\n]*\]\]",
                    lambda m: m.group(0).replace("|", "\x00"), masked)
    return [c.replace("\x00", "|").replace("\x01", "\\|")
            for c in masked.split("|")]


def _people_render(pages: list, ambiguous: frozenset = frozenset()) -> tuple | None:
    """(path, new_text, old_text) for mocs/people.md with the 'Where they
    appear' column recomputed — in EVERY table that carries one, since the
    manual sanctions grouping people into several tables. None when there is
    nothing to do (no people.md, no such column, or an unreadable file)."""
    ppath = brain_dir() / "mocs" / "people.md"
    try:
        old = ppath.read_text(encoding="utf-8")
    except (FileNotFoundError, UnicodeDecodeError, OSError):
        return None
    lines = old.split("\n")

    # Person pages keyed by path ref; a bare row link resolves only when its
    # stem is unique among them (same rule the linter applies store-wide).
    persons: dict = {}
    by_stem: dict = {}
    for p in pages:
        if is_person(p):
            ref = rel(p.path)[: -len(".md")]
            persons[ref] = p
            by_stem.setdefault(p.slug, []).append(ref)
    sources = [q for q in pages if rel(q.path) != "mocs/people.md"]
    targets = [(q, _page_wiki_targets(q)) for q in sources]
    appearances = {
        ref: sorted(page_ref(q, ambiguous) for q, ts in targets
                    if q.path != p.path and {p.slug, ref} & ts)
        for ref, p in persons.items()}

    found = False
    col_i = None  # the appearances column of the table we're inside, if any
    for i, ln in enumerate(lines):
        if not ln.lstrip().startswith("|"):
            col_i = None  # the current table (if any) ended
            continue
        cells = _table_cells(ln)
        if col_i is None:
            for j, cell in enumerate(cells):
                if PEOPLE_COL_RE.search(cell):
                    col_i, found = j, True
                    break
            continue  # a header, or a row of a table without the column
        if _TABLE_SEP_RE.match(ln) or col_i >= len(cells) or len(cells) < 2:
            continue
        m = WIKILINK_RE.search(cells[1])  # cells[0] is before the leading |
        if not m:
            continue  # a row without a person page stays hand-maintained
        target = m.group(1).strip()
        if "/" in target:
            ref = target if target in persons else None
        else:
            candidates = by_stem.get(target, [])
            ref = candidates[0] if len(candidates) == 1 else None
        if ref is None:
            continue
        refs = appearances[ref]
        cells[col_i] = " " + (", ".join(f"[[{r}]]" for r in refs) or "—") + " "
        lines[i] = "|".join(cells)
    if not found:
        return None
    return ppath, "\n".join(lines), old


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

_GOAL_BODY = """
<!-- 2-4 lines: the quarterly outcome, and why it earns one of the 3-5 slots. REWRITE. -->
<!-- TODO: fill -->

**Next:** <!-- one concrete action; mirror it into the `next` field -->

## Why this goal

<!-- The rationale, written once so it isn't re-litigated. Touch only if the premise changes. -->

## Success criteria

<!-- REWRITE IN PLACE. Falsifiable — each line checkable true/false at quarter
     end: "shipped X", "p95 under Y", not "made progress on X". -->

## Milestones

<!-- APPEND, then check off. `- [ ]` checkbox lines: review counts checked vs
     total from here at read time — never store a percentage anywhere. -->

## Decisions

<!-- APPEND. `### <decision> — <date>`, each with why + consequences.
     Superseded ones stay, struck through, pointing at what replaced them. -->

## Open

<!-- Questions, risks, blockers. Delete lines as they close — this section should SHRINK. -->
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

<!-- One line per member: `- [[page]] — <its role in THIS map>` (index.md
     already carries the summary; the role is what this map adds). A real
     [[link]] only — the gate rejects links to pages that don't exist. -->

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
    "goal": _GOAL_BODY,
    "project": _PROJECT_BODY,
    "initiative": _PROJECT_BODY,
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
    # A slug may carry subdirectory components (`new resource scripts/deploy`),
    # matching what the store already grows organically (nested resources are
    # discovered by rglob, validated, and indexed by path) — without this, the
    # constrained writer couldn't create the very pages the gate covers.
    if not args.slug or Path(args.slug).is_absolute():
        die(f"invalid slug '{args.slug}'")
    slug = args.slug.strip("/")
    parts = Path(slug).parts
    # Component whitelist rather than a ".."-blacklist: pathlib normalises "."
    # away entirely (Path(".").parts == ()), and backslashes, spaces or hidden
    # files should never become page filenames either.
    if not parts or not all(re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*", s) for s in parts):
        die(f"invalid slug '{args.slug}'")
    path = brain_dir() / bucket / f"{slug}.md"
    if path.exists():
        die(f"page already exists: {path.relative_to(brain_dir())}")
    # Filename stems are store-unique — same invariant mv enforces on rename.
    # A duplicate would make bare [[slug]] links ambiguous, and reindex would
    # then have to emit path-form links for both forever.
    if brain_dir().is_dir():
        clash = sorted(rel(p) for p in _store_md_files() if p.stem == parts[-1])
        if clash:
            die(f"a page named '{parts[-1]}' already exists "
                f"({', '.join(clash)}) — bare [[{parts[-1]}]] links would be "
                f"ambiguous; pick another slug, or `brain mv` the old page first")
    path.parent.mkdir(parents=True, exist_ok=True)
    title = args.title or parts[-1].replace("-", " ").title()
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
            if opt == "parent" and "[[" not in v:
                v = f"[[{v}]]"  # a parent is a reference — the gate must see it
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
        previous = page.fields.get("status")
        page.fields["status"] = value
        # Stamp only when the status actually *crosses* into active/done. Setting
        # a status to the value the page already carries is a no-op, not a
        # lifecycle event — without this guard, re-setting `status active` on a
        # long-running page that has no `started` (an area or moc, which never
        # gets one) invents a start date of today.
        if value != previous:
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
        if field == "parent" and value and "[[" not in value:
            value = f"[[{value}]]"  # a parent is a reference — gate-visible
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
    errs, _ = validate_page(page, required_fm=True)
    if errs:
        # The problems necessarily pre-date this command (done only touches
        # status/finished/updated) — point at the remedy, not just the refusal.
        die("refusing to write invalid page — these problems pre-date `done`; "
            "fix the listed fields (or run /brain --sync) and retry:\n  "
            + "\n  ".join(errs))
    write_page(page)
    print(f"{rel(path)}: done ({page.fields['finished']})")
    return 0


def _normalize_paths(paths: list) -> list:
    """The repair-on-drift pass; returns the store-relative paths it changed."""
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
        # A bare `parent: hub` predating the writers' wrapping: make it the
        # wikilink the gate and mv both understand.
        pv = str(page.fields.get("parent") or "").strip()
        if pv and "[[" not in pv:
            page.fields["parent"] = f"[[{pv}]]"
        # Freshly-seeded scaffold pages carry the sentinel date; stamp them for real.
        for df in ("created", "updated"):
            if page.fields.get(df) == SCAFFOLD_DATE:
                page.fields[df] = today()
        after = serialize(page)
        if before != after:
            write_page(page)
            changed.append(rel(path))
    return changed


def cmd_normalize(args) -> int:
    paths = ([Path(p).resolve() for p in args.paths] if args.paths else all_pages())
    changed = _normalize_paths(paths)
    for c in changed:
        print(f"normalized {c}")
    if not changed:
        print("nothing to normalize")
    return 0


# --------------------------------------------------------------------------
# mv — move/rename a page, rewriting [[references]] across the store
#
# The mechanical half of the archive lifecycle (and of any rename): without
# it, moving a page silently breaks every path-qualified [[bucket/slug]] link
# pointing at it, and renaming breaks the bare ones too. Judgment stays with
# the caller: mv never changes status/kind — it warns on the mismatch instead.
# --------------------------------------------------------------------------

def cmd_mv(args) -> int:
    buckets = REQUIRED_BUCKETS + OPTIONAL_BUCKETS
    src = resolve_page(args.page)
    srel = rel(src)
    if len(Path(srel).parts) < 2 or Path(srel).parts[0] not in buckets:
        die(f"'{srel}' is not a bucket page — only pages under "
            f"{'/'.join(sorted(buckets))} can move (index/log/raw stay put)")

    dest = args.dest.strip("/")
    if dest.endswith(".md"):
        dest = dest[: -len(".md")]
    dparts = Path(dest).parts
    # Same component whitelist as `new` — mv must not mint paths new couldn't.
    if Path(args.dest).is_absolute() or len(dparts) < 2 or \
            not all(re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*", s) for s in dparts):
        die(f"invalid destination '{args.dest}' — use <bucket>/<slug>, "
            f"e.g. archive/{src.stem}")
    if dparts[0] not in buckets:
        die(f"destination bucket '{dparts[0]}' must be one of {sorted(buckets)}")
    dst = brain_dir() / (dest + ".md")
    if dst.exists():
        die(f"destination already exists: {dest}.md")

    old_slug, new_slug = src.stem, dst.stem
    old_ref = srel[: -len(".md")]
    if new_slug != old_slug:
        clash = [rel(p) for p in _store_md_files()
                 if p.stem == new_slug and p.resolve() != src.resolve()]
        if clash:
            die(f"renaming to '{new_slug}' would make bare [[{new_slug}]] links "
                f"ambiguous with {', '.join(sorted(clash))} — pick another slug")
        # And the old bare form must be unambiguous too, or the rewrite would
        # steal links that mean the OTHER same-stem page — silently, since
        # retargeting also removes the lint error that would have flagged it.
        shared = [rel(p) for p in _store_md_files()
                  if p.stem == old_slug and p.resolve() != src.resolve()]
        if shared:
            die(f"bare [[{old_slug}]] links are ambiguous with "
                f"{', '.join(sorted(shared))} — fix them to the path form first "
                f"(brain links shows them)")

    dst.parent.mkdir(parents=True, exist_ok=True)
    src.rename(dst)
    # Bare slug at bucket top level, path otherwise — path also when the stem
    # is shared with another file, so the rewrite never mints an ambiguous ref.
    new_ref = page_ref(parse_page(dst), _dup_stems())

    # Reference rewrite: textual and store-wide, including log*.md — mechanically
    # retargeting a link preserves what an entry says, the same way rotate-log
    # moves entries verbatim. raw/ is immutable and the manual/README carry
    # example links, so those never change; code fences, comments and inline
    # code are skipped (what the linter says isn't a link, mv must not touch).
    # Bare [[slug]] links resolve by filename wherever the page lives, so they
    # are rewritten only on a rename. Padding ([[ slug ]]) is tolerated the
    # same way the linter tolerates it, and normalized away by the rewrite.
    pats = [(re.compile(r"\[\[[ \t]*" + re.escape(old_ref) + r"[ \t]*([\]|#])"),
             f"[[{new_ref}\\1")]
    if new_slug != old_slug:
        pats.append((re.compile(r"\[\[[ \t]*" + re.escape(old_slug) + r"[ \t]*([\]|#])"),
                     f"[[{new_ref}\\1"))
    rewritten, total = [], 0
    for f in _store_md_files():
        fr = rel(f)
        if fr in ("CLAUDE.md", "README.md") or fr.startswith("raw/"):
            continue
        try:
            text = f.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue
        n = 0
        for pat, repl in pats:
            text, k = _sub_outside_verbatim(pat, repl, text)
            n += k
        if n:
            f.write_text(text, encoding="utf-8")
            rewritten.append(fr)
            total += n

    moved = parse_page(dst)
    if moved.has_fm:
        moved.fields["updated"] = today()
        write_page(moved)
        fld = moved.fields
        if dparts[0] == "archive" and fld.get("status") not in ("done", "archived"):
            print(f"note: status is '{fld.get('status')}' — archive/ holds finished "
                  f"work; brain set {new_ref} status archived", file=sys.stderr)
        elif dparts[0] != "archive" and fld.get("kind") \
                and KIND_BUCKET.get(fld["kind"]) != dparts[0]:
            print(f"note: kind '{fld['kind']}' pages normally live in "
                  f"{KIND_BUCKET.get(fld['kind'])}/ — moved anyway", file=sys.stderr)

    print(f"moved {srel} → {dest}.md"
          + (f" ({total} link(s) rewritten in {len(rewritten)} file(s): "
             f"{', '.join(rewritten)})" if rewritten else " (no links to rewrite)"))
    cmd_reindex(argparse.Namespace(check=False))
    return 0


# --------------------------------------------------------------------------
# review — the read-only briefing
#
# Writes NOTHING. It is the generated half of a "now" page: the goals rollup,
# what's in focus, what's gone quiet, what's blocked or overdue, what the
# clock says. The judgment half (why this ordering, what you're deliberately
# not doing) stays in mocs/now.md, which no command may rewrite.
# --------------------------------------------------------------------------

OVERSIZE_LINES = 300      # a page past this wants splitting
NOW_MAX_LINES = 60        # a `now` page with more *content* lines than this is
                          # holding generated content (see _now_content_lines:
                          # frontmatter, comments and blanks don't count)


def _read_focus() -> str | None:
    index = brain_dir() / "index.md"
    try:
        text = index.read_text(encoding="utf-8")
    except (FileNotFoundError, UnicodeDecodeError, OSError):
        return None
    m = re.search(r"^\*\*▶ Current focus:\*\*\s*(.+)$", text, re.M)
    return m.group(1).strip() if m else None


def _recent_log(limit: int) -> list:
    log = brain_dir() / "log.md"
    try:
        text = log.read_text(encoding="utf-8")
    except (FileNotFoundError, UnicodeDecodeError, OSError):
        return []
    return [ln for ln in text.splitlines() if ln.startswith("- ")][:limit]


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
    try:
        text = inbox.read_text(encoding="utf-8")
    except (FileNotFoundError, UnicodeDecodeError, OSError):
        return 0
    return sum(1 for ln in text.splitlines() if ln.startswith("- "))


def _page_lines(page: Page) -> int:
    try:
        return len(page.path.read_text(encoding="utf-8").splitlines())
    except (OSError, UnicodeDecodeError):
        return 0


def _quiet_days(p: Page) -> int | None:
    # `verified` is the real signal — when the page's claims were last
    # checked against reality. `updated` moves on a typo fix, so it is only
    # the fallback for pages that have never been verified.
    return days_since(p.fields.get("verified") or p.fields.get("updated") or "")


_CHECKBOX_RE = re.compile(r"^\s*[-*]\s+\[([ xX])\]", re.M)


def _milestones(page: Page) -> tuple | None:
    """(done, total) over the checkbox lines under the body's '## Milestones'
    heading, or None when the section or its checkboxes don't exist — so
    callers omit the figure rather than print 0/0. Counted at read time and
    never written back: a stored percentage is a second copy that rots.
    Verbatim regions are blanked first, so an example checkbox in a comment
    or code fence is not a milestone."""
    body = _lintable(page.body)
    m = re.search(r"^##\s+Milestones\s*$", body, re.M)
    if m is None:
        return None
    section = body[m.end():]
    nxt = re.search(r"^#{1,2}\s", section, re.M)  # ### subsections stay inside
    if nxt:
        section = section[: nxt.start()]
    boxes = _CHECKBOX_RE.findall(section)
    if not boxes:
        return None
    return sum(1 for b in boxes if b.strip()), len(boxes)


def _goal_parent_match(child, goal) -> bool:
    """A bare `parent` ref matches this goal by stem, but a path-form ref
    (mv's rewrite) must match the goal's real path: stems collide across
    buckets, and a goals/x page must not claim work pointed at areas/x."""
    v = str(child.fields.get("parent") or "").strip().strip("[]").strip()
    v = v.split("#")[0].split("|")[0].strip()
    if "/" in v:
        return v.removesuffix(".md") == rel(goal.path).removesuffix(".md")
    return v == goal.slug


def _goal_rollup(pages: list) -> list:
    """The goals layer, derived entirely at read time. Per live goal: its live
    children (WORK_KINDS pages whose `parent` names it), milestone counts and
    the two week-plan flags — ORPHANED (no live child to move it) and STALLED
    (the goal and every live child quiet beyond GOAL_STALL_DAYS; one touched
    page anywhere in the tree clears it)."""
    live = [p for p in pages if p.fields.get("status") in LIVE_STATUSES]
    out = []
    for g in (p for p in live if p.fields.get("kind") == "goal"):
        children = [c for c in live
                    if c is not g and c.fields.get("kind") in WORK_KINDS
                    and _goal_parent_match(c, g)]
        # A page without a usable date can't vouch for movement, so it counts
        # as untouched rather than shielding the goal from the flag.
        stalled = all((q := _quiet_days(p)) is None or q > GOAL_STALL_DAYS
                      for p in [g, *children])
        out.append({
            "page": g, "children": children, "quiet": _quiet_days(g),
            "milestones": _milestones(g),
            "orphaned": not children, "stalled": stalled,
        })
    return out


def _goal_json(g: dict) -> dict:
    ms = g["milestones"]
    return dict(
        page_json(g["page"]), quiet_days=g["quiet"],
        milestones=None if ms is None else {"done": ms[0], "total": ms[1]},
        orphaned=g["orphaned"], stalled=g["stalled"],
        children=[dict(page_json(c), quiet_days=_quiet_days(c))
                  for c in g["children"]])


def _collect(stale_days: int) -> dict:
    # One unreadable file (a non-UTF-8 export dropped into resources/, say)
    # must not take review/health down with a traceback: health runs
    # unattended, and a crash there silently blanks ALL vitals. The gate
    # (check) still hard-fails on such files; here they become a signal.
    pages, unreadable = [], []
    for path in all_pages():
        try:
            pg = parse_page(path)
        except (UnicodeDecodeError, OSError):
            unreadable.append(rel(path))
            continue
        if pg.has_fm:
            pages.append(pg)
    live = [p for p in pages if is_live_work(p)]
    now = today()

    return {
        "focus_pointer": _read_focus(),
        "goals": _goal_rollup(pages),
        "focus": [p for p in live if p.fields.get("attention") == "focus"],
        "working": [p for p in live if not p.fields.get("attention")],
        "tracking": [p for p in live if p.fields.get("attention") == "tracking"],
        "blocked": [p for p in pages if p.fields.get("status") == "blocked"],
        "overdue": [p for p in pages
                    if (d := p.fields.get("due")) and is_valid_date(str(d))
                    and d < now and p.fields.get("status") not in ("done", "archived")],
        "quiet": sorted(((p, q) for p in live if (q := _quiet_days(p)) is not None
                         and q > stale_days), key=lambda t: -t[1]),
        "unverified": [p for p in live if not p.fields.get("verified")],
        "oversized": sorted(((p, n) for p in pages
                             if (n := _page_lines(p)) > OVERSIZE_LINES),
                            key=lambda t: -t[1]),
        "unreadable": unreadable,
        "pages": pages,
    }


_HTML_COMMENT_RE = re.compile(r"<!--.*?-->", re.DOTALL)


def _now_content_lines(body: str) -> int:
    """Count what a `now` page actually says, not how long its file is.

    Measuring the whole file charged the template's own scaffold against the
    budget: frontmatter, the `<!-- REWRITE … -->` instructions and markdown
    spacing come to ~36 lines before a word of judgment is written, so a page
    holding no generated content at all could still trip NOW_MAX_LINES. The
    threshold is about content volume, so only content is counted — frontmatter
    never reaches here (`Page.body` starts after the closing `---`), and HTML
    comments and blank lines are dropped.
    """
    stripped = _HTML_COMMENT_RE.sub("", body)
    unterminated = stripped.find("<!--")   # malformed comment: ignore the rest
    if unterminated != -1:
        stripped = stripped[:unterminated]
    return sum(1 for line in stripped.splitlines() if line.strip())


NOW_STALE_DAYS = 14       # `now` judgment this far behind the log has been overtaken


def _now_signals() -> tuple[int, int | None] | None:
    """`(content lines, days behind the newest log entry)` for `mocs/now.md`.

    None when the page is missing or unreadable; `behind` is None when it can't
    be derived. Both detector arms read this, so the thresholds live in one
    place and `review` and `health` can never disagree about which one fired.
    """
    now_page = brain_dir() / "mocs" / "now.md"
    if not now_page.exists():
        return None
    try:
        page = parse_page(now_page)
    except (UnicodeDecodeError, OSError):
        return None
    upd = page.fields.get("updated") if page.has_fm else None
    dates = _log_dates()
    behind = None
    if upd and dates and is_valid_date(str(upd)) and is_valid_date(dates[0]):
        behind = (datetime.date.fromisoformat(dates[0])
                  - datetime.date.fromisoformat(str(upd))).days
    return _now_content_lines(page.body), behind


def _now_faults() -> tuple[int, int | None, bool, bool] | None:
    """The signals plus which arm each trips. None when the page is fine.

    The two faults are independent and unrelated: a page can be too long, too
    stale, or both, and each wants different advice — trimming a page that is
    merely stale is the wrong move.
    """
    signals = _now_signals()
    if signals is None:
        return None
    lines, behind = signals
    oversized = lines > NOW_MAX_LINES
    stale = behind is not None and behind > NOW_STALE_DAYS
    if not (oversized or stale):
        return None
    return lines, behind, oversized, stale


def _now_warning() -> str | None:
    """`review`'s detail block: what is wrong, and what to do about it."""
    faults = _now_faults()
    if faults is None:
        return None
    lines, behind, oversized, stale = faults
    head = f"now.md — {lines} lines of content"
    if stale:
        head += f", {behind}d behind the newest log entry"
    notes = []
    if oversized:
        notes.append("⚠ likely holds content `brain review` now generates; keep only "
                     "why this ordering and what you're deliberately not doing")
    if stale:
        notes.append("⚠ the work moved on without it — re-read it, rewrite the judgment "
                     "that changed, and delete what has been settled")
    return "\n".join([head] + [f"   {n}" for n in notes])


def _now_health() -> str | None:
    """`health`'s one-liner, naming the fault that actually fired."""
    faults = _now_faults()
    if faults is None:
        return None
    _, behind, oversized, stale = faults
    if oversized and stale:
        return f"now.md needs trimming and is {behind}d stale (see brain review)"
    if oversized:
        return "now.md needs trimming (see brain review)"
    return f"now.md is {behind}d behind the log (see brain review)"


def _fmt(p: Page, width: int) -> str:
    f = p.fields
    bits = f"{page_ref(p):{width}} {f.get('status',''):8}"
    q = _quiet_days(p)
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


def _fmt_goal(g: dict, width: int) -> str:
    """One goal's rollup block: the goal line (flags ride it), its next move,
    then each live child one level deeper."""
    p = g["page"]
    f = p.fields
    bits = f"{page_ref(p):{width}} {f.get('status',''):8}"
    if f.get("attention"):
        bits += f" · `{f['attention']}`"
    if f.get("due"):
        bits += f" · due {f['due']}"
    q = g["quiet"]
    if q is not None:
        bits += f" · {'verified' if f.get('verified') else 'updated'} {q}d"
    if g["milestones"]:
        done, total = g["milestones"]
        bits += f" · milestones {done}/{total}"
    if g["orphaned"]:
        bits += "  ⚠ ORPHANED"
    if g["stalled"]:
        bits += "  ⚠ STALLED"
    lines = [bits.rstrip()]
    if f.get("next"):
        lines.append(f"{' ' * 4}→ {f['next']}")
    for c in g["children"]:
        cf = c.fields
        cq = _quiet_days(c)
        cage = f" {'verified' if cf.get('verified') else 'updated'} {cq}d" \
            if cq is not None else ""
        lines.append(f"    {page_ref(c):{width}} {cf.get('status',''):8}{cage}".rstrip())
    return "\n".join(lines)


def cmd_review(args) -> int:
    if args.since is not None:
        return _review_window(args)
    d = _collect(args.stale)
    if args.json:
        import json
        print(json.dumps({
            "date": today(),
            "focus_pointer": d["focus_pointer"],
            "goals": [_goal_json(g) for g in d["goals"]],
            **{k: [page_json(p) for p in d[k]]
               for k in ("focus", "working", "tracking", "blocked", "overdue",
                         "unverified")},
            "quiet": [dict(page_json(p), quiet_days=n) for p, n in d["quiet"]],
            "oversized": [dict(page_json(p), lines=n) for p, n in d["oversized"]],
            "unreadable": d["unreadable"],
            "dstask_open": len(_dstask_open()),
            "inbox_pending": _inbox_count(),
        }, indent=2))
        return 0

    refs = [page_ref(p) for p in d["pages"]] or [""]
    w = min(max(len(r) for r in refs), 34)
    out = [f"brain — {today()}"]
    if d["focus_pointer"]:
        out += ["", f"▶ Focus  {d['focus_pointer']}"]

    if d["goals"]:
        out += ["", f"Goals ({len(d['goals'])})"]
        out += [f"  {_fmt_goal(g, w)}" for g in d["goals"]]

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
    if d["unreadable"]:
        out += ["", f"Unreadable ({len(d['unreadable'])})",
                "  " + ", ".join(d["unreadable"])]

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


def _append_log_entry(message: str) -> str:
    """Prepend a dated entry (newest first), dating it from the system clock."""
    log = brain_dir() / "log.md"
    entry = f"- {today()} — {message}"
    if not log.exists():
        log.write_text(f"# Log\n\nAppend-only activity log. Newest first.\n\n{entry}\n",
                       encoding="utf-8")
        return entry
    lines = log.read_text(encoding="utf-8").splitlines()
    idx = next((i for i, ln in enumerate(lines) if ln.startswith("- ")), None)
    if idx is None:
        while lines and not lines[-1].strip():
            lines.pop()
        lines += ["", entry]
    else:
        lines.insert(idx, entry)  # newest first, above existing entries
    log.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return entry


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
    # The date comes from the system clock so it is never hand-typed (and thus
    # never inferred from the corpus).
    print(_append_log_entry(args.message))
    return 0


# --------------------------------------------------------------------------
# rotate-log — mechanical rotation of log.md's tail into log-archive/
#
# Pure mechanics, no judgment: entries move verbatim, newest-first order is
# preserved everywhere, and nothing is summarised — so the agent runs it the
# moment `health`/`review` flags the log as oversized, without asking.
# --------------------------------------------------------------------------

LOG_MAX_LINES = 400       # log.md past this wants rotating (mirrored in CLAUDE.md)
LOG_KEEP_ENTRIES = 150    # newest entries kept hot in log.md by rotate-log


def _log_entry_groups(lines: list) -> tuple:
    """Split log lines into (head, groups, tail). `head` is everything before
    the first dated entry; each group is one `- YYYY-MM-DD …` entry plus its
    continuation lines (blank or indented — they move with the entry so
    nothing is orphaned); `tail` starts at the first non-indented line that is
    not a dated entry (trailing free text someone appended), and stays in
    log.md rather than being mis-filed into an archive as a continuation."""
    first = next((i for i, ln in enumerate(lines)
                  if re.match(r"^- \d{4}-\d{2}-\d{2}", ln)), None)
    if first is None:
        return lines, [], []
    head, groups, cur, tail = lines[:first], [], [], []
    for idx in range(first, len(lines)):
        ln = lines[idx]
        if re.match(r"^- \d{4}-\d{2}-\d{2}", ln):
            if cur:
                groups.append(cur)
            cur = [ln]
        elif not ln.strip() or ln.startswith((" ", "\t")):
            cur.append(ln)
        else:
            tail = lines[idx:]
            break
    if cur:
        groups.append(cur)
    return head, groups, tail


def cmd_rotate_log(args) -> int:
    log = brain_dir() / "log.md"
    if not log.exists():
        print("no log.md")
        return 0
    lines = log.read_text(encoding="utf-8").splitlines()
    if len(lines) <= args.threshold and not args.force:
        print(f"log.md is {len(lines)} lines (<= {args.threshold}) — nothing to rotate")
        return 0
    head, groups, tail = _log_entry_groups(lines)
    hot, cold = groups[:args.keep], groups[args.keep:]  # newest-first: tail = oldest
    # health flags on LINES while we keep by ENTRIES; when entries run long
    # (continuation lines), shrink the hot window further until the log fits
    # the threshold — never below a small floor — so the health-flag →
    # rotate-log loop converges instead of nagging forever with a no-op remedy.
    floor = min(20, len(groups))
    while len(hot) > floor and \
            len(head) + len(tail) + sum(len(g) for g in hot) > args.threshold:
        cold.insert(0, hot.pop())
    if not cold:
        print(f"log.md has only {len(groups)} entries — nothing to rotate")
        return 0
    archive_dir = brain_dir() / "log-archive"
    archive_dir.mkdir(exist_ok=True)

    # The rotated tail goes to one file per year. Within a file newest stays
    # first, and entries from a later rotation are newer than anything already
    # archived for that year — so they are inserted above the existing entries.
    by_year: dict = {}
    for g in cold:
        by_year.setdefault(g[0][2:6], []).append(g)
    for year in sorted(by_year):
        f = archive_dir / f"{year}.md"
        moved = [ln for g in by_year[year] for ln in g]
        if f.exists():
            ohead, ogroups, otail = _log_entry_groups(f.read_text(encoding="utf-8").splitlines())
            body = ohead + moved + [ln for g in ogroups for ln in g] + otail
        else:
            body = [f"# Log archive {year}", "",
                    "Rotated out of log.md by `brain rotate-log`. Newest first.", ""] + moved
        f.write_text("\n".join(body).rstrip("\n") + "\n", encoding="utf-8")

    new_lines = head + [ln for g in hot for ln in g] + tail
    log.write_text("\n".join(new_lines).rstrip("\n") + "\n", encoding="utf-8")
    dest = ", ".join(f"log-archive/{y}.md" for y in sorted(by_year))
    print(f"rotated {len(cold)} entries → {dest}; log.md now "
          f"{len(new_lines)} lines ({len(hot)} entries)")
    return 0


# --------------------------------------------------------------------------
# health — one line of store vitals, built to be surfaced ambiently
#
# Everything here is a pull-only signal somewhere else (review, check, the
# version note); health exists because none of those are seen unless someone
# runs them. It is read-only, deterministic, SILENT when the store is clean
# (so ambient consumers have nothing to relay), and exits non-zero on any
# breach so a timer can turn it into a notification.
# --------------------------------------------------------------------------

HEALTH_LOG_QUIET_DAYS = 7   # days without a log entry before health mentions it
HEALTH_INBOX_AGE_DAYS = 3   # a pending capture older than this is a breach


def _inbox_oldest_days() -> int | None:
    inbox = brain_dir() / "raw" / "inbox.md"
    try:
        text = inbox.read_text(encoding="utf-8")
    except (FileNotFoundError, UnicodeDecodeError, OSError):
        return None
    ages = [d for ln in text.splitlines()
            if (m := re.match(r"^- (\d{4}-\d{2}-\d{2})", ln))
            and (d := days_since(m.group(1))) is not None]
    return max(ages, default=None)


def _remote_state(fetch: bool) -> dict | None:
    """Ahead/behind counts vs origin. Fail-soft by design: any git or network
    problem returns None — health must never error on an offline laptop."""
    d = str(brain_dir())
    # Respect an existing GIT_SSH_COMMAND (it may carry keys/config the push
    # depends on); the subprocess timeout is the real hang protection anyway.
    env = dict(os.environ)
    env.setdefault("GIT_SSH_COMMAND", "ssh -oBatchMode=yes")
    # Parsed defensively OUTSIDE the git try-block: a malformed value must not
    # silently disable the whole remote check via the ValueError handler below.
    try:
        fetch_timeout = int(os.environ.get("BRAIN_FETCH_TIMEOUT", "4"))
    except ValueError:
        fetch_timeout = 4

    def git(*a, timeout=5):
        return subprocess.run(["git", "-C", d, *a], capture_output=True,
                              text=True, timeout=timeout, env=env)

    try:
        if git("remote", "get-url", "origin").returncode != 0:
            return None
        branch_p = git("symbolic-ref", "--short", "HEAD")
        if branch_p.returncode != 0:
            return None
        branch = branch_p.stdout.strip()
        if fetch:
            try:
                git("fetch", "--quiet", "origin", branch, timeout=fetch_timeout)
            except subprocess.TimeoutExpired:
                pass  # offline/slow: fall back to the last-fetched state
        if git("rev-parse", "--verify", "--quiet", f"origin/{branch}").returncode != 0:
            return None
        ahead = git("rev-list", "--count", f"origin/{branch}..HEAD")
        behind = git("rev-list", "--count", f"HEAD..origin/{branch}")
        if ahead.returncode or behind.returncode:
            return None
        return {"ahead": int(ahead.stdout.strip()), "behind": int(behind.stdout.strip())}
    except (subprocess.TimeoutExpired, OSError, ValueError):
        return None


def cmd_health(args) -> int:
    if not brain_dir().is_dir():
        return 0  # no store on this machine — never nag, never fail

    issues = []  # (key, one human-readable segment)

    sv = store_version()
    if sv != TEMPLATE_VERSION:
        seen = "unstamped" if sv is None else f"v{sv}"
        issues.append(("version_drift",
                       f"store {seen} < cli v{TEMPLATE_VERSION} — run brain sync"))

    d = _collect(args.stale)
    if d["overdue"]:
        issues.append(("overdue", f"{len(d['overdue'])} overdue"))
    if d["quiet"]:
        issues.append(("quiet", f"{len(d['quiet'])} gone quiet >{args.stale}d"))
    if d["unverified"]:
        issues.append(("unverified", f"{len(d['unverified'])} never verified"))

    stalled = sum(1 for g in d["goals"] if g["stalled"])
    orphaned = sum(1 for g in d["goals"] if g["orphaned"])
    if stalled or orphaned:
        parts = [f"{stalled} goal(s) stalled"] if stalled else []
        if orphaned:
            parts.append(f"{orphaned} orphaned" if stalled
                         else f"{orphaned} goal(s) orphaned")
        issues.append(("goals", ", ".join(parts)))

    pending, oldest = _inbox_count(), _inbox_oldest_days()
    # An undated pending line (hand-added, not via `capture`) can't age-gate —
    # flag it rather than letting it hide behind the missing timestamp.
    if pending and (oldest is None or oldest >= HEALTH_INBOX_AGE_DAYS):
        age = f"oldest {oldest}d" if oldest is not None else "age unknown"
        issues.append(("inbox", f"inbox {pending} pending ({age})"))

    dates = _log_dates()
    last_log = days_since(dates[0]) if dates else None
    if last_log is not None and last_log > HEALTH_LOG_QUIET_DAYS:
        issues.append(("log_quiet", f"last log entry {last_log}d ago"))

    log = brain_dir() / "log.md"
    try:
        loglines = log.read_text(encoding="utf-8").splitlines()
    except (FileNotFoundError, UnicodeDecodeError, OSError):
        loglines = []
    if len(loglines) > LOG_MAX_LINES:
        _, groups, _ = _log_entry_groups(loglines)
        # Only nag when rotate-log can actually act (it keeps a floor of ~20
        # entries) — otherwise the flag would loop forever with a no-op remedy.
        if len(groups) > 20:
            issues.append(("log_size",
                           f"log.md {len(loglines)} lines — run brain rotate-log"))

    if d["unreadable"]:
        issues.append(("unreadable",
                       f"{len(d['unreadable'])} unreadable page(s): "
                       + ", ".join(d["unreadable"][:3])))

    # The gate blocks NEW broken links at commit time; this catches the ones
    # that predate the gate, or slipped in past a --no-verify it can't stop.
    lerrs, _ = _link_lint()
    if lerrs:
        issues.append(("links", f"{len(lerrs)} broken link(s) — run brain links"))

    now_fault = _now_health()
    if now_fault:
        issues.append(("now_rot", now_fault))

    remote = _remote_state(fetch=not args.no_fetch)
    if remote:
        if remote["behind"]:
            issues.append(("behind",
                           f"{remote['behind']} commit(s) behind remote — "
                           f"git -C ~/brain pull --rebase before writing"))
        if remote["ahead"]:
            issues.append(("ahead", f"{remote['ahead']} unpushed commit(s)"))

    if args.json:
        import json
        print(json.dumps({
            "date": today(), "ok": not issues,
            "issues": [{"key": k, "detail": s} for k, s in issues],
        }, indent=2))
        return 1 if issues else 0
    if issues:
        print(" | ".join(s for _, s in issues))
        return 1
    return 0  # clean: print nothing, so ambient consumers stay silent


# --------------------------------------------------------------------------
# sync — THE migration behavior: mechanical refresh, then stamp when safe
#
# The original design kept every migration a model-executed procedure ("no
# migration script, deliberately"); the measured cost was stores sitting a
# version behind for weeks, because even the judgment-free phase needed a
# supervised session. `sync` executes that phase directly — replace the
# canonical manual, create missing scaffold (never overwriting), normalize,
# reindex, untrack newly-ignored — in one tight commit, then stamps in a
# second, UNLESS the version gap crosses an entry in JUDGMENT_MIGRATIONS.
# Those still need a model + human (diff-and-ask backfill per SKILL.md), and
# the CLI must never stamp across work it didn't do: stamp-last survives.
# --------------------------------------------------------------------------

_TEMPLATE_DIR = "@brainTemplateDir@"  # substituted with the Nix store path at build

# Versions whose upgrade needs judgment — a model-executed, diff-and-ask
# backfill per the skill's sync procedure. `sync` stops before stamping when
# the store's gap crosses one of these. Purely additive bumps don't register.
JUDGMENT_MIGRATIONS = {
    8: "backfill `verified`/`attention`/`next`/`progress` from prose, split "
       "over-long summaries, re-file adr pages whose decision lives in a repo "
       "doc, tag person pages (see the skill's v8 notes)",
    11: "people.md's 'Where they appear' column is now generated from the link "
        "graph — appearances recorded as bare name-mentions vanish from it. "
        "Diff the column against the pre-sync cells (git history has them) and "
        "add [[person-page]] links to pages where the appearance matters; fix "
        "any pre-existing `brain links` errors (see the skill's v11 notes)",
    12: "the adr kind is gone — the store keeps personal notes about a "
        "decision, never the decision record itself. Re-file each kind: adr "
        "page: move the decision text to its external system of record and "
        "keep a kind: project page tracking the rollout. Then wire the goals "
        "layer if adopting it: create goal pages in goals/ and set `parent` "
        "on the live projects/initiatives each one covers (see the skill's "
        "v12 notes)",
}


def template_dir() -> Path | None:
    env = os.environ.get("BRAIN_TEMPLATE_DIR")
    if env:
        return Path(env)
    if not _TEMPLATE_DIR.startswith("@"):  # substituted by the Nix build
        return Path(_TEMPLATE_DIR)
    # Running straight from the repo (uninstalled): fall back to the deployed
    # skill copy, which tracks the last rebuild.
    fallback = Path.home() / ".claude" / "skills" / "brain" / "templates"
    return fallback if fallback.is_dir() else None


def cmd_sync(args) -> int:
    store = brain_dir()
    if not (store / ".git").is_dir():
        die(f"{store} is not a git repository")
    tpl = template_dir()
    if tpl is None or not (tpl / "CLAUDE.md").is_file():
        die("canonical template not found — rebuild this machine, or set BRAIN_TEMPLATE_DIR")

    def git(*a):
        return subprocess.run(["git", "-C", str(store), *a],
                              capture_output=True, text=True)

    sv = store_version()
    if sv is not None and sv > TEMPLATE_VERSION:
        die(f"store is v{sv}, ahead of cli v{TEMPLATE_VERSION} — rebuild this machine first")
    gap = f"v{'?' if sv is None else sv} → v{TEMPLATE_VERSION}"

    # Plan: the manual is canonical (always replaced when it differs);
    # everything else in the template is create-if-missing, never overwritten.
    plan = []
    for src in sorted(tpl.rglob("*")):
        relp = src.relative_to(tpl)
        dst = store / relp
        if src.is_dir():
            if not dst.is_dir():
                plan.append(("mkdir", str(relp)))
        elif str(relp) == "CLAUDE.md":
            if not dst.exists() or dst.read_bytes() != src.read_bytes():
                plan.append(("replace", "CLAUDE.md"))
        elif not dst.exists():
            plan.append(("create", str(relp)))

    if args.dry_run:
        print(f"brain sync (dry run, {gap}):")
        for action, relp in plan or [("noop", "template files all present and current")]:
            print(f"  {action:8} {relp}")
        print("  then: normalize, reindex, untrack newly-ignored, commit; "
              "stamp unless a judgment migration is pending")
        return 0

    # Tight, revertible commits need a clean start (untracked files are fine —
    # they are never staged here and stay untouched).
    dirty = [ln for ln in git("status", "--porcelain").stdout.splitlines()
             if ln and not ln.startswith("??")]
    if dirty:
        die("store has uncommitted changes — commit them first so the sync "
            "commits stay tight and revertible:\n  " + "\n  ".join(dirty))

    changed = []
    for action, relp in plan:
        dst = store / relp
        if action == "mkdir":
            dst.mkdir(parents=True, exist_ok=True)
        else:
            dst.parent.mkdir(parents=True, exist_ok=True)
            dst.write_bytes((tpl / relp).read_bytes())
            changed.append(relp)
    changed += _normalize_paths(all_pages())
    cmd_reindex(argparse.Namespace(check=False))
    # Untrack anything the (possibly just-created) .gitignore now covers.
    ignored = [ln for ln in
               git("ls-files", "-ci", "--exclude-standard").stdout.splitlines() if ln]
    for f in ignored:
        git("rm", "-r", "--cached", "-q", "--", f)

    if plan or changed or ignored:
        _append_log_entry(f"brain sync: mechanical refresh, {gap}")
        # people.md's generated column may have been refreshed by the reindex
        # above; adding a path that doesn't exist is a harmless no-op here.
        for f in changed + ["log.md", "index.md", "mocs/people.md"]:
            git("add", "--", f)
        r = git("commit", "-m", f"brain sync: mechanical refresh ({gap})")
        if r.returncode != 0:
            die("mechanical commit failed (pre-commit gate?):\n"
                + (r.stderr or r.stdout).strip())
        print(f"committed mechanical refresh: {len(plan)} template action(s), "
              f"{len(changed)} file(s), {len(ignored)} untracked")
    else:
        print("mechanical phase: nothing to do")

    # Stamp only when the CLI can vouch for the whole gap. An unstamped store
    # has unknown provenance, and a gap crossing JUDGMENT_MIGRATIONS carries
    # work the CLI didn't do — both stay visibly behind until /brain --sync.
    pending = None if sv is None else {
        v: JUDGMENT_MIGRATIONS[v]
        for v in range(sv + 1, TEMPLATE_VERSION + 1) if v in JUDGMENT_MIGRATIONS}
    if pending == {}:
        if sv == TEMPLATE_VERSION:
            print(f"store already stamped v{TEMPLATE_VERSION}")
            return 0
        (store / VERSION_FILE).write_text(f"{TEMPLATE_VERSION}\n", encoding="utf-8")
        git("add", "--", VERSION_FILE)
        r = git("commit", "-m", f"brain sync: stamp v{TEMPLATE_VERSION}")
        if r.returncode != 0:
            die("stamp commit failed:\n" + (r.stderr or r.stdout).strip())
        print(f"stamped v{TEMPLATE_VERSION} — store is current")
        return 0
    why = ("the store has never been stamped — its schema state is unknown"
           if pending is None
           else "\n".join(f"  v{v}: {note}" for v, note in pending.items()))
    print("NOT stamped — judgment migration(s) pending; finish via /brain --sync, "
          f"then `brain version --stamp`:\n{why}", file=sys.stderr)
    return 1


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

    r = sub.add_parser("reindex", help="regenerate index.md's generated region "
                                       "+ people.md's generated column")
    r.add_argument("--check", action="store_true", help="exit non-zero if stale, don't write")
    r.set_defaults(func=cmd_reindex)

    lk = sub.add_parser("links", help="lint internal links; --to lists backlinks")
    lk.add_argument("--to", metavar="PAGE",
                    help="list the pages linking to PAGE instead of linting")
    lk.add_argument("--strict", action="store_true",
                    help="relative-markdown-path warnings are fatal too")
    lk.add_argument("--json", action="store_true")
    lk.set_defaults(func=cmd_links)

    mv = sub.add_parser("mv", help="move/rename a page, rewriting [[links]] store-wide")
    mv.add_argument("page")
    mv.add_argument("dest", help="<bucket>/<slug> (e.g. archive/foo); .md optional")
    mv.set_defaults(func=cmd_mv)

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
    n.add_argument("slug", help="page slug; may carry subdirectories (scripts/deploy)")
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

    rl = sub.add_parser("rotate-log",
                        help="move log.md's older tail into log-archive/ (mechanical)")
    rl.add_argument("--threshold", type=int, default=LOG_MAX_LINES, metavar="LINES",
                    help=f"only rotate past this many lines (default {LOG_MAX_LINES})")
    rl.add_argument("--keep", type=int, default=LOG_KEEP_ENTRIES, metavar="N",
                    help=f"newest entries to keep hot (default {LOG_KEEP_ENTRIES})")
    rl.add_argument("--force", action="store_true", help="rotate even under the threshold")
    rl.set_defaults(func=cmd_rotate_log)

    h = sub.add_parser("health",
                       help="one-line store vitals; exit 1 when something needs attention")
    h.add_argument("--stale", type=int, default=STALE_DAYS, metavar="DAYS",
                   help=f"gone-quiet threshold (default {STALE_DAYS})")
    h.add_argument("--no-fetch", action="store_true",
                   help="skip the remote ahead/behind check's fetch")
    h.add_argument("--json", action="store_true")
    h.set_defaults(func=cmd_health)

    sy = sub.add_parser("sync",
                        help="mechanical template refresh; stamps unless a "
                             "judgment migration is pending")
    sy.add_argument("--dry-run", action="store_true",
                    help="print the plan, change nothing")
    sy.set_defaults(func=cmd_sync)

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
