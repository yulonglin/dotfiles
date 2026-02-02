#!/bin/bash
# Pre-session start hook: Warn about stale docs and outdated ground truth

set -euo pipefail

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")
CLAUDE_MD="$REPO_ROOT/CLAUDE.md"
DOCS_DIR="${REPO_ROOT}/docs"  # Formerly ai_docs

# Get terminal width for formatted output
TERM_WIDTH=$(tput cols 2>/dev/null || echo 80)

# Color codes (safe for terminal)
WARN="⚠️"
INFO="ℹ️"
TICK="✓"

# Function to check doc staleness in days
check_doc_age() {
    local doc="$1"

    if [[ ! -f "$doc" ]]; then
        echo 999  # Return large number if file doesn't exist
        return
    fi

    if command -v git >/dev/null 2>&1 && git rev-parse --git-dir >/dev/null 2>&1; then
        # Git-aware: Use last commit date
        local commit_time
        commit_time=$(git log -1 --format=%ct "$doc" 2>/dev/null || echo $(date +%s))
        echo $(( ($(date +%s) - commit_time) / 86400 ))
    else
        # Fallback: Use file modification time
        local mod_time
        if [[ "$(uname)" == "Darwin" ]]; then
            mod_time=$(stat -f "%m" "$doc" 2>/dev/null || echo $(date +%s))
        else
            mod_time=$(stat -c "%Y" "$doc" 2>/dev/null || echo $(date +%s))
        fi
        echo $(( ($(date +%s) - mod_time) / 86400 ))
    fi
}

# Function to check commits since doc last updated
check_commits_since() {
    local doc="$1"

    if [[ ! -f "$doc" ]] || ! command -v git >/dev/null 2>&1; then
        echo 0
        return
    fi

    if git rev-parse --git-dir >/dev/null 2>&1; then
        git log --oneline "$doc".. 2>/dev/null | wc -l || echo 0
    else
        echo 0
    fi
}

# Main checks
HAS_WARNINGS=0

# Check CLAUDE.md staleness
if [[ -f "$CLAUDE_MD" ]]; then
    DAYS_SINCE=$(check_doc_age "$CLAUDE_MD")
    COMMITS_SINCE=$(check_commits_since "$CLAUDE_MD")

    # Warn if significantly stale
    if [[ $COMMITS_SINCE -gt 100 ]] || [[ $DAYS_SINCE -gt 180 ]]; then
        if [[ $HAS_WARNINGS -eq 0 ]]; then
            echo ""
            echo "$(printf '%.0s─' $(seq 1 $TERM_WIDTH))"
            echo "⚠️  Project Documentation Status"
            echo "$(printf '%.0s─' $(seq 1 $TERM_WIDTH))"
            HAS_WARNINGS=1
        fi

        echo ""
        echo "$WARN CLAUDE.md outdated"
        if [[ $COMMITS_SINCE -gt 0 ]]; then
            echo "   • $COMMITS_SINCE commits since last update"
        fi
        if [[ $DAYS_SINCE -gt 0 ]]; then
            echo "   • Last updated $DAYS_SINCE days ago"
        fi
        echo ""
        echo "   Consider refreshing ground truth: Verify hyperparams, fix stale patterns"
        echo "   See: /claude-md-improver to audit and improve CLAUDE.md"
    fi
elif [[ -d "$REPO_ROOT" ]]; then
    # Project has no CLAUDE.md
    if [[ $HAS_WARNINGS -eq 0 ]]; then
        echo ""
        echo "$(printf '%.0s─' $(seq 1 $TERM_WIDTH))"
        echo "⚠️  Project Documentation Status"
        echo "$(printf '%.0s─' $(seq 1 $TERM_WIDTH))"
        HAS_WARNINGS=1
    fi

    echo ""
    echo "$INFO No CLAUDE.md in $(basename "$REPO_ROOT")"
    echo "   Create one to document project patterns, setup, and conventions"
fi

# Check docs/ staleness
if [[ -d "$DOCS_DIR" ]]; then
    STALE_COUNT=0

    for doc in "$DOCS_DIR"/*.md; do
        [[ ! -f "$doc" ]] && continue

        DAYS=$(check_doc_age "$doc")
        doc_name=$(basename "$doc")

        if [[ $DAYS -gt 365 ]]; then
            if [[ $HAS_WARNINGS -eq 0 ]]; then
                echo ""
                echo "$(printf '%.0s─' $(seq 1 $TERM_WIDTH))"
                echo "⚠️  Project Documentation Status"
                echo "$(printf '%.0s─' $(seq 1 $TERM_WIDTH))"
                HAS_WARNINGS=1
            fi

            if [[ $STALE_COUNT -eq 0 ]]; then
                echo ""
                echo "$WARN Stale documentation in docs/"
            fi

            echo "   • $doc_name (${DAYS} days old)"
            ((STALE_COUNT++))
        fi
    done
fi

# Print closing line if we had warnings
if [[ $HAS_WARNINGS -eq 1 ]]; then
    echo ""
    echo "$(printf '%.0s─' $(seq 1 $TERM_WIDTH))"
    echo ""
fi

# Optional: Check for stale git branches
STALE_BRANCHES=$(git branch -v 2>/dev/null | grep '\[gone\]' | wc -l || echo 0)
if [[ $STALE_BRANCHES -gt 0 ]]; then
    echo "$INFO Found $STALE_BRANCHES stale branches (deleted on remote)"
    echo "   Tip: clean_gone  # Clean up with built-in alias"
fi

exit 0
