# Workflow Defaults

## Task and Agent Organization

Plans and tasks are **per-project**, not global.

- Plans: `<repo>/.claude/plans/` (NOT `~/.claude/plans/`)
- Tasks: `<repo>/.claude/tasks/` (NOT `~/.claude/tasks/`)

**Plan Naming:** `YYYYMMDD_HHmmss_UTC_descriptive_name.md`
**Task List Naming:** `YYYYMMDD_HHmmss_UTC_description` (set via `CLAUDE_CODE_TASK_LIST_ID`)
**Task Subject Naming:** `[Component] Imperative action` (e.g., `[Auth] Refactor OAuth flow to JWT`)

**Configuration:**
```bash
export CLAUDE_CODE_PLANS_DIR='.claude/plans'
export CLAUDE_CODE_TASKS_DIR='.claude/tasks'
```

**Agent Tracking** — when spawning agents:
```
Spawning <agent-type> for: <description>
agentId: <id>
Save with: claude-agent-save <id> <suggested-name>
```

**Commit plans and tasks** regularly — they provide valuable context for resuming work.

For work taking >30 minutes:
- Automatically use background agents when appropriate
- For parallel independent tasks, spawn multiple background agents
- User can monitor progress with Ctrl+T
- Notify user when background work completes

## File Creation Policy (CRITICAL)

- **NEVER create new files** unless absolutely necessary
- **ALWAYS prefer editing** existing files
- **NEVER create documentation** (*.md) unless explicitly requested
- **NEVER create ambiguous file variants** (no `-simple`, `-updated`, `-new`, `-final` suffixes)
  - Prefer editing existing file over creating new versions
  - If new version needed: use clear ordering (`-v2`, `-v3` or timestamps)
  - ASK if uncertain which file to update
- Temporary files → `tmp/`
- Failed runs → `archive/` with `REASON.txt`

## Shell Commands

- **Use subagent** for verbose output (scripts, builds, tests, logs)
- Direct execution OK for: `git status`, `ls`, `pwd`, simple commands
- Check `history` before running `.sh`/`.py` to match user's typical args
- **`tee` doesn't create parent directories** — always `mkdir -p dir/` before `cmd | tee dir/file.log`
- **Piped output appears stuck?** The upstream program is block-buffering (libc switches from line to block buffering when stdout isn't a TTY). Fix with `stdbuf -oL cmd | ...` or Python's `-u` flag
- **Prefer command-specific limits** over pipes: `git log -n 10` not `git log | head -10`

## Mid-Implementation Checkpoints

**Problem:** Claude reads code, makes assumptions, and starts implementing against a wrong mental model. This causes misunderstandings that waste context and require rework.

**When to checkpoint:** After exploring/reading code and BEFORE writing changes for any task touching 3+ files or involving unfamiliar code.

**Checkpoint format** (inline, not a separate document):
1. **Current state**: What the code does now (1-2 sentences)
2. **Goal mapping**: How planned changes achieve the objective
3. **Risky assumptions**: What I'm assuming that could be wrong (explicit list)
4. **Scope**: Files that will be touched

**Skip when**: Single-file change, code already read this session, or user says "just do it"

## Output Strategy (CRITICAL)

**Programmatic > contextual.** Code is reproducible; conversation context is not.

- **Generate code/scripts** rather than relying on previous context or memory
  - If a task will be repeated: write a script
  - If results need verification: produce checkable artifacts
  - If values come from earlier in conversation: re-derive them programmatically
- **Non-destructive outputs**: NEVER overwrite previous results
  - Experiment outputs → timestamped dirs (`out/DD-MM-YYYY_HH-MM-SS_name/`)
  - Data files → append mode (`>>`) or versioned naming (`-v2`, `-v3`)
  - Figures/tables → new timestamped files, symlink "latest" if needed
  - Analysis results → JSONL append, not JSON overwrite
