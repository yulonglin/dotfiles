#!/bin/bash
# Pre-task creation hook: Validate location

set -euo pipefail

# Get task details
TASK_PATH="${1:-.}"
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "")

# Validate: Tasks must be in per-project .claude/tasks, NOT global ~/.claude/tasks
if [[ "$TASK_PATH" == "$HOME/.claude/tasks/"* ]]; then
    cat >&2 <<'EOF'
❌ ERROR: Tasks must be per-project, not global

Global location (~/.claude/tasks/):
  ❌ WRONG - tasks mix work from different projects

Per-project location (.claude/tasks/):
  ✅ CORRECT - each project has its own tasks

Solution:
  1. Check current directory: pwd
  2. Ensure you're in the project root
  3. Create task again (Claude will auto-detect .claude/tasks/)
  4. Alternative: Set environment variables
     export CLAUDE_CODE_PLANS_DIR='.claude/plans'
     export CLAUDE_CODE_TASKS_DIR='.claude/tasks'

EOF
    exit 1
fi

exit 0
