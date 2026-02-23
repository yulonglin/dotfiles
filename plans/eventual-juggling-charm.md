# Plan: Gitignore usage-data + Modern CLI tool defaults

## Context

Two changes requested:
1. `claude/usage-data/` has ~100 untracked files cluttering `git status` — should be gitignored
2. Modern Rust CLI tools (eza, dust, duf, bat, btop) should transparently replace legacy commands when available

The repo already has a `config/modern_tools.sh` (sourced after `aliases.sh`) with conditional overrides for `eza`, `bat`, `fd`, `rg`, `delta`. But `dust` (du), `duf` (df), and `btop` (top) are missing. There are also some inconsistencies in `aliases.sh` (unconditional eza tree aliases, stale commented-out block).

## Changes

### 1. `.gitignore` — add usage-data

Add to the "Claude Code Runtime State" section (~line 509):
```
claude/usage-data/
```

### 2. `config/modern_tools.sh` — add missing tool overrides

Add conditional blocks for:

```sh
# dust: Modern du replacement with visual breakdown
if command -v dust &> /dev/null; then
    alias du='dust'
    alias usage='dust'
fi

# duf: Modern df replacement with color table
if command -v duf &> /dev/null; then
    alias df='duf'
fi

# htop: Better top replacement
if command -v htop &> /dev/null; then
    alias top='htop'
fi
```

### 3. `config/aliases.sh` — fix inconsistencies

**a)** Move tree aliases (lines 246-249) into the eza block in `modern_tools.sh` (they currently use `eza` unconditionally — breaks if eza not installed). Replace with plain `tree` fallback in `aliases.sh`.

**b)** Remove the commented-out modern tools block (lines 411-419) — it's dead code now that `modern_tools.sh` handles this.

**c)** The existing `du='du -kh'` and `df='df -kTh'` aliases (lines 116-117) stay as-is — they're the baseline that `modern_tools.sh` overrides when dust/duf are available.

### Files to modify

| File | Change |
|------|--------|
| `.gitignore` | Add `claude/usage-data/` |
| `config/modern_tools.sh` | Add dust, duf, btop blocks; absorb tree/t1/t2/t3 aliases from aliases.sh |
| `config/aliases.sh` | Fix unconditional eza tree aliases; remove dead commented block |

### Verification

```bash
# 1. Gitignore works
git status  # usage-data files should disappear

# 2. Aliases resolve correctly (with tools installed)
type ls    # → eza
type du    # → dust
type df    # → duf
type tree  # → eza --tree ...
type top   # → btop

# 3. Aliases still work without modern tools (e.g., on a fresh Linux box)
# The aliases.sh baselines should remain functional
```
