# Auto-Deny Hook for Background Agents

## Context

Currently `yolo` (`--dangerously-skip-permissions`) is all-or-nothing: either everything is allowed or normal prompting applies. Background agents running in `acceptEdits` mode can hang on permission prompts with no one watching.

Inspired by alignment-hive's autopilot plugin, we add a `PermissionRequest` hook that auto-denies unpermitted commands when autonomous mode is active. This creates a middle ground: agents keep working (with denials logged) instead of hanging.

## Design

### Core: `auto_deny.sh` (PermissionRequest hook)

A hook that fires on every permission prompt. Logic:

1. Check if autonomous mode is enabled (state file exists and `autonomous_mode == true`)
2. If not enabled, exit 0 (normal prompting)
3. If enabled, auto-deny the command with an informative message
4. Log denied commands to `$HOME/.cache/claude/auto-deny.log`

**State file:** `.claude/autopilot/state.json` (per-project, in `.gitignore`)
```json
{ "autonomous_mode": true }
```

### Activation: simple aliases

No wizard needed — your existing alias pattern is simpler:

```bash
# In config/aliases.sh
alias auto='claude --permission-mode acceptEdits'          # acceptEdits + auto-deny
alias an='auto -t'                                         # auto with task name
alias cwa() { _cw_launch --auto "$@"; }                   # worktree + auto-deny
```

Toggle autonomous mode per-project:
```bash
alias auto-on='mkdir -p .claude/autopilot && echo '\''{"autonomous_mode":true}'\'' > .claude/autopilot/state.json'
alias auto-off='rm -f .claude/autopilot/state.json'
```

### Files to create/modify

| File | Action | Purpose |
|------|--------|---------|
| `claude/hooks/auto_deny.sh` | **Create** | PermissionRequest hook — auto-deny when autonomous |
| `claude/settings.json` | **Edit** | Add PermissionRequest hook entry |
| `config/aliases.sh` | **Edit** | Add `auto`, `auto-on`, `auto-off` aliases |
| `config/ignore_global` | **Edit** | Add `.claude/autopilot/` to gitignore |

### Hook implementation (`claude/hooks/auto_deny.sh`)

```bash
#!/bin/bash
set -euo pipefail

input=$(cat)
STATE_FILE="$CLAUDE_PROJECT_DIR/.claude/autopilot/state.json"
LOG="$HOME/.cache/claude/auto-deny.log"

# Not configured → normal prompting
[ -f "$STATE_FILE" ] || exit 0

# Check autonomous mode (jq available via PATH)
jq -e '.autonomous_mode == true' "$STATE_FILE" >/dev/null 2>&1 || exit 0

# Extract what's being requested for the log/message
rule=$(echo "$input" | jq -r '
  [.permission_suggestions // [] | .[] |
   select(.type == "addRules") | .rules[]? | .ruleContent
  ] | first // "unknown"')

# Log and deny
printf '%s DENIED: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$rule" >> "$LOG" 2>/dev/null

jq -n --arg msg "Auto-denied in autonomous mode: \`$rule\` not in allow list. Use /auto-deny:add or auto-off to disable." '{
  hookSpecificOutput: {
    hookEventName: "PermissionRequest",
    decision: { behavior: "deny", message: $msg, interrupt: false }
  }
}'
```

### settings.json addition

```json
"PermissionRequest": [
  {
    "hooks": [
      {
        "type": "command",
        "command": "$HOME/.claude/hooks/auto_deny.sh",
        "timeout": 5
      }
    ]
  }
]
```

## Verification

1. `auto-on` in a test project → confirm `state.json` created
2. Run `claude --permission-mode acceptEdits` → trigger a command not in allow list → confirm auto-denied (not prompted)
3. Check `~/.cache/claude/auto-deny.log` for denial entry
4. `auto-off` → confirm normal prompting resumes
5. Without state file → confirm hook is transparent (exit 0)
