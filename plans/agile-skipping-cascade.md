# Session Watchdog: Detect Stuck Claude Code Sessions

## Context

Claude Code frequently gets stuck thinking/waiting for hours with no visible progress. Well-documented across multiple GitHub reports:
- [#20336](https://github.com/anthropics/claude-code/issues/20336): Post-response hang in "Caramelizing" state (19+ min)
- [#24478](https://github.com/anthropics/claude-code/issues/24478): CLI freezes after ~10 min, requires SIGKILL
- [#15945](https://github.com/anthropics/claude-code/issues/15945): MCP server hangs 16+ hours, 70+ zombie processes
- [#25629](https://github.com/anthropics/claude-code/issues/25629): Hangs after completing task, never closes
- [#18390](https://github.com/anthropics/claude-code/issues/18390): Background tasks show "running" after crash

No built-in watchdog or timeout exists. Hooks are event-driven (not periodic), so the solution is a **background watchdog process launched via SessionStart hook**.

## Approach

A lightweight background script launched at session start that:
1. Tracks whether Claude is **actively working** (vs idle waiting for user)
2. Monitors the transcript file for staleness when in working state
3. Sends macOS notification when no progress detected for threshold duration

### Key design decisions

- **Notification only** (no auto-interrupt) — user decides how to intervene
- **Only alerts during processing** — uses UserPromptSubmit/Stop hooks to track working state, avoids false positives when user is away
- **10-min default threshold** — catches both quick-command hangs (`ls` stuck for hours) and experiments producing no output. Configurable via env var
- **Global hooks in settings.json** — avoids plugin cache sync complexity

## Files

### New files (4)

| File | Purpose |
|------|---------|
| `claude/hooks/watchdog.sh` | Background monitor loop (long-running detached process) |
| `claude/hooks/watchdog_start.sh` | SessionStart hook: extract session info, launch watchdog |
| `claude/hooks/watchdog_stop.sh` | SessionEnd hook: kill watchdog, cleanup |
| `claude/hooks/watchdog_mark.sh` | UserPromptSubmit/Stop hook: toggle working state marker |

### Modified files (1)

| File | Change |
|------|--------|
| `claude/settings.json` | Add `hooks` section with 4 hook events |

## Implementation

### Hook wiring (`claude/settings.json`)

Add `hooks` key at top level:

```json
"hooks": {
  "SessionStart": [
    {
      "matcher": "startup|resume",
      "hooks": [{
        "type": "command",
        "command": "$HOME/.claude/hooks/watchdog_start.sh"
      }]
    }
  ],
  "UserPromptSubmit": [
    {
      "hooks": [{
        "type": "command",
        "command": "$HOME/.claude/hooks/watchdog_mark.sh working"
      }]
    }
  ],
  "Stop": [
    {
      "hooks": [{
        "type": "command",
        "command": "$HOME/.claude/hooks/watchdog_mark.sh idle"
      }]
    }
  ],
  "SessionEnd": [
    {
      "hooks": [{
        "type": "command",
        "command": "$HOME/.claude/hooks/watchdog_stop.sh"
      }]
    }
  ]
}
```

### `watchdog_start.sh` (SessionStart hook)

1. Read JSON from stdin → extract `session_id`, `transcript_path`
2. Check `CLAUDE_WATCHDOG_ENABLED` (default `1`), exit 0 if disabled
3. Kill any existing watchdog for this session (handles `resume`)
4. Launch `watchdog.sh <session_id> <transcript_path>` detached (`nohup ... & disown`)
5. Exit 0 immediately

### `watchdog_mark.sh` (UserPromptSubmit + Stop hook)

- Accepts `working` or `idle` as `$1`
- Reads `session_id` from JSON stdin
- `working` → `touch $TMPDIR/claude-watchdog-<session_id>.working`
- `idle` → `rm -f $TMPDIR/claude-watchdog-<session_id>.working`
- Exit 0

### `watchdog.sh` (background process)

Arguments: `<session_id> <transcript_path>`

1. Write PID to `$TMPDIR/claude-watchdog-<session_id>.pid`
2. Trap EXIT → cleanup PID file
3. Loop every `CLAUDE_WATCHDOG_INTERVAL` (default 60s):
   - **Exit conditions:** transcript file missing, max lifetime exceeded (8h)
   - **Skip if not working:** marker file `$TMPDIR/claude-watchdog-<session_id>.working` must exist
   - **Check transcript mtime:** cross-platform (`stat -f %m` macOS / `stat -c %Y` Linux)
   - **If stale > `CLAUDE_WATCHDOG_TIMEOUT` (default 600s):**
     - macOS notification: `osascript -e 'display notification "..." with title "Claude Code" sound name "Submarine"'`
     - Terminal bell: `printf '\a'`
     - Set cooldown — don't re-notify for another TIMEOUT seconds
   - **Cooldown prevents spam** — after one notification, waits full TIMEOUT again

### `watchdog_stop.sh` (SessionEnd hook)

1. Read `session_id` from JSON stdin
2. Kill watchdog process via PID file
3. Remove PID file + marker file

### Configuration (env vars)

| Variable | Default | Description |
|----------|---------|-------------|
| `CLAUDE_WATCHDOG_ENABLED` | `1` | Set to `0` to disable |
| `CLAUDE_WATCHDOG_TIMEOUT` | `600` | Seconds of inactivity before alerting (10 min) |
| `CLAUDE_WATCHDOG_INTERVAL` | `60` | Check frequency in seconds |
| `CLAUDE_WATCHDOG_MAX_LIFE` | `28800` | Max watchdog lifetime (8 hours) |

Set in shell profile or `claude/settings.json` env section.

## What it catches

| Failure mode | How detected |
|-------------|-------------|
| CLI freeze mid-processing (#24478) | Working marker set, transcript stops updating |
| "Caramelizing" hang post-response (#20336) | Stop hook fires (marker cleared), but if hang happens BEFORE Stop → caught. If AFTER Stop → not caught (working on v2: SubagentStop tracking) |
| MCP server hang (#15945) | Tool call started, PostToolUse never fires, transcript stale |
| Background task hang (#18390) | If Claude is waiting (working state), transcript stale |
| Simple command hang (ls, git) | Working marker set, no output → stale transcript |

## Verification

1. **Launch:** Start session → `ps aux | grep watchdog` → process running
2. **PID file:** `ls $TMPDIR/claude-watchdog-*.pid` → exists
3. **Working marker:** Submit prompt → `ls $TMPDIR/claude-watchdog-*.working` → exists
4. **Idle marker:** Wait for Claude to respond → marker gone
5. **Fast notification test:** `CLAUDE_WATCHDOG_TIMEOUT=10 CLAUDE_WATCHDOG_INTERVAL=5` → submit slow prompt → notification in ~15s
6. **Resume:** Resume session → old watchdog killed, new one started
7. **Cleanup:** Exit session → watchdog process gone, all temp files removed
8. **Disable:** `CLAUDE_WATCHDOG_ENABLED=0` → no watchdog process
