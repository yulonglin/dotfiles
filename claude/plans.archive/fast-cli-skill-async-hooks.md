# Plan: Fast CLI Skill + Async Hooks

## Summary

1. ✅ Created `fast-cli` skill at `claude/skills/fast-cli/SKILL.md`
2. Make appropriate hooks async in `claude/settings.json`

## Changes

### 1. Fast CLI Skill (DONE)

Created `claude/skills/fast-cli/SKILL.md` with:
- Tool mappings (eza, fd, rg, bat, dust, duf, fzf, zoxide, delta, jq)
- Smart defaults for each tool
- Custom utilities from `custom_bins/`
- Common usage patterns

### 2. Async Hooks

Update `claude/settings.json` to add `"async": true` to logging hooks.

**Analysis of hooks:**

| Hook | Can be async? | Reason |
|------|---------------|--------|
| `auto_log.sh START` | ✅ Yes | Just logging, no return value needed |
| `check_secrets.sh` | ❌ No | Returns exit 2 to BLOCK commits |
| `auto_log.sh END` | ✅ Yes | Just logging, no return value needed |
| `truncate_output.sh` | ❌ No | Returns JSON to suppress/modify output |
| `check_read_size.sh` | ❌ No | Returns JSON with decision (block/allow) |

**Modification:**
```json
{
  "type": "command",
  "command": "~/.claude/hooks/auto_log.sh START",
  "async": true
}
```

## Verification

1. Test fast-cli skill triggers on "list files with eza"
2. Verify async hooks don't break (run a bash command, check logs still written)
3. Verify sync hooks still block (test secret detection with mock commit)
