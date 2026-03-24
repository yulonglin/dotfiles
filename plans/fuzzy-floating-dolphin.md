# Single Source of Truth for ls/tree Aliases

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate alias override conflicts between `aliases.sh` and `modern_tools.sh` by making each alias defined in exactly one place with conditional eza/ls logic. Also prune unused aliases.

**Architecture:** Move ls/tree-family aliases out of `aliases.sh` into `modern_tools.sh` as a single `if eza; then ... else ... fi` block. Drop rarely-used aliases (`lx`, `lk`, `lc`, `lu`, `lm`, `lr`).

**Context:** Editing `ll` in `aliases.sh` had no effect because `modern_tools.sh` (loaded later) silently overrides it. Additionally, some aliases (`lx`, `lk`, `lc`) broke silently when `ls` was aliased to `eza` because flag meanings differ (e.g., eza `-X` = dereference, not sort-by-extension).

---

## Changes

### Files
- Modify: `config/aliases.sh:789-806` — remove entire ls/tree section
- Modify: `config/modern_tools.sh:5-15` — expand eza block with fallbacks

### Kept aliases: `l`, `ll`, `la`, `lt`, `tree`, `t1`, `t2`, `t3`
### Dropped aliases: `lx`, `lk`, `lc`, `lu`, `lm`, `lr` (full eza commands are readable enough to type directly)

---

## Task 1: Consolidate ls/tree aliases

- [ ] **Step 1: Replace the eza block in `modern_tools.sh` (lines 5-15)**

```bash
# eza: Modern ls replacement with git integration and colors
# ALL ls/tree aliases live here — single source of truth
if command -v eza &> /dev/null; then
    alias ls='eza'
    alias l='eza -F'                                 # Classify with type indicators
    alias ll='eza -lah --git'                        # Long, hidden, headers, git status
    alias la='eza -lah --git'                        # Same as ll (muscle memory)
    alias lt='eza -l --sort=modified --reverse'      # Sort by modification time, newest last
    alias tree='eza --tree --icons --git-ignore'     # Tree view with icons
    alias t1='eza --tree --level=1'
    alias t2='eza --tree --level=2'
    alias t3='eza --tree --level=3'
else
    alias l='ls -CF --color=auto'
    alias ll='ls -lah --group-directories-first'
    alias la='ls -Al'
    alias lt='ls -ltr'                               # Sort by date, most recent last
    alias tree='tree'                                # No-op, just for consistency
    alias t1='tree -L 1'
    alias t2='tree -L 2'
    alias t3='tree -L 3'
fi
```

- [ ] **Step 2: Remove the ls/tree section from `aliases.sh` (lines 789-806)**

Replace the entire block (header + all aliases) with a pointer:

```bash
# ls/tree aliases → config/modern_tools.sh (single source of truth)
```

- [ ] **Step 3: Verify in a new shell**

```bash
# Check all kept aliases resolve correctly
zsh -l -c 'type l ll la lt tree t1 t2 t3'

# Verify no duplicates across files
grep -rn 'alias ll=' config/

# Verify dropped aliases are gone
zsh -l -c 'type lx lk lc lu lm lr 2>&1'
```

- [ ] **Step 4: Commit**

```bash
git add config/aliases.sh config/modern_tools.sh
git commit -m "refactor: single source of truth for ls/tree aliases in modern_tools.sh

Move ls/tree aliases from aliases.sh to modern_tools.sh conditional block.
Drop unused aliases (lx, lk, lc, lu, lm, lr). Fixes silent breakage
where eza flags have different meanings than ls flags."
```

---

## Verification

1. `ll` shows hidden files + headers + git status
2. `grep -rn 'alias ll=' config/` → exactly one match in `modern_tools.sh`
3. Dropped aliases (`lx`, `lk`, etc.) return "not found"
4. `l`, `lt`, `tree`, `t1-t3` all work
