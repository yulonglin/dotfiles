#!/usr/bin/env python3
"""
Check installed Claude Code plugins for available updates, with a release-age quarantine.

Reports two classes of staleness:

1. Local install lags marketplace pin — the marketplace says install version X, you have X-1.
   Fix: /plugin update <name>@<marketplace>

2. Marketplace pin lags upstream — the marketplace says X, but the upstream repo has X+1
   tagged and quarantine has expired. Fix: nudge the marketplace maintainer or switch to
   one that pins to upstream HEAD.

Only checks plugins whose marketplace source has an explicit `url` (i.e., points at a separate
GitHub repo). Plugins with relative-path sources are owned by the marketplace itself; their
freshness is the marketplace's concern, not this script's.

Output: ~/.claude/state/plugin-updates.json
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
import subprocess
import sys
from pathlib import Path

CLAUDE_HOME = Path(os.environ.get("CLAUDE_CONFIG_DIR", Path.home() / ".claude"))
INSTALLED = CLAUDE_HOME / "plugins" / "installed_plugins.json"
MARKETPLACES = CLAUDE_HOME / "plugins" / "marketplaces"
STATE_DIR = CLAUDE_HOME / "state"
REPORT_PATH = STATE_DIR / "plugin-updates.json"

DEFAULT_MIN_RELEASE_AGE_DAYS = 7

GITHUB_URL_RE = re.compile(
    r"^(?:https?://github\.com/|git@github\.com:)([^/]+)/([^/.]+?)(?:\.git)?/?$"
)
SEMVER_TAG_RE = re.compile(r"^v?(\d+)\.(\d+)\.(\d+)(?:[-+][\w.-]+)?$")


def _parse_github(url: str) -> tuple[str, str] | None:
    m = GITHUB_URL_RE.match(url.strip())
    return (m.group(1), m.group(2)) if m else None


def _semver_tuple(tag: str) -> tuple[int, int, int] | None:
    m = SEMVER_TAG_RE.match(tag)
    return (int(m.group(1)), int(m.group(2)), int(m.group(3))) if m else None


def _run(cmd: list[str], **kwargs) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        cmd,
        capture_output=True,
        text=True,
        timeout=30,
        check=False,
        **kwargs,
    )


def ls_remote_tags(url: str) -> list[tuple[str, str]]:
    """Return [(tag, sha), ...] sorted newest-semver-first. Returns [] on failure."""
    proc = _run(["git", "ls-remote", "--tags", "--refs", url])
    if proc.returncode != 0:
        return []
    out: list[tuple[str, str, tuple[int, int, int]]] = []
    for line in proc.stdout.splitlines():
        sha, _, ref = line.partition("\t")
        if not ref.startswith("refs/tags/"):
            continue
        tag = ref.removeprefix("refs/tags/")
        sv = _semver_tuple(tag)
        if sv is None:
            continue
        out.append((tag, sha, sv))
    out.sort(key=lambda x: x[2], reverse=True)
    return [(t, s) for t, s, _ in out]


def commit_date(owner: str, repo: str, sha: str) -> dt.datetime | None:
    """Resolve a commit's authored date via gh CLI. Returns UTC datetime or None."""
    proc = _run(
        ["gh", "api", f"repos/{owner}/{repo}/commits/{sha}", "--jq", ".commit.author.date"]
    )
    if proc.returncode != 0 or not proc.stdout.strip():
        return None
    raw = proc.stdout.strip().rstrip("Z") + "+00:00"
    try:
        return dt.datetime.fromisoformat(raw)
    except ValueError:
        return None


def load_installed() -> dict[str, list[dict]]:
    if not INSTALLED.is_file():
        return {}
    try:
        return json.loads(INSTALLED.read_text())["plugins"]
    except (json.JSONDecodeError, KeyError):
        return {}


def load_marketplace(name: str) -> dict | None:
    path = MARKETPLACES / name / ".claude-plugin" / "marketplace.json"
    if not path.is_file():
        return None
    try:
        return json.loads(path.read_text())
    except json.JSONDecodeError:
        return None


def find_plugin_in_marketplace(mkt: dict, plugin_name: str) -> dict | None:
    for p in mkt.get("plugins", []):
        if p.get("name") == plugin_name:
            return p
    return None


def check_plugin(
    plugin_id: str,
    installed_meta: dict,
    *,
    min_age_days: int,
    now: dt.datetime,
    verbose: bool = False,
) -> dict | None:
    """Return a status dict, or None if we can't introspect this plugin."""
    name, _, marketplace = plugin_id.partition("@")
    if not marketplace:
        return None

    mkt = load_marketplace(marketplace)
    if mkt is None:
        return {"plugin": plugin_id, "skipped": "no marketplace manifest"}

    p = find_plugin_in_marketplace(mkt, name)
    if p is None:
        return {"plugin": plugin_id, "skipped": "plugin not in marketplace manifest"}

    source = p.get("source")
    if isinstance(source, str):
        return None  # relative-path plugin; not in scope

    if not isinstance(source, dict) or "url" not in source:
        return None

    gh = _parse_github(source["url"])
    if gh is None:
        return {"plugin": plugin_id, "skipped": f"non-GitHub source: {source.get('url')}"}

    owner, repo = gh
    pinned_sha = source.get("sha")

    tags = ls_remote_tags(source["url"])
    if not tags:
        return {"plugin": plugin_id, "skipped": "no semver tags on upstream"}

    installed_version = installed_meta.get("version", "?")
    installed_sv = _semver_tuple(installed_version)

    latest_tag, latest_sha = tags[0]
    latest_sv = _semver_tuple(latest_tag)

    # Resolve marketplace-pinned version: if a SHA is pinned, find the matching tag.
    marketplace_version = None
    if pinned_sha:
        for tag, sha in tags:
            if sha == pinned_sha:
                marketplace_version = tag
                break

    if installed_sv is None or latest_sv is None:
        return {"plugin": plugin_id, "skipped": "non-semver versions"}

    # No update available
    if installed_sv >= latest_sv:
        return {
            "plugin": plugin_id,
            "installed": installed_version,
            "marketplace_pin": marketplace_version,
            "upstream_latest": latest_tag,
            "status": "up_to_date",
        }

    # An update exists. Quarantine check on upstream commit date.
    commit_at = commit_date(owner, repo, latest_sha)
    age_days = (now - commit_at).days if commit_at else None

    if age_days is None:
        status = "quarantine_unknown"
    elif age_days < min_age_days:
        status = "in_quarantine"
    else:
        status = "ready"

    return {
        "plugin": plugin_id,
        "installed": installed_version,
        "marketplace_pin": marketplace_version,
        "upstream_latest": latest_tag,
        "upstream_sha": latest_sha,
        "upstream_published_at": commit_at.isoformat() if commit_at else None,
        "upstream_age_days": age_days,
        "marketplace_lags_upstream": marketplace_version != latest_tag,
        "status": status,
    }


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--min-release-age-days", type=int, default=DEFAULT_MIN_RELEASE_AGE_DAYS)
    ap.add_argument("--verbose", "-v", action="store_true")
    ap.add_argument("--stdout", action="store_true", help="print report instead of writing state file")
    args = ap.parse_args()

    installed = load_installed()
    if not installed:
        print(f"No installed plugins found at {INSTALLED}", file=sys.stderr)
        return 1

    now = dt.datetime.now(dt.timezone.utc)
    results: list[dict] = []

    for plugin_id, instances in sorted(installed.items()):
        if not instances:
            continue
        meta = instances[0]
        try:
            r = check_plugin(plugin_id, meta, min_age_days=args.min_release_age_days, now=now, verbose=args.verbose)
        except subprocess.TimeoutExpired:
            r = {"plugin": plugin_id, "skipped": "timeout"}
        if r is not None:
            results.append(r)
            if args.verbose:
                print(json.dumps(r), file=sys.stderr)

    report = {
        "generated_at": now.isoformat(),
        "min_release_age_days": args.min_release_age_days,
        "results": results,
        "summary": {
            "ready": sum(1 for r in results if r.get("status") == "ready"),
            "in_quarantine": sum(1 for r in results if r.get("status") == "in_quarantine"),
            "up_to_date": sum(1 for r in results if r.get("status") == "up_to_date"),
            "skipped": sum(1 for r in results if "skipped" in r),
            "marketplace_lags_upstream": sum(
                1 for r in results if r.get("marketplace_lags_upstream")
            ),
        },
    }

    if args.stdout:
        print(json.dumps(report, indent=2))
    else:
        STATE_DIR.mkdir(parents=True, exist_ok=True)
        REPORT_PATH.write_text(json.dumps(report, indent=2))
        print(f"Wrote {REPORT_PATH}")
        s = report["summary"]
        print(
            f"  ready={s['ready']}  quarantine={s['in_quarantine']}  "
            f"up_to_date={s['up_to_date']}  skipped={s['skipped']}  "
            f"marketplace_lags={s['marketplace_lags_upstream']}"
        )

    return 0


if __name__ == "__main__":
    sys.exit(main())
