# Plan: Triage and fix suspicious unstaged changes

## Context

Several files drifted from running tools on this Linux machine. Need to revert accidental changes and commit intentional ones.

## Revert (4 files — accidental drift)

| File | What happened | Why revert |
|------|--------------|------------|
| `.claude/settings.json` | `claude-context` re-ran, expanded 6 plugin entries → 30+. Functionally same, just noisier | SessionStart hook regenerates this every session. Keep committed version minimal |
| `claude/settings.json` | (a) hooks block moved in JSON (serializer noise). (b) 5 plugins accidentally enabled globally: Notion, figma, huggingface-skills, vercel, coderabbit | These were deliberately disabled. Enabling globally means they load in ALL projects |
| `codex/rules/default.rules` | Comment path changed `/Users/yulong/` → `/home/yulong/` (auto-gen script embeds local path) | Machine-specific drift, would ping-pong between macOS/Linux |
| `custom_bins/claude-tools` | macOS Mach-O binary replaced with Linux ELF binary (rebuilt on this machine) | Committing Linux version breaks macOS |

```bash
git restore -- .claude/settings.json claude/settings.json codex/rules/default.rules custom_bins/claude-tools
```

## Commit (3 groups)

### Commit 1: `deploy.sh` + `install.sh` improvements
- `deploy.sh`: Generalized marketplace registration (hardcoded → loop over `PLUGIN_MARKETPLACES[]`)
- `install.sh`: apt cache freshness check (skip update if <1h old)

### Commit 2: Guard `claude-context --clean` against git-tracked files
- `custom_bins/claude-context`: Added `_is_git_tracked()` check in `reset()`, `--force` flag
- `custom_bins/claude-plugin-reset`: Pass `--force` through to `claude-context`

### Commit 3: Upstream Codex system skill update
- Stage all changes in `claude/skills/.system/` (deletions + modifications)
- Add new untracked files: `package_skill.py`, `list-curated-skills.py`

## Cleanup

- Delete stale plan file: `.claude/plans/jaunty-knitting-lemur.md`

## Verification

- `git status` → clean working tree
- `claude-context --clean` in dotfiles → blocked
- `claude-context` (no args) → works normally (already tested)
