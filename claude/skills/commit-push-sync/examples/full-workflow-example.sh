#!/bin/bash
# Example: Full commit-push-sync workflow
# Demonstrates the complete workflow handled by the commit-push-sync skill

set -e  # Exit on error

echo "=== Commit-Push-Sync Workflow Example ==="
echo

# Step 1: Check current state
echo "Step 1: Checking current state..."
echo

# Check for uncommitted changes
echo "Checking for uncommitted changes:"
git status

# Check for unpushed commits
echo
echo "Checking for unpushed commits:"
git log @{u}.. --oneline || echo "No unpushed commits"

# Check for remote commits to pull
echo
echo "Checking for remote commits:"
git log ..@{u} --oneline || echo "No remote commits to pull"

echo
echo "---"
echo

# Step 2: Commit changes (if needed)
echo "Step 2: Committing changes (if any)..."
echo

# Check if there are uncommitted changes
if ! git diff-index --quiet HEAD --; then
  echo "Found uncommitted changes. Gathering context..."

  # Gather context (parallel)
  echo "Running git status..."
  git status

  echo
  echo "Running git diff (staged)..."
  git diff --staged

  echo
  echo "Running git diff (unstaged)..."
  git diff

  echo
  echo "Running git log for commit style..."
  git log -10 --oneline

  echo
  echo "Drafting commit message..."
  echo "Example: 'feat: add commit-push-sync skill with full workflow'"

  # Stage specific files (example - in real use, specify actual files)
  echo
  echo "Staging files..."
  echo "Example: git add SKILL.md references/ examples/"

  # Commit with HEREDOC format
  echo
  echo "Creating commit..."
  echo "Example:"
  cat <<'EXAMPLE'
git commit -m "$(cat <<'EOF'
feat: add commit-push-sync skill

Combines commit, pull rebase, and push into single workflow.
Includes conflict resolution and force-push guidelines.
EOF
)"
EXAMPLE

  echo
  echo "Verifying commit..."
  echo "git status  # Should show commit succeeded"
else
  echo "No uncommitted changes found."
fi

echo
echo "---"
echo

# Step 3: Pull with rebase
echo "Step 3: Pulling with rebase..."
echo

echo "Fetching latest from remote..."
echo "git fetch"

echo
echo "Pulling with rebase..."
echo "git pull --rebase"

echo
echo "If conflicts occur:"
cat <<'CONFLICTS'
  1. Review conflicts: git status
  2. Resolve manually (edit files, remove markers)
  3. Stage resolved files: git add <files>
  4. Continue rebase: git rebase --continue
  5. Or abort: git rebase --abort
CONFLICTS

echo
echo "---"
echo

# Step 4: Push to remote
echo "Step 4: Pushing to remote..."
echo

echo "Pushing commits..."
echo "git push"

echo
echo "Handling push failures:"
cat <<'FAILURES'
  - rejected (non-fast-forward): Pull rebase again
  - no upstream branch: git push -u origin <branch>
  - protected branch: Need PR or permissions
  - force required: Use --force-with-lease (after confirmation)
FAILURES

echo
echo "---"
echo

# Step 5: Verify success
echo "Step 5: Verifying success..."
echo

echo "Checking status..."
echo "git status  # Should show 'up to date with origin/<branch>'"

echo
echo "Showing recent commits..."
echo "git log -3 --oneline"

echo
echo "=== Workflow Complete ==="
echo
echo "Summary:"
echo "  ✓ Committed: [commit message]"
echo "  ✓ Pulled: [N] commits from remote"
echo "  ✓ Pushed: [N] commits to origin/<branch>"
