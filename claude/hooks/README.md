# Claude Code Hooks

Hooks for automating task and agent management workflows.

## Available Hooks

### inject_timestamp.sh + elapsed_stamp.sh (time awareness)

**Purpose:** Keep the model clock-aware. `inject_timestamp.sh` (UserPromptSubmit) prints `[Now: Thu 2026-08-27 02:40 PDT (UTC-07:00) · 09:40 UTC · 2h13m since your last message]` — the gap clause only past `CLAUDE_TIME_GAP_MIN` (10). `elapsed_stamp.sh` (PostToolUse, all tools) emits `[Time check: 25m elapsed in this turn · now …]` as `additionalContext`, at most once per `CLAUDE_TIME_STAMP_INTERVAL_MIN` (5) — the piece Ofengenden & Andriushchenko (2026) show agents need most: scrubbing timestamps roughly doubles their elapsed-time error. Shared code and rationale: `lib_time_stamp.sh`.

**Zone:** `CLAUDE_LOCAL_TZ` (exported from `config/zshrc.sh`, default `America/Los_Angeles`) → `TZ` → `/etc/timezone` → `/etc/localtime` → UTC; an invalid zone warns loudly in the stamp.

**Off switches:** `time = off` in `features.conf` (global); `touch .claude/no-time-stamps` (per repo — model-organism repos, since a stated date is a backdoor-trigger surface); `CLAUDE_TIME_STAMPS=off` (per shell). The remember plugin's own `[HH:MM UTC — user]` stamp is retired via `"prompt_stamp": "off"` in `~/.remember/config.json` so time has one owner.

**Test:** `tests/test_time_stamps.sh`.

### agent_spawned.sh

**Purpose:** Reminds user to save agent IDs when agents are spawned

**Triggers:** When an agent is spawned with an ID

**Output:**
```
═══════════════════════════════════════════════════
🤖 Agent Spawned: a5b5164
═══════════════════════════════════════════════════

💾 Save this agent for later:
   claude-agent-save a5b5164 <description>

📋 Example:
   claude-agent-save a5b5164 oauth-experiments

📊 Monitor progress: Press Ctrl+T
═══════════════════════════════════════════════════
```

### auto_commit.sh

**Purpose:** SessionEnd trigger that enqueues guarded auto-commit work.

**Behavior:**
- Resolves repo from hook payload and exits fast on opt-out conditions.
- Delegates to `auto_commit_worker.sh` (async by default).
- Honors global disable sentinel and `.no-auto-commit`.

### auto_commit_worker.sh

**Purpose:** Executes auto-commit with safety and cost controls.

**Key safeguards:**
- Depth gate via `AUTO_AGENT_MAX_DEPTH` / `AUTO_AGENT_DEPTH`.
- Per-repo lock, cooldown, and hourly cap.
- Skips gitlinks/submodules and `.claude/worktrees/*` paths.
- Anomaly gating through `custom_bins/ccusage-guard` with weekly pace WARN/STOP states.
- Anomaly STOP is repo-scoped by default (repo disable sentinel).
- Hard projected-limit STOP is global (global emergency sentinel).
- Default backend order is non-Claude (`codex,gemini`); Claude fallback is opt-in.

### check_agent_depth.sh

**Purpose:** `PreToolUse` guard for `Task` delegation depth.

**Behavior:**
- Blocks tool call when `AUTO_AGENT_DEPTH >= AUTO_AGENT_MAX_DEPTH`.
- Intended to cap recursive delegation chains.

### simplify_mark_dirty.sh / simplify_track_reuse.py / simplify_nudge.sh

**Purpose:** Suggest a `/simplify` pass when the session produced work worth one. Two independent signals feed one `Stop` message; both are soft nudges (`systemMessage`) that never continue the turn.

**Behavior:**
- `simplify_mark_dirty.sh` (`PostToolUse`, `Write|Edit`) touches a per-session marker when a code file changes → "run a quality pass".
- `simplify_track_reuse.py` (`PostToolUse`, `Bash`) tallies *executions* of throwaway scripts in a per-session JSON state file (under a 0700 per-user dir in `TMPDIR` — its contents reach the user as a message). A run whose file is unchanged since the previous run counts as "stable", so edit-run-edit-run debugging never accumulates, and a path that can't be stat'ed is never stable.
- Scratch-ness is judged *relative to the enclosing repo*: `tmp_probe.py` or anything under a `tmp/`/`scratch/` segment qualifies, but a repo or worktree checked out under `/tmp` doesn't turn its own `tests/` into scratch. Commands are followed through `cd`, glued operators, interpreter flags and `uv run`; redirect targets and huge inline programs are skipped.
- `simplify_nudge.sh` (`Stop`) fires when a script hit `CLAUDE_SIMPLIFY_REUSE_RUNS` (default 3) runs with at least one stable run → "promote it into a permanent component" (criteria and destinations: `rules/reusable-component-promotion.md`). Each candidate is nudged once per session.

**Tests:** `test_simplify_reuse.sh`.

## Runtime Policy

Shared config is in `config/ai_automation.sh` (optionally overridden by `~/.claude/ai_automation.local.sh`).

Useful controls:
- `auto-guard` → show current guard state
- `auto-approve [minutes]` → temporary WARN override
- `auto-disable` / `auto-enable` → repo-scoped stop / resume
- `auto-disable --global` / `auto-enable --global` → global emergency stop / resume
- `auto-trace [project]` → generate anomaly trace report

## Hook Integration

### Automatic Integration (If Supported)

If Claude Code supports automatic hook triggering, this would be configured in `settings.json`:

```json
{
  "hooks": {
    "agent_spawned": {
      "command": "~/.claude/hooks/agent_spawned.sh",
      "trigger": "agent_output",
      "pattern": "agentId:"
    }
  }
}
```

### Manual Integration

Until automatic hooks are available, the reminder is built into Claude's behavior via:
- CLAUDE.md conventions (Claude outputs save commands automatically)
- task-management.md skill (agents follow the pattern)

## Adding New Hooks

To add a new hook:

1. Create the hook script in this directory
2. Make it executable: `chmod +x hooks/<name>.sh`
3. Document it in this README
4. Test it manually first
5. Add automatic integration when Claude Code supports it

## Future Hooks

Potential hooks to implement:

- **task_list_created.sh** - Reminds to set up .claude_task_list_id
- **task_completed.sh** - Celebrates milestone completions
- **session_start.sh** - Shows task list summary on startup
- **agent_completed.sh** - Summarizes agent work and suggests cleanup

## Testing Hooks

Test the agent_spawned hook manually:

```bash
# Simulate agent output
echo "agentId: a5b5164" | ./agent_spawned.sh

# Or with full output
./agent_spawned.sh "Spawning agent... agentId: a5b5164"
```

## Integration with Task Management

These hooks complement the task management system:
- Shell functions: `claude-new`, `claude-agent-save`, etc.
- CLAUDE.md: Conventions for naming and behavior
- Skills: `task-management.md` for agent usage
- Hooks: Automatic reminders and triggers

Together they create a seamless workflow for managing complex, long-running work.
