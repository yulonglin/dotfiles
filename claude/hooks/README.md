# Claude Code Hooks

Hooks for automating task and agent management workflows.

## Available Hooks

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
