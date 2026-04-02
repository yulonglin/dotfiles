#!/bin/bash
set -euo pipefail

# PreToolUse(Bash) hook: block git commit after a failed rebase/merge
# when staged files may contain regressions (remote's old content instead of local changes).
#
# Mechanism:
# 1. Detects `git commit` commands
# 2. Checks if a rebase or merge recently failed (marker files in .git/)
# 3. If so, compares staged changes against the previous commit
# 4. BLOCKS if any staged file appears to REMOVE lines that were ADDED in the previous commit
#    (i.e., the staged diff is the inverse of the previous commit's diff for that file)

input=$(cat)
command=$(echo "$input" | jq -r '.tool_input.command // ""')

[[ -z "$command" ]] && exit 0

# Only trigger on git commit commands (not git add, git status, etc.)
if ! [[ "$command" =~ ^[[:space:]]*(git[[:space:]]+commit) ]]; then
    exit 0
fi

# Check if we're in a git repo
git_dir=$(git rev-parse --git-dir 2>/dev/null) || exit 0

# Check for signs of a recently failed rebase or merge:
# - .git/rebase-merge/ or .git/rebase-apply/ exist (rebase in progress or just aborted)
# - .git/MERGE_HEAD exists (merge in progress)
# - .git/REBASE_ABORT_SAFETY file (left after some aborts)
# Also check if the last git operation was a pull that failed (heuristic: look at reflog)
failed_sync=false

if [[ -d "$git_dir/rebase-merge" ]] || [[ -d "$git_dir/rebase-apply" ]] || [[ -f "$git_dir/MERGE_HEAD" ]]; then
    failed_sync=true
fi

# Also check: was a rebase/merge recently aborted? Look for our marker.
marker="$git_dir/POST_SYNC_GUARD"
if [[ -f "$marker" ]]; then
    # Marker exists — a sync operation failed recently in this session
    marker_age=$(( $(date +%s) - $(stat -f %m "$marker" 2>/dev/null || stat -c %Y "$marker" 2>/dev/null || echo 0) ))
    if (( marker_age < 300 )); then  # Within 5 minutes
        failed_sync=true
    else
        rm -f "$marker"
    fi
fi

if ! $failed_sync; then
    exit 0
fi

# We're committing after a failed sync. Check if any staged files are regressions.
# Get the list of staged files
staged_files=$(git diff --cached --name-only 2>/dev/null) || exit 0
[[ -z "$staged_files" ]] && exit 0

# Get the previous commit's changed files
prev_commit_files=$(git diff-tree --no-commit-id --name-only -r HEAD 2>/dev/null) || exit 0

# Find overlap: files that were in the previous commit AND are now staged
overlap=""
while IFS= read -r file; do
    if echo "$prev_commit_files" | grep -qxF "$file"; then
        overlap="$overlap $file"
    fi
done <<< "$staged_files"

[[ -z "$overlap" ]] && exit 0

# For overlapping files, check if the staged diff is reverting the previous commit
regression_files=""
for file in $overlap; do
    # What did the previous commit add to this file?
    prev_added=$(git diff HEAD~1 HEAD -- "$file" 2>/dev/null | grep '^+[^+]' | wc -l)
    # What does the staged diff remove from this file?
    staged_removed=$(git diff --cached HEAD -- "$file" 2>/dev/null | grep '^-[^-]' | wc -l)
    staged_added=$(git diff --cached HEAD -- "$file" 2>/dev/null | grep '^+[^+]' | wc -l)

    # Heuristic: if staged diff REMOVES more than it ADDS, and the removals are
    # similar in count to what the previous commit ADDED, this is likely a regression
    if (( staged_removed > 0 && staged_added < staged_removed && prev_added > 0 )); then
        # More specific: check if lines added in prev commit are being removed
        ratio=$(( staged_removed * 100 / (prev_added + 1) ))
        if (( ratio > 50 )); then
            regression_files="$regression_files $file"
        fi
    fi
done

if [[ -n "$regression_files" ]]; then
    cat <<WARN
{
  "decision": "block",
  "reason": "REGRESSION GUARD: A rebase/merge recently failed, and these staged files appear to REVERT changes from your previous commit (HEAD): ${regression_files}\n\nThis is likely working tree contamination from the failed sync — the remote's old content replaced your local changes.\n\nBefore committing:\n1. Run: git diff --cached HEAD -- <file> (check if YOUR additions are being removed)\n2. Restore your version: git checkout HEAD -- <file>\n3. Or if intentional, create the marker: rm $git_dir/POST_SYNC_GUARD"
}
WARN
    exit 0
fi

# Files overlap but don't look like regressions — allow with a nudge
exit 0
