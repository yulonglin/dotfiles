# Skill-to-Agent Conversion Implementation Plan

**Date:** 2026-02-03
**Context:** Converting delegation-based skills (codex-cli, claude-code) into agents based on analysis in recursive-seeking-hellman.md
**Plugin:** code-toolkit v1.0.0

## Summary

Convert two delegation-pattern skills into agents for better semantic clarity. Skills represent workflows Claude follows; agents represent delegation to external tools/services.

**Affected skills:**
- `code-toolkit:codex-cli` → `code-toolkit:codex` agent
- `code-toolkit:claude-code` → `code-toolkit:claude` agent

**Rationale:** These skills contain zero workflow logic—they only wrap CLI tools. This matches the pattern of existing agents like `gemini-cli` (pure delegation).

## Critical Files

### To Create
- `/Users/yulong/.claude/plugins/cache/local-marketplace/code-toolkit/1.0.0/agents/codex.md` (new agent)
- `/Users/yulong/.claude/plugins/cache/local-marketplace/code-toolkit/1.0.0/agents/claude.md` (new agent)

### To Update
- `/Users/yulong/code/dotfiles/claude/CLAUDE.md` (delegation hierarchy documentation)
- `/Users/yulong/.claude/plugins/cache/local-marketplace/code-toolkit/1.0.0/skills/codex-cli/SKILL.md` (deprecation notice)
- `/Users/yulong/.claude/plugins/cache/local-marketplace/code-toolkit/1.0.0/skills/claude-code/SKILL.md` (deprecation notice)

## Implementation Steps

### Step 1: Create Agent Definitions

Create two new agent files following the gemini-cli.md pattern:

**`agents/codex.md` structure:**
```markdown
---
name: codex
description: |
  Delegate well-scoped implementation tasks to Codex CLI. Use when:
  - Implementing defined functions, modules, features
  - Bug fixes with known root cause
  - Scoped refactoring
  - File generation from specs
  - Getting second opinion on implementation plans

  Do NOT use for:
  - Exploration (use Explore agent)
  - Ambiguous tasks
  - Quick edits <10 lines
  - Tasks requiring conversation context
  - Judgment/taste decisions

  <examples>...</examples>
model: inherit
color: blue
tools: ["Bash"]
---

# PURPOSE
Delegate well-scoped implementation to Codex CLI for parallel execution.

# VALUE PROPOSITION
- Fast, precise implementation of clear specs
- Parallel work while Claude handles other tasks
- Strong at concrete errors, weak at taste/judgment

# CODEX CLI SYNTAX
[Commands and patterns from current skill]

# WORKFLOW
[Execution modes: sync, async via tmux]

# OUTPUT FORMAT
[How to integrate Codex results]

# BEST PRACTICES
[When to use, prompt construction, tips]

# LIMITATIONS
[What Codex can't do well]
```

**`agents/claude.md` structure:**
```markdown
---
name: claude
description: |
  Delegate tasks to Claude Code CLI for Claude-powered second opinions,
  parallel implementation, or plan review. Use when you want Claude's
  judgment, tool use, or MCP access as a delegate.

  Do NOT use for:
  - Pure implementation (use codex)
  - Large context analysis (use gemini-cli)
  - Quick edits <10 lines

  <examples>...</examples>
model: inherit
color: purple
tools: ["Bash"]
---

# PURPOSE
Delegate judgment-heavy tasks to separate Claude Code CLI process.

# VALUE PROPOSITION
- Claude's judgment and taste
- Tool use and MCP access
- Parallel independent work

# CLAUDE CLI SYNTAX
[Commands and patterns from current skill]

# WORKFLOW
[Execution modes: sync, async via tmux]

# BEST PRACTICES
[When to use, complementary to Codex/Gemini]

# LIMITATIONS
[Context window, speed vs Codex]
```

**Key changes from skills:**
- Convert frontmatter from skill format to agent format
- Add model, color, tools fields
- Add examples in description (required for agents)
- Restructure content for agent consumption (focus on tool invocation)
- Keep all technical content (CLI syntax, tmux patterns, prompt templates)

### Step 2: Add Deprecation Notices to Skills

Update both skill files with frontmatter deprecation and body warning:

```markdown
---
name: codex-cli
deprecated: true
deprecation_message: |
  This skill has been converted to the 'codex' agent. Use Task tool with
  subagent_type="code-toolkit:codex" instead of the Skill tool.

  Migration: /codex-cli "task" → Task(subagent_type="code-toolkit:codex", prompt="task")
description: |
  DEPRECATED: Use code-toolkit:codex agent instead.
  [original description]
---

# ⚠️ DEPRECATED - Use code-toolkit:codex Agent

This skill has been migrated to an agent. Use:

```
Task tool → subagent_type: "code-toolkit:codex", prompt: "your task"
```

Instead of:

```
Skill tool → skill: "codex-cli", args: "your task"
```

[Original skill content remains below for reference]
```

**Rationale for keeping skills:**
- Graceful migration period
- Users with bookmarked commands still see clear guidance
- Prevents confusion from missing skills

### Step 3: Update Global CLAUDE.md

Add delegation hierarchy section to `/Users/yulong/code/dotfiles/claude/CLAUDE.md`:

```markdown
## Task Delegation Strategy

**Principle:** Skills = workflows you execute, Agents = delegation to external tools.

### Available Delegates (Use Task Tool)

| Agent | Use Case | Strength |
|-------|----------|----------|
| **gemini-cli** | Large context analysis (>100KB) | 1M+ token window, PDFs, entire codebases |
| **code-toolkit:codex** | Well-scoped implementation | Fast, precise, follows specs exactly |
| **code-toolkit:claude** | Judgment-heavy tasks | Taste, tool use, MCP access, nuanced reasoning |

### Decision Tree

```
Need delegation?
├─ Large context (PDF, codebase)? → gemini-cli
├─ Clear implementation spec? → code-toolkit:codex
├─ Need judgment/taste? → code-toolkit:claude
└─ Multi-step workflow? → Use skills (brainstorming, debugging, TDD)
```

### Invocation Pattern

```bash
# Agent (Task tool)
Task tool → subagent_type: "code-toolkit:codex", prompt: "implement X"

# Skill (Skill tool)
Skill tool → skill: "brainstorming", args: "feature idea"
```
```

**Location:** Insert after "## Subagent Strategy" section (around line 285)

### Step 4: Verify Task Tool Registration

**Check:** Task tool's `subagent_type` enum includes new agent types

If not auto-discovered, agents may need to be registered in plugin manifest or Task tool configuration. The existing agents (gemini-cli, llm-billing) are listed in the Task tool description, so these should appear automatically once the files are created.

**Verification command:**
```bash
# Check if agents are discoverable
grep -r "code-toolkit:codex\|code-toolkit:claude" ~/.claude/
```

## Verification Plan

### After Creating Agents

1. **File existence check:**
   ```bash
   ls -la ~/.claude/plugins/cache/local-marketplace/code-toolkit/1.0.0/agents/
   # Should show: codex.md, claude.md (plus existing agents)
   ```

2. **Frontmatter validation:**
   ```bash
   head -20 ~/.claude/plugins/cache/local-marketplace/code-toolkit/1.0.0/agents/codex.md
   # Verify: name, description, model, color, tools fields present
   ```

3. **Test invocation:** (in new Claude Code session)
   ```
   # Try invoking the agent
   Task tool → subagent_type: "code-toolkit:codex",
               prompt: "List available Codex models",
               description: "Test codex agent"

   # Should execute: codex models
   ```

4. **Check deprecation notices:**
   ```bash
   grep -A5 "DEPRECATED" ~/.claude/plugins/cache/local-marketplace/code-toolkit/1.0.0/skills/codex-cli/SKILL.md
   # Should show migration guidance
   ```

### Integration Testing

**End-to-end workflow:**
1. Start fresh Claude Code session
2. Request: "Use Codex to implement a simple function"
3. Verify: Claude invokes Task tool with `code-toolkit:codex`, not Skill tool
4. Check output: Codex CLI command executed, results returned

**Expected behavior:**
- Agents appear in Task tool's available subagent types
- Skills still callable but show deprecation warnings
- Documentation clearly guides users to new pattern

## Migration Timeline

**Immediate (this session):**
- Create agent definitions
- Add deprecation notices to skills
- Update CLAUDE.md

**Future (optional):**
- Monitor usage for 2-4 weeks
- Remove deprecated skills after verification no breakage
- Update any other docs referencing old skills

## Rollback Plan

If agents don't work as expected:
1. Remove deprecation notices from skills
2. Keep agent files (no harm in having both)
3. Debug agent registration issue
4. Retry after fix

**Low risk:** Keeping skills ensures backward compatibility during migration.

## Success Criteria

- ✅ Both agents callable via Task tool
- ✅ Agent descriptions appear in system reminders
- ✅ Skills show clear migration guidance
- ✅ CLAUDE.md documents new pattern
- ✅ No existing workflows broken

## Notes

**Why this matters:**
- Semantic clarity: Task tool = delegation, Skill tool = workflows
- Consistency: Matches gemini-cli pattern (CLI delegation → agent)
- Better UX: "Delegate a task" is clearer than "use a skill to delegate"

**Design decision:** Keep skills during migration for graceful transition, not abrupt breaking change.
