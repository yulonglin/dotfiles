#!/bin/bash
# Claude Code PreToolUse hook: Block git commit/add if secrets detected in staged changes
# Runs BEFORE Claude executes git commit or git add commands
#
# Exit codes:
#   0 - Allow (no secrets found or not a git commit/add command)
#   2 - Block (secrets detected, shows message to Claude)

set -euo pipefail

# Check for required dependencies
if ! command -v jq &> /dev/null; then
    echo "ERROR: jq is required but not installed" >&2
    exit 1
fi

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""')

# Only check on git commit or git add (use word boundaries to avoid false matches)
if ! echo "$COMMAND" | grep -qE '\bgit\s+(commit|add)\b'; then
    exit 0
fi

# Scan staged changes for secrets
if command -v gitleaks &> /dev/null; then
    # Use gitleaks if available (comprehensive patterns)
    OUTPUT=$(gitleaks protect --staged --no-banner 2>&1) || {
        echo "BLOCKED: Secrets detected in staged changes" >&2
        echo "$OUTPUT" >&2
        exit 2
    }
else
    # Fallback to regex patterns if gitleaks not installed
    STAGED_DIFF=$(git diff --cached --diff-filter=ACMR 2>/dev/null || true)

    if [ -z "$STAGED_DIFF" ]; then
        exit 0
    fi

    # Common secret patterns (kept conservative to avoid false positives)
    # For comprehensive detection, install gitleaks: brew install gitleaks
    PATTERNS=(
        'AKIA[0-9A-Z]{16}'                          # AWS Access Key ID
        'gh[pousr]_[A-Za-z0-9_]{36,}'               # GitHub tokens
        'sk-[A-Za-z0-9]{48,}'                       # OpenAI API keys
        'sk-ant-[A-Za-z0-9_-]{90,}'                 # Anthropic API keys
        'xox[baprs]-[A-Za-z0-9-]{10,}'              # Slack tokens
        'ya29\.[A-Za-z0-9_-]{50,}'                  # Google OAuth tokens
        'AIza[0-9A-Za-z_-]{35}'                     # Google API keys
        '-----BEGIN (RSA |DSA |EC |OPENSSH )?PRIVATE KEY-----'  # Private keys
    )

    for pattern in "${PATTERNS[@]}"; do
        if echo "$STAGED_DIFF" | grep -qE "$pattern"; then
            echo "BLOCKED: Potential secret detected in staged changes (pattern: $pattern)" >&2
            echo "Install gitleaks for more accurate detection: brew install gitleaks" >&2
            exit 2
        fi
    done
fi

exit 0
