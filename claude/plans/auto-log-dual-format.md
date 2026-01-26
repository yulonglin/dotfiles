# Plan: Improve auto_log.sh with dual format logging

## Goal
Make bash command logs both human-scannable (in Cursor) AND programmatically queryable (with jq).

## Changes

### 1. Update `claude/hooks/auto_log.sh`

**Write to two files:**

`bash-commands.log` - human-readable:
```
10:30 [OK] dotfiles (main) | git status
10:31 [!1] dotfiles (main) | pytest tests/
10:32 [OK] dotfiles (main) | git add -A
```

`bash-commands.jsonl` - structured:
```json
{"ts":"2026-01-26T10:30:00+00:00","exit":0,"cmd":"git status","cwd":"/path/to/project","branch":"main"}
```

**Fields:**
- `ts` - ISO timestamp
- `exit` - exit code (null for START phase, number for END)
- `cmd` - the command
- `cwd` - working directory
- `branch` - git branch (if in git repo, else omitted)

**Human-readable format:**
- Time only (HH:MM) - date in JSONL if needed
- Fixed-width markers: `[OK]` for success, `[!N]` for exit code N
- Project name + branch: extracted from cwd and git
- Pipe separator before command (variable length)
- Only log END phase (START adds noise for human reading)

**Extracting project + branch:**
- Project name: basename of `$CLAUDE_PROJECT_DIR` (or cwd if not set)
- Branch: `git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null` (omit if not git)

### 2. File locations

Both in `${CLAUDE_PROJECT_DIR}/.claude/`:
- `bash-commands.log` - open in Cursor to scan
- `bash-commands.jsonl` - query with jq

## Verification

1. Run commands in Claude Code session
2. Check `.log` is readable in Cursor
3. Check `.jsonl` parses: `jq '.' bash-commands.jsonl`
4. Test query: `jq 'select(.exit != 0)' bash-commands.jsonl`
