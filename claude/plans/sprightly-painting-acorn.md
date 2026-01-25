# Claude Code Optimization Plan

Based on [Boris Cherny's full setup thread](https://twitter-thread.com/t/2007179832300581177).

## Boris's Full Setup (Summary)

| Practice | Your Status | Action |
|----------|-------------|--------|
| Plan mode default | ✅ `defaultMode: "plan"` | None needed |
| Opus 4.5 with thinking | ❓ Check model setting | Consider enabling |
| Verification loop (2-3x quality boost) | ⚠️ Missing | **Priority: Add** |
| `/commit-push-pr` slash command | ⚠️ Missing | Add workflow command |
| PostToolUse formatting hook | ✅ Have `truncate_output.sh` | Already similar |
| Subagents (code-simplifier, verify-app) | ✅ Have 9 agents | Already covered |
| MCP integrations (Slack, BigQuery, Sentry) | ❓ Unknown | Check if relevant |
| Team CLAUDE.md in git | ✅ Already doing this | None needed |
| Pre-allowed permissions via `/permissions` | ✅ Extensive allow list | None needed |

## Key Insight from Boris

> "Providing Claude with feedback mechanisms increases result quality 2-3x"

His verification approach:
- Claude Chrome extension for UI testing
- Unit tests to verify code changes
- Subagent `verify-app` for automated validation

## Current Setup Summary

**Already Aligned:**
- Plan mode enabled by default
- CLAUDE.md framework (shared, in git)
- Solid hooks: secret detection, output truncation, command logging
- Rich agent ecosystem (9 agents)
- Pre-allowed permissions

**Gaps:**
- **No verification loop** - Missing the 2-3x quality boost
- **No `/commit-push-pr` command** - Missing workflow optimization
- **alwaysThinkingEnabled** vs Opus 4.5 - May need model check

## Recommended Optimizations

### 1. Enhance `/commit` with Pre-computed Context (Priority: Medium)

You already have `/commit`. Boris's key optimization: **inline bash to pre-compute git status**.

**Modify:** `claude/commands/commit.md`

Add pre-computed context block:
```markdown
Pre-computed context (read first):
$( git status --short )
$( git diff --stat )
$( git log --oneline -3 )
```

This eliminates back-and-forth by giving Claude the state upfront.

**Optional:** Create separate `/push-pr` command for the push+PR workflow.

### 2. Add `/verify` Subagent (Priority: High)

Boris's `verify-app` subagent provides the 2-3x quality boost.

**File:** `claude/agents/verify-app.md`

Purpose: After code changes, verify they work:
- Run relevant tests (`pytest`, `npm test`)
- For UI: use playwright or browser screenshots
- Report pass/fail with specific errors

### 3. Add Verification Permissions

Add to `settings.json`:
```json
"Bash(pytest:*)",
"Bash(uv run pytest:*)",
"Bash(npm test:*)",
"Bash(npx playwright:*)"
```

### 4. (Optional) Code Formatting Hook

Boris has a PostToolUse hook for code formatting. Your `truncate_output.sh` handles output, but consider adding:

**File:** `claude/hooks/format_code.sh`
- Runs `ruff format` or `prettier` after edits
- Prevents CI formatting failures

### 5. CLAUDE.md Guidance for Verification

Add to CLAUDE.md's default behaviors:
```markdown
- **Verify changes** - run tests after implementing; use /verify for UI changes
```

## Implementation Order

1. Add permissions to `settings.json` (quick win)
2. Create `/commit-push-pr` command
3. Create `verify-app` agent
4. Add verification guidance to CLAUDE.md
5. (Optional) Code formatting hook

## Files to Modify

| File | Change |
|------|--------|
| `claude/settings.json` | Add pytest/playwright permissions |
| `claude/commands/commit.md` | Add pre-computed git context |
| `claude/agents/verify-app.md` | New - verification subagent |
| `claude/CLAUDE.md` | Add verification behavior |
| `claude/hooks/format_code.sh` | Optional - auto-formatting |

## Not Recommended

**Simplifying CLAUDE.md** - Your research-focused setup is appropriate for your workflow. Boris's "vanilla" approach works for him because Claude Code team has different needs. Your extensive CLAUDE.md is valuable for AI safety research context.
