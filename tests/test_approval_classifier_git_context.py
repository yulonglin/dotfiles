#!/usr/bin/env python3
"""Tests: the classifier injects deterministic git state when classifying pushes.

Why this file exists. The push rules in approval_classifier_rules.md distinguish
the default branch from feature branches and trivial pushes from substantive
ones — but a bare `git push` names no branch and carries no diff, and
build_classify_user_msg used to send only the command, cwd, and recent
messages. The model was being asked to apply a branch-sensitive rule with no
branch in sight (Codex P1 on PR #68). The fix gathers the facts with git and
injects a "Git context" block; these tests pin that the block exists, is
accurate against a real repo, and degrades toward "unknown" (which the rules
map to `unsure`, i.e. a manual prompt) rather than guessing.

Real git repos in tmp_path, no mocks: the failure mode being guarded is a
mismatch between what git actually reports and what the prompt claims.
"""
import importlib.util
import os
import pathlib
import subprocess
import sys

import pytest

ROOT = pathlib.Path(__file__).resolve().parent.parent
HOOK = pathlib.Path(
    os.environ.get("APPROVAL_CLASSIFIER_PATH")
    or ROOT / "claude" / "hooks" / "approval_classifier.py"
)


def load_module():
    spec = importlib.util.spec_from_file_location("approval_classifier", HOOK)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


@pytest.fixture(scope="module")
def ac():
    return load_module()


def _git(cwd, *args):
    subprocess.run(
        ["git", "-C", str(cwd), *args],
        check=True, capture_output=True, text=True,
    )


@pytest.fixture()
def repo(tmp_path):
    """A clone with a real origin, one pushed commit, and origin/HEAD set."""
    origin = tmp_path / "origin.git"
    subprocess.run(
        ["git", "init", "--bare", "-b", "main", str(origin)],
        check=True, capture_output=True, text=True,
    )
    work = tmp_path / "work"
    subprocess.run(
        ["git", "clone", str(origin), str(work)],
        check=True, capture_output=True, text=True,
    )
    _git(work, "config", "user.email", "test@test")
    _git(work, "config", "user.name", "test")
    (work / "f.txt").write_text("one\n")
    _git(work, "add", "f.txt")
    _git(work, "commit", "-m", "initial commit")
    _git(work, "push", "-u", "origin", "main")
    _git(work, "remote", "set-head", "origin", "main")
    return work


def test_non_push_commands_get_no_block(ac, repo):
    assert ac._git_push_context("git status && ls", str(repo)) == ""
    # `push` beyond a statement separator is a different command, not this push
    assert ac._git_push_context("git status; other push", str(repo)) == ""


def test_push_on_default_branch_reports_branch_and_pending_commit(ac, repo):
    (repo / "f.txt").write_text("two\n")
    _git(repo, "commit", "-am", "substantive change to f")

    ctx = ac._git_push_context("git push", str(repo))
    assert "current branch: main" in ctx
    assert "default branch (origin/HEAD): main" in ctx
    # The commit subject is what lets the model judge trivial vs substantive
    assert "substantive change to f" in ctx
    assert "diffstat:" in ctx


def test_push_on_feature_branch_without_upstream_uses_origin_default(ac, repo):
    _git(repo, "switch", "-c", "feature-x")
    (repo / "g.txt").write_text("new\n")
    _git(repo, "add", "g.txt")
    _git(repo, "commit", "-m", "feature work")

    ctx = ac._git_push_context("git push -u origin feature-x", str(repo))
    assert "current branch: feature-x" in ctx
    assert "default branch (origin/HEAD): main" in ctx
    # No upstream yet -> compared against origin/<default>
    assert "origin/main..HEAD" in ctx
    assert "feature work" in ctx


def test_push_with_nothing_ahead_says_so(ac, repo):
    ctx = ac._git_push_context("git push", str(repo))
    assert "no commits ahead of origin/main" in ctx


def test_degrades_to_unknown_when_git_fails(ac, tmp_path):
    """The rules send 'unknown' to `unsure`; the block must not vanish or guess.

    A nonexistent cwd makes every git call fail, which is the same degraded
    shape as a broken repo. (An existing empty dir won't do here: pytest's
    tmp_path can land inside this very repo, and git walks up.)
    """
    ctx = ac._git_push_context("git push", str(tmp_path / "does-not-exist"))
    assert "current branch: (unknown or detached)" in ctx
    assert "default branch (origin/HEAD): unknown" in ctx


def test_user_msg_carries_block_only_for_push_commands(ac, repo):
    with_push = ac.build_classify_user_msg(
        "Bash", {"command": "git push"}, str(repo))
    assert "Git context" in with_push

    without_push = ac.build_classify_user_msg(
        "Bash", {"command": "ls -la"}, str(repo))
    assert "Git context" not in without_push

    # Non-Bash tools never trigger git subprocesses
    edit = ac.build_classify_user_msg(
        "Edit", {"file_path": "git push notes.md"}, str(repo))
    assert "Git context" not in edit


if __name__ == "__main__":
    sys.exit(pytest.main([__file__, "-v"]))
