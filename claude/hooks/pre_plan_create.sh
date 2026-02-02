#!/bin/bash
# Pre-plan creation hook: Validate location and naming conventions

set -euo pipefail

# Get plan details from arguments or environment
# Claude Code will pass the plan path or we read from env
PLAN_PATH="${1:-.}"

# Determine repo root
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "")

# Validate: Plans must be in per-project .claude/plans, NOT global ~/.claude/plans
if [[ "$PLAN_PATH" == "$HOME/.claude/plans/"* ]]; then
    cat >&2 <<'EOF'
❌ ERROR: Plans must be per-project, not global

Global location (.claude/.claude/plans/):
  ❌ WRONG - plans mix work from different projects

Per-project location (.claude/plans/):
  ✅ CORRECT - each project has its own plans

Solution:
  1. Check current directory: pwd
  2. Ensure you're in the project root
  3. Create plan again (Claude will auto-detect .claude/plans/)
  4. Alternative: Set environment variables
     export CLAUDE_CODE_PLANS_DIR='.claude/plans'
     export CLAUDE_CODE_TASKS_DIR='.claude/tasks'

EOF
    exit 1
fi

# Warn if plan name doesn't follow UTC timestamp convention
PLAN_NAME=$(basename "$PLAN_PATH" 2>/dev/null || echo "unknown")
if [[ ! "$PLAN_NAME" =~ ^[0-9]{8}_[0-9]{6}_UTC ]]; then
    cat >&2 <<EOF
⚠️  Plan naming convention

Recommended format: YYYYMMDD_HHMMSS_UTC_descriptive_name.md

Example:
  20260202_143022_UTC_authentication_refactor.md
  20260202_143022_UTC_bug_fix_login_flow.md

Current name:
  $PLAN_NAME

Why use UTC timestamp:
  • Chronological sorting (ID order = time order)
  • Easy recovery/finding plans by date
  • No naming conflicts
  • Consistent across all repos/users

This is optional but strongly recommended.
EOF
fi

# Verify plan is in a git repo (if we're in one)
if [[ -n "$REPO_ROOT" ]]; then
    if [[ ! "$PLAN_PATH" =~ "$REPO_ROOT" ]]; then
        cat >&2 <<EOF
⚠️  Plan location warning

You're in git repo: $REPO_ROOT
But plan seems to be outside:
  $PLAN_PATH

Did you mean to create in:
  $REPO_ROOT/.claude/plans/
EOF
    fi
fi

exit 0
