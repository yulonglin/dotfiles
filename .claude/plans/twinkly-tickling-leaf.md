# Plan: Auto-Background Long-Running Bash Commands

## Context

Claude Code runs bash commands synchronously by default, blocking the conversation. Commands that take >1-2 minutes (package installs, builds, full test suites) should run in the background via `run_in_background: true` so the user can continue working. Currently this relies on Claude choosing to set the flag, which it often doesn't.

**Goal**: Create a PreToolUse hook that detects long-running command patterns and automatically sets `run_in_background: true` via the `updatedInput` API.

## Approach

### 1. Create `claude/hooks/auto_background.sh`

PreToolUse hook that:
1. Reads `tool_input.command` from stdin JSON
2. Skips if already backgrounded or matches exclusion patterns
3. **Tier 1 (force)**: Matches high-confidence long-running patterns → returns `updatedInput` with `run_in_background: true`
4. **Tier 2 (suggest)**: Matches medium-confidence patterns → returns `additionalContext` suggesting Claude background it

**Tier 1 patterns (force-background):**
- Package installs: `npm install|ci`, `pip install`, `uv sync|add`, `brew install|upgrade`, `apt install`
- Build commands: `npm run build`, `cargo build`, `docker build`, `docker compose up`, `make` (without `-n`)
- Full test suites: `npm test`, `cargo test`, `go test ./...`, `make test`
- Git network ops: `git clone`
- ML workloads: `python.*train|finetune|eval`, Hydra experiments
- System updates: `brew update`, `apt update|upgrade`

**Tier 2 patterns (suggest-background):**
- `pytest` (without more specific match), `docker exec|run`, `wget`, `rsync`, `scp`, `conda install`

**Exclusions (never background):**
- Already `run_in_background: true`
- `--version`, `--help`, `--dry-run`
- Read-only commands: `pip list`, `npm list`, `docker ps|images`, `git status|log|diff`

**Configuration via env vars** (follows existing hook conventions):
- `CLAUDE_AUTOBACKGROUND=0` to disable
- `CLAUDE_AUTOBACKGROUND_MODE=suggest` to switch from force to suggest-only
- `CLAUDE_AUTOBACKGROUND_EXTRA` for additional force patterns (pipe-separated)

### 2. Add to `claude/settings.json` as separate matcher group

**Critical**: Must be in its **own** `"matcher": "Bash"` entry, not alongside existing hooks. Bug [#15897](https://github.com/anthropics/claude-code/issues/15897) causes `updatedInput` to be silently dropped when multiple hooks exist in the same matcher group (hooks run in parallel; other hooks returning exit 0 without updatedInput overwrite ours).

The `deny > ask > allow` precedence still works across groups, so `check_secrets.sh` (exit 2) still blocks dangerous commands.

```json
{
  "matcher": "Bash",
  "hooks": [
    { "type": "command", "command": "~/.claude/hooks/auto_background.sh" }
  ]
}
```

Inserted after the existing Bash matcher group in the `PreToolUse` array.

### 3. Hook output format

For force-backgrounded commands:
```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow",
    "updatedInput": { "command": "...", "run_in_background": true },
    "additionalContext": "Auto-backgrounded: long-running command detected. Use TaskOutput to check results when done."
  }
}
```

`updatedInput` includes the full original `tool_input` merged with `run_in_background: true` (safe regardless of whether the API does merge vs replace).

## Files to modify

| File | Action |
|------|--------|
| `claude/hooks/auto_background.sh` | **Create** — new hook script |
| `claude/settings.json` | **Edit** — add second Bash matcher group to PreToolUse |

## Verification

1. Test force-background: `echo '{"tool_input":{"command":"npm install"}}' | ./claude/hooks/auto_background.sh` → JSON with `run_in_background: true`
2. Test passthrough: `echo '{"tool_input":{"command":"git status"}}' | ./claude/hooks/auto_background.sh` → exit 0, no output
3. Test exclusion: `echo '{"tool_input":{"command":"npm --version"}}' | ./claude/hooks/auto_background.sh` → exit 0, no output
4. Test already-bg: `echo '{"tool_input":{"command":"npm install","run_in_background":true}}' | ./claude/hooks/auto_background.sh` → exit 0, no output
5. Test suggest: `echo '{"tool_input":{"command":"pytest"}}' | ./claude/hooks/auto_background.sh` → JSON with `additionalContext` only
6. Test disable: `CLAUDE_AUTOBACKGROUND=0 echo '...' | ./claude/hooks/auto_background.sh` → exit 0, no output
7. Live test: start a new Claude Code session, ask it to run `npm install` in a node project, verify it runs in background
