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
    assert "push destination: origin/feature-x" in ctx
    # No upstream yet -> compared against origin/<default>
    assert "origin/main..feature-x" in ctx
    assert "feature work" in ctx


def test_push_with_nothing_ahead_says_so(ac, repo):
    ctx = ac._git_push_context("git push", str(repo))
    assert "push destination: origin/main" in ctx
    assert "no commits ahead of origin/main" in ctx


def test_refspec_to_default_branch_reported_as_destination(ac, repo):
    """`git push origin HEAD:main` from a feature branch updates main —
    the destination line, not the current branch, must say so (Codex P1 r5)."""
    _git(repo, "switch", "-c", "feature-y")
    (repo / "f.txt").write_text("sneaky\n")
    _git(repo, "commit", "-am", "change aimed at main")

    ctx = ac._git_push_context("git push origin HEAD:main", str(repo))
    assert "current branch: feature-y" in ctx
    assert "push destination: origin/main" in ctx
    assert "change aimed at main" in ctx


def test_pushing_another_local_branch_uses_that_branch_for_commits(ac, repo):
    """`git push origin main` from a feature worktree pushes local main."""
    (repo / "f.txt").write_text("on main\n")
    _git(repo, "commit", "-am", "commit landed on main")
    _git(repo, "switch", "-c", "feature-z")

    ctx = ac._git_push_context("git push origin main", str(repo))
    assert "current branch: feature-z" in ctx
    assert "push destination: origin/main" in ctx
    assert "origin/main..main" in ctx
    assert "commit landed on main" in ctx


def test_dash_c_push_describes_the_target_repo(ac, repo, tmp_path):
    """`git -C <path> push` operates on <path>; the block must describe it,
    not the session cwd (which here is not a repo at all)."""
    outside = tmp_path / "not-a-repo"
    outside.mkdir()
    ctx = ac._git_push_context(f"git -C {repo} push", str(outside))
    assert "current branch: main" in ctx
    assert "push destination: origin/main" in ctx


def test_value_taking_option_not_mistaken_for_remote(ac, repo):
    ctx = ac._git_push_context("git push -o ci.skip origin main", str(repo))
    assert "push destination: origin/main" in ctx


def test_force_and_delete_forms_are_surfaced(ac, repo):
    forced = ac._git_push_context("git push --force-with-lease origin main", str(repo))
    assert "force flags present: --force-with-lease" in forced

    deleted = ac._git_push_context("git push origin --delete feature-x", str(repo))
    assert "push destination: origin/feature-x (ref DELETION)" in deleted


def test_unresolvable_forms_degrade_not_guess(ac, repo):
    # Quoted through another shell: the parser can't see inside — no block,
    # and the rules map an absent block to `unsure` for pushes.
    assert ac._git_push_context('bash -c "git push"', str(repo)) == ""
    # Several refspecs: don't pretend to know the destination that matters.
    ctx = ac._git_push_context("git push origin main feature-x", str(repo))
    assert "push destination: unknown" in ctx


def test_fast_path_cannot_allow_option_prefixed_git_writes(ac):
    """`git` is in the compound-safe allowlist gated by the unsafe denylist;
    global options between `git` and the subcommand must not defeat it
    (Codex P1 r5: `git -C x push` was auto-allowed as a safe compound)."""
    assert not ac._is_compound_shell_safe("git -C ../dotfiles push origin main")
    assert not ac._is_compound_shell_safe("git -c push.default=current push")
    assert not ac._is_compound_shell_safe("git -C /tmp/x reset --hard")
    assert not ac._is_compound_shell_safe("git push && echo done")
    # Read-only git compounds must stay on the fast path
    assert ac._is_compound_shell_safe("git status && git log --oneline")


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
