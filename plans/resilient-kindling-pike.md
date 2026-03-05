# Plan: Move ai-safety-plugins to ~/code/marketplaces/

## Context

`~/code/ai-safety-plugins` exists but nothing references that path. Both `profiles.yaml` (`local: ${CODE_DIR}/marketplaces/ai-safety-plugins`) and the git-tracked symlink (`claude/ai-safety-plugins → ../../marketplaces/ai-safety-plugins`, which resolves via the physical path `dotfiles/claude/` → `~/code/marketplaces/ai-safety-plugins`) already expect it at `~/code/marketplaces/ai-safety-plugins`.

**Key insight from critics:** The current symlink is already correct — relative symlinks resolve from the **real** (physical) path, not the logical path. Since `~/.claude` → `dotfiles/claude/`, the target `../../marketplaces/ai-safety-plugins` resolves: `dotfiles/claude/` → up 2 → `~/code/` → `~/code/marketplaces/ai-safety-plugins`. No symlink change needed.

**Goal:** Move the clone to where everything already expects it, rebind the marketplace registration to use local source.

## Changes

### 1. Move clone to correct path
```bash
# Guards: verify source exists and destination doesn't
test -d ~/code/ai-safety-plugins/.claude-plugin || { echo "Source missing"; exit 1; }
test ! -e ~/code/marketplaces/ai-safety-plugins || { echo "Destination exists"; exit 1; }
mkdir -p ~/code/marketplaces
mv ~/code/ai-safety-plugins ~/code/marketplaces/ai-safety-plugins
```

### 2. Rebind marketplace registration
`claude-context --sync` skips `marketplace add` if already registered (even if the source changed from GitHub to local). Need to remove and re-register:
```bash
claude plugin marketplace rm ai-safety-plugins
claude-context --sync -v
```
This makes `claude-context --sync` detect the local clone and register from there instead of GitHub.

### 3. Keep everything else as-is
- **Symlink** `claude/ai-safety-plugins` — already correct (resolves to `~/code/marketplaces/ai-safety-plugins`)
- **`profiles.yaml`** — already correct (`local: ${CODE_DIR}/marketplaces/ai-safety-plugins` + GitHub fallback)
- **`CLAUDE.md`** — already documents `ai-safety-plugins -> ~/code/marketplaces/ai-safety-plugins`
- **`claude/CLAUDE.md`** — already references `github.com/yulonglin/ai-safety-plugins`

### Notes
- The symlink is cosmetic — no code path reads it. `claude-context --sync` uses `profiles.yaml`. But it's correct and harmless, so keep it.
- The symlink hardcodes `~/code/` while `profiles.yaml` handles `${CODE_DIR}` — acceptable trade-off for a convenience link.
- On machines without a local clone, the symlink dangles and `claude-context` falls back to GitHub. Both are fine.

## Verification

1. `ls ~/code/marketplaces/ai-safety-plugins/.claude-plugin` → exists
2. `readlink -f ~/.claude/ai-safety-plugins` → `/home/yulong/code/marketplaces/ai-safety-plugins`
3. `ls ~/.claude/ai-safety-plugins/plugins/` → lists plugin dirs (core, research, writing, code, workflow, viz)
4. `claude-context --sync -v` → shows `ai-safety-plugins` registered from local source
5. `claude-context` → plugins load normally
