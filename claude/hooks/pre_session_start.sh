#!/usr/bin/env bash
# SessionStart hook: Warn about stale CLAUDE.md, stale docs/, and [gone] branches.
#
# Outputs hookSpecificOutput JSON with additionalContext so warnings appear
# in the session context (not just terminal stderr).

set -euo pipefail

# Reset per-session flags so warnings repeat in new sessions
rm -f "$HOME/.cache/claude/auto-classify-no-key-warned" 2>/dev/null || true

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")
CLAUDE_MD="$REPO_ROOT/CLAUDE.md"
DOCS_DIR="${REPO_ROOT}/docs"

# --- Helper functions ---

check_doc_age() {
    local doc="$1"
    [[ ! -f "$doc" ]] && echo 999 && return

    if command -v git >/dev/null 2>&1 && git rev-parse --git-dir >/dev/null 2>&1; then
        local commit_time
        commit_time=$(git log -1 --format=%ct -- "$doc" 2>/dev/null || echo "$(date +%s)")
        echo $(( ($(date +%s) - commit_time) / 86400 ))
    else
        local mod_time
        if [[ "$(uname)" == "Darwin" ]]; then
            mod_time=$(stat -f "%m" "$doc" 2>/dev/null || echo "$(date +%s)")
        else
            mod_time=$(stat -c "%Y" "$doc" 2>/dev/null || echo "$(date +%s)")
        fi
        echo $(( ($(date +%s) - mod_time) / 86400 ))
    fi
}

check_commits_since() {
    local doc="$1"
    [[ ! -f "$doc" ]] && echo 0 && return
    command -v git >/dev/null 2>&1 || { echo 0; return; }
    git rev-parse --git-dir >/dev/null 2>&1 || { echo 0; return; }
    local last_commit
    last_commit=$(git log -1 --format=%H -- "$doc" 2>/dev/null) || { echo 0; return; }
    [[ -z "$last_commit" ]] && echo 0 && return
    git rev-list --count "${last_commit}..HEAD" 2>/dev/null || echo 0
}

# --- Check auto-classify health ---

# Verify auto-classify can function (rules file + API key)
CLASSIFY_RULES="$HOME/.claude/hooks/auto_classify_rules.md"
# Resolve DOT_DIR: hooks/ lives inside claude/ which is symlinked to ~/.claude/
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
_DOT_DIR="${DOT_DIR:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
SECRETS_HELPER="$_DOT_DIR/custom_bins/dotfiles-secrets"

classify_ok=true
classify_warnings=""

if [[ ! -f "$CLASSIFY_RULES" ]]; then
    classify_ok=false
    classify_warnings+="auto-classify rules missing: $CLASSIFY_RULES"$'\n'
fi

# Check if API key is available (same logic as with-anthropic-key.sh)
has_key=false
if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
    has_key=true
elif [[ -x "$SECRETS_HELPER" ]] && "$SECRETS_HELPER" shell ANTHROPIC_API_KEY >/dev/null 2>&1; then
    has_key=true
fi

if ! $has_key; then
    classify_ok=false
    classify_warnings+="auto-classify has NO API key — all non-trivial commands will need manual approval. Fix: setup-envrc ANTHROPIC_API_KEY"$'\n'
fi

# --- Collect warnings ---

warnings=""

if ! $classify_ok; then
    # Loud terminal warning (stderr — user sees this immediately)
    printf '\033[1;31m🚨 AUTO-CLASSIFY DEGRADED:\033[0m\n%s\n' "$classify_warnings" >&2
    # Also include in Claude's context
    warnings+="🚨 AUTO-CLASSIFY DEGRADED:"$'\n'"$classify_warnings"
fi

# Check CLAUDE.md staleness
if [[ -f "$CLAUDE_MD" ]]; then
    DAYS_SINCE=$(check_doc_age "$CLAUDE_MD")
    COMMITS_SINCE=$(check_commits_since "$CLAUDE_MD")

    if [[ $COMMITS_SINCE -gt 100 ]] || [[ $DAYS_SINCE -gt 180 ]]; then
        warnings+="CLAUDE.md is stale"
        [[ $COMMITS_SINCE -gt 0 ]] && warnings+=" ($COMMITS_SINCE commits since last update)"
        [[ $DAYS_SINCE -gt 0 ]] && warnings+=", last updated $DAYS_SINCE days ago"
        warnings+=". Consider running /claude-md-improver."
        warnings+=$'\n'
    fi
elif [[ -d "$REPO_ROOT" ]]; then
    warnings+="No CLAUDE.md in $(basename "$REPO_ROOT"). Consider creating one."
    warnings+=$'\n'
fi

# Check docs/ staleness
if [[ -d "$DOCS_DIR" ]]; then
    stale_docs=""
    for doc in "$DOCS_DIR"/*.md; do
        [[ ! -f "$doc" ]] && continue
        DAYS=$(check_doc_age "$doc")
        if [[ $DAYS -gt 365 ]]; then
            stale_docs+="  - $(basename "$doc") (${DAYS} days old)"$'\n'
        fi
    done
    if [[ -n "$stale_docs" ]]; then
        warnings+="Stale docs/ files (>1 year since last commit):"$'\n'"$stale_docs"
    fi
fi

# Check for [gone] branches
STALE_BRANCHES=$(git branch -v 2>/dev/null | grep -c '\[gone\]' || true)
STALE_BRANCHES=${STALE_BRANCHES:-0}
if [[ "$STALE_BRANCHES" -gt 0 ]]; then
    warnings+="$STALE_BRANCHES stale branch(es) with deleted remote tracking. Run: clean_gone"
    warnings+=$'\n'
fi

# --- Output ---

# Exit silently if nothing to report
[[ -z "$warnings" ]] && exit 0

# Emit structured hook output so Claude sees the warnings in context
jq -n --arg w "$warnings" '{
    hookSpecificOutput: {
        hookEventName: "SessionStart",
        additionalContext: ("Documentation staleness check:\n" + $w)
    }
}'

exit 0
