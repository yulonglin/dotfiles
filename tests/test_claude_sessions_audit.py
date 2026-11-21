"""claude-sessions-audit must fail closed: never call unlanded worktree work "complete".

A false "complete" leads a sweep to `claude rm`, which deletes the worktree; its
unpushed-commit guard does not cover work that is pushed but unmerged.
"""

from __future__ import annotations

import importlib.machinery
import importlib.util
import subprocess
import sys
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
