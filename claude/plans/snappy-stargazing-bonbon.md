# Plan: Restructure Parallelise section

## Context
The "Parallelise" section mixes two levels of abstraction in a flat list: session-level tools (git worktrees, tmux) and within-session Claude features (background subagents, agent teams). Agent teams also gets disproportionate detail as a `####` sub-heading while the others are bullet points.

## Approach
Group by level of parallelism with two sub-sections:

### Across sessions
- Git worktrees + tmux (external tools for running multiple Claude Code instances)

### Within a session
- Background subagents (fire-and-forget, lightweight)
- Agent teams (coordinated peers, heavyweight) — keep the existing detail but at the same structural level

## Files
- `src/content/writing/claude-code.md` lines 96–114

## Verification
- Read the section after editing to confirm the grouping reads naturally
