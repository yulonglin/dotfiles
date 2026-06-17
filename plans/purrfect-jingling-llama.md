# Plan: Fix hookify excessive hook firings

## Context

hookify's PreToolUse/PostToolUse hooks fire on **every** tool call (no matchers in hooks.json). Each invocation spawns Python, and Claude Code logs "Async hook PreToolUse/PostToolUse completed" for each. With parallel subagents making dozens of tool calls, this produces 100+ noise lines per turn.

## Root cause

hooks.json registers hooks without `matcher` fields. Claude Code fires unmatched hooks for ALL tool types. But hookify only handles:
- PreToolUse/PostToolUse: `Bash`, `Edit`, `Write`, `MultiEdit`
- Stop: always relevant (1 firing per stop)
- UserPromptSubmit: always relevant (1 firing per prompt)

## Fix: Add matchers to hooks.json

**File:** `claude/ai-safety-plugins/hookify/hooks/hooks.json`

Add `"matcher"` to PreToolUse and PostToolUse entries so they only fire for tools hookify actually processes. Stop and UserPromptSubmit don't need matchers (they fire once per event, not per tool call).

**Plus:** Add early-exit glob check in all 4 Python scripts as defense-in-depth — skip stdin parsing and rule loading when no rule files exist.

### Changes

1. **`hookify/hooks/hooks.json`** — add matchers:
   - PreToolUse: `"matcher": "Bash|Edit|Write|MultiEdit"`
   - PostToolUse: `"matcher": "Bash|Edit|Write|MultiEdit"`
   - Stop/UserPromptSubmit: no change needed

2. **`hookify/hooks/pretooluse.py`** — add early-exit before stdin read:
   ```python
   import glob, sys
   if not glob.glob('.claude/hookify.*.local.md'):
       print('{}'); sys.exit(0)
   ```

3. **`hookify/hooks/posttooluse.py`** — same early-exit

4. **`hookify/hooks/stop.py`** — same early-exit

5. **`hookify/hooks/userpromptsubmit.py`** — same early-exit

6. **Update plugin cache** — sync to `~/.claude/plugins/cache/`

### Files to modify

- `claude/ai-safety-plugins/hookify/hooks/hooks.json`
- `claude/ai-safety-plugins/hookify/hooks/pretooluse.py`
- `claude/ai-safety-plugins/hookify/hooks/posttooluse.py`
- `claude/ai-safety-plugins/hookify/hooks/stop.py`
- `claude/ai-safety-plugins/hookify/hooks/userpromptsubmit.py`

### Verification

1. Make several tool calls (Read, Grep, Glob) — no hookify "Async hook" noise
2. Run a Bash command — hookify fires (but only once per Bash call)
3. Create a test `.claude/hookify.test.local.md` rule, verify it still triggers
4. Remove test rule, verify clean output
