#!/usr/bin/env python3
"""Build the artifacts table in ARTIFACTS.md from one YAML file per published page.

Every artifact PR used to insert a row at the top of the same Markdown table, so any
two of them conflicted on the same line. The rows now live one-per-file — in each
artifact's own `artifacts/<slug>/meta.yml`, or in `artifacts/index-rows/<slug>.yml`
for a page whose source was never kept — and this script assembles them. Two PRs
adding two artifacts touch two different files.

The table is spliced between the BEGIN/END markers in ARTIFACTS.md. Everything else
in that file is hand-written prose and is never touched. A merge conflict inside the
generated block is resolved mechanically: take either side, re-run this script, commit.
No row can be lost that way, because the rows are not in the conflicting file.

Usage:
    python3 scripts/build_artifacts_index.py            # rewrite ARTIFACTS.md
    python3 scripts/build_artifacts_index.py --check    # exit 1 if it is stale
"""

from __future__ import annotations

import argparse
import datetime as dt
import difflib
import re
import sys
from pathlib import Path

import yaml

# md2artifact renders ARTIFACTS.md with raw HTML escaped, so an HTML comment would
# show up as literal text on the published index page. A link reference definition
# is the marker form CommonMark renders as nothing at all.
BEGIN = "[//]: # (BEGIN GENERATED ARTIFACTS TABLE)"
END = "[//]: # (END GENERATED ARTIFACTS TABLE)"

HEADER = [
    "| Artifact | Org | Status | Source | Public | Updated |",
    "|---|---|---|---|---|---|",
]

# The five values the artifacts-sync skill allows, and nothing else.
STATUSES = ("live", "done", "archived", "superseded", "elsewhere")

URL_RE = re.compile(r"^https://claude\.ai/code/artifact/[0-9a-fA-F-]{36}$")
ISO_DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")

# The only values that mean "no row yet". Anything else that is not a URL is a
# typo in a published artifact's address, and dropping its row would delete the
# repo's only record of that page — so the build fails instead of skipping it.
PLACEHOLDERS = ("", "unpublished", "pending-first-publish")

REQUIRED = ("title", "url", "org", "status", "last_updated", "summary")

# The two designated locations for a row, and nothing else.
ARTIFACT_ROW = "meta.yml"
INDEX_ROWS = "index-rows"

# THE ONE RULE THIS FILE KEEPS BREAKING, stated once so the next reader has it:
# never normalise a value parsed from YAML before its type has been checked.
# Python treats False, 0, "", [] and {} as equally falsey, so `x or default` and
# `str(x or "")` cannot tell any of them from "absent" — and here "absent" means
# a published page's row is left out of ARTIFACTS.md with a success exit code,
# and ARTIFACTS.md is this repo's only record of that page. Inspect the parsed
# value, reject the wrong type by naming the file, the key, the type and the
# value as written, and only then apply a default the schema documents. There is
# no `or` fallback on parsed data anywhere below, and that is deliberate.
#
# The rule covers files as well as values, because a row this builder cannot
# see is a row it drops just as silently. "Was this file meant to be a row?" has
# no answer a filename can give, so discovery asks the decidable question
# instead: every artifact directory must have a row file in one of the two
# locations above, and one that does not is named and fails the build.
#
# So: this builder must never drop a row, and never ignore an intended row, for
# anything it cannot read. Every skip is a path the schema explicitly designates
# — a url that is empty or one of the two placeholders above — and everything
# else stops the build.

# The type each key is allowed to have, and what to tell a human who got it
# wrong. Exact types, not isinstance: YAML's `true` is a bool, and a bool is an
# int in Python, so an isinstance check on int would wave `public: true` through
# as a number and `last_updated: false` through as a date.
TYPES: dict[str, tuple[type, ...]] = {
    "url": (str,),
    "title": (str,),
    "org": (str,),
    "status": (str,),
    "status_note": (str,),
    "index_source": (str,),
    "summary": (str,),
    "last_updated": (str, dt.date, dt.datetime),
    "public": (str, bool),
}

TYPE_HINT = {
    "url": (
        "the published address as text (https://claude.ai/code/artifact/<uuid>), "
        "or one of the unpublished placeholders "
        f"{', '.join(PLACEHOLDERS[1:])}"
    ),
    "title": "the page title as text",
    "org": "the publishing org as text",
    "status": f"one of {', '.join(STATUSES)}, as text",
    "status_note": "the clause after the status, as text",
    "index_source": "the Source cell, as text",
    "summary": "what the page established, as text",
    "last_updated": "an ISO date, e.g. 2026-09-01",
    "public": "`no`, `yes`, or the public mirror URL as text",
}


class BuildError(Exception):
    pass


class DuplicateKey(Exception):
    """A key written twice in one mapping, with the line of the second one."""

    def __init__(self, key: str, line: int) -> None:
        super().__init__(key)
        self.key, self.line = key, line


class UniqueKeyLoader(yaml.SafeLoader):
    """`yaml.safe_load` keeps the last value for a repeated key and discards the
    first without a word — this file's one rule again, a value lost before
    anything checks it. A row holding `url:` twice indexes one address and
    silently forgets the other, so the load fails instead."""

    def construct_mapping(self, node, deep=False):
        mapping = super().construct_mapping(node, deep=deep)
        seen: set = set()
        for key_node, _ in node.value:
            key = self.construct_object(key_node, deep=deep)
            if key in seen:
                raise DuplicateKey(key, key_node.start_mark.line + 1)
            seen.add(key)
        return mapping


def _value(data: dict, key: str, rel: Path):
    """The parsed value for `key`, type-checked and otherwise untouched.

    An absent key and an explicit YAML null both come back as None, and the
    caller decides whether that is a documented default or a missing required
    key. Nothing is coerced or defaulted here: a default applied ahead of the
    type check is the bug this whole file guards against.
    """
    if key not in data:
        return None
    value = data[key]
    if value is None:
        return None
    if type(value) in TYPES[key]:
        return value
    raise BuildError(
        f"{rel}: {key} is {type(value).__name__} {value!r}. Write {TYPE_HINT[key]}. "
        f"A bare `no`, `off`, `yes` or `on` is a boolean in YAML 1.1 — quote it. "
        f"No row is ever dropped, blanked or defaulted for a value the builder "
        f"cannot read."
    )


def _text(data: dict, key: str, rel: Path) -> str:
    """A string-typed value, stripped. Absent, null and blank all give ""; the
    caller reports it as missing if the key is required."""
    value = _value(data, key, rel)
    return "" if value is None else value.strip()


def _iso(data: dict, rel: Path) -> str:
    value = _value(data, "last_updated", rel)
    if value is None:
        return ""
    if isinstance(value, (dt.date, dt.datetime)):
        return value.strftime("%Y-%m-%d")
    text = value.strip()
    if not text:
        return ""
    # The table sorts on this string, so a date the builder cannot parse would
    # silently reorder the log rather than fail.
    if not ISO_DATE_RE.match(text):
        raise BuildError(
            f"{rel}: last_updated is '{text}', which is not an ISO date "
            f"(YYYY-MM-DD). The table sorts on it, so an unreadable date would "
            f"silently reorder the index."
        )
    try:
        dt.date.fromisoformat(text)
    except ValueError as exc:
        raise BuildError(f"{rel}: last_updated '{text}' is not a real date — {exc}") from exc
    return text


def _public(data: dict, rel: Path) -> str:
    value = _value(data, "public", rel)
    # The documented default — artifacts/index-rows/README.md: `public` is `no`
    # unless a mirror URL is given. It is applied here, after the type check,
    # which is the whole point.
    if value is None or value is False:
        return "no"
    if value is True:
        return "yes"
    text = value.strip()
    return text if text else "no"


def _cell(text: str, where: Path, column: str) -> str:
    # Every caller passes a value _value() has already type-checked, so there is
    # no str() coercion here to hide a list or a mapping behind its repr.
    text = " ".join(text.split())
    if re.search(r"(?<!\\)\|", text):
        raise BuildError(
            f"{where}: the {column} value contains an unescaped '|', which would "
            f"split the table row. Write it as '\\|'."
        )
    return text


def _document(path: Path, rel: Path) -> dict:
    """The parsed mapping, or a loud failure.

    `yaml.safe_load(...) or {}` used to run one line above the isinstance check
    below, so a file whose whole document was `false`, `0`, `''` or `[]` became
    an empty mapping, read as an absent url, and dropped its row with exit 0 —
    while whole-document `true` and a non-empty list were rejected, which is how
    we know the check existed and merely ran in the wrong order.
    """
    try:
        doc = yaml.load(path.read_text(encoding="utf-8"), Loader=UniqueKeyLoader)
    except DuplicateKey as exc:
        raise BuildError(
            f"{rel}: the key '{exc.key}' is written twice (line {exc.line}). YAML "
            f"keeps the last one and discards the first, so one of the two values "
            f"would be lost before this builder ever read it. Delete the line that "
            f"does not belong."
        ) from exc
    except yaml.YAMLError as exc:
        raise BuildError(f"{rel}: not valid YAML — {exc}") from exc
    if doc is None:
        raise BuildError(
            f"{rel}: the file is empty, or is a single YAML null. A row file with "
            f"nothing in it is a row this index cannot print, and it will not be "
            f"silently ignored — fill it in, or delete the file."
        )
    if not isinstance(doc, dict):
        raise BuildError(
            f"{rel}: the document is {type(doc).__name__} {doc!r}, not a mapping. "
            f"Write the row as `key: value` lines; "
            f"artifacts/{INDEX_ROWS}/README.md lists the keys."
        )
    if not doc:
        raise BuildError(
            f"{rel}: the document is an empty mapping. A row file with no keys is "
            f"a row this index cannot print — fill it in, or delete the file."
        )
    return doc


def find_row_files(root: Path) -> list[Path]:
    """Every row file, plus a loud failure for an artifact that has none.

    Discovery reads exactly two paths, so a row saved anywhere else is invisible:
    the build succeeds and the published page has no row. Guessing from a
    filename which strays were meant to be rows is unwinnable — a rule catching
    `metadata.txt` must still leave a page's own data files alone — so the check
    is inverted. Every directory under `artifacts/` must have a row file in one
    of the two designated locations, and one that does not is named. A renamed
    or misplaced row then reads as "this artifact has no row", which is true.
    """
    artifacts = root / "artifacts"
    if not artifacts.is_dir():
        raise BuildError(
            f"{artifacts.relative_to(root) if artifacts.is_relative_to(root) else artifacts}"
            f": the artifacts directory does not exist, so there is nothing to "
            f"build from. An empty table is a dropped index, not a valid result."
        )

    rows: list[Path] = []
    seen: set[Path] = set()
    for path in [
        *sorted(artifacts.glob(f"*/{ARTIFACT_ROW}")),
        *sorted(artifacts.glob(f"{INDEX_ROWS}/*.yml")),
    ]:
        if path not in seen:
            seen.add(path)
            rows.append(path)

    uncovered = [
        d.name
        for d in sorted(artifacts.iterdir())
        if d.is_dir()
        and d.name != INDEX_ROWS
        and not d.name.startswith(".")
        # A directory holding no files at all is a leftover, not an artifact —
        # git cannot record one, so it only ever exists in a working tree.
        and any(child.is_file() for child in d.rglob("*"))
        and not (d / ARTIFACT_ROW).is_file()
        and not (artifacts / INDEX_ROWS / f"{d.name}.yml").is_file()
    ]
    if uncovered:
        raise BuildError(
            "these artifact directories have no row file, so each is a published "
            "page ARTIFACTS.md would silently not list:\n"
            + "\n".join(f"  artifacts/{name}/" for name in uncovered)
            + f"\nA row lives at `artifacts/<slug>/{ARTIFACT_ROW}`, or at "
            f"`artifacts/{INDEX_ROWS}/<slug>.yml` when it is kept apart from the "
            f"directory. One renamed, given another extension or moved out of "
            f"those two paths reads as a missing row, which is what this is. A "
            f"directory that is not an artifact does not belong under `artifacts/`."
        )
    return rows


def load_rows(root: Path) -> tuple[list[dict], list[tuple[Path, str]]]:
    """Return (rows, skipped) — skipped holds artifacts with no URL yet."""
    rows: list[dict] = []
    skipped: list[tuple[Path, str]] = []
    seen: dict[str, Path] = {}

    for path in find_row_files(root):
        rel = path.relative_to(root)
        data = _document(path, rel)

        # Read the url as it was written. Every value below follows the same
        # order — type first, default second — for the reason given at the top
        # of this file.
        url = _text(data, "url", rel)

        if not URL_RE.match(url):
            if url.lower() in PLACEHOLDERS:
                # Not published yet: the one skip the schema designates
                # (artifacts/README.md — a url that is empty or one of the two
                # placeholders). It has no row until it has a URL; it is
                # reported, never invented.
                skipped.append((rel, url if url else "(no url)"))
                continue
            raise BuildError(
                f"{rel}: url '{url}' is neither a published artifact address "
                f"(https://claude.ai/code/artifact/<uuid>) nor one of the "
                f"unpublished placeholders {', '.join(PLACEHOLDERS[1:])}. "
                f"Fix the url — a row is never dropped for an unreadable one."
            )

        title = _text(data, "title", rel)
        org = _text(data, "org", rel)
        summary = _text(data, "summary", rel)
        status = _text(data, "status", rel)
        note = _text(data, "status_note", rel)
        last_updated = _iso(data, rel)

        present = {
            "title": title,
            "url": url,
            "org": org,
            "status": status,
            "last_updated": last_updated,
            "summary": summary,
        }
        missing = [k for k in REQUIRED if not present[k]]
        if missing:
            raise BuildError(f"{rel}: missing required key(s): {', '.join(missing)}")

        if status not in STATUSES:
            raise BuildError(
                f"{rel}: status '{status}' is not one of {', '.join(STATUSES)}"
            )
        if status == "superseded" and "](" not in note:
            raise BuildError(
                f"{rel}: a superseded row must link to its replacement in status_note"
            )

        if url in seen:
            raise BuildError(f"{rel}: duplicate url, already claimed by {seen[url]}")
        seen[url] = rel

        source = _text(data, "index_source", rel)
        if not source:
            # The documented default: the artifact's own directory, or an em
            # dash for a row that has none.
            parent = path.parent
            source = (
                "—"
                if parent.name == INDEX_ROWS
                else f"`{parent.relative_to(root).as_posix()}/`"
            )

        rows.append(
            {
                "path": rel,
                "url": url,
                "last_updated": last_updated,
                "artifact": _cell(f"[{title}]({url}) — {summary}", rel, "title/summary"),
                "org": _cell(org, rel, "org"),
                "bare_status": status,
                "status": _cell(f"{status} — {note}" if note else status, rel, "status"),
                "source": _cell(source, rel, "index_source"),
                "public": _cell(_public(data, rel), rel, "public"),
            }
        )

    # Newest first, so the table reads as a log. The url tie-break keeps two
    # sessions adding rows on the same day from producing two different tables.
    rows.sort(key=lambda r: (r["last_updated"], r["url"]), reverse=True)
    return rows, skipped


def render(rows: list[dict]) -> str:
    lines = list(HEADER)
    for r in rows:
        lines.append(
            f"| {r['artifact']} | {r['org']} | {r['status']} | "
            f"{r['source']} | {r['public']} | {r['last_updated']} |"
        )
    # The tally used to be a hand-written paragraph and went stale on every
    # publish. It is one line of arithmetic, so the generator owns it.
    counts = [f"{sum(1 for r in rows if r['bare_status'] == s)} {s}" for s in STATUSES]
    counts = [c for c in counts if not c.startswith("0 ")]
    lines.append("")
    lines.append(f"{len(rows)} rows: {', '.join(counts)}.")
    return "\n".join(lines)


def splice(index_text: str, table: str, index_path: Path) -> str:
    if index_text.count(BEGIN) != 1 or index_text.count(END) != 1:
        raise BuildError(
            f"{index_path}: expected exactly one {BEGIN} and one {END} marker"
        )
    head, rest = index_text.split(BEGIN, 1)
    _, tail = rest.split(END, 1)
    # Blank lines around each marker keep it a standalone block, which is what
    # makes it invisible; butted against the table it would render as text.
    return f"{head}{BEGIN}\n\n{table}\n\n{END}{tail}"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--check",
        action="store_true",
        help="exit 1 with a diff if ARTIFACTS.md does not match the YAML files",
    )
    parser.add_argument(
        "--repo-root",
        type=Path,
        default=Path(__file__).resolve().parent.parent,
        help="repo to build in (default: this script's repo)",
    )
    args = parser.parse_args(argv)

    root = args.repo_root.resolve()
    index_path = root / "ARTIFACTS.md"
    if not index_path.is_file():
        print(f"error: {index_path} does not exist", file=sys.stderr)
        return 2

    try:
        rows, skipped = load_rows(root)
        current = index_path.read_text(encoding="utf-8")
        wanted = splice(current, render(rows), index_path)
    except BuildError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2

    if args.check:
        if wanted == current:
            print(f"ARTIFACTS.md is up to date ({len(rows)} rows).")
            return 0
        diff = difflib.unified_diff(
            current.splitlines(keepends=True),
            wanted.splitlines(keepends=True),
            fromfile="ARTIFACTS.md (on disk)",
            tofile="ARTIFACTS.md (from artifacts/*/meta.yml)",
        )
        sys.stdout.writelines(diff)
        print(
            "\nerror: the generated table is stale. "
            "Run: python3 scripts/build_artifacts_index.py",
            file=sys.stderr,
        )
        return 1

    if wanted != current:
        index_path.write_text(wanted, encoding="utf-8")
        print(f"ARTIFACTS.md rewritten ({len(rows)} rows).")
    else:
        print(f"ARTIFACTS.md already current ({len(rows)} rows).")
    for rel, url in skipped:
        print(f"  not published yet, no row: {rel} (url: {url})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
