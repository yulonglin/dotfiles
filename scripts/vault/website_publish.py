#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Carry website content between the Obsidian vault and the git repo, and publish it.

The vault is where Yulong writes, including on a phone. The repo is what CI and
Netlify build, and the only place the prose is versioned. Neither can be a
symlink to the other: git would store the link instead of the text and the
Netlify build machine has no vault, while a symlink inside a synced vault is
what `vault-deliverables.md` forbids and what iOS Obsidian ignores outright. So
the two are kept in step by copying, and this script is the thing that copies.

    status     what differs right now, and which way each file would move
    sync       perform the copies, refusing any file edited on both sides
    publish    sync, then open a PR, wait for CI, and merge it when green

Direction is decided per file against a recorded hash of its last agreed state,
not by timestamp: mtime is meaningless after a sync client rewrites a file.

    vault differs, repo matches record  ->  PULL   vault wins, this is publishing
    repo differs, vault matches record  ->  PUSH   repo wins, vault was stale
    both differ                         ->  CONFLICT, reported and skipped
    absent one side, present the other  ->  copied across, never deleted

Nothing is ever deleted. A file that disappears from one side is reported and
left alone, because a sync client mid-run looks exactly like a deletion.

`publish` builds locally before it opens anything, so a broken post costs a few
seconds rather than a CI round trip. The repo is private on a free plan, which
has no branch protection and therefore no GitHub auto-merge, so this polls the
checks itself and merges when they pass.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

VAULT = Path(os.environ.get("WEBSITE_VAULT", Path.home() / "vault/writing/website"))
REPO = Path(os.environ.get("WEBSITE_REPO", Path.home() / "code/yulonglin.github.io"))
STATE = Path(
    os.environ.get(
        "WEBSITE_PUBLISH_STATE",
        Path.home() / ".local/state/website-publish/state.json",
    )
)

# vault-relative -> repo-relative. The vault names are the ones that read well
# in Obsidian's file tree; `posts` is friendlier than a second `writing`.
DIRS = {
    "site": "src/content/site",
    "posts": "src/content/writing",
    "research": "src/content/research",
    "jobs": "src/content/jobs",
}
FILES = {"resume.pdf": "public/resume.pdf"}

SITE = "https://yulonglin.com"

# Where each collection actually surfaces, read off the pages that consume it
# rather than assumed: site/ is pulled entry by entry, research/ renders as
# anchored sections of one page, and jobs/ appears inside the about page.
LIVE_URL = {
    "posts": lambda stem: f"{SITE}/writing/{stem}",
    "research": lambda stem: f"{SITE}/research#{stem}",
    "jobs": lambda stem: f"{SITE}/about",
    "site": lambda stem: f"{SITE}/" + {"home": "", "about": "about", "things": "things"}.get(stem, stem),
}

# Only these collections have a draft flag in the Astro schema, so only these
# can carry an opt-in. site/ holds three fixed pages and jobs/ holds CV entries;
# neither is a place drafting happens.
OPT_IN_DIRS = {"posts", "research"}

# Astro's telemetry tries to create ~/.config/astro, which the sandbox denies;
# the build dies before it compiles anything unless this is set.
BUILD_ENV = {**os.environ, "ASTRO_TELEMETRY_DISABLED": "1"}

PULL, PUSH, CONFLICT, NEW_VAULT, NEW_REPO, GONE, NO_OPT_IN = (
    "pull",
    "push",
    "conflict",
    "new-in-vault",
    "new-in-repo",
    "missing",
    "no-opt-in",
)


@dataclass
class Item:
    """One file, tracked by its path on each side and what to do about it."""

    key: str  # stable identity, used as the state-file key
    vault: Path
    repo: Path
    action: str

    @property
    def arrow(self) -> str:
        return {
            PULL: "vault -> repo",
            NEW_VAULT: "vault -> repo (new)",
            PUSH: "repo -> vault",
            NEW_REPO: "repo -> vault (new)",
            CONFLICT: "BOTH CHANGED",
            GONE: "missing one side",
            NO_OPT_IN: "no explicit draft: line",
        }[self.action]


def frontmatter(path: Path) -> list[str]:
    """The frontmatter lines of a markdown file, or [] if it has none."""
    try:
        lines = path.read_text().split("\n")
    except (OSError, UnicodeDecodeError):
        return []
    if not lines or lines[0].strip() != "---":
        return []
    try:
        return lines[1 : lines.index("---", 1)]
    except ValueError:
        return []


def has_explicit_draft(path: Path) -> bool:
    """True when the file states draft: outright rather than leaning on a default.

    Silence used to mean published, because the Astro schema defaulted draft to
    false. A note typed on a phone with no frontmatter at all would therefore
    have gone straight to the live site. The schema default is now true, and
    this is the second half of that: publishing requires the file to say so.
    """
    return any(line.startswith("draft:") for line in frontmatter(path))


def is_draft(path: Path) -> bool:
    for line in frontmatter(path):
        if line.startswith("draft:"):
            return line.split(":", 1)[1].strip() == "true"
    return True  # silence means unpublished


def is_unlisted(path: Path) -> bool:
    for line in frontmatter(path):
        if line.startswith("unlisted:"):
            return line.split(":", 1)[1].strip() == "true"
    return False


def sha(path: Path) -> str | None:
    if not path.exists():
        return None
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load_state() -> dict[str, str]:
    if not STATE.exists():
        return {}
    try:
        return json.loads(STATE.read_text())
    except json.JSONDecodeError:
        # A truncated state file would otherwise make every file look changed
        # on both sides, i.e. a wall of false conflicts. Start clean instead.
        print(f"warning: {STATE} is unreadable, treating as a first run", file=sys.stderr)
        return {}


def save_state(state: dict[str, str]) -> None:
    STATE.parent.mkdir(parents=True, exist_ok=True)
    tmp = STATE.with_suffix(".tmp")
    tmp.write_text(json.dumps(state, indent=2, sort_keys=True))
    tmp.replace(STATE)


def classify(key: str, vault: Path, repo: Path, state: dict[str, str]) -> str | None:
    """Decide which way this file moves, or None when the two sides agree."""
    v, r = sha(vault), sha(repo)
    if v == r:
        return None
    if v is None or r is None:
        # One side has it and the other does not. If the record has never seen
        # it, it is genuinely new and gets copied across. If the record HAS
        # seen it, someone deleted it, and a half-finished sync looks identical
        # to that, so it is reported rather than acted on.
        if key in state:
            return GONE
        return NEW_VAULT if r is None else NEW_REPO
    known = state.get(key)
    if known is None:
        return CONFLICT  # both exist, differ, and nothing says which is newer
    if v != known and r == known:
        return PULL
    if r != known and v == known:
        return PUSH
    return CONFLICT


def pairs() -> list[tuple[str, Path, Path]]:
    """Every file this script tracks, as (key, vault path, repo path)."""
    out: list[tuple[str, Path, Path]] = []
    for vdir, rdir in DIRS.items():
        vroot, rroot = VAULT / vdir, REPO / rdir
        names = {p.name for p in vroot.glob("*.md")} | {p.name for p in rroot.glob("*.md")}
        for name in sorted(names):
            out.append((f"{vdir}/{name}", vroot / name, rroot / name))
    for vname, rname in FILES.items():
        out.append((vname, VAULT / vname, REPO / rname))
    return out


def survey(state: dict[str, str]) -> list[Item]:
    items = []
    for key, vault, repo in pairs():
        action = classify(key, vault, repo, state)
        if not action:
            continue
        # A file heading for the live site has to opt in explicitly. This is
        # only a gate on the publish direction: a repo-to-vault copy is just
        # keeping the vault current and carries no such risk.
        if (
            action in (PULL, NEW_VAULT)
            and key.split("/")[0] in OPT_IN_DIRS
            and not has_explicit_draft(vault)
        ):
            action = NO_OPT_IN
        items.append(Item(key, vault, repo, action))
    return items


def record_agreed(state: dict[str, str]) -> int:
    """Record the hash of every file whose two sides currently match.

    Without this, a first run over identical trees writes no state at all, and
    the next genuine edit has nothing to compare against - so it is reported as
    a conflict rather than published. Seeding on agreement is what makes the
    very first edit work.
    """
    seeded = 0
    for key, vault, repo in pairs():
        v = sha(vault)
        if v is not None and v == sha(repo) and state.get(key) != v:
            state[key] = v
            seeded += 1
    return seeded


README_WARNING = """# Everything in these folders is published to yulonglin.com

This is not a private notes folder. Once the publish timer is running, an edit
saved here reaches the public internet on its own, within about ten minutes,
as soon as CI passes. There is no second confirmation step.

A file is only published if its frontmatter says so outright. A note with no
`draft:` line stays unpublished, in the Astro schema and in the sync script
both, so a half-finished thought typed on a phone cannot go live by accident.
To publish, set `draft: false`. To retire something that is already public
without breaking links other people hold, set `unlisted: true` -- the page and
its URL stay alive, but it leaves the listings and the feed.

`site/` and `jobs/` have no draft flag: those are three fixed pages and the CV
entries on the about page, and they are always live.

This file is generated by `website_publish.py` on every sync. Edits to it are
overwritten.
"""

STATE_LABEL = {
    (False, False): "live",
    (False, True): "unlisted",
    (True, False): "draft",
    (True, True): "draft",
}


def write_readme() -> None:
    """Regenerate the vault index: what publishes, what does not, and where."""
    out = [README_WARNING, f"Generated {datetime.now(timezone.utc):%Y-%m-%d %H:%M} UTC.\n"]
    titles = {"site": "Site pages", "posts": "Posts", "research": "Research", "jobs": "CV entries"}
    for vdir in ("site", "posts", "research", "jobs"):
        root = VAULT / vdir
        files = sorted(root.glob("*.md"))
        if not files:
            continue
        out.append(f"## {titles[vdir]}\n")
        gated = vdir in OPT_IN_DIRS
        out.append("| file | state | live at |" if gated else "| file | live at |")
        out.append("|---|---|---|" if gated else "|---|---|")
        for f in files:
            stem = f.stem
            url = LIVE_URL[vdir](stem)
            if not gated:
                out.append(f"| [[{stem}]] | {url} |")
                continue
            # A -zh post has no page of its own: [slug].astro looks it up from
            # the UNFILTERED collection and renders it behind the language
            # toggle on its English counterpart. Its own draft flag is never
            # consulted, so reporting one here would be a lie.
            if stem.endswith("-zh"):
                parent = stem[: -len("-zh")]
                shown = (root / f"{parent}.md").exists() and not is_draft(root / f"{parent}.md")
                where = f"{LIVE_URL[vdir](parent)} (Chinese toggle)" if shown else "not published"
                out.append(f"| [[{stem}]] | follows [[{parent}]] | {where} |")
                continue
            if not has_explicit_draft(f):
                out.append(f"| [[{stem}]] | **no `draft:` line** | not published |")
                continue
            state = STATE_LABEL[(is_draft(f), is_unlisted(f))]
            where = "not published" if state == "draft" else url
            out.append(f"| [[{stem}]] | {state} | {where} |")
        out.append("")
    resume = VAULT / "resume.pdf"
    if resume.exists():
        out.append("## CV\n")
        out.append(f"`resume.pdf` is published at {SITE}/resume.pdf. Replace the file to update it.\n")
    (VAULT / "README.md").write_text("\n".join(out))


def copy(src: Path, dst: Path) -> None:
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, dst)


def run(cmd: list[str], cwd: Path = REPO, check: bool = True, env=None):
    return subprocess.run(
        cmd, cwd=cwd, check=check, text=True, capture_output=True, env=env or os.environ
    )


def report(items: list[Item]) -> None:
    if not items:
        print("vault and repo agree; nothing to do")
        return
    width = max(len(i.key) for i in items)
    for group, label in (
        (CONFLICT, "conflicts (skipped)"),
        (NO_OPT_IN, "not published - add an explicit `draft: true` or `draft: false`"),
        (GONE, "missing on one side (skipped)"),
        (PULL, "vault -> repo"),
        (NEW_VAULT, "vault -> repo (new)"),
        (PUSH, "repo -> vault"),
        (NEW_REPO, "repo -> vault (new)"),
    ):
        rows = [i for i in items if i.action == group]
        if rows:
            print(f"\n{label}:")
            for i in rows:
                print(f"  {i.key:{width}}  {i.arrow}")


def do_sync(items: list[Item], state: dict[str, str], dry: bool) -> tuple[int, int]:
    """Apply the copies. Returns (to_repo, to_vault) counts."""
    to_repo = to_vault = 0
    for item in items:
        if item.action in (CONFLICT, GONE, NO_OPT_IN):
            continue
        if item.action in (PULL, NEW_VAULT):
            if not dry:
                copy(item.vault, item.repo)
            to_repo += 1
        else:
            if not dry:
                copy(item.repo, item.vault)
            to_vault += 1
        if not dry:
            state[item.key] = sha(item.vault)
    return to_repo, to_vault


def build_ok() -> tuple[bool, str]:
    proc = subprocess.run(
        ["bun", "run", "build"],
        cwd=REPO,
        text=True,
        capture_output=True,
        env=BUILD_ENV,
        check=False,
    )
    if proc.returncode == 0:
        return True, ""
    return False, (proc.stdout + proc.stderr)[-3000:]


def notify(text: str) -> None:
    """Best-effort Telegram ping. Silence here must never fail a publish."""
    env_file = Path.home() / ".claude/channels/telegram/tripwire.env"
    if not env_file.exists():
        return
    creds = {}
    for line in env_file.read_text().splitlines():
        if "=" in line and not line.startswith("#"):
            k, _, v = line.partition("=")
            creds[k.strip()] = v.strip()
    token, chat = creds.get("TELEGRAM_BOT_TOKEN"), creds.get("TELEGRAM_CHAT_ID")
    if not token or not chat:
        return
    import urllib.parse
    import urllib.request

    data = urllib.parse.urlencode({"chat_id": chat, "text": text}).encode()
    try:
        urllib.request.urlopen(
            f"https://api.telegram.org/bot{token}/sendMessage", data=data, timeout=20
        )
    except Exception as exc:  # noqa: BLE001 - notification is not the job
        print(f"warning: telegram notify failed: {exc}", file=sys.stderr)


def open_publish_pr() -> str | None:
    """The number of an already-open vault-sync PR, if there is one.

    Without this check a timer firing every ten minutes against a red CI opens
    a fresh branch and PR on every tick, burying the one that actually needs
    looking at. One outstanding publish at a time; the next tick waits.
    """
    proc = run(["gh", "pr", "list", "--json", "number,headRefName"], check=False)
    if proc.returncode != 0:
        return None
    try:
        for pr in json.loads(proc.stdout or "[]"):
            if pr.get("headRefName", "").startswith("vault-sync/"):
                return str(pr["number"])
    except json.JSONDecodeError:
        return None
    return None


def do_publish(count: int, dry: bool) -> int:
    existing = open_publish_pr()
    if existing:
        print(
            f"a vault-sync PR is already open (#{existing}); not opening another. "
            "Merge or close it, then re-run."
        )
        return 1

    stamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
    branch = f"vault-sync/{stamp}"

    # Branch from main, not from wherever the clone was left. A publish run that
    # started on a feature branch would sweep that whole branch into the PR and
    # merge it to the live site as a side effect of someone editing a post on
    # their phone. Being on main also means the repo-to-vault direction compares
    # against what is actually published rather than against unmerged work.
    if run(["git", "status", "--porcelain"], check=False).stdout.strip():
        print("the repo has uncommitted changes; refusing to publish from a dirty tree")
        return 1
    run(["git", "checkout", "main"])
    run(["git", "pull", "--ff-only"])

    dirty = run(["git", "status", "--porcelain", "--", "src/", "public/"]).stdout.strip()
    if not dirty:
        print("nothing staged for the site; vault changes did not alter the repo")
        return 0

    if dry:
        print(f"would publish {count} file(s) on branch {branch}")
        print(dirty)
        return 0

    print("building locally before opening anything...")
    ok, err = build_ok()
    if not ok:
        print("BUILD FAILED - not publishing. Fix the content and re-run.\n")
        print(err)
        notify(f"Website publish blocked: the build failed.\n\n{err[-800:]}")
        return 1
    print("  build passed")

    run(["git", "checkout", "-b", branch])
    try:
        run(["git", "add", "--", "src/", "public/"])
        run(["git", "commit", "-m", f"Publish vault edits ({stamp})"])
        run(["git", "push", "-u", "origin", branch])
        pr = run(
            [
                "gh", "pr", "create",
                "--title", f"Publish vault edits ({stamp})",
                "--body",
                (
                    "Automated by `website_publish.py`. Content edited in the Obsidian "
                    "vault, copied into the repo, built locally, and opened here so CI "
                    "can gate it before it reaches the live site."
                ),
            ]
        ).stdout.strip()
        print(f"  opened {pr}")

        print("  waiting for CI...")
        checks = subprocess.run(
            ["gh", "pr", "checks", branch, "--watch", "--interval", "20"],
            cwd=REPO,
            text=True,
            capture_output=True,
            check=False,
        )
        if checks.returncode != 0:
            print("CI FAILED - the PR stays open for you to look at.\n")
            print(checks.stdout[-2000:])
            notify(f"Website publish stopped: CI failed.\n{pr}")
            return 1

        run(["gh", "pr", "merge", branch, "--squash", "--delete-branch"])
        run(["git", "checkout", "main"], check=False)
        run(["git", "pull", "--ff-only"], check=False)
        print("  merged; Netlify will deploy from main")
        notify(f"Website published: {count} file(s) live shortly.\n{pr}")
    finally:
        run(["git", "checkout", "main"], check=False)
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument(
        "command",
        nargs="?",
        default="status",
        choices=["status", "sync", "publish", "index", "adopt-repo", "adopt-vault"],
        help=(
            "status: report only (default). sync: copy. publish: sync, PR, merge on "
            "green. index: regenerate the vault README without copying anything. "
            "adopt-repo / adopt-vault: declare that side authoritative for every "
            "differing file and reset the baseline - for a first run, or after "
            "resolving conflicts by hand."
        ),
    )
    ap.add_argument("--dry-run", action="store_true", help="say what would happen, change nothing")
    ap.add_argument(
        "--obsidian-sync",
        action="store_true",
        help="run `ob sync` first, so the vault reflects the phone before comparing",
    )
    args = ap.parse_args()

    for path, what in ((VAULT, "vault"), (REPO, "repo")):
        if not path.is_dir():
            print(f"error: {what} not found at {path}", file=sys.stderr)
            return 2

    if args.obsidian_sync:
        print("running ob sync...")
        proc = subprocess.run(
            ["ob", "sync", "--path", str(VAULT.parent)],
            text=True,
            capture_output=True,
            check=False,
        )
        if proc.returncode != 0:
            # A stale vault is worse than a loud failure: it would publish an
            # old version of a post the phone has already changed.
            print(f"error: ob sync failed, refusing to compare a stale vault\n{proc.stderr}",
                  file=sys.stderr)
            return 2

    if args.command == "index":
        if not args.dry_run:
            write_readme()
        print(f"wrote {VAULT / 'README.md'}")
        return 0

    state = load_state()
    items = survey(state)
    report(items)

    if args.command in ("adopt-repo", "adopt-vault"):
        winner = "repo" if args.command == "adopt-repo" else "vault"
        moved = 0
        for key, vault, repo in pairs():
            src, dst = (repo, vault) if winner == "repo" else (vault, repo)
            if sha(src) is None or sha(src) == sha(dst):
                continue
            if not args.dry_run:
                copy(src, dst)
            moved += 1
        if not args.dry_run:
            record_agreed(state)
            save_state(state)
        print(f"\nadopted the {winner} side for {moved} file(s); baseline reset")
        return 0

    conflicts = [i for i in items if i.action in (CONFLICT, GONE, NO_OPT_IN)]
    if args.command == "status":
        return 1 if conflicts else 0

    to_repo, to_vault = do_sync(items, state, args.dry_run)
    if not args.dry_run:
        write_readme()
        seeded = record_agreed(state)
        save_state(state)
        if seeded:
            print(f"recorded {seeded} already-matching file(s) as the agreed baseline")
    print(f"\ncopied {to_repo} into the repo, {to_vault} into the vault")
    if conflicts:
        print(f"{len(conflicts)} file(s) skipped and left for you; resolve them by hand")

    if args.command == "publish":
        if to_repo == 0:
            print("no vault edits to publish")
            return 1 if conflicts else 0
        return do_publish(to_repo, args.dry_run) or (1 if conflicts else 0)
    return 1 if conflicts else 0


if __name__ == "__main__":
    sys.exit(main())
