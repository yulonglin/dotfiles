---
name: task-management
description: Use timestamped task lists and track agent IDs following project conventions
---

# Task and Agent Management

This skill enables proper use of the task management system with UTC timestamps and agent tracking.

## When to Use This Skill

- Starting work on a multi-step project
- Spawning background agents for long-running work
- Coordinating parallel work across multiple agents
- Resuming previous work

## Plan Naming

When creating plans (via EnterPlanMode or in plan mode), save them with informative, timestamped names:

**Format:** `.claude/plans/YYYYMMDD_HHmmss_UTC_descriptive_name.md`

**Examples:**
- `.claude/plans/20260125_143022_UTC_stripe_payment_integration.md`
- `.claude/plans/20260125_150000_UTC_database_migration_postgres15.md`
- `.claude/plans/20260125_160000_UTC_auth_refactor_to_oauth2.md`

**Best practices:**
- Include the feature/problem name in the filename
- Use underscores for readability
- Avoid generic names like "plan.md" or "implementation.md"
- Save to `.claude/plans/` directory for organization

## Task List Management

### Creating Timestamped Task Lists

When starting new work, use UTC timestamped task list IDs:

**Format:** `YYYYMMDD_HHmmss_UTC_description`

**How to set:**
```bash
export CLAUDE_CODE_TASK_LIST_ID=20260125_154500_UTC_oauth_refactor
```

**User-friendly commands:**
- `claude-new <description>` - Creates timestamped task list automatically
- `claude-last` - Resumes last task list in directory
- `claude-with <name>` - Uses specific task list

### Task Subject Naming

When creating tasks (via TaskCreate tool), follow these conventions:

**Format:** `[Component] Imperative action`

**Examples:**
- `[Auth] Refactor OAuth flow to JWT`
- `[API] Implement rate limiting middleware`
- `[Database] Add migration for user roles`

**For multi-day tasks, prefix with UTC date:**
- `20260125_UTC [Auth] Complete OAuth migration`

### Monitoring Tasks

User can monitor with `Ctrl+T` to see:
- All tasks in current task list
- Status (pending/in_progress/completed)
- Dependencies (blockedBy, blocks)

## Agent Tracking

### When Spawning Agents

When you spawn an agent using the Task tool, always output:

```
Spawning <agent-type> for: <clear description>
agentId: <actual-agent-id>

Save this agent: claude-agent-save <actual-agent-id> <suggested-name>
```

**Suggested name format:** Use descriptive keywords (no timestamp needed, script adds it)
- Good: `oauth-experiments`
- Good: `payment-integration-tests`
- Bad: `agent` or `background-work`

### Agent Management Commands

The user has these commands available:
- `claude-agent-save <id> <description>` - Saves agent with timestamped name
- `claude-agent-resume [name]` - Shows how to resume an agent
- `claude-agent-list` - Lists all saved agents

### Resuming Agents

When user wants to resume previous work:
1. They run `claude-agent-list` to see saved agents
2. They run `claude-agent-resume <name>` to get the agent ID
3. They tell you: "Resume agent <id>"
4. You call Task tool with `resume: "<id>"` parameter

## Background Agents

### When to Use Background Agents

Use `run_in_background: true` when:
- Work will take >30 minutes
- Parallel independent tasks can run simultaneously
- User wants to continue working while agent executes

**Example:**
```
Task(
  subagent_type="research-engineer",
  prompt="Run experiments with 1000 samples",
  run_in_background=true
)
```

### Communicating Background Work

When starting background work:
1. Explain what will run in background
2. Output the agent ID clearly
3. Suggest save command
4. Tell user they can monitor with Ctrl+T
5. Mention they'll be notified on completion

**Template:**
```
Starting background agent for: <description>
This will take approximately <estimate>

agentId: <id>
Save with: claude-agent-save <id> <description>

Monitor progress: Press Ctrl+T anytime
You'll be notified when complete.
```

## Shared Task Lists

### Cross-Session Coordination

Multiple Claude sessions can share a task list by using the same ID:

```bash
# Session 1
export CLAUDE_CODE_TASK_LIST_ID=20260125_154500_UTC_project_name
claude

# Session 2 (different terminal, sees same tasks)
export CLAUDE_CODE_TASK_LIST_ID=20260125_154500_UTC_project_name
claude
```

When user starts a new session with existing task list:
1. Check current tasks with TaskList tool
2. Report what's in progress
3. Ask what they want to work on
4. Coordinate to avoid conflicts (don't edit same files)

## Best Practices

### Task Organization
- Create clear task subjects with component names
- Set up dependencies (blockedBy) for sequential work
- Mark tasks in_progress when starting, completed when done
- Update task status regularly so user sees progress

### Agent Coordination
- Always output agent IDs clearly for tracking
- Suggest descriptive save names
- For parallel work, explain the agent strategy
- Remind user they can resume agents later

### Communication
- Proactively suggest using task lists for complex work
- Remind user to save agent IDs before they lose them
- Report task progress at natural checkpoints
- Use Ctrl+T references for monitoring

## Integration with Existing Workflows

### With CLAUDE.md Conventions
This skill implements the conventions documented in CLAUDE.md:
- UTC timestamps for all date/time references
- Descriptive naming patterns
- Background work for long operations
- Proper coordination across agents

### With Other Tools
- Works with `/spec-interview` for large features
- Works with `EnterPlanMode` for planning before tasks
- Works with existing UTC timestamp utilities (utc_date, utc_timestamp)
- Compatible with .claude_task_list_id files

## Examples

### Starting Complex Project
```
User: "I need to refactor our authentication to OAuth2"

Agent: "Let me set up organized task tracking for this work.

I recommend creating a task list:
claude-new oauth-refactor

This creates: 20260125_154500_UTC_oauth-refactor

I'll create tasks for:
1. [Auth] Analyze current authentication flow
2. [Auth] Design OAuth2 integration
3. [Auth] Implement backend OAuth
4. [API] Update API endpoints
5. [Tests] Add OAuth test coverage

Should I proceed with this plan?"
```

### Spawning Background Agent
```
User: "Run experiments on 5 different models"

Agent: "I'll spawn a background agent for this work.

Spawning research-engineer for: 5-model comparison experiments
agentId: a5b5164

Save this agent: claude-agent-save a5b5164 model-comparison

This will run in the background (approximately 2-3 hours).
Monitor progress: Press Ctrl+T
You'll be notified when complete.

You can continue working on other tasks."
```

### Resuming Previous Work
```
User: "Continue the OAuth work from yesterday"

Agent: "Checking task list from yesterday...

Task list: 20260125_154500_UTC_oauth-refactor
Found 5 tasks:
- [Auth] Analyze current flow (completed)
- [Auth] Design OAuth2 integration (completed)
- [Auth] Implement backend (in_progress)
- [API] Update endpoints (pending, blocked by backend)
- [Tests] Add coverage (pending, blocked by backend)

The backend implementation is in progress. Want to continue that,
or work on something else?"
```

## Troubleshooting

**Q: User forgot to save agent ID**
- Check conversation history for "agentId: <id>" mentions
- Can resume from agent ID without saved name

**Q: Task list disappeared**
- Task lists are in ~/.claude/tasks/
- If no CLAUDE_CODE_TASK_LIST_ID set, tasks are ephemeral
- Use claude-tasks-list to see available lists

**Q: Multiple agents editing same file**
- Never spawn multiple agents to edit same file
- Coordinate tasks to work on different files
- Use dependencies (blockedBy) to sequence file edits

## Summary

Use this skill to:
- Create properly named task lists with UTC timestamps
- Track agent IDs for resuming work
- Coordinate background and parallel work
- Follow project conventions automatically

The goal is seamless organization of complex, long-running work with clear tracking and easy resuming.
