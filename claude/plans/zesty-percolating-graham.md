# Plan: Workaround for `classifyHandoffIfNeeded` Agent Crash Bug

## Context

Claude Code has a pervasive bug (16+ open issues, all platforms, since ~v2.1.27) where agents crash on **completion** with `ReferenceError: classifyHandoffIfNeeded is not defined`. The function is called in the completion handler but never defined in the bundled `cli.js`.

**Critical insight:** Agent work **always completes successfully** — files are written, commits made, outputs exist on disk. The crash happens AFTER all tool calls finish, during the handoff/classification step. The Task tool then falsely reports `status: failed`, and no summary is returned to the parent context.

**Impact on us:** When delegating to agents (Explore, Plan, general-purpose, custom), the parent thinks the agent failed and either retries unnecessarily, halts, or wastes context trying to understand a non-existent failure.

## Approach: Rules-Based Mitigation (Temporary)

Add a known-issue section to `rules/agents-and-delegation.md` that instructs Claude to recognize and handle this false failure. This is the highest-leverage approach because:
- Rules are auto-loaded every session across all projects
- Rules directly influence Claude's decision-making when it sees the error
- No hook infrastructure needed (SubagentStop hooks are not currently wired)
- Easy to remove once the bug is fixed upstream

## Changes

### 1. Edit `claude/rules/agents-and-delegation.md`

Add a new section at the end:

```markdown
## Known Issue: `classifyHandoffIfNeeded` False Failures (Temporary)

**Bug:** Claude Code agents crash on completion with `classifyHandoffIfNeeded is not defined`. This is a build bug — the function is referenced but never defined. Tracked in 16+ issues: https://github.com/anthropics/claude-code/issues?q=classifyHandoffIfNeeded

**What actually happens:** Agent work completes successfully (files written, commits made, all tool calls finish). The crash occurs AFTER completion during the handoff step. Task tool falsely reports `status: failed`.

**Required behavior when you see this error:**

1. **Do NOT treat as a real failure** — the work is done
2. **Verify the output exists** — check files, git log, or expected artifacts on disk
3. **If output exists → proceed as if agent succeeded** — use the results normally
4. **Do NOT retry the agent** — retrying wastes context and produces duplicate work
5. **For background agents** — read the output file; the data is there despite the failure notification

**Remove this section** when the upstream fix lands (check: `claude --version` changelog).
```

## Files to Modify

1. `claude/rules/agents-and-delegation.md` — append known-issue section (~15 lines)

## What This Does NOT Do

- No hook changes (SubagentStop not wired in settings.json, and the error happens inside Claude Code's internal handler — a hook can't intercept it)
- No settings.json changes
- No code patches (can't patch the bundled cli.js)

## Verification

1. Read back `agents-and-delegation.md` to confirm the section looks clean
2. Start a new session, spawn a Task agent, and confirm the workaround guidance activates if the error occurs
3. Check that the rule doesn't interfere with detecting real agent failures (the rule is specific to the `classifyHandoffIfNeeded` error string)

## Removal Criteria

Remove the known-issue section when Claude Code ships a version that fixes `classifyHandoffIfNeeded`. Check release notes or test by spawning an agent and confirming no crash on completion.
