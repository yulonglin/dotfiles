# Multi-Agent Coordination

Multiple coding agents (Claude Code, Codex, Cursor, Gemini) may work on this codebase simultaneously. Coordinate to avoid conflicts.

## Claims Directory

Claims live in `.agent-claims/` at the project root (gitignored globally via `config/ignore_global`). Each agent writes its own file — no shared mutable state, no write conflicts.

Agents in different worktrees don't need coordination — they have isolated file copies and merge later. Chope (Singaporean English: to reserve a spot) is for agents sharing the same working tree.

## Before Starting Work

**Read ALL claim files**, then decide:

```bash
CLAIMS_DIR="$(git rev-parse --show-toplevel)/.agent-claims"
# Reap dead claims (process exited/crashed)
# Note: kill -0 only works for same-user, same-machine agents.
# For remote agents (SSH, containers), fall back to timestamp: claims >2h old are stale.
for f in "$CLAIMS_DIR"/* 2>/dev/null; do
  [ -f "$f" ] || continue
  pid=$(grep '^pid:' "$f" | awk '{print $2}')
  if [ -n "$pid" ]; then
    kill -0 "$pid" 2>/dev/null || rm -f "$f"  # ephemeral claim file, safe to delete
  else
    # No PID (remote agent?) — check timestamp staleness
    since=$(grep '^since:' "$f" | awk '{print $2}')
    if [ -n "$since" ]; then
      age=$(( $(date -u +%s) - $(date -j -u -f "%Y-%m-%dT%H:%MZ" "$since" +%s 2>/dev/null || echo 0) ))
      [ "$age" -gt 7200 ] && rm -f "$f"
    fi
  fi
done
# Show surviving claims
for f in "$CLAIMS_DIR"/* 2>/dev/null; do
  [ -f "$f" ] && echo "=== $(basename "$f") ===" && cat "$f" && echo
done
```

If another agent's claim overlaps with files you need:
- **Use a worktree** — `cw <name>` for full isolation (preferred)
- **Wait** — if the overlap is minor and the agent is close to finishing
- **Coordinate** — if in an agent team, use SendMessage to negotiate

## Claiming Work ("Chope")

Use `$PPID` (the parent Claude Code process), not `$$` (ephemeral subshell PID). `$PPID` is stable across Bash invocations within a session.

```bash
CLAIMS_DIR="$(git rev-parse --show-toplevel)/.agent-claims"
mkdir -p "$CLAIMS_DIR"
printf '%s\n' \
  "agent: claude-code" \
  "pid: $PPID" \
  "branch: $(git branch --show-current)" \
  "worktree: $(git rev-parse --show-toplevel)" \
  "files: deploy.sh, config/aliases.sh" \
  "task: Refactoring deploy components" \
  "since: $(date -u +%Y-%m-%dT%H:%MZ)" \
  > "$CLAIMS_DIR/$PPID"
```

**Release when done:**
```bash
rm -f "$(git rev-parse --show-toplevel)/.agent-claims/$PPID"  # ephemeral claim file, safe to delete
```

### Claim format

```yaml
agent: <type>              # claude-code, cursor, codex, gemini, human
pid: <process-id>          # parent process for liveness checking (kill -0)
branch: <branch-name>      # current git branch
worktree: <abs-path>       # working directory
files: <file1>, <file2>    # specific files (not globs — explicit paths for reliable overlap detection)
task: <description>        # what you're doing (human-readable)
since: <ISO-8601 UTC>      # when work started
```

All fields are plain `key: value` text — readable by `cat`, parseable by `grep`/`awk`. No special tools needed.

Claim at **file level**. If you need finer granularity (e.g., specific functions), note it in the `task:` field, but assume file-level overlap detection.

### Why this design avoids problems

| Problem | How it's solved |
|---------|----------------|
| **Race conditions** | Each agent writes only its own file (keyed by PPID). No concurrent writes to shared state |
| **Deadlocks** | Claims are advisory. No blocking. Agents can always proceed with awareness |
| **Stale claims** | `kill -0 $pid` detects dead processes instantly. Fallback: 2h timestamp expiry for remote agents |
| **Agent crashes** | PID dies → next agent's reap step cleans it up automatically |
| **Multiple agents, same branch** | PPID is unique per session. Two agents on `main` get separate claim files |
| **Different worktrees** | No coordination needed — isolated files, merge later |
| **Remote agents** | `kill -0` won't work across machines; timestamp fallback handles this |
| **Sandbox `rm` rule** | Claim files are ephemeral coordination artifacts — `rm -f` is safe (not user code) |

### Rules

- Check ALL claims before starting — not just your own
- Remove your claim on commit or when switching tasks
- Reap dead claims (PID check) before reading
- Claims are **advisory** — they surface conflicts, they don't enforce locks

## Conflict Resolution

| Situation | Action |
|-----------|--------|
| Dead PID / stale timestamp | Reap it (already handled by check step) |
| Live claim, non-overlapping files | Proceed (no conflict) |
| Live claim, overlapping files | Use worktree isolation or wait |
| Live claim, same worktree + overlapping files | **Stop** — one agent must move to a worktree |
| Different worktrees | Safe — merge later with `cwmerge` |

## What NOT to Do

- Don't skip checking claims — it's one `ls` + `cat`
- Don't edit files another live agent has claimed without checking
- Don't hold claims across unrelated tasks — release and re-claim
- Don't use `$$` for claim IDs — use `$PPID` (stable across Bash invocations)
