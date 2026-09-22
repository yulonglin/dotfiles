#!/usr/bin/env bash
#
# Keeps `dotfiles-sync` from being broken by vendored content under claude/skills/.
#
# claude/skills/.gitignore ignores everything and then re-includes any file with
# an extension, because personal skill content always has one. That rule also
# re-includes whatever Claude Code and Codex drop in at runtime, so each such
# directory has to be named in the deny list. Three have been needed so far:
# .system/, anthropic-style-workspace/ and synced/.
#
# Missing one is not a cosmetic problem. The pre-commit hard-wrap gate covers
# every staged '^claude/.*\.md$', vendored SKILL.md files are routinely
# hard-wrapped, and dotfiles-sync stages everything it finds -- so one
# unignored vendor directory rejects the auto-commit on every run, for ever.
# DOTFILES_SYNC_HOLD_BACK only ever retries without claude/settings.json, so
# nothing recovers it. That is exactly how sync stayed broken from 2026-09-20.
#
# Test 1 pins the three known directories. Test 2 is the canary that catches the
# next one: anything under claude/skills/ that git would let a sync stage must
# already satisfy the gate that would judge it.

set -u

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || { echo "FATAL: cannot cd to $REPO_ROOT" >&2; exit 1; }

PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); echo "ok   - $1"; }
fail() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }

echo "## known runtime/vendor directories are ignored"
# git check-ignore matches a path against the rules and does not require the
# path to exist, so this is meaningful in a worktree and in CI, where these
# runtime directories are absent.
for d in .system anthropic-style-workspace synced; do
    if git check-ignore -q "claude/skills/$d/"; then
        pass "claude/skills/$d/ is ignored"
    else
        fail "claude/skills/$d/ is NOT ignored -- a sync would stage it"
    fi
done

echo "## canary: nothing a sync could stage under claude/skills/ fails the hard-wrap gate"
# Files git neither tracks nor ignores are exactly what dotfiles-sync would add.
mapfile -t STAGEABLE < <(git ls-files --others --exclude-standard -- 'claude/skills/*.md' 2>/dev/null)

if [[ ${#STAGEABLE[@]} -eq 0 ]]; then
    pass "no untracked Markdown under claude/skills/ (nothing for a sync to stage)"
else
    checker=""
    if [[ -x "$REPO_ROOT/custom_bins/md-unwrap" ]]; then
        checker="$REPO_ROOT/custom_bins/md-unwrap"
    elif command -v md-unwrap >/dev/null 2>&1; then
        checker="md-unwrap"
    fi

    if [[ -z "$checker" ]]; then
        echo "skip - md-unwrap unavailable; cannot evaluate ${#STAGEABLE[@]} untracked file(s)"
    elif "$checker" --check "${STAGEABLE[@]}" >/dev/null 2>&1; then
        pass "${#STAGEABLE[@]} untracked Markdown file(s) pass the hard-wrap gate"
    else
        fail "untracked Markdown under claude/skills/ is hard-wrapped, so the next dotfiles-sync commit will be rejected; add its directory to the deny list in claude/skills/.gitignore"
        printf '       %s\n' "${STAGEABLE[@]:0:5}"
        [[ ${#STAGEABLE[@]} -gt 5 ]] && echo "       ... and $(( ${#STAGEABLE[@]} - 5 )) more"
    fi
fi

echo
echo "passed: $PASS, failed: $FAIL"
[[ $FAIL -eq 0 ]]
