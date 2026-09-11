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

# The only values that mean "no row yet". Anything else that is not a URL is a
# typo in a published artifact's address, and dropping its row would delete the
# repo's only record of that page — so the build fails instead of skipping it.
PLACEHOLDERS = ("", "unpublished", "pending-first-publish")

REQUIRED = ("title", "url", "org", "status", "last_updated", "summary")


class BuildError(Exception):
    pass


def _iso(value) -> str:
    if isinstance(value, (dt.date, dt.datetime)):
        return value.strftime("%Y-%m-%d")
    return str(value).strip()


def _public(value) -> str:
    # YAML 1.1 turns a bare `no` into False, which is the value we want to print.
    if value is True:
        return "yes"
    if value is False or value is None:
        return "no"
    return str(value).strip()


def _cell(text: str, where: Path, column: str) -> str:
    text = " ".join(str(text).split())
    if re.search(r"(?<!\\)\|", text):
        raise BuildError(
            f"{where}: the {column} value contains an unescaped '|', which would "
            f"split the table row. Write it as '\\|'."
        )
    return text


def load_rows(root: Path) -> tuple[list[dict], list[tuple[Path, str]]]:
    """Return (rows, skipped) — skipped holds artifacts with no URL yet."""
    paths = sorted(root.glob("artifacts/*/meta.yml"))
    paths += sorted(root.glob("artifacts/index-rows/*.yml"))

    rows: list[dict] = []
    skipped: list[tuple[Path, str]] = []
    seen: dict[str, Path] = {}

    for path in paths:
        rel = path.relative_to(root)
        try:
            data = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
        except yaml.YAMLError as exc:
            raise BuildError(f"{rel}: not valid YAML — {exc}") from exc
        if not isinstance(data, dict):
            raise BuildError(f"{rel}: expected a YAML mapping")

        # Read the url as it was written, before any normalisation. `str(x or "")`
        # collapses False, 0 and an empty collection into "", which is a supported
        # "not published yet" placeholder — so a url of `no` (YAML 1.1 False) used
        # to delete a published page's row and exit 0. This builder must NEVER drop
        # a row for metadata it cannot read: ARTIFACTS.md is that page's only record
        # in this repo. Every skip must be one the schema designates, and anything
        # else fails loudly.
        raw_url = data.get("url")
        if raw_url is None:
            # Absent or null. artifacts/README.md: a url that is one of the two
            # placeholders "or empty" gets no row and is listed as a reminder.
            url = ""
        elif isinstance(raw_url, str):
            url = raw_url.strip()
        else:
            raise BuildError(
                f"{rel}: url is {type(raw_url).__name__} {raw_url!r}, not a string. "
                f"Write the published address as text "
                f"(https://claude.ai/code/artifact/<uuid>), or one of the "
                f"unpublished placeholders {', '.join(PLACEHOLDERS[1:])}. "
                f"Quote a bare `no`/`off`/`yes`, which YAML reads as a boolean. "
                f"A row is never dropped for an unreadable url."
            )

        if not URL_RE.match(url):
            if url.lower() in PLACEHOLDERS:
                # Not published yet. It has no row until it has a URL; it is
                # reported, never invented.
                skipped.append((rel, url or "(no url)"))
                continue
            raise BuildError(
                f"{rel}: url '{url}' is neither a published artifact address "
                f"(https://claude.ai/code/artifact/<uuid>) nor one of the "
                f"unpublished placeholders {', '.join(PLACEHOLDERS[1:])}. "
                f"Fix the url — a row is never dropped for an unreadable one."
            )

        missing = [k for k in REQUIRED if not str(data.get(k) or "").strip()]
        if missing:
            raise BuildError(f"{rel}: missing required key(s): {', '.join(missing)}")

        status = str(data["status"]).strip()
        if status not in STATUSES:
            raise BuildError(
                f"{rel}: status '{status}' is not one of {', '.join(STATUSES)}"
            )
        note = str(data.get("status_note") or "").strip()
        if status == "superseded" and "](" not in note:
            raise BuildError(
                f"{rel}: a superseded row must link to its replacement in status_note"
            )

        if url in seen:
            raise BuildError(f"{rel}: duplicate url, already claimed by {seen[url]}")
        seen[url] = rel

        source = str(data.get("index_source") or "").strip()
        if not source:
            parent = path.parent
            source = (
                "—"
                if parent.name == "index-rows"
                else f"`{parent.relative_to(root).as_posix()}/`"
            )

        rows.append(
            {
                "path": rel,
                "url": url,
                "last_updated": _iso(data["last_updated"]),
                "artifact": _cell(
                    f"[{str(data['title']).strip()}]({url}) — {str(data['summary']).strip()}",
                    rel,
                    "title/summary",
                ),
                "org": _cell(data["org"], rel, "org"),
                "bare_status": status,
                "status": _cell(f"{status} — {note}" if note else status, rel, "status"),
                "source": _cell(source, rel, "index_source"),
                "public": _cell(_public(data.get("public")), rel, "public"),
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
