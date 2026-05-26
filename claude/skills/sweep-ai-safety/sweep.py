#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = [
#   "httpx>=0.27",
#   "PyYAML>=6.0",
#   "feedparser>=6.0",
#   "python-dateutil>=2.9",
# ]
# ///
"""Sweep AI safety sources, emit a dated markdown digest.

Reads sources.yaml + terms (regex aliases) and fetches feeds. arXiv search terms
are queried via the export API in one batched request per term.

CLI:
  --since 7d|14d|30d|YYYY-MM-DD   Time window (default 7d)
  --output PATH                   Write markdown to PATH (default: stdout)
  --source KEY                    Only fetch this source key (repeatable)
  --term TERM                     Only show items matching this regex alias key
  --arxiv-only                    Skip blog/paper sources, just hit arXiv
  --json                          Emit NDJSON instead of markdown
  --no-arxiv                      Skip arXiv keyword searches
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import time
from dataclasses import dataclass, field, asdict
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any
from urllib.parse import quote_plus

import feedparser
import httpx
import yaml
from dateutil import parser as date_parser

HERE = Path(__file__).resolve().parent
SOURCES_YAML = HERE / "sources.yaml"
ARXIV_API = "http://export.arxiv.org/api/query"
USER_AGENT = "sweep-ai-safety/0.1 (+https://github.com/yulonglin/dotfiles)"
HTTP_TIMEOUT = 20.0
ARXIV_DELAY = 3.5  # arXiv rate limit ~ 1 req / 3s

# Generic safety-relevant terms for sources tagged `safety_filter: true`. Items
# that don't hit a tracked glossary alias can still pass if they look broadly
# safety-related (preparedness updates, frontier model risk posts, etc.).
SAFETY_KEYWORDS_RX = re.compile(
    r"\b(safety|alignment|preparedness|frontier|misuse|risk|harm|"
    r"red[\s-]team|jailbreak|evaluation|model[\s-]card)\b",
    re.IGNORECASE,
)


@dataclass
class Item:
    source_key: str
    source_org: str
    source_name: str
    title: str
    url: str
    published: datetime | None
    summary: str = ""
    authors: list[str] = field(default_factory=list)
    arxiv_id: str | None = None
    matched_terms: list[str] = field(default_factory=list)

    def to_dict(self) -> dict[str, Any]:
        d = asdict(self)
        d["published"] = self.published.isoformat() if self.published else None
        return d


def parse_since(since: str) -> datetime:
    """Parse '7d', '30d', or 'YYYY-MM-DD' into a UTC cutoff."""
    now = datetime.now(timezone.utc)
    m = re.fullmatch(r"(\d+)\s*d", since.strip())
    if m:
        return now - timedelta(days=int(m.group(1)))
    try:
        d = date_parser.parse(since)
        if d.tzinfo is None:
            d = d.replace(tzinfo=timezone.utc)
        return d
    except (ValueError, date_parser.ParserError) as exc:
        raise SystemExit(f"invalid --since value: {since!r} ({exc})")


def load_config() -> dict[str, Any]:
    if not SOURCES_YAML.exists():
        raise SystemExit(f"missing sources.yaml at {SOURCES_YAML}")
    with SOURCES_YAML.open() as f:
        return yaml.safe_load(f)


def compile_term_regexes(cfg: dict[str, Any]) -> dict[str, re.Pattern[str]]:
    out: dict[str, re.Pattern[str]] = {}
    for key, pattern in (cfg.get("term_regex_aliases") or {}).items():
        try:
            out[key] = re.compile(pattern, re.IGNORECASE)
        except re.error as exc:
            print(f"warning: bad regex for {key!r}: {exc}", file=sys.stderr)
    return out


def match_terms(text: str, regexes: dict[str, re.Pattern[str]]) -> list[str]:
    return [k for k, rx in regexes.items() if rx.search(text)]


def parse_feed_datetime(entry: Any) -> datetime | None:
    for attr in ("published", "updated", "created"):
        val = getattr(entry, attr, None) or entry.get(attr) if isinstance(entry, dict) else getattr(entry, attr, None)
        if val:
            try:
                d = date_parser.parse(val)
                if d.tzinfo is None:
                    d = d.replace(tzinfo=timezone.utc)
                return d.astimezone(timezone.utc)
            except (ValueError, date_parser.ParserError):
                continue
    parsed = getattr(entry, "published_parsed", None) or getattr(entry, "updated_parsed", None)
    if parsed:
        try:
            return datetime(*parsed[:6], tzinfo=timezone.utc)
        except (TypeError, ValueError):
            return None
    return None


def fetch_rss(source: dict[str, Any], cutoff: datetime, client: httpx.Client) -> tuple[list[Item], str | None]:
    rss = source.get("rss")
    if not rss:
        return [], "no rss configured"
    try:
        r = client.get(rss)
        r.raise_for_status()
    except (httpx.HTTPError, httpx.HTTPStatusError) as exc:
        return [], f"fetch failed: {exc}"

    parsed = feedparser.parse(r.content)
    if parsed.bozo and not parsed.entries:
        return [], f"feed parse error: {parsed.bozo_exception}"

    items: list[Item] = []
    for entry in parsed.entries:
        published = parse_feed_datetime(entry)
        if published is None:
            continue
        if published < cutoff:
            continue
        title = (entry.get("title") or "").strip()
        url = entry.get("link") or ""
        summary = (entry.get("summary") or entry.get("description") or "").strip()
        summary = re.sub(r"<[^>]+>", "", summary)
        authors = []
        if hasattr(entry, "authors") and entry.authors:
            authors = [a.get("name", "") for a in entry.authors if a.get("name")]
        elif entry.get("author"):
            authors = [entry["author"]]
        items.append(Item(
            source_key=source["key"],
            source_org=source["org"],
            source_name=source["name"],
            title=title,
            url=url,
            published=published,
            summary=summary,
            authors=authors,
        ))
    return items, None


ARXIV_ID_RE = re.compile(r"arxiv\.org/abs/(\d{4}\.\d{4,5})", re.IGNORECASE)


ARXIV_PAGE_SIZE = 50
ARXIV_MAX_PAGES = 6  # safety cap: at most 300 results per term


def fetch_arxiv_term(term: str, cutoff: datetime, client: httpx.Client) -> tuple[list[Item], str | None]:
    """Query arXiv export API for a single phrase.

    Results are sorted by submittedDate desc, so we paginate until we see an
    entry older than ``cutoff`` (or hit the safety cap).
    """
    query = f'all:"{term}"'
    items: list[Item] = []
    for page in range(ARXIV_MAX_PAGES):
        params = {
            "search_query": query,
            "sortBy": "submittedDate",
            "sortOrder": "descending",
            "start": page * ARXIV_PAGE_SIZE,
            "max_results": ARXIV_PAGE_SIZE,
        }
        try:
            r = client.get(ARXIV_API, params=params)
            r.raise_for_status()
        except (httpx.HTTPError, httpx.HTTPStatusError) as exc:
            return items, f"arxiv query failed for {term!r}: {exc}"

        parsed = feedparser.parse(r.content)
        if not parsed.entries:
            break

        stop = False
        for entry in parsed.entries:
            published = parse_feed_datetime(entry)
            if published is None:
                continue
            if published < cutoff:
                stop = True
                continue
            url = entry.get("link", "")
            m = ARXIV_ID_RE.search(url)
            arxiv_id = m.group(1) if m else None
            title = re.sub(r"\s+", " ", (entry.get("title") or "").strip())
            summary = re.sub(r"\s+", " ", (entry.get("summary") or "").strip())
            authors = [a.get("name", "") for a in (entry.get("authors") or []) if a.get("name")]
            items.append(Item(
                source_key=f"arxiv:{term}",
                source_org="arXiv",
                source_name=f"arXiv search: {term}",
                title=title,
                url=url,
                published=published,
                summary=summary,
                authors=authors,
                arxiv_id=arxiv_id,
            ))

        if stop or len(parsed.entries) < ARXIV_PAGE_SIZE:
            break
        time.sleep(ARXIV_DELAY)
    return items, None


def dedupe(items: list[Item]) -> list[Item]:
    """Dedupe by arxiv_id, then by normalized title.

    When two items share a title, prefer the one with an arxiv_id, then the one
    with tracked-term matches. Tags from dropped duplicates are merged into the
    kept item so a blog summary's term match isn't lost.
    """
    ranked = sorted(
        enumerate(items),
        key=lambda p: (0 if p[1].arxiv_id else 1, 0 if p[1].matched_terms else 1, p[0]),
    )
    seen_ids: dict[str, int] = {}
    seen_titles: dict[str, int] = {}
    keep: set[int] = set()
    for idx, it in ranked:
        norm = re.sub(r"\W+", " ", it.title.lower()).strip()
        kept_idx: int | None = None
        if it.arxiv_id and it.arxiv_id in seen_ids:
            kept_idx = seen_ids[it.arxiv_id]
        elif norm and norm in seen_titles:
            kept_idx = seen_titles[norm]
        if kept_idx is not None:
            kept = items[kept_idx]
            for tag in it.matched_terms:
                if tag not in kept.matched_terms:
                    kept.matched_terms.append(tag)
            continue
        if it.arxiv_id:
            seen_ids[it.arxiv_id] = idx
        if norm:
            seen_titles[norm] = idx
        keep.add(idx)
    return [items[i] for i in range(len(items)) if i in keep]


def tag_terms(items: list[Item], regexes: dict[str, re.Pattern[str]]) -> None:
    for it in items:
        text = f"{it.title}\n{it.summary}"
        it.matched_terms = match_terms(text, regexes)


def render_markdown(
    items: list[Item],
    cutoff: datetime,
    errors: list[tuple[str, str]],
    skipped: list[tuple[str, str, str]] | None = None,
) -> str:
    skipped = skipped or []
    now = datetime.now(timezone.utc)
    lines: list[str] = []
    lines.append(f"# AI safety sweep — {now.strftime('%Y-%m-%d')}")
    lines.append("")
    lines.append(f"Window: items published since **{cutoff.strftime('%Y-%m-%d')}** ({(now - cutoff).days}d).")
    lines.append(f"Sources surfaced: **{len({i.source_key.split(':')[0] for i in items})}**.  "
                 f"Items: **{len(items)}**.")
    if skipped:
        lines.append(f"Manual sources (no auto-fetch): **{len(skipped)}** (see end).")
    if errors:
        lines.append(f"Failures: **{len(errors)}** (see end).")
    lines.append("")

    items_by_term: dict[str, list[Item]] = {}
    items_other: list[Item] = []
    for it in items:
        if it.matched_terms:
            for t in it.matched_terms:
                items_by_term.setdefault(t, []).append(it)
        else:
            items_other.append(it)

    if items_by_term:
        lines.append("## Tagged by tracked term")
        lines.append("")
        for term in sorted(items_by_term):
            lines.append(f"### {term}")
            lines.append("")
            for it in sorted(items_by_term[term], key=lambda i: i.published or datetime.min.replace(tzinfo=timezone.utc), reverse=True):
                lines.extend(render_item(it))
            lines.append("")

    if items_other:
        lines.append("## Other items")
        lines.append("")
        by_source: dict[str, list[Item]] = {}
        for it in items_other:
            by_source.setdefault(it.source_org, []).append(it)
        for org in sorted(by_source):
            lines.append(f"### {org}")
            lines.append("")
            for it in sorted(by_source[org], key=lambda i: i.published or datetime.min.replace(tzinfo=timezone.utc), reverse=True):
                lines.extend(render_item(it))
            lines.append("")

    if skipped:
        lines.append("## Manual sources (not auto-fetched)")
        lines.append("")
        lines.append("These sources have no RSS feed. WebFetch the URL to check for recent items.")
        lines.append("")
        lines.append("| source | url | reason |")
        lines.append("|---|---|---|")
        for key, url, reason in skipped:
            lines.append(f"| `{key}` | {url} | {reason} |")
        lines.append("")

    if errors:
        lines.append("## Fetch failures")
        lines.append("")
        lines.append("| source | reason |")
        lines.append("|---|---|")
        for key, reason in errors:
            lines.append(f"| `{key}` | {reason} |")
        lines.append("")

    return "\n".join(lines)


def render_item(it: Item) -> list[str]:
    date_str = it.published.strftime("%Y-%m-%d") if it.published else "????-??-??"
    authors = ", ".join(it.authors[:5])
    if len(it.authors) > 5:
        authors += f", +{len(it.authors) - 5}"
    head = f"- **[{it.title}]({it.url})** — {it.source_name} · {date_str}"
    if authors:
        head += f" · {authors}"
    out = [head]
    if it.matched_terms:
        out.append(f"  - tags: {', '.join(it.matched_terms)}")
    if it.summary:
        out.append(f"  - {it.summary[:280]}{'…' if len(it.summary) > 280 else ''}")
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description="Sweep AI safety sources.")
    ap.add_argument("--since", default="7d", help="time window: e.g. 7d, 30d, YYYY-MM-DD")
    ap.add_argument("--output", type=Path, help="write markdown to file")
    ap.add_argument("--source", action="append", default=[], help="restrict to source key(s)")
    ap.add_argument("--term", help="restrict to items matching this regex alias key")
    ap.add_argument("--arxiv-only", action="store_true", help="skip blog/paper sources")
    ap.add_argument("--no-arxiv", action="store_true", help="skip arXiv search")
    ap.add_argument("--json", action="store_true", help="emit NDJSON instead of markdown")
    args = ap.parse_args()

    cutoff = parse_since(args.since)
    cfg = load_config()
    regexes = compile_term_regexes(cfg)

    if args.term:
        raw = args.term.strip()
        normalized = re.sub(r"[\s_]+", "-", raw.lower())
        if normalized in regexes:
            args.term = normalized
        else:
            matched = next((k for k, rx in regexes.items() if rx.search(raw)), None)
            if matched:
                args.term = matched
            else:
                valid = ", ".join(sorted(regexes.keys()))
                raise SystemExit(
                    f"--term {raw!r}: no matching alias "
                    f"(tried key {normalized!r} and regex search). Valid keys: {valid}"
                )

    arxiv_terms = list(cfg.get("arxiv_search_terms", []))
    if args.term:
        term_rx = regexes[args.term]
        matching = [t for t in arxiv_terms if term_rx.search(t)]
        arxiv_terms = matching if matching else [args.term.replace("-", " ")]

    items: list[Item] = []
    errors: list[tuple[str, str]] = []
    skipped: list[tuple[str, str, str]] = []

    with httpx.Client(timeout=HTTP_TIMEOUT, follow_redirects=True, headers={"User-Agent": USER_AGENT}) as client:
        if not args.arxiv_only:
            for src in cfg.get("sources", []):
                if src.get("key") == "arxiv-terms":
                    continue
                if args.source and src["key"] not in args.source:
                    continue
                if not src.get("rss"):
                    skipped.append((src["key"], src.get("url", ""), "no RSS — needs manual WebFetch"))
                    print(f"[skip] {src['key']}: no RSS configured", file=sys.stderr)
                    continue
                got, err = fetch_rss(src, cutoff, client)
                if err:
                    errors.append((src["key"], err))
                else:
                    items.extend(got)
                    print(f"[ok] {src['key']}: {len(got)} items", file=sys.stderr)

        if not args.no_arxiv and (not args.source or "arxiv-terms" in args.source):
            for term in arxiv_terms:
                got, err = fetch_arxiv_term(term, cutoff, client)
                if got:
                    items.extend(got)
                    suffix = " (partial)" if err else ""
                    print(f"[ok] arxiv:{term}: {len(got)} items{suffix}", file=sys.stderr)
                if err:
                    errors.append((f"arxiv:{term}", err))
                time.sleep(ARXIV_DELAY)

    tag_terms(items, regexes)
    items = dedupe(items)

    safety_filtered = {
        src["key"] for src in cfg.get("sources", []) if src.get("safety_filter")
    }
    if safety_filtered:
        items = [
            i for i in items
            if i.source_key not in safety_filtered
            or i.matched_terms
            or SAFETY_KEYWORDS_RX.search(f"{i.title}\n{i.summary}")
        ]

    if args.term:
        items = [i for i in items if args.term in i.matched_terms]

    items.sort(key=lambda i: i.published or datetime.min.replace(tzinfo=timezone.utc), reverse=True)

    if args.json:
        out = "\n".join(json.dumps(i.to_dict(), ensure_ascii=False) for i in items)
    else:
        out = render_markdown(items, cutoff, errors, skipped)

    if args.output:
        args.output.write_text(out + "\n")
        print(
            f"wrote {args.output} ({len(items)} items, {len(errors)} errors, "
            f"{len(skipped)} skipped)",
            file=sys.stderr,
        )
    else:
        print(out)

    return 0


if __name__ == "__main__":
    sys.exit(main())
