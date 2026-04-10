#!/bin/bash
set -euo pipefail

# PreToolUse(Bash) hook: enforce fetch-before-commit to prevent post-commit
# sync contamination.
#
# The problem this solves:
#   1. You commit local changes
#   2. git pull --rebase fails (sandbox, conflicts, etc.)
#   3. Working tree is silently contaminated with remote's old content
#   4. You blindly commit the contaminated files → regression
#
# The fix: block git commit when remote has unpulled commits. This forces
# the sync to happen FIRST (while local changes are still uncommitted and
# safe), so you can compare and resolve divergence cleanly.
#
# Also blocks if a sync recently failed (POST_SYNC_GUARD marker from
# mark_failed_sync.sh), since the working tree may be contaminated.

input=$(cat)
command=$(echo "$input" | jq -r '.tool_input.command // ""')

[[ -z "$command" ]] && exit 0

# Only trigger on git commit commands
if ! [[ "$command" =~ ^[[:space:]]*(git[[:space:]]+commit) ]]; then
    exit 0
fi

git_dir=$(git rev-parse --git-dir 2>/dev/null) || exit 0

# --- Check 1: Did a sync recently fail? ---
# Block hard — working tree may be contaminated.

if [[ -d "$git_dir/rebase-merge" ]] || [[ -d "$git_dir/rebase-apply" ]] || [[ -f "$git_dir/MERGE_HEAD" ]]; then
    cat <<WARN
{
  "decision": "block",
  "reason": "SYNC GUARD: A rebase or merge is in progress. Resolve or abort it before committing.\n\nCheck: git status\nAbort rebase: git rebase --abort\nAbort merge: git merge --abort"
}
WARN
    exit 0
fi

marker="$git_dir/POST_SYNC_GUARD"
if [[ -f "$marker" ]]; then
    marker_age=$(( $(date +%s) - $(stat -f %m "$marker" 2>/dev/null || stat -c %Y "$marker" 2>/dev/null || echo 0) ))
    if (( marker_age < 300 )); then
        cat <<WARN
{
  "decision": "block",
  "reason": "SYNC GUARD: A git pull/rebase/merge failed in the last 5 minutes. The working tree may contain remote content that overwrites your local changes.\n\nBefore committing:\n1. git diff  — check each dirty file for regressions\n2. git checkout HEAD -- <file>  — restore your version if needed\n3. rm $marker  — dismiss this guard if you've verified everything"
}
WARN
        exit 0
    else
        rm -f "$marker"
    fi
fi

# --- Check 2: Remote ahead? Force sync first. ---
# Uses locally cached refs (from prior fetch). Doesn't fetch here — that
# would be slow and could fail (network). The commit-push-sync skill and
# normal workflow already fetch before pushing.

upstream=$(git rev-parse --abbrev-ref '@{u}' 2>/dev/null) || exit 0
behind=$(git rev-list --count 'HEAD..@{u}' 2>/dev/null) || exit 0

if (( behind > 0 )); then
    # Warn but don't block — committing first then pulling/merging is fine.
    # Blocking creates a deadlock when sandbox prevents stash/pull with dirty files.
    echo "SYNC GUARD: Remote ($upstream) has $behind unpulled commit(s). Remember to pull after committing." >&2
    exit 0
fi

exit 0
