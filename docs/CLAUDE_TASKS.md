# Claude Code Task and Agent Management

Quick reference for managing tasks and agents in Claude Code with timestamped tracking.

## Task List Management

### Starting New Work

```bash
# Start Claude with a new timestamped task list
claude-new oauth-refactor
# Creates: 20260125_034300_UTC_oauth-refactor
# Saves to .claude_task_list_id for resuming

# Resume the last task list in current directory
claude-last

# Start with a specific task list name
claude-with 20260125_034300_UTC_oauth-refactor

# List all available task lists
claude-tasks-list
```

### Task List Storage

Task lists are stored in: `~/.claude/tasks/<TASK_LIST_ID>/`

The `.claude_task_list_id` file in your project directory remembers your last task list.

### Monitoring Tasks

While Claude is running:
- Press `Ctrl+T` to toggle task list view
- Shows up to 10 tasks with status and dependencies
- Real-time updates as work progresses

## Agent Management

### Saving Agent IDs

When Claude spawns an agent, it outputs:
```
Spawning research-engineer for: OAuth experiments
agentId: a5b5164
Save with: claude-agent-save a5b5164 oauth-experiments
```

Save it immediately:
```bash
claude-agent-save a5b5164 oauth-experiments
# Saves as: 20260125_034500_UTC_oauth-experiments
```

### Resuming Agents

```bash
# Resume the most recent agent
claude-agent-resume
# Shows: Tell Claude: 'Resume agent a5b5164'

# Resume a specific agent by name
claude-agent-resume 20260125_034500_UTC_oauth-experiments

# List all saved agents
claude-agent-list
```

### Agent Storage

Agents are saved in: `~/.claude/saved_agents/`
- Timestamped filenames for chronological tracking
- `last` pointer always references most recent agent

## Complete Workflow Example

### Day 1: Start New Feature
```bash
# Start with timestamped task list
claude-new payment-integration

# In Claude:
> "Implement Stripe payment integration. Use background agents for experiments."
# Output: agentId: a5b5164

# In terminal, save the agent:
claude-agent-save a5b5164 stripe-experiments

# Exit Claude (Ctrl+C)
```

### Day 2: Resume Work
```bash
# Resume yesterday's task list
claude-last

# Check what agents were working
claude-agent-list

# In Claude:
> "What's the status of tasks?"
> "Resume agent a5b5164"  # From agent list output
```

### Working Across Multiple Sessions

```bash
# Terminal 1: Backend work
export CLAUDE_CODE_TASK_LIST_ID=20260125_034300_UTC_payment-integration
claude
> "Work on backend payment API"

# Terminal 2: Frontend work (sees same tasks!)
export CLAUDE_CODE_TASK_LIST_ID=20260125_034300_UTC_payment-integration
claude
> "What tasks are in progress?"
> "Work on frontend payment UI"
```

## Naming Conventions

### Task Lists
Format: `YYYYMMDD_HHmmss_UTC_description`
- Always UTC timestamps for consistency
- Descriptive name explains the work

### Task Subjects (Created by Claude)
Format: `[Component] Action`
- Example: `[Auth] Refactor OAuth flow`
- Example: `[API] Implement rate limiting`

### Agent Save Names
Format: `YYYYMMDD_HHmmss_UTC_description`
- Automatically timestamped when you save
- Description should match the agent's purpose

## Tips

1. **Save agent IDs immediately** when Claude outputs them
2. **Use descriptive names** for task lists (not "test" or "work")
3. **Check Ctrl+T frequently** to monitor parallel work
4. **Use `.claude_task_list_id`** to track current project work
5. **List agents before resuming** to remember what was running

## Troubleshooting

**Q: Lost track of an agent ID**
```bash
claude-agent-list  # Shows all saved agents with IDs
```

**Q: Forgot what task list I was using**
```bash
cat .claude_task_list_id  # Shows current directory's task list
```

**Q: Want to see all task lists**
```bash
claude-tasks-list  # Lists 20 most recent
ls -lt ~/.claude/tasks/  # Full chronological list
```

**Q: Agent completed but I can't find the output**
- Check the conversation history in Claude
- Background agents notify on completion
- Output files are shown when agent launches

## Integration with Existing Dotfiles

These commands work seamlessly with your existing setup:
- `utc_timestamp` - Used internally by the scripts
- `custom_bins/` - Agent scripts auto-added to PATH
- `aliases.sh` - Task management functions loaded automatically
- Global CLAUDE.md - Contains conventions Claude follows
