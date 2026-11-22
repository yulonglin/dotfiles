"""claude-sessions-audit must fail closed: never call unlanded worktree work "complete".

A false "complete" leads a sweep to `claude rm`, which deletes the worktree; its
unpushed-commit guard does not cover work that is pushed but unmerged.
"""

from __future__ import annotations

import importlib.machinery
import importlib.util
import json
import subprocess
import sys
from datetime import UTC, datetime, timedelta
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "custom_bins" / "claude-sessions-audit"


def load_module():
    loader = importlib.machinery.SourceFileLoader("claude_sessions_audit", str(SCRIPT))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[loader.name] = mod  # dataclasses resolve types via sys.modules
    loader.exec_module(mod)
    return mod


audit = load_module()


def sh(cwd: Path, *args: str) -> str:
    return subprocess.run(
        ["git", "-C", str(cwd), *args], check=True, capture_output=True, text=True
    ).stdout.strip()


def make_repo(tmp_path: Path) -> tuple[Path, Path]:
    """A clone with origin/main, plus a feature branch pushed with one new commit."""
    remote, work = tmp_path / "remote.git", tmp_path / "work"
    subprocess.run(
        ["git", "init", "-q", "--bare", "-b", "main", str(remote)], check=True
    )
    subprocess.run(["git", "clone", "-q", str(remote), str(work)], check=True)
    for k, v in (
        ("user.email", "t@t"),
        ("user.name", "t"),
        ("commit.gpgsign", "false"),
    ):
        sh(work, "config", k, v)
    (work / "a.txt").write_text("base\n")
    sh(work, "add", "a.txt")
    sh(work, "commit", "-qm", "base", "--no-verify")
    sh(work, "push", "-q", "origin", "main")
    sh(work, "remote", "set-head", "origin", "main")
    sh(work, "checkout", "-qb", "feature")
    (work / "b.txt").write_text("feature\n")
    sh(work, "add", "b.txt")
    sh(work, "commit", "-qm", "feature", "--no-verify")
    sh(work, "push", "-q", "origin", "feature")
    return remote, work


def job_with(wt) -> object:
    return audit.Job(id="x", name="x", state="done", updated="", result="", worktree=wt)


def test_pushed_unmerged_branch_is_not_complete(tmp_path, monkeypatch):
    _, work = make_repo(tmp_path)
    monkeypatch.setattr(audit, "pr_state", lambda *_: None)
    wt = audit.inspect_worktree(str(work), "feature", prs=True)
    assert wt.landed is False and wt.pushed
    assert audit.verdict(job_with(wt))[0] == "unmerged"


def test_merged_pr_for_an_older_head_does_not_certify_new_commits(
    tmp_path, monkeypatch
):
    _, work = make_repo(tmp_path)
    old_head = sh(work, "rev-parse", "HEAD")
    (work / "c.txt").write_text("after the merge\n")
    sh(work, "add", "c.txt")
    sh(work, "commit", "-qm", "later work", "--no-verify")
    sh(work, "push", "-q", "origin", "feature")
    pr = {"number": 7, "state": "MERGED", "headRefOid": old_head, "baseRefName": "main"}
    monkeypatch.setattr(audit, "pr_state", lambda *_: pr)
    wt = audit.inspect_worktree(str(work), "feature", prs=True)
    assert wt.landed is False
    assert audit.verdict(job_with(wt))[0] == "unmerged"


def test_merged_pr_for_exactly_this_head_counts_as_landed(tmp_path, monkeypatch):
    _, work = make_repo(tmp_path)
    head = sh(work, "rev-parse", "HEAD")
    pr = {"number": 7, "state": "MERGED", "headRefOid": head, "baseRefName": "main"}
    monkeypatch.setattr(audit, "pr_state", lambda *_: pr)
    wt = audit.inspect_worktree(str(work), "feature", prs=True)
    assert wt.landed is True
    assert audit.verdict(job_with(wt))[0] == "complete"


def test_unknown_landing_evidence_is_check_not_complete(tmp_path):
    wt = audit.Worktree(
        path=str(tmp_path), branch="f", exists=True, base=None, landed=None
    )
    assert audit.verdict(job_with(wt))[0] == "check"


# --- closing markers and the digest, on a synthetic jobs directory -------------

NOW = datetime(2026, 1, 10, 12, 0, tzinfo=UTC)
SAFE = "✅ **Safe to close this session**"


def iso(dt: datetime) -> str:
    return dt.strftime("%Y-%m-%dT%H:%M:%S.000Z")


def write_job(
    jobs: Path,
    job_id: str,
    state: str,
    result: str = "",
    text: str = "",
    age: timedelta = timedelta(hours=1),
    worktree: Path | None = None,
    now: datetime = NOW,
) -> Path:
    """A fake ~/.claude/jobs/<id> with state.json and a one-entry timeline."""
    d = jobs / job_id
    d.mkdir(parents=True)
    at = iso(now - age)
    state_json = {
        "state": state,
        "name": f"synthetic {job_id}",
        "updatedAt": iso(now - timedelta(days=30)),  # timeline must win
        "output": {"result": result} if result else None,
        "detail": result,
    }
    if worktree:
        state_json["worktreePath"] = str(worktree)
        state_json["worktreeBranch"] = "feature"
    (d / "state.json").write_text(json.dumps(state_json))
    entry = {"at": at, "state": state, "detail": result, "text": text}
    (d / "timeline.jsonl").write_text(json.dumps(entry) + "\n")
    return d


def final_text(*lines: str, result: str) -> str:
    return "\n".join(["Did the synthetic thing.", *lines, f"result: {result}"])


def test_safe_marker_beats_follow_up_words(tmp_path):
    result = "fixture done; you need nothing, still fine"
    d = write_job(tmp_path, "safe1", "done", result, final_text(SAFE, result=result))
    j = audit.load(d, prs=False, now=NOW)
    assert j.follow_up  # the guessed words are still found ...
    assert j.marker == "safe"
    assert audit.verdict(j)[0] == "complete"  # ... but the explicit marker wins


def test_keep_open_marker_is_check_even_without_follow_up_words(tmp_path):
    result = "fixture shipped"
    text = final_text("⚠️ **Keep open:** synthetic review of item 2", result=result)
    j = audit.load(write_job(tmp_path, "keep1", "done", result, text), False, NOW)
    assert not j.follow_up
    assert (j.marker, j.keep_open) == ("keep", "synthetic review of item 2")
    assert audit.verdict(j)[0] == "check"
    assert audit.section(j) == "needs"


def test_keep_open_wins_when_both_markers_appear():
    text = f"⚠ Keep open: one thing\n{SAFE}\nresult: x"
    assert audit.find_marker(text, "x") == ("keep", "one thing")


def test_safe_marker_counts_only_as_the_footer_of_the_current_result():
    assert audit.find_marker(f"body\n{SAFE}\nresult: x", "x") == ("safe", "")
    assert audit.find_marker("✅ Safe to close this session\nresult: x", "x")[0] == (
        "safe"
    )
    # Discussed inline, not a whole line.
    discussed = f"The rule says to end with `{SAFE}` when done.\nresult: x"
    assert audit.find_marker(discussed, "x") == (None, "")
    # A whole line, but not directly above the result line.
    gap = f"{SAFE}\nOne more paragraph.\nresult: x"
    assert audit.find_marker(gap, "x") == (None, "")
    # An earlier turn's footer, followed by a later result that differs.
    stale = f"{SAFE}\nresult: old\nlater work\nresult: review pending"
    assert audit.find_marker(stale, "review pending") == (None, "")
    # The footer's result does not match the job's current result.
    assert audit.find_marker(f"{SAFE}\nresult: old", "review pending") == (None, "")
    # No terminal result line at all.
    assert audit.find_marker(f"body\n{SAFE}", "x") == (None, "")


def test_marker_ignored_unless_state_json_says_done(tmp_path):
    text = final_text(SAFE, result="x")
    j = audit.load(write_job(tmp_path, "f1", "failed", "x", text), False, NOW)
    assert j.marker is None
    assert audit.section(j) == "needs"


def test_safe_marker_never_beats_an_unlanded_worktree(tmp_path, monkeypatch):
    _, work = make_repo(tmp_path)
    monkeypatch.setattr(audit, "pr_state", lambda *_: None)
    jobs = tmp_path / "jobs"
    d = write_job(
        jobs,
        "wt1",
        "done",
        "fixture",
        final_text(SAFE, result="fixture"),
        worktree=work,
    )
    j = audit.load(d, prs=True, now=NOW)
    assert j.marker == "safe"
    assert audit.verdict(j)[0] == "unmerged"
    assert audit.section(j) == "needs"


def test_age_comes_from_the_timeline_and_falls_back_to_state(tmp_path):
    d = write_job(tmp_path, "a1", "working", age=timedelta(days=3, hours=2))
    j = audit.load(d, False, NOW)
    assert audit.fmt_age(j.age_seconds) == "3d"
    (d / "timeline.jsonl").write_text("")
    assert audit.fmt_age(audit.load(d, False, NOW).age_seconds) == "30d"
    assert [audit.fmt_age(s) for s in (59, 600, 7200, None)] == ["0m", "10m", "2h", "?"]


def test_every_job_lands_in_exactly_one_section(tmp_path):
    write_job(tmp_path, "blocked1", "blocked")
    write_job(tmp_path, "weird1", "some-new-state")
    write_job(tmp_path, "check1", "done", "await your merge")
    write_job(tmp_path, "new1", "done", "fixture finished", age=timedelta(hours=2))
    write_job(tmp_path, "old1", "done", "fixture finished", age=timedelta(days=4))
    write_job(tmp_path, "run1", "working", age=timedelta(minutes=5))
    write_job(tmp_path, "stall1", "working", age=timedelta(days=2))
    jobs = [audit.load(p, False, NOW) for p in sorted(tmp_path.iterdir())]
    got = {j.id: audit.section(j) for j in jobs}
    assert got == {
        "blocked1": "needs",
        "weird1": "needs",
        "check1": "needs",
        "new1": "new",
        "old1": "earlier",
        "run1": "progress",
        "stall1": "progress",
    }


def test_cli_digest_is_plain_when_piped_and_json_has_age(tmp_path):
    now = datetime.now(UTC)  # the CLI reads the real clock
    write_job(tmp_path, "new1", "done", "fixture done", age=timedelta(hours=2), now=now)
    write_job(tmp_path, "stall1", "working", age=timedelta(days=2), now=now)
    write_job(tmp_path, "blocked1", "blocked", now=now)
    cmd = [sys.executable, str(SCRIPT), "--jobs-dir", str(tmp_path), "--no-prs"]
    out = subprocess.run(cmd, capture_output=True, text=True, check=True).stdout
    assert "\033" not in out
    for title in ("Needs you (1)", "New (complete", "In progress (1)", "Done earlier"):
        assert title in out
    assert "stalled?" in out
    rows = json.loads(
        subprocess.run(
            [*cmd, "--json"], capture_output=True, text=True, check=True
        ).stdout
    )
    assert "\033" not in json.dumps(rows)
    assert {r["id"]: r["section"] for r in rows} == {
        "blocked1": "needs",
        "new1": "new",
        "stall1": "progress",
    }
    assert all(isinstance(r["age_seconds"], int) for r in rows)
