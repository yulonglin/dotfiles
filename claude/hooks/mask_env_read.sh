#!/usr/bin/env bash
# PreToolUse hook: mask secret values when .env/.envrc files are read.
#
# Intercepts:
#   - Read tool: file_path matching .env, .env.*, .envrc
#   - Bash tool: cat/head/tail/grep/bat on .env files
#
# Instead of allowing raw access, denies the read and returns the masked
# content as the denial reason. Keys are visible, values show first 4 chars
# + ****.
#
# Hook output format (JSON on stdout):
#   hookSpecificOutput.permissionDecision = "deny"
#   hookSpecificOutput.permissionDecisionReason = <masked content>
#
# WARNING: the deny key is permissionDecision. Claude Code silently ignores a
# nested decision.behavior object — the hook emitted that shape from its first
# commit until 2026-09-12 and blocked nothing at all for its whole life, while
# its test asserted only that the substring "deny" appeared somewhere in the
# output. Assert the KEY, never the substring.
#
# Exit 0 always (JSON output controls behavior).

set -euo pipefail

INPUT=$(cat)

# The one deny path. Shape matches block_vault_structure.sh exactly: Claude
# Code reads hookSpecificOutput.permissionDecision and nothing else.
deny() {
    jq -n --arg r "$1" \
      '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
    exit 0
}

# Extract tool_name and tool_input
TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null) || exit 0
[[ -z "$TOOL_NAME" ]] && exit 0

# Determine the target file path based on tool type
FILE_PATH=""

if [[ "$TOOL_NAME" == "Read" ]]; then
    FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null) || exit 0
elif [[ "$TOOL_NAME" == "Bash" ]]; then
    CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null) || exit 0
    [[ -z "$CMD" ]] && exit 0

    # Check EVERY shell segment, not just the whole command's first word.
    # A pipeline is not an exemption: `cat .env | head` leaks exactly as much
    # as `cat .env`, and `ls && cat .env` hides the read behind an innocuous
    # first word. Splitting on ||, &&, ; and | closes both.
    #
    # BEHAVIOR NOTE: this deliberately changes results for pipelines that used
    # to run unguarded — `cat .env | wc -l` now returns the masked-content
    # denial instead of a line count. The count is recoverable from the masked
    # output; a raw value in the transcript is not recoverable at all.
    #
    # If a command reads more than one env file, only the FIRST match is
    # reported; the rest are suppressed along with the whole command.
    while IFS= read -r SEGMENT; do
        [[ -z "${SEGMENT// /}" ]] && continue
        CMD_NAME=$(printf '%s' "$SEGMENT" | awk '{print $1}')
        case "$CMD_NAME" in
            cat|head|tail|bat|less|more|grep) ;;
            */cat|*/head|*/tail|*/bat|*/less|*/more|*/grep) ;;
            *) continue ;;
        esac
        # Extract file paths that look like env files from the segment's args
        FILE_PATH=$(printf '%s' "$SEGMENT" | grep -oE '[^[:space:]]+/(\.env[^[:space:]]*|\.envrc)|[[:space:]](\.env[^[:space:]]*|\.envrc)' | tr -d ' ' | tail -1) || true
        # Also try: command operates on a bare .env in cwd
        if [[ -z "$FILE_PATH" ]]; then
            FILE_PATH=$(printf '%s' "$SEGMENT" | grep -oE '\b\.env[a-zA-Z._]*\b|\b\.envrc\b' | tail -1) || true
        fi
        [[ -n "$FILE_PATH" ]] && break
    done < <(printf '%s' "$CMD" | awk '{gsub(/\|\||&&|[;|]/, "\n"); print}')
fi

# No env file detected — allow
[[ -z "$FILE_PATH" ]] && exit 0

# Normalize the filename (basename for pattern matching)
BASENAME=$(basename "$FILE_PATH")

# Check if file matches .env patterns: .env, .env.*, .envrc
case "$BASENAME" in
    .env|.envrc) ;; # match
    .env.*) ;; # match .env.local, .env.production, etc.
    *) exit 0 ;; # not an env file, allow
esac

# Resolve the full path (handle relative paths using cwd from hook input)
if [[ "$FILE_PATH" != /* ]]; then
    CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // ""' 2>/dev/null) || CWD=""
    if [[ -n "$CWD" ]]; then
        FILE_PATH="$CWD/$FILE_PATH"
    fi
fi

# Check if file exists
if [[ ! -f "$FILE_PATH" ]]; then
    # File doesn't exist — let the Read tool handle the error naturally
    exit 0
fi

# Check if file is binary (skip masking for binary files)
if file -b "$FILE_PATH" 2>/dev/null | grep -qi 'binary\|executable\|data'; then
    deny "Binary .env file detected — refusing to read."
fi

# Read and mask the file content
# Masking rules:
#   KEY=value      → KEY=valu****
#   KEY=ab         → KEY=ab****
#   KEY=           → KEY=           (empty, unchanged)
#   KEY="quoted"   → KEY="quot****"
#   export KEY=val → export KEY=valu****
#   # comment      → # comment      (unchanged)
#   empty lines    → (unchanged)

# Limit file size to prevent huge outputs (100KB max)
FILE_SIZE=$(wc -c < "$FILE_PATH" 2>/dev/null || echo 0)
if (( FILE_SIZE > 102400 )); then
    deny "Env file too large to mask safely: $FILE_PATH is over 100KB. This is unusually large for an env file — inspect it manually outside the transcript."
fi

# Process the file line by line
MASKED_CONTENT=$(python3 -c '
import sys, re

def mask_value(val):
    """Mask a value, preserving quotes if present."""
    if not val:
        return val

    # Detect and preserve surrounding quotes
    quote_char = ""
    inner = val
    if len(val) >= 2 and val[0] == val[-1] and val[0] in ("\"", "'\''"):
        quote_char = val[0]
        inner = val[1:-1]

    if not inner:
        return val  # empty quoted string

    # Show first 4 chars, mask the rest
    visible = min(4, len(inner))
    masked = inner[:visible] + "****"

    if quote_char:
        return quote_char + masked + quote_char
    return masked

lines = []
for line in sys.stdin:
    line = line.rstrip("\n")

    # Preserve comments and blank lines
    stripped = line.lstrip()
    if not stripped or stripped.startswith("#"):
        lines.append(line)
        continue

    # Match: optional "export " + KEY = VALUE
    m = re.match(r"^(\s*(?:export\s+)?)([\w.]+)(=)(.*)", line)
    if m:
        prefix, key, eq, value = m.groups()
        lines.append(prefix + key + eq + mask_value(value))
    else:
        # Non-assignment lines (source directives, etc.) — pass through
        lines.append(line)

print("\n".join(lines))
' < "$FILE_PATH" 2>/dev/null) || {
    # Python failed — deny without content
    deny "Failed to mask env file: $FILE_PATH. Refusing the read rather than falling through to the raw value."
}

# Build the output JSON with masked content
# Truncate masked content if very long (keep the denial reason under 8KB)
MASKED_LENGTH=${#MASKED_CONTENT}
if (( MASKED_LENGTH > 8000 )); then
    MASKED_CONTENT="${MASKED_CONTENT:0:8000}
... (truncated, file has $MASKED_LENGTH chars)"
fi

deny "## Masked contents of $FILE_PATH

Secret values are masked (first 4 chars visible).

\`\`\`
$MASKED_CONTENT
\`\`\`

To read one value: \`dotfiles-secrets get-value 'ENV_NAME - description'\` (list keys with \`dotfiles-secrets keys-meta\`). To USE a secret without printing it: \`secrets run KEY_NAME -- <command>\`. Note \`printenv KEY_NAME\` is blocked by block_secret_expansion.sh — it would write the value into the transcript permanently."
