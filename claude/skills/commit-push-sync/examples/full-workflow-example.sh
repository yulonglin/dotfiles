#!/bin/bash
# Example: Full commit-push-sync workflow with smart pull strategy
# Demonstrates the decision tree for choosing merge vs rebase vs fast-forward

set -e  # Exit on error

echo "=== Commit-Push-Sync Workflow (Smart Pull Strategy) ==="
echo

# Step 1: Fetch and evaluate state
echo "Step 1: Fetch and evaluate state..."
echo

echo "Checking upstream tracking..."
UPSTREAM=$(git rev-parse --abbrev-ref @{u} 2>/dev/null) || {
  echo "No upstream tracking branch. Will push with -u after commit."
  echo "git push -u origin $(git branch --show-current)"
  UPSTREAM=""
}

if [ -n "$UPSTREAM" ]; then
  # Fetch the correct remote (not hardcoded origin — @{u} may point elsewhere)
  UPSTREAM_REMOTE=$(echo "$UPSTREAM" | cut -d/ -f1)
  echo "Upstream: $UPSTREAM (remote: $UPSTREAM_REMOTE)"
  echo
  echo "Fetching from $UPSTREAM_REMOTE (MUST succeed or abort)..."
  git fetch "$UPSTREAM_REMOTE" || { echo "FATAL: fetch failed — aborting workflow"; exit 1; }
  echo

  # Gather state (these would run in parallel in Claude)
  echo "Local-only commits (ahead):"
  git log @{u}.. --oneline || echo "  (none)"

  echo
  echo "Remote-only commits (behind):"
  git log ..@{u} --oneline || echo "  (none)"

  echo
  echo "Merge commits in local history:"
  git log @{u}.. --merges --oneline || echo "  (none)"

  # Classify state
  LOCAL_COUNT=$(git log @{u}.. --oneline 2>/dev/null | wc -l | tr -d ' ')
  REMOTE_COUNT=$(git log ..@{u} --oneline 2>/dev/null | wc -l | tr -d ' ')
  MERGE_COUNT=$(git log @{u}.. --merges --oneline 2>/dev/null | wc -l | tr -d ' ')

  echo
  echo "State: $LOCAL_COUNT ahead, $REMOTE_COUNT behind, $MERGE_COUNT merge commits"
fi

echo
echo "---"
echo

# Step 2: Commit changes (if needed)
echo "Step 2: Committing changes (if any)..."
echo

if ! git diff-index --quiet HEAD -- 2>/dev/null; then
  echo "Found uncommitted changes. Gathering context..."

  echo "Running git status..."
  git status

  echo
  echo "Drafting commit message..."
  echo "Example: 'feat: add smart pull strategy to commit-push-sync'"

  echo
  echo "Staging and committing (sandbox-safe, no heredoc)..."
  echo 'Example:'
  echo '  git add SKILL.md references/ examples/'
  echo '  mkdir -p "$TMPDIR" && printf '"'"'%s\n'"'"' "feat: add smart pull" "" "Uses context-aware strategy." > "$TMPDIR/commit_msg.txt" && git commit -F "$TMPDIR/commit_msg.txt"'
  echo '  # Or for single-line: git commit -m "feat: add smart pull"'

  echo
  echo "Verifying commit..."
  echo "  git status  # Should show commit succeeded"
else
  echo "No uncommitted changes found."
fi

echo
echo "---"
echo

# Step 3: Sync with remote (smart pull)
echo "Step 3: Sync with remote (smart pull strategy)..."
echo

if [ -n "$UPSTREAM" ]; then
  if [ "$REMOTE_COUNT" -eq 0 ]; then
    echo "Case A: Local strictly ahead — skip pull, go to push"
    echo "  (No remote-only commits to incorporate)"

  elif [ "$LOCAL_COUNT" -eq 0 ]; then
    echo "Case B: Local behind only — fast-forward"
    echo "  git pull --ff-only"

  elif [ "$MERGE_COUNT" -gt 0 ]; then
    echo "Case C: Diverged with merge commits — use merge (preserve merges)"
    echo "  git pull --no-rebase"
    echo
    echo "  WHY: rebase drops merge commits and replays their individual commits."
    echo "  A merge commit with 78 upstream commits would become 78 individual replays."

  elif [ "$LOCAL_COUNT" -gt 20 ]; then
    echo "Case C: Diverged with >20 local commits — use merge (too many to rebase)"
    echo "  git pull --no-rebase"

  else
    echo "Case D: Diverged, few commits ($LOCAL_COUNT), no merges — rebase is safe"
    echo "  git pull --rebase"
  fi

  echo
  echo "If conflicts occur during ANY strategy:"
  echo "  1. Immediately abort: git rebase --abort  OR  git merge --abort"
  echo "  2. Show state: git status"
  echo "  3. Show divergence:"
  echo "     git log @{u}.. --oneline  # your commits"
  echo "     git log ..@{u} --oneline  # remote commits"
  echo "  4. Ask user how to proceed — NEVER auto-resolve"
else
  echo "No upstream — skipping pull (will push with -u in next step)"
fi

echo
echo "---"
echo

# Step 4: Push to remote
echo "Step 4: Pushing to remote..."
echo

if [ -n "$UPSTREAM" ]; then
  echo "git push"
else
  echo "git push -u origin $(git branch --show-current 2>/dev/null || echo '<branch>')"
fi

echo
echo "Push failure handling:"
echo "  - rejected (non-fast-forward): Re-fetch, re-evaluate, sync again"
echo "  - no upstream branch: git push -u origin <branch>"
echo "  - protected branch: Need PR or permissions"
echo
echo "Force push (only if user requests):"
echo "  ALWAYS use --force-with-lease over --force"
echo "  See references/force-push-guidelines.md"

echo
echo "---"
echo

# Step 5: Verify success
echo "Step 5: Verifying success..."
echo

echo "git status  # Should show 'up to date with origin/<branch>'"
echo "git log -3 --oneline"

echo
echo "=== Workflow Complete ==="
echo
echo "Summary:"
echo "  Committed: [commit message] (if needed)"
echo "  Synced: [N] commits via [merge/rebase/fast-forward] (if needed)"
echo "  Pushed: [N] commits to origin/<branch>"
