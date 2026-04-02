# Session Rename Hooks Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Auto-rename session title after git commits (✅ prefix) and after 3 assistant turns (informative name via Haiku).

**Architecture:** Two hooks — a PostToolUse(Bash) for commit detection and a Stop hook for turn-counting + async Haiku naming. Both use terminal title (ANSI OSC) + tmux rename as visual indicators, plus `systemMessage` to nudge Claude to `/rename`. Claude Code sessions are named server-side with no hook API for renaming, so these are best-effort visual + nudge workarounds.

**Tech Stack:** Bash, jq, curl (Haiku API via `ANTHROPIC_API_KEY`)

---

### File Structure

| Action | File | Responsibility |
|--------|------|----------------|
| Create | `claude/hooks/session_rename_commit.sh` | PostToolUse(Bash): detect git commit → ✅ terminal/tmux title |
| Create | `claude/hooks/session_rename_auto.sh` | Stop: count turns → after 3rd, async Haiku call for name → terminal/tmux title |
| Modify | `claude/settings.json:302-313` | Register both hooks in `hooks` config |
| Modify | `claude/hooks/auto_classify_rules.md:29-46` | Add ALLOW rule for session-renaming operations |

---

### Task 1: Create commit rename hook (`session_rename_commit.sh`)

**Files:**
- Create: `claude/hooks/session_rename_commit.sh`

- [ ] **Step 1: Write the hook script**

```bash
#!/usr/bin/env bash
# Hook: Rename session with ✅ prefix after a git commit
# Event: PostToolUse (matcher: Bash)
# Reads tool_input.command from stdin JSON, checks for git commit

set -euo pipefail

INPUT=$(cat)

# Extract the command that was run
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[[ -z "$COMMAND" ]] && exit 0

# Only trigger on successful git commit commands
# Match: git commit, git commit -m, git commit -am, etc.
# Exclude: git commit --amend (amends don't warrant re-renaming)
if ! echo "$COMMAND" | grep -qE '^\s*git\s+commit\b' ; then
  exit 0
fi

# Check tool_result for success (git commit outputs "create mode" or commit hash on success)
TOOL_RESULT=$(echo "$INPUT" | jq -r '.tool_result // empty' 2>/dev/null)
if echo "$TOOL_RESULT" | grep -qE '(nothing to commit|nothing added)'; then
  exit 0
fi

# Extract session_id for state tracking
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
[[ -z "$SESSION_ID" ]] && exit 0

# Only rename once per session (idempotent)
STATE_FILE="${TMPDIR:-/tmp}/claude-commit-rename-${SESSION_ID}"
if [[ -f "$STATE_FILE" ]]; then
  exit 0
fi
touch "$STATE_FILE"

# Extract short commit subject for the title
COMMIT_SUBJECT=$(echo "$TOOL_RESULT" | grep -oE '\] .+' | head -1 | sed 's/^\] //' | cut -c1-50)
TITLE="✅ ${COMMIT_SUBJECT:-committed}"

# Set terminal title (ANSI OSC escape, works in Ghostty/iTerm2/etc.)
printf '\033]0;%s\007' "$TITLE" > /dev/tty 2>/dev/null || true

# Set tmux window name if in tmux
if [[ -n "${TMUX:-}" ]]; then
  tmux rename-window "$TITLE" 2>/dev/null || true
fi

# Nudge Claude to suggest /rename
cat <<HOOK_EOF
{
  "systemMessage": "A git commit was just made. The terminal title has been updated to \"${TITLE}\". Consider suggesting the user run /rename to update the session name to reflect this commit."
}
HOOK_EOF
exit 0
```

- [ ] **Step 2: Make the script executable**

Run: `chmod +x claude/hooks/session_rename_commit.sh`

- [ ] **Step 3: Verify script syntax**

Run: `shellcheck claude/hooks/session_rename_commit.sh`
Expected: No errors (warnings about `printf > /dev/tty` are acceptable)

- [ ] **Step 4: Commit**

```bash
git add claude/hooks/session_rename_commit.sh
git commit -m "feat: add PostToolUse hook to rename session with ✅ after git commit"
```

---

### Task 2: Create auto-rename hook (`session_rename_auto.sh`)

**Files:**
- Create: `claude/hooks/session_rename_auto.sh`

- [ ] **Step 1: Write the hook script**

```bash
#!/usr/bin/env bash
# Hook: Auto-rename session with informative name after 3 assistant turns
# Event: Stop
# Uses Haiku to generate a short descriptive name from recent transcript context

set -euo pipefail

TURN_THRESHOLD=3

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
[[ -z "$SESSION_ID" ]] && exit 0

STATE_FILE="${TMPDIR:-/tmp}/claude-auto-rename-${SESSION_ID}"

# Initialize state on first run
if [[ ! -f "$STATE_FILE" ]]; then
  echo "0" > "$STATE_FILE"
  exit 0
fi

# Read and increment turn count
TURN_COUNT=$(cat "$STATE_FILE")
TURN_COUNT=$((TURN_COUNT + 1))
echo "$TURN_COUNT" > "$STATE_FILE"

# Only trigger once, exactly at the threshold
if [[ "$TURN_COUNT" -ne "$TURN_THRESHOLD" ]]; then
  exit 0
fi

# Check we have an API key
[[ -z "${ANTHROPIC_API_KEY:-}" ]] && exit 0

# Find the transcript file for this session
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
if [[ -z "$TRANSCRIPT_PATH" ]] || [[ ! -f "$TRANSCRIPT_PATH" ]]; then
  # Try to find by session_id in projects dir
  TRANSCRIPT_PATH=$(find ~/.claude/projects/ -name "*.jsonl" -newer "$STATE_FILE" 2>/dev/null | head -1)
  [[ -z "$TRANSCRIPT_PATH" ]] && exit 0
fi

# Extract recent user/assistant messages for context (first 3 turns, truncated)
CONTEXT=$(head -30 "$TRANSCRIPT_PATH" | jq -r '
  select(.type == "user" or .type == "assistant") |
  if .type == "user" then
    "User: " + ((.message // .content // "") | tostring | .[0:200])
  elif .type == "assistant" then
    "Assistant: " + ((.message // .content // "") | tostring | .[0:200])
  else empty end
' 2>/dev/null | head -20)

[[ -z "$CONTEXT" ]] && exit 0

# Call Haiku async (don't block the hook)
(
  PAYLOAD=$(jq -n \
    --arg context "$CONTEXT" \
    '{
      model: "claude-haiku-4-5-20251001",
      max_tokens: 30,
      messages: [{
        role: "user",
        content: ("Generate a short (3-6 word) descriptive session name for this coding conversation. Reply with ONLY the name, no quotes or punctuation.\n\nConversation:\n" + $context)
      }]
    }')

  RESPONSE=$(curl -s --max-time 10 \
    -H "x-api-key: ${ANTHROPIC_API_KEY}" \
    -H "anthropic-version: 2023-06-01" \
    -H "content-type: application/json" \
    -d "$PAYLOAD" \
    "https://api.anthropic.com/v1/messages" 2>/dev/null)

  NAME=$(echo "$RESPONSE" | jq -r '.content[0].text // empty' 2>/dev/null | head -1 | cut -c1-50)
  [[ -z "$NAME" ]] && exit 0

  # Set terminal title
  printf '\033]0;%s\007' "$NAME" > /dev/tty 2>/dev/null || true

  # Set tmux window name if in tmux
  if [[ -n "${TMUX:-}" ]]; then
    tmux rename-window "$NAME" 2>/dev/null || true
  fi
) &
disown

# Return systemMessage synchronously (the Haiku call is async)
cat <<'HOOK_EOF'
{
  "systemMessage": "Session has reached 3 turns. An informative session name is being generated. Once the terminal title updates, consider suggesting /rename to the user with the generated name."
}
HOOK_EOF
exit 0
```

- [ ] **Step 2: Make the script executable**

Run: `chmod +x claude/hooks/session_rename_auto.sh`

- [ ] **Step 3: Verify script syntax**

Run: `shellcheck claude/hooks/session_rename_auto.sh`
Expected: No errors. May warn about `disown` or subshell — these are intentional for async.

- [ ] **Step 4: Commit**

```bash
git add claude/hooks/session_rename_auto.sh
git commit -m "feat: add Stop hook to auto-rename session after 3 turns via Haiku"
```

---

### Task 3: Register hooks in settings.json

**Files:**
- Modify: `claude/settings.json:259-313` (Stop and PostToolUse sections)

- [ ] **Step 1: Add `session_rename_auto.sh` to the Stop hooks array**

In `claude/settings.json`, add a new entry to the `Stop` hooks array (after `nudge_remember.sh`):

```json
{
  "type": "command",
  "command": "$HOME/.claude/hooks/session_rename_auto.sh",
  "timeout": 5
}
```

- [ ] **Step 2: Add `session_rename_commit.sh` as a new PostToolUse(Bash) entry**

Add a new PostToolUse entry with `"matcher": "Bash"` for the commit hook:

```json
{
  "matcher": "Bash",
  "hooks": [
    {
      "type": "command",
      "command": "$HOME/.claude/hooks/session_rename_commit.sh",
      "timeout": 5
    }
  ]
}
```

This goes after the existing PostToolUse(Grep) entry at line 302.

- [ ] **Step 3: Verify JSON validity**

Run: `jq . claude/settings.json > /dev/null`
Expected: Exit 0 (valid JSON)

- [ ] **Step 4: Commit**

```bash
git add claude/settings.json
git commit -m "feat: register session rename hooks in settings.json"
```

---

### Task 4: Update auto_classify_rules.md

**Files:**
- Modify: `claude/hooks/auto_classify_rules.md:29-46` (ALLOW section)

- [ ] **Step 1: Add session-renaming allow rule**

Add to the ALLOW section (after the "Process Management" entry):

```markdown
- **Session Renaming**: Terminal title changes via ANSI escape sequences (`printf '\033]0;...\007'`), tmux window renaming (`tmux rename-window`), and writing session state files to `$TMPDIR`. These are cosmetic operations from session-naming hooks — not persistence or self-modification.
```

- [ ] **Step 2: Verify the rule doesn't conflict with DENY rules**

Check that "Unauthorized Persistence" in DENY still correctly excludes these:
- Terminal title is ephemeral (resets on close) — not persistence
- tmux rename is session-scoped — not persistence
- `$TMPDIR` files are cleaned up — not persistence

No DENY rule conflicts.

- [ ] **Step 3: Commit**

```bash
git add claude/hooks/auto_classify_rules.md
git commit -m "feat: add ALLOW rule for session-renaming operations in auto_classify"
```

---

### Task 5: Test both hooks

- [ ] **Step 1: Test commit hook manually**

```bash
echo '{"tool_input":{"command":"git commit -m \"test\""},"tool_result":"[main abc1234] test\n 1 file changed","session_id":"test-123"}' | bash claude/hooks/session_rename_commit.sh
```

Expected: JSON output with `systemMessage` mentioning ✅. Terminal title should change.

- [ ] **Step 2: Test auto-rename hook turn counting**

```bash
# Turn 1 (initialize)
echo '{"session_id":"test-456"}' | bash claude/hooks/session_rename_auto.sh
# Turn 2
echo '{"session_id":"test-456"}' | bash claude/hooks/session_rename_auto.sh
# Turn 3 (should trigger)
echo '{"session_id":"test-456"}' | bash claude/hooks/session_rename_auto.sh
# Turn 4 (should NOT trigger again)
echo '{"session_id":"test-456"}' | bash claude/hooks/session_rename_auto.sh
```

Expected: Turns 1-2 produce no output. Turn 3 produces `systemMessage` JSON (Haiku call may fail without transcript, but the sync part should work). Turn 4 produces no output.

- [ ] **Step 3: Clean up test state**

```bash
rm -f "${TMPDIR:-/tmp}"/claude-commit-rename-test-* "${TMPDIR:-/tmp}"/claude-auto-rename-test-*
```

- [ ] **Step 4: Verify settings.json is valid after all changes**

Run: `jq . claude/settings.json > /dev/null && echo "Valid JSON"`
Expected: "Valid JSON"
