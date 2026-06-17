# Plan: Auto-Background Long-Running Bash Commands

## Context

Claude Code runs bash commands synchronously by default, blocking the conversation. Commands that take >1-2 minutes (package installs, builds, full test suites, dev servers) should run in the background via `run_in_background: true` so the user can continue working. Currently this relies on Claude choosing to set the flag, which it often doesn't.

**Goal**: Create a PreToolUse hook that detects long-running command patterns and automatically sets `run_in_background: true` via the `updatedInput` API.

## Approach

### 1. Create `claude/hooks/auto_background.sh`

PreToolUse hook with this flow:
1. Early exits: disabled, no jq, empty command, already backgrounded, explicit short timeout (≤30s)
2. Exclusion check via `case` statement (zero subprocess cost)
3. **Tier 1 (force)**: Single combined regex for high-confidence patterns → returns `updatedInput` with `run_in_background: true`
4. **Tier 2 (suggest)**: Single combined regex for medium-confidence patterns → returns `additionalContext` only

#### Tier 1 patterns (force-background) — combined into one regex

```
# Sleep / explicit waits
sleep\s+[0-9]

# Package managers: install/update
(npm|yarn|pnpm|bun)\s+(install|ci|add)
(pip|pip3)\s+install
uv\s+(sync|pip\s+install|add)
brew\s+(install|upgrade|update)
(apt|apt-get)\s+(install|update|upgrade|dist-upgrade)
conda\s+(install|update|create)

# Build commands
(npm|yarn|pnpm|bun)\s+run\s+build
cargo\s+build
docker\s+build
docker\s+compose\s+(up|build)

# Full test suites
(npm|yarn|pnpm|bun)\s+(test|run\s+test)
cargo\s+test
go\s+test\s+\./\.\.\.

# Dev servers (run forever)
(npm|yarn|pnpm|bun)\s+run\s+(dev|start|serve|watch)
(npm|yarn|pnpm|bun)\s+(start)
python.*\b(manage\.py\s+runserver|http\.server|flask\s+run|uvicorn|gunicorn)
next\s+(dev|start)
vite(\s|$)

# Git network ops
git\s+clone

# ML/training workloads
(python3?|uv\s+run)\s+.*\b(train|finetune|eval)\b
HYDRA_FULL_ERROR
```

#### Tier 2 patterns (suggest only)

```
pytest                    # Could be single fast test or full suite
docker\s+(exec|run)       # Depends on container command
wget|curl.*\.(tar|zip|gz) # File downloads
rsync|scp                 # File transfers
make\b                    # make clean is fast, make all is slow
tsc(\s|$)                 # TypeScript compilation
```

#### Exclusions (checked first, via bash `case` — no subprocess)

```
*--version* | *--help* | *--dry-run* | *-h | *-V
*pip list* | *pip show* | *pip freeze*
*npm list* | *npm ls* | *npm --version*
*brew list* | *brew info*
*docker ps* | *docker images* | *docker inspect*
*git status* | *git log* | *git diff* | *git branch* | *git show*
*make -n* | *make clean* | *make help* | *make format* | *make lint* | *make check*
*npm run lint* | *npm run format*
```

#### Performance: combined regexes

Instead of looping through 20+ patterns with individual `grep -qE` calls (20 subprocesses per command), combine all Tier 1 patterns into a single ERE and match once. Same for Tier 2. Exclusions use `case` (bash builtin, zero subprocess cost). Total: **2 grep calls max** per hook invocation.

```bash
TIER1_RE='sleep\s+[0-9]|\b(npm|yarn|pnpm|bun)\s+(install|ci|add|test|run\s+(build|test|dev|start|serve|watch)|start)\b|...'
if echo "$COMMAND" | grep -qE "$TIER1_RE"; then ...
```

### 2. Hook output format

**Key change from v1**: Do NOT include `permissionDecision: "allow"` — this bypasses the permission system (deny/ask lists, sandbox). Only return `updatedInput` to modify the input while letting the normal permission flow continue.

**Key change from v1**: `updatedInput` is a **partial merge** — only pass `{"run_in_background": true}`, not the full `tool_input`. The docs confirm: "Only fields present in updatedInput are replaced; other fields remain unchanged."

For force-backgrounded commands (Tier 1):
```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "updatedInput": { "run_in_background": true },
    "additionalContext": "Auto-backgrounded: long-running command detected. Use TaskOutput to check results. To override: re-run with run_in_background: false."
  }
}
```

For suggest-background commands (Tier 2):
```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "additionalContext": "NOTE: This command may take >1 minute. Consider using run_in_background: true."
  }
}
```

**Fallback**: If testing reveals `updatedInput` without `permissionDecision` doesn't work, add `"permissionDecision": "ask"` to show the user the modified input for confirmation.

### 3. Add to `claude/settings.json` as separate matcher group

**Critical**: Must be in its **own** `"matcher": "Bash"` entry. Bug [#15897](https://github.com/anthropics/claude-code/issues/15897) causes `updatedInput` to be silently dropped when multiple hooks share a matcher group.

```json
{
  "matcher": "Bash",
  "hooks": [
    { "type": "command", "command": "~/.claude/hooks/auto_background.sh" }
  ]
}
```

Inserted as second entry in the `PreToolUse` array, after the existing Bash hooks group.

### 4. Configuration

Env vars (follows existing hook conventions like `CLAUDE_READ_THRESHOLD`, `CLAUDE_TRUNCATE_THRESHOLD`):

| Env var | Default | Description |
|---------|---------|-------------|
| `CLAUDE_AUTOBACKGROUND` | `1` | Set to `0` to disable |
| `CLAUDE_AUTOBACKGROUND_MODE` | `force` | `force` (updatedInput) or `suggest` (additionalContext only) |
| `CLAUDE_AUTOBACKGROUND_EXTRA` | empty | Additional ERE patterns appended to Tier 1 regex (use `\|` for alternation within the ERE) |
| `CLAUDE_AUTOBACKGROUND_DEBUG` | `0` | Set to `1` to log decisions to stderr |

`CLAUDE_AUTOBACKGROUND_EXTRA` is treated as a single ERE string appended to the combined regex (not split on pipes), so patterns like `\b(webpack|vite)\b` work correctly.

### 5. Edge case handling

| Edge case | Handling |
|-----------|----------|
| Already `run_in_background: true` | Early exit, no modification |
| Explicit short timeout (≤30s) | Early exit — caller expects fast execution |
| Compound: `kill $PID && npm install` | Exclusion list doesn't match, Tier 1 matches `npm install`. But permission system still applies `ask` for `kill` since we don't return `permissionDecision: "allow"` |
| `sudo npm install` | Still matches Tier 1 (regex matches substring) |
| `NODE_ENV=prod npm run build` | Still matches Tier 1 (env prefix doesn't prevent match) |
| `make clean` | Caught by exclusion `case` before Tier 2 match |
| `grep -E` and `set -e` | All grep calls inside `if` guards to avoid premature exit |
| No `jq` available | Early exit with stderr warning |

## Files to modify

| File | Action |
|------|--------|
| `claude/hooks/auto_background.sh` | **Create** — new hook script (~80 lines) |
| `claude/settings.json` | **Edit** — add second Bash matcher group to PreToolUse array |

## Verification

```bash
# 1. Force-background (Tier 1)
echo '{"tool_input":{"command":"npm install"}}' | ./claude/hooks/auto_background.sh
# → JSON with updatedInput.run_in_background = true

# 2. Passthrough (no match)
echo '{"tool_input":{"command":"git status"}}' | ./claude/hooks/auto_background.sh
# → exit 0, no output

# 3. Exclusion (--version)
echo '{"tool_input":{"command":"npm --version"}}' | ./claude/hooks/auto_background.sh
# → exit 0, no output

# 4. Already backgrounded
echo '{"tool_input":{"command":"npm install","run_in_background":true}}' | ./claude/hooks/auto_background.sh
# → exit 0, no output

# 5. Suggest (Tier 2)
echo '{"tool_input":{"command":"pytest"}}' | ./claude/hooks/auto_background.sh
# → JSON with additionalContext only, no updatedInput

# 6. Disabled
CLAUDE_AUTOBACKGROUND=0 bash -c 'echo '\''{"tool_input":{"command":"npm install"}}'\'' | ./claude/hooks/auto_background.sh'
# → exit 0, no output

# 7. Dev server detection
echo '{"tool_input":{"command":"npm run dev"}}' | ./claude/hooks/auto_background.sh
# → JSON with updatedInput.run_in_background = true

# 8. Sleep detection
echo '{"tool_input":{"command":"sleep 30 && curl localhost:8080"}}' | ./claude/hooks/auto_background.sh
# → JSON with updatedInput.run_in_background = true

# 9. make clean exclusion
echo '{"tool_input":{"command":"make clean"}}' | ./claude/hooks/auto_background.sh
# → exit 0, no output

# 10. Short timeout skip
echo '{"tool_input":{"command":"npm install","timeout":10000}}' | ./claude/hooks/auto_background.sh
# → exit 0, no output (timeout ≤ 30s)

# 11. Live test: new Claude Code session, run "npm install" in a node project
```
