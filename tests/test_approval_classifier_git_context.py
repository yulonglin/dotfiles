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


def test_multi_ref_modes_report_unknown_destination(ac, repo):
    """`git push --all origin` updates every branch, including main from a
    feature branch — a single destination line would be a lie (Codex P1 r6)."""
    for form in ("git push --all origin", "git push --mirror origin",
                 "git push origin --tags", "git push --prune origin"):
        ctx = ac._git_push_context(form, str(repo))
        assert "push destination: unknown" in ctx, form
        assert "commits being pushed" not in ctx, form


def test_configured_push_refspecs_report_unknown_destination(ac, repo):
    _git(repo, "config", "remote.origin.push", "refs/heads/*:refs/heads/*")
    ctx = ac._git_push_context("git push", str(repo))
    assert "push destination: unknown" in ctx
    assert "configured push refspecs" in ctx


def test_plus_refspec_marker_counts_as_force(ac, repo):
    """`+refspec` is git's force-update marker (Codex P1 r6)."""
    ctx = ac._git_push_context("git push origin +main:main", str(repo))
    assert "force flags present: +main:main" in ctx


def test_directory_and_repo_redirection_yield_no_block(ac, repo):
    """`cd x && git push`, `--git-dir`, and `GIT_DIR=` run the push against a
    repo the probes can't see — no block, which the rules map to `unsure`."""
    assert ac._git_push_context("cd ../elsewhere && git push", str(repo)) == ""
    assert ac._git_push_context("git --git-dir=../x/.git push", str(repo)) == ""
    assert ac._git_push_context("git --git-dir ../x/.git push", str(repo)) == ""
    assert ac._git_push_context("GIT_DIR=../x/.git git push", str(repo)) == ""


def test_repo_option_selects_the_remote(ac, repo):
    """`--repo upstream` is a remote selector (used when no positional names
    the repository); defaulting to origin would advertise a push to a shared
    remote as origin/<branch> (Codex P1 r6)."""
    for form in ("git push --repo upstream", "git push --repo=upstream"):
        ctx = ac._git_push_context(form, str(repo))
        assert "push destination: upstream/main" in ctx, form
        # `upstream` isn't configured in this repo — the URL must say so
        assert "remote push URL (upstream): unknown" in ctx, form


def test_remote_url_reported_for_trust_judgement(ac, repo, tmp_path):
    """The personal-repo rule judges ownership from the remote URL; the block
    reports the URL of the repo the push actually targets, and flags when
    that repo differs from the session working directory (Codex P1 r6)."""
    ctx = ac._git_push_context("git push", str(repo))
    assert f"remote push URL (origin): {tmp_path / 'origin.git'}" in ctx
    assert "DIFFERENT repository" not in ctx

    other = tmp_path / "other"
    subprocess.run(["git", "init", "-b", "main", str(other)],
                   check=True, capture_output=True, text=True)
    ctx = ac._git_push_context(f"git -C {repo} push", str(other))
    assert f"remote push URL (origin): {tmp_path / 'origin.git'}" in ctx
    assert "DIFFERENT repository" in ctx


def test_command_local_config_overrides_yield_no_block(ac, repo):
    """`git -c remote.origin.push=HEAD:main push` redefines the push in config
    the probes can't see — no block, which the rules map to `unsure` (Codex P1 r7)."""
    assert ac._git_push_context(
        "git -c remote.origin.push=HEAD:main push", str(repo)) == ""
    assert ac._git_push_context(
        "git --config-env=remote.origin.push=VAR push", str(repo)) == ""


def test_push_default_matching_degrades_to_unknown(ac, repo):
    """push.default=matching makes a bare push update every matching branch —
    naming only the current branch's upstream would mislead (Codex P1 r7)."""
    _git(repo, "config", "push.default", "matching")
    ctx = ac._git_push_context("git push", str(repo))
    assert "push destination: unknown" in ctx
    assert "commits being pushed" not in ctx


def test_configured_push_remote_is_honored(ac, repo, tmp_path):
    """remote.pushDefault (and branch.<name>.pushRemote) reroute a bare push
    away from the fetch upstream; the destination must follow git's own
    resolution, not default to origin (Codex P1 r7)."""
    shared = tmp_path / "shared.git"
    subprocess.run(["git", "init", "--bare", "-b", "main", str(shared)],
                   check=True, capture_output=True, text=True)
    _git(repo, "remote", "add", "shared", str(shared))
    _git(repo, "fetch", "shared")
    _git(repo, "config", "remote.pushDefault", "shared")
    ctx = ac._git_push_context("git push", str(repo))
    assert "push destination: shared/main" in ctx
    assert f"remote push URL (shared): {shared}" in ctx


def test_default_branch_read_from_destination_remote(ac, repo, tmp_path):
    """`git push upstream trunk` must be judged against upstream's default
    branch, not origin's (Codex P1 r7)."""
    upstream = tmp_path / "upstream.git"
    subprocess.run(["git", "init", "--bare", "-b", "trunk", str(upstream)],
                   check=True, capture_output=True, text=True)
    _git(repo, "remote", "add", "upstream", str(upstream))
    _git(repo, "push", "upstream", "main:trunk")
    _git(repo, "remote", "set-head", "upstream", "trunk")
    ctx = ac._git_push_context("git push upstream main:trunk", str(repo))
    assert "default branch (upstream/HEAD): trunk" in ctx
    assert "push destination: upstream/trunk" in ctx


def test_pushurl_reported_instead_of_fetch_url(ac, repo, tmp_path):
    """remote.<name>.pushurl is where the push actually writes; reporting the
    fetch URL would misstate ownership (Codex P1 r7). Multiple push URLs are
    all updated by one push, so all must be shown and flagged."""
    _git(repo, "remote", "set-url", "--push", "origin", "/elsewhere/repo.git")
    ctx = ac._git_push_context("git push", str(repo))
    assert "remote push URL (origin): /elsewhere/repo.git" in ctx
    assert str(tmp_path / "origin.git") not in ctx

    _git(repo, "remote", "set-url", "--push", "--add", "origin", "/second/repo.git")
    ctx = ac._git_push_context("git push", str(repo))
    assert "MULTIPLE" in ctx
    assert "/elsewhere/repo.git" in ctx and "/second/repo.git" in ctx


def test_credentials_redacted_from_push_urls(ac, repo):
    """Remote URLs can embed HTTPS credentials; the block is sent to the
    classifier backends, so userinfo must never enter the prompt (Codex P1 r7)."""
    _git(repo, "remote", "add", "cred", "https://user:sekret-token@example.com/x.git")
    ctx = ac._git_push_context("git push cred main", str(repo))
    assert "sekret-token" not in ctx
    assert "remote push URL (cred): https://example.com/x.git" in ctx


def test_branch_remote_without_upstream_is_honored(ac, repo, tmp_path):
    """For a bare push, branch.<name>.remote follows pushRemote and
    remote.pushDefault in Git's precedence even without branch.<name>.merge
    (focused review after Codex r8)."""
    shared = tmp_path / "shared.git"
    subprocess.run(["git", "init", "--bare", "-b", "main", str(shared)],
                   check=True, capture_output=True, text=True)
    _git(repo, "remote", "add", "shared", str(shared))
    _git(repo, "switch", "-c", "topic")
    _git(repo, "config", "branch.topic.remote", "shared")
    _git(repo, "config", "push.default", "current")
    ctx = ac._git_push_context("git push", str(repo))
    assert "push destination: shared/topic" in ctx
    assert f"remote push URL (shared): {shared}" in ctx


def test_shell_expanded_destination_yields_no_block(ac, repo):
    """shlex cannot prove whether expansion syntax was quoted literally. Any
    token the shell can rewrite after the hook runs must fail closed rather than
    advertise a literal feature destination while executing a main push."""
    for form in (
        'git push origin "${DEST:-main}"',
        "git push origin $(printf main)",
        "git push origin 'release-*'",
        "git push ~/other main",
        "git push origin feature-{a,b}",
    ):
        assert ac._git_push_context(form, str(repo)) == "", form


def test_abbreviated_multi_ref_modes_report_unknown(ac, repo):
    """Git accepts unique long-option prefixes (`git push -h`, git 2.43).
    Abbreviated mirror/all/tags/prune must not look like a single-ref push."""
    for form in (
        "git push --mir origin",
        "git push --al origin",
        "git push --ta origin",
        "git push --pru origin",
    ):
        ctx = ac._git_push_context(form, str(repo))
        assert "push destination: unknown" in ctx, form
        assert "commits being pushed" not in ctx, form


def test_prior_shell_state_and_wrappers_yield_no_block(ac, repo):
    """The probes run before the shell. Earlier statements, env assignments,
    and wrappers can alter Git state/config before the push executes, so only a
    direct git invocation in the first statement is modelled (Codex P1 r8)."""
    assert ac._git_push_context(
        "git config remote.origin.push HEAD:main && git push", str(repo)) == ""
    assert ac._git_push_context(
        "GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=push.default "
        "GIT_CONFIG_VALUE_0=matching git push", str(repo)) == ""
    assert ac._git_push_context("env GIT_DIR=../x/.git git push", str(repo)) == ""


def test_explicit_remote_upstream_mode_uses_tracked_branch(ac, repo):
    """With push.default=upstream, `git push origin` updates the tracked remote
    branch, whose name need not match the local branch (Codex P1 r8)."""
    _git(repo, "switch", "-c", "topic", "--track", "origin/main")
    _git(repo, "config", "push.default", "upstream")
    ctx = ac._git_push_context("git push origin", str(repo))
    assert "current branch: topic" in ctx
    assert "push destination: origin/main" in ctx


def test_bundled_destructive_flags_are_surfaced(ac, repo):
    """Git accepts bundled short flags; `-fq` and `-dq` must retain their
    destructive force/delete semantics in the context block (Codex P1 r8)."""
    forced = ac._git_push_context("git push -fq origin main", str(repo))
    assert "force flags present: -fq" in forced

    deleted = ac._git_push_context("git push -dq origin topic", str(repo))
    assert "push destination: origin/topic (ref DELETION)" in deleted

    # Unambiguous long-option abbreviations accepted by git must also fail
    # toward safety (`git push -h`, git 2.43: --force-w / --dele accepted;
    # --forc is ambiguous and rejected, so it is deliberately not the test).
    assert "force flags present: --force-w" in ac._git_push_context(
        "git push --force-w origin main", str(repo))
    assert "(ref DELETION)" in ac._git_push_context(
        "git push --dele origin topic", str(repo))


def test_recurse_submodules_operand_not_mistaken_for_remote(ac, repo):
    ctx = ac._git_push_context(
        "git push --recurse-submodules on-demand origin main", str(repo))
    assert "push destination: origin/main" in ctx


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
