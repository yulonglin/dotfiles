# Plan: Strengthen Plan Mode Guidance in CLAUDE.md

## Goal
Make Claude default to plan mode for non-trivial tasks while staying concise.

## Research (Best Practices)
From Anthropic and community sources:
- "The more time you spend planning, the more likely Claude will succeed"
- "Ask Claude to make a plan before coding. Explicitly tell it not to code until confirmed"
- "2 minutes planning saves 20 minutes refactoring"

## Changes

### 1. Add to Default Behaviors (line 31-38)
Add as first bullet point (highest priority):
```markdown
- **Plan before implementing** - use `EnterPlanMode` for non-trivial tasks; don't write code until plan approved
```

### 2. Strengthen Research Workflow (line 139-145)
Make step 2 more explicit about plan mode:
```markdown
### Workflow
1. **Explore** via subagents, check `specs/`
2. **Plan first** - use `EnterPlanMode`, don't code until user approves approach
3. **Start small** (N=10-50) to validate
4. **Implement** with CLI args, JSONL outputs
5. **Review** with code-reviewer agent
6. **Iterate**
```

### 3. Add Common Failure Mode (line 147-154)
Add to the failure modes list:
```markdown
- Jumping into implementation without planning (2 min planning saves 20 min refactoring)
```

## Files to Modify
- `/Users/yulong/code/dotfiles/claude/CLAUDE.md`

## Rationale
- First bullet in Default Behaviors = highest visibility
- Explicit "don't write code until plan approved" is direct and actionable
- Time-saving framing ("2 min saves 20 min") motivates the behavior
- Stays concise - only 3 small additions

## Sources
- [Anthropic: Claude Code Best Practices](https://www.anthropic.com/engineering/claude-code-best-practices)
- [Claude Blog: Using CLAUDE.MD Files](https://claude.com/blog/using-claude-md-files)
