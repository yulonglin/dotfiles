#!/usr/bin/env bash
# SessionStart hook: Warn about stale CLAUDE.md, stale docs/, and [gone] branches.
#
# Outputs hookSpecificOutput JSON with additionalContext so warnings appear
# in the session context (not just terminal stderr).

set -euo pipefail

# Clear the classifier's per-session no-key warning flag. The classifier stopped
# writing this file once the subscription fallback landed (a missing API key is
# now a degradation the statusline reports, not a once-per-session warning), so
# this only cleans up the leftover from an older checkout.
rm -f "$HOME/.cache/claude/auto-classify-no-key-warned" 2>/dev/null || true

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")
CLAUDE_MD="$REPO_ROOT/CLAUDE.md"
DOCS_DIR="${REPO_ROOT}/docs"

# Pre-create remember plugin's log dir so its `2>> .remember/logs/hook-errors.log`
# redirect doesn't fail on first-session-in-new-project. The shell evaluates the
# redirect before running session-start-hook.sh (which would otherwise mkdir it).
mkdir -p "$REPO_ROOT/.remember/logs" 2>/dev/null || true

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

# --- Check approval classifier health ---

# Verify approval classifier can function (rules file + API key)
CLASSIFY_RULES="$HOME/.claude/hooks/approval_classifier_rules.md"
# Resolve DOT_DIR: hooks/ lives inside claude/ which is symlinked to ~/.claude/
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
_DOT_DIR="${DOT_DIR:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
SECRETS_HELPER="$_DOT_DIR/custom_bins/dotfiles-secrets"

# Hooks run with minimal PATH — ensure bws/sops are discoverable
for d in "$HOME/.local/bin" /opt/homebrew/bin /usr/local/bin "$_DOT_DIR/custom_bins"; do
  [[ -d "$d" ]] && [[ ":$PATH:" != *":$d:"* ]] && PATH="$d:$PATH"
done
export PATH

classify_ok=true
classify_warnings=""

if [[ ! -f "$CLASSIFY_RULES" ]]; then
    classify_ok=false
    classify_warnings+="approval classifier rules missing: $CLASSIFY_RULES"$'\n'
fi

# Check if API key is available (same logic as with-anthropic-key.sh).
# The helper can exit 0 having resolved nothing, so a zero status is NOT
# evidence of a key — require actual output. Its stderr carries the reason
# (ambiguous env name, stale cache, no BWS token), so keep it and surface it
# below instead of discarding it: a probe that says "no key" without saying why
# is what made this take days to diagnose.
has_key=false
key_error=""
if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
    has_key=true
elif [[ -x "$SECRETS_HELPER" ]]; then
    # This hook runs under `set -e`, so a bare mktemp that fails would abort the
    # WHOLE SessionStart hook — no degraded-classifier warning, no stale-doc
    # checks — and $TMPDIR is genuinely unwritable under the Claude Code sandbox.
    # Try the plausible dirs, and if none works, still probe: losing the reason
    # is acceptable, losing every other session warning is not.
    key_probe_err=""
    for _probe_dir in "${TMPDIR:-/tmp}" /tmp "$HOME/.cache/claude"; do
        [[ -d "$_probe_dir" ]] || continue
        if key_probe_err=$(mktemp "$_probe_dir/claude-keyprobe.XXXXXX" 2>/dev/null); then
            break
        fi
        key_probe_err=""
    done
    if [[ -n "$key_probe_err" ]]; then
        if [[ -n "$("$SECRETS_HELPER" shell ANTHROPIC_API_KEY 2>"$key_probe_err")" ]]; then
            has_key=true
        else
            key_error=$(tr '\n' ' ' < "$key_probe_err" | cut -c1-300)
        fi
        rm -f "$key_probe_err"
    elif [[ -n "$("$SECRETS_HELPER" shell ANTHROPIC_API_KEY 2>/dev/null)" ]]; then
        has_key=true
    else
        key_error="(no writable temp dir to capture the reason — run: dotfiles-secrets shell ANTHROPIC_API_KEY)"
    fi
fi

if ! $has_key; then
    classify_ok=false
    # Not a dead end any more: without a key the classifier falls back to the
    # Claude subscription (`claude -p`), which still auto-approves but takes
    # ~9s per call instead of ~1s. Still worth a warning — it is a real
    # slowdown, and the fallback fails too if the CLI is not logged in.
    classify_warnings+="approval classifier has NO API key — falling back to the slower subscription backend (~9s/call). Fix: setup-envrc ANTHROPIC_API_KEY"$'\n'
    [[ -n "$key_error" ]] && classify_warnings+="  reason: $key_error"$'\n'
fi

# --- Collect warnings ---

warnings=""
feature_rc=0
python3 "$HOME/.claude/hooks/hook_feature.py" enabled nudges.session-start-warnings >/dev/null 2>&1 || feature_rc=$?
advisory_enabled=true
[[ "$feature_rc" -eq 1 ]] && advisory_enabled=false

if ! $classify_ok; then
    # Loud terminal warning stays active; it adds no model context.
    printf '\033[1;31m🚨 APPROVAL CLASSIFIER DEGRADED:\033[0m\n%s\n' "$classify_warnings" >&2
    # Keep collecting so the same result can enter context when enabled.
    warnings+="🚨 APPROVAL CLASSIFIER DEGRADED:"$'\n'"$classify_warnings"
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

# Exit silently if nothing should enter the session context. The setup and health
# checks above still run when advisory nudges are disabled.
[[ -z "$warnings" ]] && exit 0
$advisory_enabled || exit 0

# Emit structured hook output so Claude sees the warnings in context
jq -n --arg w "$warnings" '{
    hookSpecificOutput: {
        hookEventName: "SessionStart",
        additionalContext: ("Documentation staleness check:\n" + $w)
    }
}'

exit 0
