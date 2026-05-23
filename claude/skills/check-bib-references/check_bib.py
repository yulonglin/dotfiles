#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = ["httpx[socks]>=0.27"]
# ///
"""Verify bib entries against arXiv / OpenReview.

For each entry with an arXiv eprint or OpenReview URL, fetch the live
metadata and diff title + first author against the bib. Catches the
common LLM-fabrication failure mode where a plausible-looking citation
points at the wrong paper.

Usage:
    uv run paper/src/scripts/check_bib.py paper/main.bib
    uv run paper/src/scripts/check_bib.py paper/main.bib --only-mismatches
"""

from __future__ import annotations

import argparse
import re
import sys
import time
import unicodedata
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from pathlib import Path

import httpx

ARXIV_API = "http://export.arxiv.org/api/query"
OPENREVIEW_API = "https://api2.openreview.net/notes"
ATOM_NS = {"a": "http://www.w3.org/2005/Atom"}

TITLE_SIMILARITY_THRESHOLD = 0.85


@dataclass
class BibEntry:
    key: str
    fields: dict[str, str]

    @property
    def arxiv_id(self) -> str | None:
        if self.fields.get("eprint"):
            return self.fields["eprint"]
        for field in ("journal", "url", "howpublished"):
            text = self.fields.get(field, "")
            m = re.search(r"(?:arxiv[:.]?\s*|/abs/)(\d{4}\.\d{4,5})", text, re.IGNORECASE)
            if m:
                return m.group(1)
        return None

    @property
    def openreview_id(self) -> str | None:
        url = self.fields.get("url", "")
        m = re.search(r"openreview\.net/forum\?id=([A-Za-z0-9_-]+)", url)
        return m.group(1) if m else None

    @property
    def title(self) -> str:
        return self.fields.get("title", "")

    @property
    def first_author_lastname(self) -> str | None:
        authors = self.fields.get("author", "")
        if not authors:
            return None
        first = re.split(r"\s+and\s+", authors)[0].strip()
        if "," in first:
            return first.split(",")[0].strip()
        parts = first.split()
        return parts[-1] if parts else None


def parse_bib(path: Path) -> list[BibEntry]:
    text = path.read_text()
    entries: list[BibEntry] = []
    for match in re.finditer(r"@\w+\s*\{\s*([^,\s]+)\s*,(.*?)\n\}", text, re.DOTALL):
        key = match.group(1)
        body = match.group(2)
        fields: dict[str, str] = {}
        for fmatch in re.finditer(
            r"(\w+)\s*=\s*[{\"](.+?)[}\"]\s*[,}]?\s*$",
            body,
            re.MULTILINE | re.DOTALL,
        ):
            name = fmatch.group(1).lower()
            value = re.sub(r"\s+", " ", fmatch.group(2)).strip()
            value = re.sub(r"[{}]", "", value)
            fields[name] = value
        entries.append(BibEntry(key=key, fields=fields))
    return entries


def strip_latex_accents(s: str) -> str:
    """Convert LaTeX accent escapes to ASCII letter, e.g. {\"u} -> u, \'e -> e."""
    s = re.sub(r"\\[\"'`^~=.](?:\{(\w)\}|(\w))", lambda m: m.group(1) or m.group(2), s)
    s = re.sub(r"\{\\ss\}|\\ss\b", "ss", s)
    return s


def normalize(s: str) -> str:
    s = strip_latex_accents(s)
    s = unicodedata.normalize("NFKD", s)
    s = "".join(c for c in s if not unicodedata.combining(c))
    s = re.sub(r"[^a-z0-9 ]+", " ", s.lower())
    return re.sub(r"\s+", " ", s).strip()


def title_similarity(a: str, b: str) -> float:
    """Token Jaccard on normalized titles. Cheap, no extra deps."""
    ta, tb = set(normalize(a).split()), set(normalize(b).split())
    if not ta or not tb:
        return 0.0
    return len(ta & tb) / len(ta | tb)


def fetch_arxiv_batch(ids: list[str], client: httpx.Client) -> dict[str, dict]:
    """Fetch many arxiv IDs in one request. Returns id -> {title, authors} or {error}.

    Retries on 429 with backoff. arXiv's rate limit is "1 req per 3s",
    but bursty clients get IP-throttled for ~30-60s.
    """
    out: dict[str, dict] = {}
    if not ids:
        return out
    backoffs = [0, 5, 30, 60]
    last_err: Exception | None = None
    r = None
    for delay in backoffs:
        if delay:
            time.sleep(delay)
        try:
            r = client.get(
                ARXIV_API,
                params={"id_list": ",".join(ids), "max_results": str(len(ids))},
                timeout=60,
            )
            if r.status_code == 429:
                last_err = httpx.HTTPStatusError(
                    "429 Too Many Requests", request=r.request, response=r
                )
                continue
            r.raise_for_status()
            break
        except httpx.HTTPError as e:
            last_err = e
            continue
    if r is None or r.status_code != 200:
        msg = f"arXiv batch fetch failed: {last_err}"
        for aid in ids:
            out[aid] = {"error": msg}
        return out
    root = ET.fromstring(r.text)
    found: dict[str, dict] = {}
    for entry in root.findall("a:entry", ATOM_NS):
        id_el = entry.find("a:id", ATOM_NS)
        title_el = entry.find("a:title", ATOM_NS)
        if id_el is None or title_el is None or not title_el.text:
            continue
        title = title_el.text.strip()
        if "Error" in title and "id" in title.lower():
            continue
        m = re.search(r"abs/([^v]+?)(v\d+)?$", id_el.text or "")
        if not m:
            continue
        aid = m.group(1)
        authors = [
            (a.find("a:name", ATOM_NS).text or "").strip()
            for a in entry.findall("a:author", ATOM_NS)
            if a.find("a:name", ATOM_NS) is not None
        ]
        found[aid] = {"title": title, "authors": authors}
    for aid in ids:
        out[aid] = found.get(aid, {"error": "arXiv: no entry returned (id may be invalid)"})
    return out


def fetch_openreview(forum_id: str, client: httpx.Client) -> dict | None:
    try:
        r = client.get(OPENREVIEW_API, params={"id": forum_id}, timeout=30)
        r.raise_for_status()
    except httpx.HTTPError as e:
        return {"error": f"OpenReview fetch failed: {e}"}
    notes = r.json().get("notes", [])
    if not notes:
        return {"error": "no note for forum id"}
    content = notes[0].get("content", {})
    title = content.get("title", {}).get("value", "")
    authors = content.get("authors", {}).get("value", [])
    if not title:
        return {"error": "OpenReview note missing title"}
    return {"title": title, "authors": authors}


def first_lastname(author: str) -> str:
    return author.split()[-1] if author else ""


def check(entry: BibEntry, arxiv_meta: dict[str, dict], client: httpx.Client) -> dict:
    if entry.arxiv_id:
        meta = arxiv_meta.get(entry.arxiv_id, {"error": "no batch result"})
        source = f"arXiv:{entry.arxiv_id}"
    elif entry.openreview_id:
        meta = fetch_openreview(entry.openreview_id, client)
        source = f"OpenReview:{entry.openreview_id}"
    else:
        return {"key": entry.key, "skipped": "no arxiv/openreview id"}

    if meta is None or "error" in meta:
        return {"key": entry.key, "source": source, "error": meta.get("error", "unknown")}

    sim = title_similarity(entry.title, meta["title"])
    bib_lastname = entry.first_author_lastname or ""
    real_lastname = first_lastname(meta["authors"][0]) if meta["authors"] else ""
    author_match = (
        normalize(bib_lastname) == normalize(real_lastname)
        if bib_lastname and real_lastname
        else None
    )

    return {
        "key": entry.key,
        "source": source,
        "title_sim": sim,
        "title_match": sim >= TITLE_SIMILARITY_THRESHOLD,
        "bib_title": entry.title,
        "real_title": meta["title"],
        "bib_first_author": bib_lastname,
        "real_first_author": real_lastname,
        "author_match": author_match,
    }


def format_result(r: dict, only_mismatches: bool) -> str | None:
    if "skipped" in r:
        return None if only_mismatches else f"  . {r['key']:40s}  [skip] {r['skipped']}"
    if "error" in r:
        return f"  ! {r['key']:40s}  [{r['source']}] ERROR: {r['error']}"

    is_mismatch = not r["title_match"] or r["author_match"] is False
    if only_mismatches and not is_mismatch:
        return None

    mark = "MISMATCH" if is_mismatch else "OK"
    lines = [f"  [{mark}] {r['key']:40s}  [{r['source']}]  title_sim={r['title_sim']:.2f}"]
    if not r["title_match"]:
        lines.append(f"      bib title:  {r['bib_title'][:90]}")
        lines.append(f"      real title: {r['real_title'][:90]}")
    if r["author_match"] is False:
        lines.append(
            f"      first author: bib={r['bib_first_author']!r}  real={r['real_first_author']!r}"
        )
    return "\n".join(lines)


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("bib_file", type=Path)
    p.add_argument("--only-mismatches", action="store_true")
    p.add_argument("--key", help="Check a single entry by citation key")
    args = p.parse_args()

    entries = parse_bib(args.bib_file)
    if args.key:
        entries = [e for e in entries if e.key == args.key]
        if not entries:
            print(f"No entry with key {args.key!r}", file=sys.stderr)
            return 1

    print(f"Checking {len(entries)} bib entries from {args.bib_file}\n")

    n_mismatch = n_error = n_skip = 0
    with httpx.Client(
        headers={"User-Agent": "check_bib.py"},
        follow_redirects=True,
        timeout=30,
    ) as client:
        arxiv_ids = [e.arxiv_id for e in entries if e.arxiv_id]
        arxiv_meta = fetch_arxiv_batch(arxiv_ids, client)
        for entry in entries:
            r = check(entry, arxiv_meta, client)
            line = format_result(r, args.only_mismatches)
            if line:
                print(line)
            if "skipped" in r:
                n_skip += 1
            elif "error" in r:
                n_error += 1
            elif not r["title_match"] or r["author_match"] is False:
                n_mismatch += 1

    n_checked = len(entries) - n_skip
    print(
        f"\n{n_checked} checked, {n_mismatch} mismatches, "
        f"{n_error} fetch errors, {n_skip} skipped (no arxiv/openreview id)"
    )
    return 1 if n_mismatch or n_error else 0


if __name__ == "__main__":
    sys.exit(main())
